import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../items.dart';
import '../mode.dart';
import '../table/events.dart';
import '../table/type_chart.dart';
import '../table/zones.dart';
import 'gym_service.dart';
import 'item_service.dart';
import 'party_service.dart';

/// Partita da tavolo: turni, azioni, posizione per zona/settore ed eventi di zona.
///
/// Firestore:
///   Party/{codice}/table/state        -> { started, round, order[], idx, actionsPerTurn, actionsLeft }
///   Party/{codice}/zoneEvents/{id}    -> { defId, zone, name, status, announceRound, startRound, endRound,
///                                          blocked[], claimedBy[], legendary, leader?, legendaryName?, defeatedBy? }
///   Party/{codice}/traps/{id}         -> { ownerUid, zone, sector, active }
///   Party/{codice}/events/{id}        -> { type:'bell', uid, zone, sector, at }
///   Users/{uid}.pos                   -> { zone, sector }      (posizione dichiarata)
///   Users/{uid}.trappedSkip           -> turni da saltare per una Trappola
///   Users/{uid}.actionPenalty         -> azioni perse al prossimo turno (es. eruzione)
class TableService {
  static final _db = FirebaseFirestore.instance;
  static final _rnd = Random();

  static DocumentReference<Map<String, dynamic>> stateRef(String party) =>
      PartyService.party(party).collection('table').doc('state');
  static CollectionReference<Map<String, dynamic>> eventsCol(String party) =>
      PartyService.party(party).collection('zoneEvents');
  static CollectionReference<Map<String, dynamic>> trapsCol(String party) =>
      PartyService.party(party).collection('traps');

  static Stream<Map<String, dynamic>?> watchState(String party) =>
      stateRef(party).snapshots().map((s) => s.data());
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchEvents(String party) => eventsCol(party).snapshots();

  static int _i(dynamic v, [int d = 0]) => v is num ? v.toInt() : d;

  // ------------------------------------------------------------ database

  /// In un Firestore nuovo la collezione "Tipi" è vuota: la riempie con la tabella dei tipi.
  static Future<void> seedTypesIfMissing() async {
    final any = await _db.collection('Tipi').limit(1).get();
    if (any.docs.isNotEmpty) return;
    final batch = _db.batch();
    kTypeWeak.forEach((t, weak) {
      batch.set(_db.collection('Tipi').doc(t), {
        'Debolezze': weak,
        'Resistenze': kTypeResist[t] ?? [],
        'altStatus': '',
        'altStatusName': '',
      });
    });
    await batch.commit();
  }

  // ------------------------------------------------------------- partita

  /// Avvia (o riavvia) la partita: ordine dei turni casuale, tutti nell'Hub, eventi pianificati.
  static Future<void> startGame(String party) async {
    final players = await PartyService.players(party).get();
    if (players.docs.length < 2) throw Exception('Servono almeno 2 giocatori nel party');
    await seedTypesIfMissing();
    final order = players.docs.map((d) => d.id).toList()..shuffle(_rnd);
    final per = order.length.isOdd ? kActionsOdd : kActionsEven;

    final batch = _db.batch();
    for (final d in (await eventsCol(party).get()).docs) {
      batch.delete(d.reference);
    }
    for (final d in (await trapsCol(party).get()).docs) {
      batch.delete(d.reference);
    }
    batch.set(stateRef(party), {
      'started': true,
      'round': 1,
      'order': order,
      'idx': 0,
      'actionsPerTurn': per,
      'actionsLeft': per,
      'startedAt': FieldValue.serverTimestamp(),
    });
    for (final uid in order) {
      batch.set(
        ItemService.userRef(uid),
        {
          'pos': {'zone': 'hub', 'sector': 1},
          'trappedSkip': 0,
          'actionPenalty': 0,
          // effetti di partite precedenti (i giri ripartono da 1)
          'repellentUntil': FieldValue.delete(),
          'koUntil': FieldValue.delete(),
          'trappedUntil': FieldValue.delete(),
          'fleeBlocks': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    }
    for (final e in _schedule()) {
      batch.set(eventsCol(party).doc(), e);
    }
    await batch.commit();
    TableClock.round = 1;
  }

  /// Sceglie a caso gli eventi e i giri in cui partono.
  static List<Map<String, dynamic>> _schedule() {
    final pool = [...kZoneEventDefs]..shuffle(_rnd);
    final chosen = pool.take(kEventsPerGame).toList();
    final defs = [...chosen, kLegendaryDef];
    final starts = [for (var i = 0; i < defs.length; i++) kFirstEventRound + i * kEventGap]..shuffle(_rnd);
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < defs.length; i++) {
      final d = defs[i];
      final start = starts[i];
      final zone = d.legendary ? (kZones.where((z) => z.id != 'hub').toList()..shuffle(_rnd)).first.id : d.zone;
      out.add({
        'defId': d.id,
        'zone': zone,
        'name': d.name,
        'status': 'scheduled',
        'announceRound': start - 1,
        'startRound': start,
        'endRound': start + d.duration - 1,
        'blocked': <int>[],
        'claimedBy': <String>[],
        'legendary': d.legendary,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return out;
  }

  // -------------------------------------------------------------- turni

  static void _checkTurn(Map<String, dynamic>? s, String uid) {
    if (s == null || s['started'] != true) throw Exception('La partita non è ancora iniziata');
    final order = List<String>.from(s['order'] as List);
    if (order[_i(s['idx'])] != uid) throw Exception('Non è il tuo turno');
  }

  /// Consuma [cost] azioni del giocatore di turno (ed eventualmente sposta la pedina).
  static Future<void> _spend(String party, String uid, int cost, {Map<String, dynamic>? setPos}) {
    final ref = stateRef(party);
    return _db.runTransaction<void>((tx) async {
      final s = (await tx.get(ref)).data();
      _checkTurn(s, uid);
      final left = _i(s!['actionsLeft']);
      if (left < cost) throw Exception('Azioni insufficienti: servono $cost, ne hai $left');
      tx.update(ref, {'actionsLeft': left - cost});
      if (setPos != null) {
        tx.set(ItemService.userRef(uid), {'pos': setPos}, SetOptions(merge: true));
      }
    });
  }

  /// "Ho usato un'azione" (cercare, raccogliere, indagare... azioni fatte al tavolo).
  static Future<void> spendAction(String party, String uid) => _spend(party, uid, 1);

  /// Fine turno: passa al giocatore successivo, saltando chi è in trappola.
  /// A fine giro avanza il contatore e aggiorna gli eventi di zona.
  static Future<void> endTurn(String party, String uid) async {
    final ref = stateRef(party);
    var roundAdvanced = false;
    var newRound = 0;
    await _db.runTransaction<void>((tx) async {
      final s = (await tx.get(ref)).data();
      _checkTurn(s, uid);
      final order = List<String>.from(s!['order'] as List);
      final per = _i(s['actionsPerTurn']);
      var idx = _i(s['idx']) + 1;
      var round = _i(s['round']);
      roundAdvanced = false;
      final writes = <MapEntry<DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>>[];
      var left = per;
      var guard = 0;
      while (true) {
        if (idx >= order.length) {
          idx = 0;
          round++;
          roundAdvanced = true;
        }
        final u = (await tx.get(ItemService.userRef(order[idx]))).data() ?? {};
        final skip = _i(u['trappedSkip']);
        if (skip > 0 && guard < order.length * 2) {
          writes.add(MapEntry(ItemService.userRef(order[idx]), {'trappedSkip': skip - 1}));
          idx++;
          guard++;
          continue;
        }
        final pen = _i(u['actionPenalty']);
        if (pen > 0) {
          left = max(0, per - pen);
          writes.add(MapEntry(ItemService.userRef(order[idx]), {'actionPenalty': 0}));
        }
        break;
      }
      for (final w in writes) {
        tx.set(w.key, w.value, SetOptions(merge: true));
      }
      tx.update(ref, {'idx': idx, 'round': round, 'actionsLeft': left});
      newRound = round;
    });
    if (roundAdvanced) {
      TableClock.round = newRound;
      await advanceEvents(party, newRound);
    }
  }

  // ------------------------------------------------------------ spostamenti

  static Future<List<Map<String, dynamic>>> activeEvents(String party) async {
    final q = await eventsCol(party).where('status', isEqualTo: 'active').get();
    return [for (final d in q.docs) {...d.data(), 'id': d.id}];
  }

  /// Costo (in azioni) di uno spostamento verso [zone], dati gli eventi attivi.
  static int moveCost(List<Map<String, dynamic>> events, String? fromZone, String zone) {
    var cost = kMoveActionCost;
    if (fromZone != zone) {
      for (final e in events) {
        if (e['zone'] == zone && e['status'] == 'active') cost += eventDef(e['defId'] as String).moveExtra;
      }
    }
    return cost;
  }

  static Set<int> blockedSectors(List<Map<String, dynamic>> events, String zone) => {
        for (final e in events)
          if (e['zone'] == zone && e['status'] == 'active')
            for (final b in (e['blocked'] as List? ?? [])) _i(b),
      };

  /// Sposta la pedina. Restituisce un messaggio se succede qualcosa (es. trappola).
  static Future<String?> moveTo({
    required String party,
    required String uid,
    required String zone,
    required int sector,
  }) async {
    final spec = zoneSpec(zone);
    if (sector < 1 || sector > spec.sectors) throw Exception('Settore non valido');
    final events = await activeEvents(party);
    if (blockedSectors(events, zone).contains(sector)) {
      throw Exception('Il settore $sector di ${spec.name} è bloccato');
    }
    final cur = ((await ItemService.userRef(uid).get()).data()?['pos']) as Map?;
    if (cur?['zone'] == zone && _i(cur?['sector']) == sector) throw Exception('Sei già in questo settore');
    final cost = moveCost(events, cur?['zone'] as String?, zone);
    await _spend(party, uid, cost, setPos: {'zone': zone, 'sector': sector});
    if (await _checkTrap(party, uid, zone, sector)) {
      return 'Sei finito in una Trappola! Salterai il prossimo turno, a meno di usare una Fune di fuga.';
    }
    return null;
  }

  static Future<bool> _checkTrap(String party, String uid, String zone, int sector) async {
    final q = await trapsCol(party)
        .where('active', isEqualTo: true)
        .where('zone', isEqualTo: zone)
        .where('sector', isEqualTo: sector)
        .get();
    for (final t in q.docs) {
      if (t.data()['ownerUid'] == uid) continue;
      final hit = await _db.runTransaction<bool>((tx) async {
        final d = (await tx.get(t.reference)).data();
        if (d == null || d['active'] != true) return false;
        tx.update(t.reference, {'active': false, 'triggeredBy': uid});
        tx.set(ItemService.userRef(uid), {'trappedSkip': FieldValue.increment(1)}, SetOptions(merge: true));
        return true;
      });
      if (hit) return true;
    }
    return false;
  }

  /// Zone dove il Radar non vede nessuno (es. nebbia).
  static Future<Set<String>> radarHiddenZones(String party) async => {
        for (final e in await activeEvents(party))
          if (eventDef(e['defId'] as String).hideRadar) e['zone'] as String,
      };

  /// Bonus di danno per tipo di mossa nella zona del giocatore (chiavi in minuscolo).
  static Future<Map<String, int>> zoneBonusFor(String? party, String uid) async {
    if (!kTableMode || party == null) return {};
    final pos = (await ItemService.userRef(uid).get()).data()?['pos'] as Map?;
    final zone = pos?['zone'];
    if (zone == null) return {};
    final out = <String, int>{};
    for (final e in await activeEvents(party)) {
      if (e['zone'] != zone) continue;
      eventDef(e['defId'] as String).typeBonus.forEach((t, b) {
        out[t.toLowerCase()] = (out[t.toLowerCase()] ?? 0) + b;
      });
    }
    return out;
  }

  // ---------------------------------------------------------- eventi di zona

  /// Chiamata a ogni nuovo giro: annuncia, avvia e chiude gli eventi.
  static Future<void> advanceEvents(String party, int round) async {
    final snap = await eventsCol(party).get();
    for (final d in snap.docs) {
      final e = d.data();
      final status = e['status'] as String? ?? 'scheduled';
      final ann = _i(e['announceRound']), start = _i(e['startRound']), end = _i(e['endRound']);
      if (status == 'ended') continue;
      if (round > end) {
        await d.reference.update({'status': 'ended'});
      } else if (round >= start && status != 'active') {
        await _activate(party, d);
      } else if (status == 'scheduled' && round >= ann && round < start) {
        await d.reference.update({'status': 'announced'});
      }
    }
  }

  static Future<void> _activate(String party, QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final e = d.data();
    final def = eventDef(e['defId'] as String);
    final zone = e['zone'] as String;
    final spec = zoneSpec(zone);
    final update = <String, dynamic>{'status': 'active'};

    if (def.blockSectors > 0) {
      final all = List<int>.generate(spec.sectors, (i) => i + 1)..shuffle(_rnd);
      update['blocked'] = all.take(min(def.blockSectors, spec.sectors - 1)).toList()..sort();
    }
    if (def.legendary) {
      final name = spec.legendaries[_rnd.nextInt(spec.legendaries.length)];
      update['leader'] = await GymService.generateLeader(spec.type, legendary: true, pokemon: name);
      update['legendaryName'] = name;
    }
    await d.reference.update(update);

    if (def.actionPenalty > 0) {
      final players = await PartyService.players(party).get();
      for (final p in players.docs) {
        final pos = (await ItemService.userRef(p.id).get()).data()?['pos'] as Map?;
        if (pos?['zone'] == zone) {
          await ItemService.userRef(p.id)
              .set({'actionPenalty': FieldValue.increment(def.actionPenalty)}, SetOptions(merge: true));
        }
      }
    }
  }

  /// Mercato / raccolto: una volta sola, chi è nella zona prende uno strumento a caso.
  static Future<String> claimEventItem(String party, String eventId, String uid) async {
    final ref = eventsCol(party).doc(eventId);
    final uref = ItemService.userRef(uid);
    late String got;
    await _db.runTransaction<void>((tx) async {
      final e = (await tx.get(ref)).data();
      final u = (await tx.get(uref)).data() ?? {};
      if (e == null || e['status'] != 'active') throw Exception('L’evento non è più attivo');
      final def = eventDef(e['defId'] as String);
      if (!def.claimItem) throw Exception('Questo evento non regala strumenti');
      if ((u['pos'] as Map?)?['zone'] != e['zone']) throw Exception('Devi essere nella zona dell’evento');
      final claimed = List<String>.from(e['claimedBy'] as List? ?? []);
      if (claimed.contains(uid)) throw Exception('Hai già preso il tuo strumento');
      final pool = def.claimPool ?? ItemId.values.map((i) => i.name).toList();
      final id = pool[_rnd.nextInt(pool.length)];
      final inv = ItemService.readInventory(u);
      inv[id] = (inv[id] ?? 0) + 1;
      tx.update(ref, {'claimedBy': [...claimed, uid]});
      tx.set(uref, {'inventory': inv}, SetOptions(merge: true));
      got = itemDef(ItemId.values.firstWhere((i) => i.name == id)).name;
    });
    return got;
  }

  /// Sfida al leggendario risvegliato (stessa meccanica dei capipalestra).
  static Future<String> challengeLegendary({
    required String party,
    required String eventId,
    required String uid,
    required String pk,
    required Future<String> Function(Map<String, dynamic> gym, Map<String, dynamic> extra) createBattle,
  }) async {
    final e = (await eventsCol(party).doc(eventId).get()).data();
    if (e == null || e['status'] != 'active' || e['legendary'] != true) {
      throw Exception('Il leggendario non è più qui');
    }
    if (e['defeatedBy'] != null) throw Exception('Il leggendario è già stato sconfitto');
    final pos = (await ItemService.userRef(uid).get()).data()?['pos'] as Map?;
    if (pos?['zone'] != e['zone']) throw Exception('Devi essere in ${zoneSpec(e['zone'] as String).name}');
    final spec = zoneSpec(e['zone'] as String);
    return createBattle(
      {'name': e['legendaryName'] ?? 'Leggendario', 'type': spec.type, 'leader': e['leader']},
      {'legendary': true, 'eventId': eventId},
    );
  }

  /// Ricompensa al primo che batte il leggendario: 2 strumenti a caso. Restituisce il testo.
  static Future<String?> rewardLegendary(String party, String eventId, String uid) async {
    final ref = eventsCol(party).doc(eventId);
    final uref = ItemService.userRef(uid);
    String? text;
    await _db.runTransaction<void>((tx) async {
      final e = (await tx.get(ref)).data();
      final u = (await tx.get(uref)).data() ?? {};
      if (e == null || e['defeatedBy'] != null) return;
      final inv = ItemService.readInventory(u);
      final names = <String>[];
      for (var i = 0; i < 2; i++) {
        final id = ItemId.values[_rnd.nextInt(ItemId.values.length)];
        inv[id.name] = (inv[id.name] ?? 0) + 1;
        names.add(itemDef(id).name);
      }
      tx.update(ref, {'defeatedBy': uid, 'status': 'ended'});
      tx.set(uref, {'inventory': inv}, SetOptions(merge: true));
      text = 'Leggendario sconfitto! Ricompensa: ${names.join(' e ')}';
    });
    return text;
  }
}
