import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../geo.dart';
import '../items.dart';
import '../mode.dart';
import '../table/sectors.dart';
import '../table/zones.dart';
import 'live_service.dart';
import 'party_service.dart';
import 'shared_stream.dart';
import 'table_service.dart';

/// Un altro party individuato dal Radar (distanza/direzione con il GPS, [place] al tavolo).
class RadarContact {
  final String name;
  final double distance;
  final String direction;
  final Duration age;
  final String? place;
  RadarContact(this.name, this.distance, this.direction, this.age, {this.place});
}

/// Gestione di inventario ed effetti degli strumenti, in due modalità:
///  - dal vivo: durate in minuti (Timestamp) e posizione GPS;
///  - tavolo:   durate in giri (numero del giro) e posizione zona/settore.
///
/// Campi su `Users/{uid}`:
///   inventory: { repellente: 1, ... }
///   repellentUntil / koUntil / trappedUntil : Timestamp (live) | ultimo giro attivo (tavolo)
///   trappedSkip (tavolo): turni da saltare;  fleeBlocks: { <uidAvversario>: scadenza }
///   location (live) | pos { zone, sector } (tavolo)
class ItemService {
  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> userRef(String uid) =>
      _db.collection('Users').doc(uid);

  /// Condiviso: un solo ascolto per utente, anche se lo usano tanti widget.
  static Stream<Map<String, dynamic>?> watchUser(String uid) =>
      shared('user:$uid', () => userRef(uid).snapshots().map((s) => s.data()));

  /// Solo alcuni campi del documento utente: emette solo quando cambiano quelli
  /// (es. la posizione GPS, scritta ogni ~20 s, non ricostruisce chi guarda solo i badge).
  static Stream<Map<String, dynamic>> watchUserFields(String uid, List<String> keys) => shared(
        'user:$uid:${keys.join(',')}',
        () => watchUser(uid).map((u) => <String, dynamic>{for (final k in keys) k: u?[k]}).distinct(jsonEquals),
      );

  /// Party corrente del giocatore (emette solo quando cambia).
  static Stream<String?> watchActualParty(String uid) => shared(
        'actualParty:$uid',
        () => watchUser(uid).map((u) {
          final p = u?['actualParty'];
          return p is String && p.isNotEmpty ? p : null;
        }).distinct(),
      );

  /// Ultimo valore noto del documento utente (per `initialData` degli StreamBuilder).
  static Map<String, dynamic>? lastUser(String uid) => sharedLast<Map<String, dynamic>?>('user:$uid');

  // ---------------------------------------------------------- inventario

  static Map<String, int> startingInventory() =>
      {for (final e in kStartingInventory.entries) e.key.name: e.value};

  /// Legge l'inventario; se manca vale la dotazione iniziale.
  static Map<String, int> readInventory(Map<String, dynamic>? user) {
    final raw = user?['inventory'];
    if (raw is! Map) return startingInventory();
    final inv = startingInventory().map((k, _) => MapEntry(k, 0));
    raw.forEach((k, v) {
      if (v is num) inv[k.toString()] = v.toInt();
    });
    return inv;
  }

  static Future<void> ensureInventory(String uid) async {
    final snap = await userRef(uid).get();
    if (snap.exists && snap.data()?['inventory'] == null) {
      await userRef(uid).set({'inventory': startingInventory()}, SetOptions(merge: true));
    }
  }

  // ------------------------------------------------------------- durate

  static DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : null;
  static Timestamp _in(int minutes) =>
      Timestamp.fromDate(DateTime.now().add(Duration(minutes: minutes)));

  /// Scadenza di un effetto: minuti (dal vivo) o giri (tavolo; incluso il giro corrente).
  static dynamic until({required int minutes, required int rounds}) =>
      kTableMode ? TableClock.round + rounds - 1 : _in(minutes);

  static dynamic fleeUntil() => until(minutes: kFleeBlockMinutes, rounds: kFleeBlockRounds);

  /// Un effetto è attivo se la scadenza è nel futuro (Timestamp) o se il giro corrente non l'ha superata.
  /// I giri valgono in entrambe le modalità (dal vivo avanzano ogni N minuti), purché la partita sia in corso.
  static bool isActive(dynamic v) {
    if (v is Timestamp) return v.toDate().isAfter(DateTime.now());
    if (v is num) return TableClock.round > 0 && TableClock.round <= v.toInt();
    return false;
  }

  /// Consuma 1 oggetto (transazione) ed applica opzionalmente altri campi.
  static Future<void> _consume(
    String uid,
    ItemId id, {
    Map<String, dynamic> Function(Map<String, dynamic> user)? effect,
  }) {
    final ref = userRef(uid);
    return _db.runTransaction<void>((tx) async {
      final user = (await tx.get(ref)).data() ?? {};
      final extra = effect?.call(user) ?? {};
      final inv = readInventory(user);
      if ((inv[id.name] ?? 0) <= 0) {
        throw Exception('Non hai più ${itemDef(id).name}');
      }
      inv[id.name] = inv[id.name]! - 1;
      tx.set(ref, {'inventory': inv, ...extra}, SetOptions(merge: true));
    });
  }

  static Future<void> consume(String uid, ItemId id) => _consume(uid, id);

  // ------------------------------------------------------------ restrizioni

  /// Controlla che il giocatore (e l'eventuale avversario) possano combattere.
  static Future<void> assertCanFight(String uid, {String? opponentUid}) async {
    final me = (await userRef(uid).get()).data() ?? {};
    if (isActive(me['koUntil'])) {
      throw Exception('Il tuo Pokémon è esausto: aspetta il recupero o usa un Revitalizzante');
    }
    if (isActive(me['trappedUntil']) || ((me['trappedSkip'] as num?) ?? 0) > 0) {
      throw Exception('Sei bloccato in una Trappola');
    }
    if (isActive(me['repellentUntil'])) {
      throw Exception('Il Repellente è attivo: non puoi essere ingaggiato in scontri');
    }
    if (opponentUid == null) return;
    final opp = (await userRef(opponentUid).get()).data() ?? {};
    if (isActive(opp['repellentUntil'])) {
      throw Exception("L'avversario è protetto da un Repellente");
    }
    if (isActive(opp['koUntil']) || isActive(opp['trappedUntil']) || ((opp['trappedSkip'] as num?) ?? 0) > 0) {
      throw Exception("L'avversario non è disponibile");
    }
    final blocks = me['fleeBlocks'];
    if (blocks is Map && isActive(blocks[opponentUid])) {
      throw Exception('Siete appena usciti da uno scontro: non potete affrontarvi subito');
    }
  }

  /// Sconfitta: il Pokémon è esausto (minuti dal vivo, giri al tavolo).
  static Future<void> setKo(String uid) => userRef(uid)
      .set({'koUntil': until(minutes: kKoMinutes, rounds: kKoRounds)}, SetOptions(merge: true));

  // -------------------------------------------------------------- oggetti

  static Future<void> useRepellent(String uid) => _consume(uid, ItemId.repellente, effect: (u) {
        if (isActive(u['repellentUntil'])) throw Exception('Il Repellente è già attivo');
        return {'repellentUntil': until(minutes: kRepellentMinutes, rounds: kRepellentRounds)};
      });

  static Future<void> useRevive(String uid) => _consume(uid, ItemId.revitalizzante, effect: (u) {
        if (!isActive(u['koUntil'])) throw Exception('Il tuo Pokémon non è esausto');
        return {'koUntil': FieldValue.delete()};
      });

  /// Fune di fuga contro la Trappola: annulla il blocco.
  static Future<void> useRopeOnTrap(String uid) => _consume(uid, ItemId.fune, effect: (u) {
        if (kTableMode) {
          if (((u['trappedSkip'] as num?) ?? 0) <= 0) throw Exception('Non sei in una trappola');
          return {'trappedSkip': 0};
        }
        if (!isActive(u['trappedUntil'])) throw Exception('Non sei in una trappola');
        return {'trappedUntil': FieldValue.delete()};
      });

  static Future<Map?> _pos(String uid) async =>
      (await userRef(uid).get()).data()?['pos'] as Map?;

  /// Calmanella: rivela la tua posizione agli altri del party.
  static Future<void> useBell(String uid, String party, Position? pos) async {
    Map<String, dynamic> payload;
    if (kTableMode) {
      final p = await _pos(uid);
      if (p == null) throw Exception('Posizione non disponibile');
      payload = {'zone': p['zone'], 'sector': p['sector']};
    } else {
      if (pos == null) throw Exception('Posizione non disponibile');
      payload = {'lat': pos.latitude, 'lng': pos.longitude};
    }
    await _consume(uid, ItemId.calmanella);
    await PartyService.party(party).collection('events').add({
      'type': 'bell',
      'uid': uid,
      ...payload,
      'at': FieldValue.serverTimestamp(),
    });
  }

  /// Radar: posizione degli altri party (esclusi quelli con Repellente o nascosti da un evento).
  static Future<List<RadarContact>> useRadar(String uid, String party, Position? pos) async {
    if (!kTableMode && pos == null) throw Exception('Posizione non disponibile');
    final me = (await userRef(uid).get()).data();
    await _consume(uid, ItemId.radar);
    final players = await PartyService.players(party).get();
    final out = <RadarContact>[];
    // nebbia: dal vivo nasconde chi è (secondo il GPS) nella zona dell'evento
    final hidden = await TableService.radarHiddenZones(party);
    final mine = shieldZone(me); // Bussola: vedi anche attraverso la nebbia di quella zona
    if (mine != null) hidden.remove(mine);
    for (final p in players.docs) {
      if (p.id == uid) continue;
      final u = (await userRef(p.id).get()).data();
      if (u == null || isActive(u['repellentUntil']) || isActive(u['stealthUntil'])) continue;
      if (kTableMode) {
        final tp = u['pos'];
        if (tp is! Map || hidden.contains(tp['zone'])) continue;
        out.add(RadarContact(p.id, 0, '', Duration.zero,
            place: '${zoneSpec('${tp['zone']}').name} · settore ${tp['sector']}'));
        continue;
      }
      if (hidden.contains((u['pos'] as Map?)?['zone'])) continue;
      final loc = u['location'];
      if (loc is! Map) continue;
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final at = _ts(loc['at']);
      out.add(RadarContact(
        p.id,
        distanceMeters(pos!.latitude, pos.longitude, lat, lng),
        compass(pos.latitude, pos.longitude, lat, lng),
        at == null ? Duration.zero : DateTime.now().difference(at),
      ));
    }
    out.sort((a, b) => a.distance.compareTo(b.distance));
    return out;
  }

  /// Trappola: piazzata nella tua posizione (GPS) o nel tuo settore (tavolo).
  static Future<void> placeTrap(String uid, String party, Position? pos) async {
    Map<String, dynamic> where;
    if (kTableMode) {
      final p = await _pos(uid);
      if (p == null) throw Exception('Posizione non disponibile');
      where = {'zone': p['zone'], 'sector': p['sector']};
    } else {
      if (pos == null) throw Exception('Posizione non disponibile');
      where = {'lat': pos.latitude, 'lng': pos.longitude};
    }
    await _consume(uid, ItemId.trappola);
    await PartyService.party(party).collection('traps').add({
      'ownerUid': uid,
      ...where,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// (Dal vivo) Un giocatore entra nel raggio di una trappola altrui: scatta una sola volta.
  static Future<bool> triggerTrap(String party, String trapId, String uid) {
    final ref = PartyService.party(party).collection('traps').doc(trapId);
    return _db.runTransaction<bool>((tx) async {
      final t = (await tx.get(ref)).data();
      final me = (await tx.get(userRef(uid))).data();
      if (t == null || t['active'] != true || t['ownerUid'] == uid) return false;
      if (isActive(me?['stealthUntil'])) return false; // Passo felpato
      tx.update(ref, {'active': false, 'triggeredBy': uid});
      tx.set(userRef(uid), {'trappedUntil': _in(kTrapPenaltyMinutes)}, SetOptions(merge: true));
      return true;
    });
  }

  // ====================================================================
  //  Monete, borsa e premi
  // ====================================================================

  static int coinsOf(Map<String, dynamic>? user) => (user?['coins'] as num?)?.toInt() ?? kStartingCoins;

  static int bagCount(Map<String, int> inv) => inv.values.fold(0, (a, b) => a + b);

  /// Aggiunge [n] pezzi alla borsa se c'è posto. Restituisce false se la borsa è piena.
  static bool addItem(Map<String, int> inv, String key, [int n = 1]) {
    if (bagCount(inv) + n > kBagLimit) return false;
    inv[key] = (inv[key] ?? 0) + n;
    return true;
  }

  /// Strumento casuale per i premi (peso = rarità). Esclude le protezioni di bioma
  /// (si comprano) e, dal vivo, quelli solo da tavolo.
  static ItemId randomDrop({Random? rnd}) {
    final r = rnd ?? Random();
    final pool = kItems.where((i) => i.zone == null && (kTableMode || !i.tableOnly)).toList();
    final total = pool.fold<int>(0, (a, i) => a + i.rarity);
    var pick = r.nextInt(total);
    for (final i in pool) {
      pick -= i.rarity;
      if (pick < 0) return i.id;
    }
    return pool.first.id;
  }

  /// Nomi (chiavi) degli strumenti che i premi possono dare.
  static List<String> dropKeys() =>
      [for (final i in kItems) if (i.zone == null && (kTableMode || !i.tableOnly)) i.key];

  /// Assegna monete e strumenti (transazione). Restituisce il testo del premio.
  static Future<String> grant(String uid, {int coins = 0, List<ItemId> items = const []}) {
    final ref = userRef(uid);
    return _db.runTransaction<String>((tx) async {
      final u = (await tx.get(ref)).data() ?? {};
      final inv = readInventory(u);
      final parts = <String>[];
      if (coins > 0) parts.add('+$coins 🪙');
      for (final id in items) {
        parts.add(addItem(inv, id.name) ? itemDef(id).name : '${itemDef(id).name} (borsa piena: perso)');
      }
      tx.set(ref, {'inventory': inv, 'coins': coinsOf(u) + coins}, SetOptions(merge: true));
      return parts.join(', ');
    });
  }

  /// Acquisto all'emporio.
  static Future<void> buy(String uid, ItemId id) {
    final ref = userRef(uid);
    return _db.runTransaction<void>((tx) async {
      final u = (await tx.get(ref)).data() ?? {};
      if (!kTableMode) LiveService.assertNotBusy(u);
      final def = itemDef(id);
      final coins = coinsOf(u);
      if (coins < def.price) throw Exception('Monete insufficienti (servono ${def.price} 🪙)');
      final inv = readInventory(u);
      if (!addItem(inv, id.name)) throw Exception('Borsa piena ($kBagLimit oggetti)');
      tx.set(ref, {'inventory': inv, 'coins': coins - def.price}, SetOptions(merge: true));
    });
  }

  /// Crafting: consuma gli ingredienti e crea il risultato.
  static Future<void> craft(String uid, Recipe r) {
    final ref = userRef(uid);
    return _db.runTransaction<void>((tx) async {
      final u = (await tx.get(ref)).data() ?? {};
      final inv = readInventory(u);
      r.inputs.forEach((id, n) {
        if ((inv[id.name] ?? 0) < n) throw Exception('Ti servono ${n}x ${itemDef(id).name}');
        inv[id.name] = inv[id.name]! - n;
      });
      if (!addItem(inv, r.output.name)) throw Exception('Borsa piena ($kBagLimit oggetti)');
      tx.set(ref, {'inventory': inv}, SetOptions(merge: true));
    });
  }

  // ====================================================================
  //  Scambi tra giocatori  (Party/{codice}/trades/{id})
  // ====================================================================

  static CollectionReference<Map<String, dynamic>> trades(String party) =>
      PartyService.party(party).collection('trades');

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchIncomingTrades(String party, String uid) => shared(
      'trades:$party/$uid', () => trades(party).where('to', isEqualTo: uid).where('status', isEqualTo: 'pending').snapshots());

  /// Offri uno strumento a un altro giocatore; [want] = cosa chiedi in cambio (null = regalo).
  static Future<void> offerTrade({
    required String party,
    required String from,
    required String to,
    required ItemId give,
    ItemId? want,
  }) async {
    if (from == to) throw Exception('Scegli un altro giocatore');
    final me = (await userRef(from).get()).data();
    if ((readInventory(me)[give.name] ?? 0) <= 0) throw Exception('Non hai più ${itemDef(give).name}');
    if (kTableMode) {
      final other = (await userRef(to).get()).data();
      final a = me?['pos'] as Map?, b = other?['pos'] as Map?;
      if (a == null || b == null || a['zone'] != b['zone']) {
        throw Exception('Per scambiare dovete essere nella stessa zona');
      }
    }
    await trades(party).add({
      'from': from,
      'to': to,
      'give': give.name,
      'want': want?.name,
      'status': 'pending',
      'at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> answerTrade(String party, String tradeId, String uid, {required bool accept}) async {
    final tref = trades(party).doc(tradeId);
    await _db.runTransaction<void>((tx) async {
      final t = (await tx.get(tref)).data();
      if (t == null || t['status'] != 'pending' || t['to'] != uid) throw Exception('Offerta non più valida');
      if (!accept) {
        tx.update(tref, {'status': 'declined'});
        return;
      }
      final fromRef = userRef(t['from'] as String), toRef = userRef(uid);
      final fu = (await tx.get(fromRef)).data() ?? {};
      final tu = (await tx.get(toRef)).data() ?? {};
      final give = t['give'] as String, want = t['want'] as String?;
      final fi = readInventory(fu), ti = readInventory(tu);
      if ((fi[give] ?? 0) <= 0) throw Exception('Chi ha offerto non ha più lo strumento');
      fi[give] = fi[give]! - 1;
      if (want != null) {
        if ((ti[want] ?? 0) <= 0) throw Exception('Non hai ${itemDef(ItemId.values.byName(want)).name} da dare in cambio');
        ti[want] = ti[want]! - 1;
        if (!addItem(fi, want)) throw Exception('La borsa di chi ha offerto è piena');
      }
      if (!addItem(ti, give)) throw Exception('Borsa piena ($kBagLimit oggetti)');
      tx.set(fromRef, {'inventory': fi}, SetOptions(merge: true));
      tx.set(toRef, {'inventory': ti}, SetOptions(merge: true));
      tx.update(tref, {'status': 'done'});
    });
  }

  // ====================================================================
  //  Nuovi strumenti
  // ====================================================================

  static CollectionReference<Map<String, dynamic>> _tracesCol(String party) =>
      PartyService.party(party).collection('traces');

  /// Registra una traccia (movimento o ricerca) leggibile con la Lente. Il Passo felpato non ne lascia.
  static Future<void> addTrace(String party, String uid, Map<String, dynamic> data) async {
    final u = (await userRef(uid).get()).data();
    if (isActive(u?['stealthUntil'])) return;
    await _tracesCol(party).add({
      'uid': uid,
      ...data,
      if (kTableMode) 'round': TableClock.round,
      'at': FieldValue.serverTimestamp(),
    });
  }

  /// Lente: zone/settori già battuti e direzioni prese dagli altri.
  static Future<LensReport> useLens(String uid, String party, Position? pos) async {
    Map? me;
    if (kTableMode) {
      me = await _pos(uid);
      if (me == null) throw Exception('Posizione non disponibile');
    } else if (pos == null) {
      throw Exception('Posizione non disponibile');
    }
    await _consume(uid, ItemId.lente);
    final docs = (await _tracesCol(party).get()).docs.map((d) => d.data()).where((t) => t['uid'] != uid).toList();
    final searched = <String>[];
    final moves = <String>[];

    if (kTableMode) {
      await TableService.loadLayout(party);
      // una traccia resta visibile per (forza × kTraceRoundsPerStrength) giri: le più evidenti durano di più
      int strength(Map t) => (t['strength'] as num?)?.toInt() ?? kTraceBaseStrength;
      final recent = docs
          .where((t) => ((t['round'] as num?)?.toInt() ?? 0) >= TableClock.round - kTraceRoundsPerStrength * strength(t))
          .toList();
      final bySector = <String, Set<int>>{};
      for (final t in recent.where((t) => t['kind'] == 'search')) {
        bySector.putIfAbsent('${t['zone']}', () => {}).add((t['sector'] as num).toInt());
      }
      for (final z in kZones) {
        final secs = bySector[z.id];
        if (secs == null) continue;
        final list = (secs.toList()..sort()).join(', ');
        searched.add('${z.name}: settori $list già battuti (${secs.length}/${z.sectors})');
      }
      for (final t in recent.where((t) => t['kind'] == 'move')) {
        final dest = '${zoneSpec('${t['zone']}').name}, settore ${t['sector']}';
        final from = '${zoneSpec('${t['fromZone']}').name}, settore ${t['fromSector']}';
        final how = 'giro ${t['round']}, traccia ${traceStrengthLabel(strength(t))}';
        if (t['fromZone'] == me!['zone'] && t['fromSector'] == me['sector']) {
          moves.add('${t['uid']} è partito da qui verso $dest ($how)');
        } else if (t['zone'] == me['zone'] && t['sector'] == me['sector']) {
          moves.add('${t['uid']} è arrivato qui da $from ($how)');
        }
      }
    } else {
      for (final t in docs.where((t) => t['kind'] == 'search' && t['lat'] != null)) {
        final at = _ts(t['at']);
        final age = at == null ? Duration.zero : DateTime.now().difference(at);
        if (age.inMinutes > kLensMinutes) continue;
        final lat = (t['lat'] as num).toDouble(), lng = (t['lng'] as num).toDouble();
        final d = distanceMeters(pos!.latitude, pos.longitude, lat, lng);
        if (d > kLensRadiusMeters) continue;
        searched.add('${t['uid']} ha cercato a ${formatDistance(d)} verso ${compass(pos.latitude, pos.longitude, lat, lng)}, ${formatAge(age)}');
      }
    }
    return LensReport(searched, moves);
  }

  /// Sensore: quanti indizi nascosti (non tuoi) ci sono qui.
  static Future<int> useSensor(String uid, String party, Position? pos) async {
    Map? me;
    if (kTableMode) {
      me = await _pos(uid);
      if (me == null) throw Exception('Posizione non disponibile');
    } else if (pos == null) {
      throw Exception('Posizione non disponibile');
    }
    await _consume(uid, ItemId.sensore);
    final q = await PartyService.party(party).collection('clues').where('status', isEqualTo: 'hidden').get();
    var n = 0;
    for (final d in q.docs) {
      final c = d.data();
      final pl = c['place'] as Map?;
      if (c['ownerUid'] == uid || pl == null) continue;
      final here = kTableMode
          ? pl['zone'] == me!['zone'] && pl['sector'] == me['sector']
          : distanceMeters(pos!.latitude, pos.longitude, (pl['lat'] as num).toDouble(), (pl['lng'] as num).toDouble()) <=
              kSensorRadiusMeters;
      if (here) n++;
    }
    return n;
  }

  /// Allarme: come la Trappola, ma non blocca: avvisa solo chi l'ha piazzato.
  static Future<void> placeAlarm(String uid, String party, Position? pos) async {
    Map<String, dynamic> where;
    if (kTableMode) {
      final p = await _pos(uid);
      if (p == null) throw Exception('Posizione non disponibile');
      where = {'zone': p['zone'], 'sector': p['sector']};
    } else {
      if (pos == null) throw Exception('Posizione non disponibile');
      where = {'lat': pos.latitude, 'lng': pos.longitude};
    }
    await _consume(uid, ItemId.allarme);
    await PartyService.party(party).collection('alarms').add({
      'ownerUid': uid,
      ...where,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Un giocatore passa su un Allarme altrui: scatta una volta e avvisa il proprietario.
  static Future<bool> triggerAlarm(String party, String alarmId, String intruder) async {
    final ref = PartyService.party(party).collection('alarms').doc(alarmId);
    Map<String, dynamic>? fired;
    await _db.runTransaction<void>((tx) async {
      final a = (await tx.get(ref)).data();
      final me = (await tx.get(userRef(intruder))).data();
      if (a == null || a['active'] != true || a['ownerUid'] == intruder) return;
      if (isActive(me?['stealthUntil'])) return; // Passo felpato
      tx.update(ref, {'active': false, 'triggeredBy': intruder});
      fired = a;
    });
    if (fired == null) return false;
    await PartyService.party(party).collection('events').add({
      'type': 'alarm',
      'ownerUid': fired!['ownerUid'],
      'uid': intruder,
      if (fired!['zone'] != null) 'zone': fired!['zone'],
      if (fired!['sector'] != null) 'sector': fired!['sector'],
      if (fired!['lat'] != null) 'lat': fired!['lat'],
      if (fired!['lng'] != null) 'lng': fired!['lng'],
      'at': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Radar meteo: eventi di zona in arrivo nei prossimi [kWeatherLookahead] giri.
  static Future<List<String>> useWeather(String uid, String party) async {
    await _consume(uid, ItemId.meteo);
    final snap = await TableService.eventsCol(party).get();
    final round = TableClock.round;
    final rows = <MapEntry<int, String>>[];
    for (final d in snap.docs) {
      final e = d.data();
      final start = (e['startRound'] as num?)?.toInt() ?? 0;
      if (e['status'] == 'ended' || e['status'] == 'active') continue;
      if (start <= round || start > round + kWeatherLookahead) continue;
      final inN = start - round;
      rows.add(MapEntry(start,
          '${e['name']} — ${zoneSpec('${e['zone']}').name}, tra $inN ${inN == 1 ? 'giro' : 'giri'} (giro $start)'));
    }
    rows.sort((a, b) => a.key.compareTo(b.key));
    return rows.map((r) => r.value).toList();
  }

  /// Zona protetta da un'Ombrello di bioma attivo (null se nessuna).
  static String? shieldZone(Map<String, dynamic>? user) {
    final s = user?['shield'];
    if (s is Map && isActive(s['until'])) return s['zone'] as String?;
    return null;
  }

  static Future<void> useShield(String uid, ItemId id) => _consume(uid, id, effect: (u) {
        final zone = itemDef(id).zone!;
        if (shieldZone(u) == zone) throw Exception('Protezione già attiva');
        return {
          'shield': {'zone': zone, 'until': TableClock.round + kShieldRounds - 1},
        };
      });

  static Future<void> useStealth(String uid) => _consume(uid, ItemId.passoFelpato, effect: (u) {
        if (isActive(u['stealthUntil'])) throw Exception('Passo felpato già attivo');
        return {'stealthUntil': until(minutes: kStealthMinutes, rounds: kStealthRounds)};
      });

  /// Clessidra: al tavolo altre azioni subito (solo nel tuo turno), dal vivo azzera le attese.
  static Future<void> useHourglass(String uid, String party) async {
    if (!kTableMode) {
      final u = (await userRef(uid).get()).data();
      if (LiveService.left(u?['busyUntil']) == null && LiveService.left(u?['searchReadyAt']) == null) {
        throw Exception('Non hai attese da azzerare');
      }
      await _consume(uid, ItemId.clessidra);
      await LiveService.clearWaits(uid);
      return;
    }
    await TableService.assertMyTurn(party, uid);
    await _consume(uid, ItemId.clessidra);
    await TableService.grantActions(party, uid);
  }

  /// Chiave: sblocca un settore bloccato nella tua zona.
  static Future<void> useKey(String uid, String party, int sector) async {
    final p = await _pos(uid);
    if (p == null) throw Exception('Posizione non disponibile');
    final events = await TableService.activeEvents(party);
    final ev = events.where((e) => e['zone'] == p['zone'] && ((e['blocked'] as List?) ?? []).contains(sector)).toList();
    if (ev.isEmpty) throw Exception('Quel settore non è bloccato');
    await _consume(uid, ItemId.chiave);
    await TableService.eventsCol(party).doc(ev.first['id'] as String).update({
      'blocked': FieldValue.arrayRemove([sector]),
    });
  }
}

/// Risultato della Lente.
class LensReport {
  final List<String> searched; // zone/settori già battuti
  final List<String> moves; // direzioni degli altri giocatori
  const LensReport(this.searched, this.moves);
}
