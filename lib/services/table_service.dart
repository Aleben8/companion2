import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../items.dart';
import '../mode.dart';
import '../table/events.dart';
import '../table/type_chart.dart';
import '../table/zones.dart';
import 'gym_service.dart';
import 'item_service.dart';
import 'live_service.dart';
import 'party_service.dart';

/// Esito di [TableService.routeTo].
enum MoveRoute { direct, passage, ticket }

/// Partita a zone: turni, azioni, posizione per zona/settore ed eventi di zona.
/// La stessa partita si gioca anche dal vivo (vedi [LiveService]): niente turni, il giro avanza
/// da solo ogni N minuti e la posizione arriva dal GPS.
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

  /// Avvia (o riavvia) la partita nella modalità corrente del party.
  /// Tavolo: ordine dei turni casuale, tutti nell'Hub. Dal vivo: parte l'orologio dei giri e
  /// la posizione arriva dal GPS (servono tutte le zone posizionate sulla mappa).
  /// In entrambi i casi gli eventi di zona vengono pianificati.
  static Future<void> startGame(String party, {bool manualEvents = false}) async {
    final live = !kTableMode;
    final players = await PartyService.players(party).get();
    if (players.docs.length < 2) throw Exception('Servono almeno 2 giocatori nel party');
    if (live) {
      final miss = LiveService.missing(await LiveService.zones(party));
      if (miss.isNotEmpty) {
        throw Exception('Posiziona prima tutte le zone sulla mappa (mancano: ${miss.map((z) => z.name).join(', ')})');
      }
    }
    await seedTypesIfMissing();
    final order = players.docs.map((d) => d.id).toList()..shuffle(_rnd);
    final per = order.length.isOdd ? kActionsOdd : kActionsEven;
    final links = await partyLinks(party);
    final minutes = await roundMinutes(party);

    final batch = _db.batch();
    for (final d in (await eventsCol(party).get()).docs) {
      batch.delete(d.reference);
    }
    for (final d in (await trapsCol(party).get()).docs) {
      batch.delete(d.reference);
    }
    for (final name in ['alarms', 'traces', 'trades']) {
      for (final d in (await PartyService.party(party).collection(name).get()).docs) {
        batch.delete(d.reference);
      }
    }
    batch.set(stateRef(party), {
      'started': true,
      'round': 1,
      'order': order,
      'idx': 0,
      'actionsPerTurn': per,
      'actionsLeft': per,
      'eventMode': manualEvents ? 'manual' : 'auto',
      'links': links.toList(),
      'roundMinutes': minutes,
      'roundStartedAt': Timestamp.now(),
      'startedAt': FieldValue.serverTimestamp(),
    });
    for (final uid in order) {
      batch.set(
        ItemService.userRef(uid),
        {
          // dal vivo la posizione la scrive il GPS appena entri in una zona
          'pos': live ? FieldValue.delete() : {'zone': 'hub', 'sector': 1},
          'busyUntil': FieldValue.delete(),
          'searchReadyAt': FieldValue.delete(),
          'trappedSkip': 0,
          'actionPenalty': 0,
          // effetti di partite precedenti (i giri ripartono da 1)
          'repellentUntil': FieldValue.delete(),
          'koUntil': FieldValue.delete(),
          'trappedUntil': FieldValue.delete(),
          'fleeBlocks': FieldValue.delete(),
          'stealthUntil': FieldValue.delete(),
          'shield': FieldValue.delete(),
          'coins': kStartingCoins,
        },
        SetOptions(merge: true),
      );
    }
    if (!manualEvents) {
      for (final e in _schedule()) {
        batch.set(eventsCol(party).doc(), e);
      }
    }
    await batch.commit();
    TableClock.round = 1;
  }

  /// Eventi disponibili nella modalità corrente: dal vivo niente treno/traghetto
  /// (ci si sposta a piedi, i collegamenti tra zone non ci sono).
  static List<ZoneEventDef> get availableEvents =>
      [for (final d in kZoneEventDefs) if (kTableMode || !d.passage) d];

  /// Sceglie a caso gli eventi e i giri in cui partono.
  static List<Map<String, dynamic>> _schedule({int base = 1}) {
    final pool = [...availableEvents]..shuffle(_rnd);
    final chosen = pool.take(kEventsPerGame).toList();
    final defs = [...chosen, kLegendaryDef];
    final starts = [for (var i = 0; i < defs.length; i++) kFirstEventRound - 1 + base + i * kEventGap]..shuffle(_rnd);
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

  // ------------------------------------------------- collegamenti tra zone

  static String linkKey(String a, String b) => ([a, b]..sort()).join('|');

  static Set<String> get defaultLinks => {for (final l in kDefaultLinks) linkKey(l[0], l[1])};

  /// Collegamenti scelti dal Master per il party (se non ne ha scelti, la proposta di [kDefaultLinks]).
  static Future<Set<String>> partyLinks(String party) async {
    final raw = (await PartyService.party(party).get()).data()?['zoneLinks'];
    return raw is List ? raw.map((e) => e.toString()).toSet() : defaultLinks;
  }

  /// Collegamenti in uso nella partita (dallo stato; altrimenti la proposta).
  static Set<String> linksOf(Map<String, dynamic>? state) {
    final raw = state?['links'];
    return raw is List ? raw.map((e) => e.toString()).toSet() : defaultLinks;
  }

  /// Il Master salva i collegamenti: valgono dalla prossima partita e, se la partita è in corso, subito.
  static Future<void> setLinks(String party, Set<String> links) async {
    final list = links.toList()..sort();
    await PartyService.party(party).set({'zoneLinks': list}, SetOptions(merge: true));
    final st = (await stateRef(party).get()).data();
    if (st != null && st['started'] == true) await stateRef(party).update({'links': list});
  }

  // ------------------------------------------------------ modalità e orologio

  /// Il Master cambia modalità (anche a partita in corso). Lo stato si adatta:
  ///  - verso il live: l'orologio riparte dal giro corrente, trappole e azioni perse diventano attese;
  ///  - verso il tavolo: se manca, si crea l'ordine dei turni; chi non è in una zona torna all'Hub.
  static Future<void> switchMode(String party, String mode) async {
    // AppMode.current lo aggiorna ModeService quando arriva il cambio (così la home si ricostruisce)
    await PartyService.setMode(party, mode);
    final st = (await stateRef(party).get()).data();
    if (st == null || st['started'] != true) return;
    final players = (await PartyService.players(party).get()).docs.map((d) => d.id).toList();
    final batch = _db.batch();
    if (mode == kModeLive) {
      batch.update(stateRef(party), {
        'roundMinutes': _i(st['roundMinutes'], await roundMinutes(party)),
        'roundStartedAt': Timestamp.now(),
      });
      // treno e traghetto non servono a piedi
      for (final d in (await eventsCol(party).get()).docs) {
        final e = d.data();
        if (e['status'] != 'ended' && eventDef(e['defId'] as String).passage) batch.update(d.reference, {'status': 'ended'});
      }
      for (final uid in players) {
        final u = (await ItemService.userRef(uid).get()).data() ?? {};
        final skip = _i(u['trappedSkip']), pen = _i(u['actionPenalty']);
        batch.set(
            ItemService.userRef(uid),
            {
              'trappedSkip': 0,
              'actionPenalty': 0,
              if (skip > 0) 'trappedUntil': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: kTrapPenaltyMinutes))),
              if (pen > 0) ...LiveService.addBusy(u, pen * kLivePenaltyMinutes),
            },
            SetOptions(merge: true));
      }
    } else {
      final order = st['order'] is List ? List<String>.from(st['order'] as List) : <String>[];
      order.removeWhere((p) => !players.contains(p));
      for (final p in players) {
        if (!order.contains(p)) order.add(p);
      }
      if (st['order'] is! List) order.shuffle(_rnd);
      final per = order.length.isOdd ? kActionsOdd : kActionsEven;
      batch.update(stateRef(party), {
        'order': order,
        'idx': _i(st['idx']) < order.length ? _i(st['idx']) : 0,
        'actionsPerTurn': per,
        if (st['actionsLeft'] == null || st['order'] is! List) 'actionsLeft': per,
      });
      for (final uid in players) {
        final u = (await ItemService.userRef(uid).get()).data() ?? {};
        if (u['pos'] is! Map) batch.set(ItemService.userRef(uid), {'pos': {'zone': 'hub', 'sector': 1}}, SetOptions(merge: true));
      }
    }
    await batch.commit();
  }

  /// Durata di un giro dal vivo, scelta dal Master.
  static Future<int> roundMinutes(String party) async {
    final v = (await PartyService.party(party).get()).data()?['roundMinutes'];
    return v is num && v > 0 ? v.toInt() : kDefaultRoundMinutes;
  }

  /// Il Master cambia la durata del giro: vale subito (se la partita è in corso) e per le prossime.
  static Future<void> setRoundMinutes(String party, int minutes) async {
    await PartyService.party(party).set({'roundMinutes': minutes}, SetOptions(merge: true));
    final st = (await stateRef(party).get()).data();
    if (st != null && st['started'] == true) await stateRef(party).update({'roundMinutes': minutes});
  }

  /// Quando parte il prossimo giro dal vivo (null se l'orologio non c'è).
  static DateTime? nextRoundAt(Map<String, dynamic>? st) {
    final at = st?['roundStartedAt'];
    if (at is! Timestamp) return null;
    return at.toDate().add(Duration(minutes: _i(st!['roundMinutes'], kDefaultRoundMinutes)));
  }

  /// Dal vivo: se il giro è scaduto lo fa avanzare (una transazione, quindi lo fa un solo telefono)
  /// e aggiorna gli eventi di zona. Restituisce il nuovo giro, o null se non è cambiato.
  static Future<int?> tickLive(String party) async {
    final ref = stateRef(party);
    final round = await _db.runTransaction<int?>((tx) async {
      final s = (await tx.get(ref)).data();
      if (s == null || s['started'] != true) return null;
      final at = s['roundStartedAt'];
      if (at is! Timestamp) {
        tx.update(ref, {'roundStartedAt': Timestamp.now()});
        return null;
      }
      final mins = _i(s['roundMinutes'], kDefaultRoundMinutes);
      final n = DateTime.now().difference(at.toDate()).inSeconds ~/ (mins * 60);
      if (n <= 0) return null;
      final r = _i(s['round'], 1) + n;
      tx.update(ref, {
        'round': r,
        'roundStartedAt': Timestamp.fromDate(at.toDate().add(Duration(minutes: mins * n))),
      });
      return r;
    });
    if (round == null) return null;
    TableClock.round = round;
    await advanceEvents(party, round);
    return round;
  }

  /// Dal vivo: il GPS ha cambiato zona/settore. Entrare in una zona con bufera/eruzione costa un'attesa.
  static Future<void> updateLivePos(String uid, Map<String, dynamic>? pos, {String? party}) async {
    final ref = ItemService.userRef(uid);
    final me = (await ref.get()).data();
    final cur = me?['pos'] as Map?;
    if (cur?['zone'] == pos?['zone'] && _i(cur?['sector']) == _i(pos?['sector'])) return;
    final update = <String, dynamic>{'pos': pos ?? FieldValue.delete()};
    final zone = pos?['zone'] as String?;
    if (party != null && zone != null && cur?['zone'] != zone && ItemService.shieldZone(me) != zone) {
      final extra = moveCost(await activeEvents(party), cur?['zone'] as String?, zone) - kMoveActionCost;
      if (extra > 0) update.addAll(LiveService.addBusy(me, extra * kLiveEnterWaitMinutes));
    }
    await ref.set(update, SetOptions(merge: true));
  }

  /// Come si va da [from] a [to]: stessa zona, collegamento diretto, passaggio di un evento
  /// (treno/traghetto) o solo con un Biglietto.
  static MoveRoute routeTo(Map<String, dynamic>? state, List<Map<String, dynamic>> events, String? from, String to) {
    if (from == null || from == to) return MoveRoute.direct;
    if (linksOf(state).contains(linkKey(from, to))) return MoveRoute.direct;
    for (final e in events) {
      if (e['status'] == 'active' && e['zone'] == from && eventDef(e['defId'] as String).passage) {
        return MoveRoute.passage;
      }
    }
    return MoveRoute.ticket;
  }

  // ------------------------------------------------------ eventi: auto / manuale

  /// Giro da cui un evento annunciato a mano "aspetta" il Master (non parte da solo).
  static const int kManualStart = 9999;

  static bool isManual(Map<String, dynamic>? state) => state?['eventMode'] == 'manual';

  /// Il Master passa da eventi automatici a manuali (e viceversa) durante la partita.
  /// Auto: pianifica nuovi eventi a partire dal giro corrente. Manuale: toglie quelli non ancora annunciati.
  /// Gli eventi già in corso restano.
  static Future<void> setEventMode(String party, {required bool manual}) async {
    final st = (await stateRef(party).get()).data();
    if (st == null || st['started'] != true) throw Exception('La partita non è iniziata');
    final round = _i(st['round'], 1);
    final batch = _db.batch();
    for (final d in (await eventsCol(party).get()).docs) {
      final status = d.data()['status'];
      if (status == 'scheduled' || (!manual && status == 'announced')) batch.delete(d.reference);
    }
    if (!manual) {
      for (final e in _schedule(base: round)) {
        batch.set(eventsCol(party).doc(), e);
      }
    }
    batch.update(stateRef(party), {'eventMode': manual ? 'manual' : 'auto'});
    await batch.commit();
  }

  /// Manuale: il Master inserisce l'evento della carta pescata. [zone] serve solo per il leggendario.
  /// Con [activateNow] l'evento parte subito, altrimenti viene solo annunciato.
  static Future<void> createManualEvent(String party, String defId,
      {String? zone, required bool activateNow}) async {
    final st = (await stateRef(party).get()).data();
    if (st == null || st['started'] != true) throw Exception('La partita non è iniziata');
    final def = eventDef(defId);
    final z = def.legendary ? zone : def.zone;
    if (z == null || z.isEmpty) throw Exception('Scegli la zona');
    final round = _i(st['round'], 1);
    final ref = eventsCol(party).doc();
    await ref.set({
      'defId': def.id,
      'zone': z,
      'name': def.name,
      'status': 'announced',
      'announceRound': round,
      'startRound': kManualStart,
      'endRound': kManualStart + def.duration - 1,
      'blocked': <int>[],
      'claimedBy': <String>[],
      'legendary': def.legendary,
      'manual': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (activateNow) await activateEvent(party, ref.id);
  }

  /// Manuale: fa partire un evento annunciato (applica subito i suoi effetti).
  static Future<void> activateEvent(String party, String eventId) async {
    final st = (await stateRef(party).get()).data();
    final round = _i(st?['round'], 1);
    final ref = eventsCol(party).doc(eventId);
    final e = (await ref.get()).data();
    if (e == null) throw Exception('Evento non trovato');
    if (e['status'] == 'active') throw Exception('L’evento è già in corso');
    final def = eventDef(e['defId'] as String);
    await ref.update({'startRound': round, 'endRound': round + def.duration - 1});
    await _activate(party, await ref.get());
    // lo stato resta in sincronia con il giro corrente
    TableClock.round = round;
  }

  /// Manuale: chiude subito un evento (in corso o annunciato).
  static Future<void> endEvent(String party, String eventId) =>
      eventsCol(party).doc(eventId).update({'status': 'ended'});

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
  static int moveCost(List<Map<String, dynamic>> events, String? fromZone, String zone, {String? shield}) {
    var cost = kMoveActionCost;
    if (fromZone != zone && shield != zone) {
      for (final e in events) {
        if (e['zone'] == zone && e['status'] == 'active') cost += eventDef(e['defId'] as String).moveExtra;
      }
    }
    return cost;
  }

  static Set<int> blockedSectors(List<Map<String, dynamic>> events, String zone, {String? shield}) => shield == zone
      ? <int>{}
      : {
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
    bool useTicket = false,
  }) async {
    final spec = zoneSpec(zone);
    if (sector < 1 || sector > spec.sectors) throw Exception('Settore non valido');
    final events = await activeEvents(party);
    final me = (await ItemService.userRef(uid).get()).data();
    final shield = ItemService.shieldZone(me);
    if (blockedSectors(events, zone, shield: shield).contains(sector)) {
      throw Exception('Il settore $sector di ${spec.name} è bloccato');
    }
    final cur = me?['pos'] as Map?;
    if (cur?['zone'] == zone && _i(cur?['sector']) == sector) throw Exception('Sei già in questo settore');
    final cost = moveCost(events, cur?['zone'] as String?, zone, shield: shield);
    var needTicket = false;
    final route = routeTo((await stateRef(party).get()).data(), events, cur?['zone'] as String?, zone);
    if (route == MoveRoute.ticket) {
      if (!useTicket) throw Exception('${spec.name} non è collegata alla tua zona: serve un Biglietto');
      if ((ItemService.readInventory(me)['biglietto'] ?? 0) <= 0) throw Exception('Non hai Biglietti');
      needTicket = true;
    }
    await _spend(party, uid, cost, setPos: {'zone': zone, 'sector': sector});
    if (needTicket) await ItemService.consume(uid, ItemId.biglietto);
    if (ItemService.isActive(me?['stealthUntil'])) return null; // Passo felpato: niente tracce, trappole o allarmi
    await ItemService.addTrace(party, uid, {
      'kind': 'move',
      'fromZone': cur?['zone'],
      'fromSector': cur?['sector'],
      'zone': zone,
      'sector': sector,
    });
    await _checkAlarms(party, uid, zone, sector);
    if (await _checkTrap(party, uid, zone, sector)) {
      return 'Sei finito in una Trappola! Salterai il prossimo turno, a meno di usare una Fune di fuga.';
    }
    return null;
  }

  static Future<void> _checkAlarms(String party, String uid, String zone, int sector) async {
    final q = await PartyService.party(party)
        .collection('alarms')
        .where('active', isEqualTo: true)
        .where('zone', isEqualTo: zone)
        .where('sector', isEqualTo: sector)
        .get();
    for (final a in q.docs) {
      await ItemService.triggerAlarm(party, a.id, uid);
    }
  }

  /// Controlla (senza modificare nulla) che sia il turno del giocatore.
  static Future<void> assertMyTurn(String party, String uid) async =>
      _checkTurn((await stateRef(party).get()).data(), uid);

  /// Clessidra: aggiunge al turno corrente altre azioni (quante ne ha un turno).
  static Future<void> grantActions(String party, String uid) {
    final ref = stateRef(party);
    return _db.runTransaction<void>((tx) async {
      final s = (await tx.get(ref)).data();
      _checkTurn(s, uid);
      tx.update(ref, {'actionsLeft': _i(s!['actionsLeft']) + _i(s['actionsPerTurn'])});
    });
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
    if (party == null) return {};
    final user = (await ItemService.userRef(uid).get()).data();
    final pos = user?['pos'] as Map?;
    final zone = pos?['zone'];
    if (zone == null || ItemService.shieldZone(user) == zone) return {};
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

  static Future<void> _activate(String party, DocumentSnapshot<Map<String, dynamic>> d) async {
    final e = d.data()!;
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
        final user = (await ItemService.userRef(p.id).get()).data();
        final pos = user?['pos'] as Map?;
        if (pos?['zone'] == zone && ItemService.shieldZone(user) != zone) {
          await ItemService.userRef(p.id).set(
              kTableMode
                  ? {'actionPenalty': FieldValue.increment(def.actionPenalty)}
                  // dal vivo le azioni perse diventano un'attesa
                  : LiveService.addBusy(user, def.actionPenalty * kLivePenaltyMinutes),
              SetOptions(merge: true));
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
      if (!kTableMode) LiveService.assertNotBusy(u);
      final claimed = List<String>.from(e['claimedBy'] as List? ?? []);
      if (claimed.contains(uid)) throw Exception('Hai già preso il tuo strumento');
      final pool = def.claimPool ?? ItemService.dropKeys();
      final id = pool[_rnd.nextInt(pool.length)];
      final inv = ItemService.readInventory(u);
      if (!ItemService.addItem(inv, id)) throw Exception('Borsa piena ($kBagLimit oggetti): fai posto e riprova');
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
        final id = ItemService.randomDrop(rnd: _rnd);
        names.add(ItemService.addItem(inv, id.name) ? itemDef(id).name : '${itemDef(id).name} (borsa piena: perso)');
      }
      tx.update(ref, {'defeatedBy': uid, 'status': 'ended'});
      tx.set(uref, {'inventory': inv, 'coins': ItemService.coinsOf(u) + kCoinsLegendary}, SetOptions(merge: true));
      text = 'Leggendario sconfitto! Ricompensa: ${names.join(' e ')} e +$kCoinsLegendary 🪙';
    });
    return text;
  }
}
