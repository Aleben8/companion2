import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../items.dart';
import '../mode.dart';
import '../constants.dart';
import '../table/events.dart';
import '../table/sectors.dart';
import '../table/type_chart.dart';
import '../table/zones.dart';
import 'battle_service.dart';
import 'clue_service.dart';
import 'gym_service.dart';
import 'item_service.dart';
import 'live_service.dart';
import 'party_service.dart';
import 'shared_stream.dart';

/// Esito di [TableService.routeTo].
enum MoveRoute { direct, passage, ticket }

/// Dove si trova chi chiede ai locali (finestra del Master: vede solo il modificatore di CD).
class LocalsCheck {
  final String uid;
  final String place;
  final SectorType? type;
  const LocalsCheck(this.uid, this.place, this.type);
  int get cdModifier => type?.localsCdModifier ?? 0;
}

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

  // condivisi: un solo ascolto per party (vedi shared_stream.dart)
  static Stream<Map<String, dynamic>?> watchState(String party) =>
      shared('state:$party', () => stateRef(party).snapshots().map((s) => s.data()));
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchEvents(String party) =>
      shared('zoneEvents:$party', () => eventsCol(party).snapshots());

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
  /// Al tavolo [biomes] sono le zone in gioco scelte dal Master (l'Hub c'è sempre; null = estrazione
  /// automatica) e i settori sono quelli impostati per il party.
  static Future<void> startGame(String party, {bool manualEvents = false, List<String>? biomes}) async {
    final live = !kTableMode;
    final players = await PartyService.players(party).get();
    if (players.docs.length < 2) throw Exception('Servono almeno 2 giocatori nel party');
    if (!live && players.docs.length > kMaxTablePlayers) {
      throw Exception('Al tavolo si gioca al massimo in $kMaxTablePlayers');
    }
    List<String>? inPlay;
    Map<String, List<SectorType>>? sectors;
    if (!live) {
      inPlay = {'hub', ...(biomes ?? drawBiomes(players.docs.length))}.toList();
      sectors = await partySectors(party);
      TableLayout.sectors = sectors;
      TableLayout.biomes = inPlay.toSet();
    }
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

    final wasStarted = (await stateRef(party).get()).data()?['started'] == true;
    final batch = _db.batch();
    // indizi: al riavvio tutti li ridispongono (simboli nuovi); al primo avvio al tavolo solo chi li
    // aveva messi in un bioma rimasto fuori dalla partita
    if (wasStarted) {
      await ClueService.resetPlacement(batch, party, order);
    } else if (inPlay != null) {
      await ClueService.dropOutOfPlay(batch, party, inPlay.toSet());
    }
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
      if (inPlay != null) 'biomes': inPlay,
      if (sectors != null) 'sectors': TableLayout.encode(sectors),
    });
    for (final uid in order) {
      batch.set(
        ItemService.userRef(uid),
        {
          // dal vivo la posizione la scrive il GPS appena entri in una zona
          'pos': live ? FieldValue.delete() : {'zone': 'hub', 'sector': 1},
          'busyUntil': FieldValue.delete(),
          'searchReadyAt': FieldValue.delete(),
          'wildEncounter': FieldValue.delete(),
          'spotted': FieldValue.delete(),
          'ticketReturn': FieldValue.delete(),
          'refugeRound': FieldValue.delete(),
          'localsInfo': FieldValue.delete(),
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
  /// (ci si sposta a piedi, i collegamenti tra zone non ci sono); al tavolo solo nei biomi in gioco.
  static List<ZoneEventDef> get availableEvents =>
      [for (final d in kZoneEventDefs) if ((kTableMode || !d.passage) && TableLayout.inPlay(d.zone)) d];

  /// Zone dove può comparire il leggendario: biomi in gioco (non l'Hub) con un settore impervio;
  /// se nessuno ne ha, uno qualsiasi dei biomi in gioco.
  static List<String> legendaryZones() {
    final biomes = [for (final z in TableLayout.zonesInPlay) if (z.id != 'hub') z.id];
    final rough = [for (final z in biomes) if (TableLayout.firstOf(z, SectorType.impervio) != null) z];
    if (!kTableMode) return biomes;
    return rough.isNotEmpty ? rough : (biomes.isNotEmpty ? biomes : [for (final z in kZones) if (z.id != 'hub') z.id]);
  }

  /// Sceglie a caso gli eventi e i giri in cui partono.
  static List<Map<String, dynamic>> _schedule({int base = 1}) {
    final pool = [...availableEvents]..shuffle(_rnd);
    final chosen = pool.take(kEventsPerGame).toList();
    final defs = [...chosen, kLegendaryDef];
    final starts = [for (var i = 0; i < defs.length; i++) kFirstEventRound - 1 + base + i * kEventGap]..shuffle(_rnd);
    final out = <Map<String, dynamic>>[];
    final legendaryIn = legendaryZones();
    for (var i = 0; i < defs.length; i++) {
      final d = defs[i];
      final start = starts[i];
      final zone = d.legendary ? legendaryIn[_rnd.nextInt(legendaryIn.length)] : d.zone;
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

  // ------------------------------------------------------- biomi in gioco

  /// Estrazione dei biomi: l'Hub c'è sempre, poi giocatori + 1 biomi a caso tra gli altri 7.
  static List<String> drawBiomes(int players) {
    final others = [for (final z in kZones) if (z.id != 'hub') z.id]..shuffle(_rnd);
    return ['hub', ...others.take(min(others.length, players + 1))];
  }

  /// Biomi della partita dallo stato (null = tutte le zone, es. partite avviate prima dei biomi).
  static Set<String>? biomesOf(Map<String, dynamic>? state) {
    final raw = state?['biomes'];
    return raw is List ? {'hub', ...raw.map((e) => '$e')} : null;
  }

  /// Biomi che l'Hub NON riesce a raggiungere a piedi con i collegamenti (solo tra biomi in gioco).
  static List<String> unreachableBiomes(Set<String> biomes, Set<String> links) {
    final seen = <String>{'hub'};
    final todo = ['hub'];
    while (todo.isNotEmpty) {
      final z = todo.removeLast();
      for (final o in biomes) {
        if (!seen.contains(o) && links.contains(linkKey(z, o))) {
          seen.add(o);
          todo.add(o);
        }
      }
    }
    return [for (final b in biomes) if (!seen.contains(b)) b];
  }

  // ------------------------------------------------------------- settori

  /// Settori scelti dal Master per il party (se non li ha cambiati, la proposta di [kDefaultSectors]).
  static Future<Map<String, List<SectorType>>> partySectors(String party) async =>
      TableLayout.parse((await PartyService.party(party).get()).data()?['sectorTypes']);

  /// Settori in uso: quelli della partita se è avviata, altrimenti quelli del party.
  static Map<String, List<SectorType>> sectorsOf(Map<String, dynamic>? state, Map<String, dynamic>? partyDoc) =>
      state?['started'] == true && state?['sectors'] is Map
          ? TableLayout.parse(state!['sectors'])
          : TableLayout.parse(partyDoc?['sectorTypes']);

  /// Ricarica settori e biomi della partita (per i servizi che non passano dall'interfaccia).
  static Future<Map<String, dynamic>?> loadLayout(String party) async {
    final st = (await stateRef(party).get()).data();
    final p = (await PartyService.party(party).get()).data();
    TableLayout.sectors = sectorsOf(st, p);
    TableLayout.biomes = st?['started'] == true ? biomesOf(st) : null;
    return st;
  }

  /// Il Master salva tipo e numero dei settori: valgono dalla prossima partita e, se è in corso, subito.
  /// Se una zona ha meno settori di prima, posizioni, tracce, indizi nascosti, trappole e allarmi
  /// che stavano nei settori spariti finiscono nell'ultimo settore rimasto.
  static Future<void> setSectorTypes(String party, Map<String, List<SectorType>> sectors) async {
    final enc = TableLayout.encode(sectors);
    await PartyService.party(party).set({'sectorTypes': enc}, SetOptions(merge: true));
    final st = (await stateRef(party).get()).data();
    final before = sectorsOf(st, null);
    if (st == null || st['started'] != true) return;
    await stateRef(party).update({'sectors': enc});
    TableLayout.sectors = sectors;
    final shrunk = <String, int>{
      for (final e in sectors.entries)
        if ((before[e.key]?.length ?? 0) > e.value.length) e.key: e.value.length,
    };
    if (shrunk.isEmpty) return;
    final batch = _db.batch();
    // sottocollezioni con { zone, sector } (indizi: { place: { zone, sector } })
    for (final name in ['traces', 'traps', 'alarms']) {
      for (final d in (await PartyService.party(party).collection(name).get()).docs) {
        final z = d.data()['zone'], s = _i(d.data()['sector']);
        final max = shrunk[z];
        if (max != null && s > max) batch.update(d.reference, {'sector': max});
        final fz = d.data()['fromZone'], fs = _i(d.data()['fromSector']);
        final fmax = shrunk[fz];
        if (fmax != null && fs > fmax) batch.update(d.reference, {'fromSector': fmax});
      }
    }
    for (final d in (await PartyService.party(party).collection('clues').get()).docs) {
      final pl = d.data()['place'];
      if (pl is! Map) continue;
      final max = shrunk[pl['zone']];
      if (max != null && _i(pl['sector']) > max) batch.update(d.reference, {'place.sector': max});
    }
    for (final p in (await PartyService.players(party).get()).docs) {
      final u = (await ItemService.userRef(p.id).get()).data();
      final pos = u?['pos'];
      final max = pos is Map ? shrunk[pos['zone']] : null;
      if (max != null && _i(pos['sector']) > max) batch.update(ItemService.userRef(p.id), {'pos.sector': max});
    }
    // settori bloccati dagli eventi in corso
    for (final d in (await eventsCol(party).get()).docs) {
      final e = d.data();
      final max = shrunk[e['zone']];
      if (max == null) continue;
      final blocked = [for (final b in (e['blocked'] as List? ?? [])) if (_i(b) <= max) _i(b)];
      batch.update(d.reference, {
        'blocked': blocked,
        if (e['sector'] != null && _i(e['sector']) > max) 'sector': max,
      });
    }
    await batch.commit();
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

  /// Come si va da [from] a [to]: stessa zona o collegamento diretto (a piedi, settore di arrivo libero),
  /// passaggio di un evento (treno/traghetto) o solo con un Biglietto. Treno, traghetto e Biglietto
  /// partono solo da un settore di passaggio e arrivano nel settore di passaggio della zona (vedi [moveTo]).
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
    String? next;
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
      next = order[idx];
    });
    if (roundAdvanced) {
      TableClock.round = newRound;
      await advanceEvents(party, newRound);
    }
    if (next != null) await _refugeRest(party, next!);
  }

  /// Rifugio: a inizio turno chi si trova in un settore rifugio recupera [kRefugeHp] PS (una volta per turno).
  static Future<void> _refugeRest(String party, String uid) async {
    final uref = ItemService.userRef(uid);
    final u = (await uref.get()).data();
    final pos = u?['pos'] as Map?;
    if (pos == null) return;
    await loadLayout(party);
    if (TableLayout.typeOf('${pos['zone']}', _i(pos['sector'])) != SectorType.rifugio) return;
    if (ItemService.isActive(u?['koUntil'])) return; // esausto: serve il recupero o un Revitalizzante
    final pk = await activePokemon(uid, u);
    if (pk == null) return;
    final pref = uref.collection('Pokemon').doc(pk);
    final hp = BattleService.currentHp((await pref.get()).data());
    if (hp >= kBaseHp) return;
    await pref.set({'currentHp': min(kBaseHp, hp + kRefugeHp)}, SetOptions(merge: true));
  }

  /// Pokémon con cui il giocatore è entrato (salvato al login); altrimenti il primo che ha.
  static Future<String?> activePokemon(String uid, [Map<String, dynamic>? user]) async {
    final u = user ?? (await ItemService.userRef(uid).get()).data();
    final a = u?['activePokemon'];
    if (a is String && a.isNotEmpty) return a;
    final q = await ItemService.userRef(uid).collection('Pokemon').limit(1).get();
    return q.docs.isEmpty ? null : q.docs.first.id;
  }

  // ------------------------------------------------------------ spostamenti

  static Future<List<Map<String, dynamic>>> activeEvents(String party) async {
    final q = await eventsCol(party).where('status', isEqualTo: 'active').get();
    return [for (final d in q.docs) {...d.data(), 'id': d.id}];
  }

  /// Costo (in azioni) di uno spostamento verso [zone] (e, al tavolo, verso il settore [sector]):
  /// +1 per gli eventi che rendono difficile entrare nella zona e +1 se il settore è impervio.
  static int moveCost(List<Map<String, dynamic>> events, String? fromZone, String zone, {String? shield, int? sector}) {
    var cost = kMoveActionCost;
    if (fromZone != zone && shield != zone) {
      for (final e in events) {
        if (e['zone'] == zone && e['status'] == 'active') cost += eventDef(e['defId'] as String).moveExtra;
      }
    }
    if (sector != null && TableLayout.typeOf(zone, sector) == SectorType.impervio) cost += kImperviousExtraCost;
    return cost;
  }

  /// Dove arrivano Biglietto, treno e traghetto: il settore di passaggio della zona.
  static int? arrivalSector(String zone) => TableLayout.firstOf(zone, SectorType.passaggio);

  /// Pulsanti della mappa: le zone dove il giocatore di turno può andare adesso (colorate; le altre
  /// in grigio). A piedi: zone collegate (o la propria, se c'è un altro settore libero) con azioni
  /// sufficienti. Biglietto / treno / traghetto: solo dal settore di passaggio, verso il passaggio della zona.
  /// Ritorno gratis del Biglietto: chi è arrivato in una zona con il Biglietto può tornare alla zona di
  /// partenza senza un altro Biglietto, finché resta nella zona d'arrivo (`Users/{uid}.ticketReturn`).
  /// Restituisce la zona dove si può tornare gratis (o null).
  static String? freeReturnZone(Map? ticketReturn, Map? pos) {
    if (ticketReturn == null || pos == null) return null;
    return ticketReturn['at'] == pos['zone'] ? ticketReturn['from'] as String? : null;
  }

  static bool canReach({
    required Map<String, dynamic>? state,
    required List<Map<String, dynamic>> events,
    required Map? pos,
    required String to,
    required int actionsLeft,
    required int tickets,
    String? shield,
    String? freeReturn,
  }) {
    final from = pos?['zone'] as String?;
    final fromSector = _i(pos?['sector']);
    final route = routeTo(state, events, from, to);
    final blocked = blockedSectors(events, to, shield: shield);
    bool ok(int s) =>
        !blocked.contains(s) &&
        !(from == to && s == fromSector) &&
        moveCost(events, from, to, shield: shield, sector: s) <= actionsLeft;
    if (route == MoveRoute.direct) {
      for (var s = 1; s <= TableLayout.count(to); s++) {
        if (ok(s)) return true;
      }
      return false;
    }
    if (from != null && TableLayout.typeOf(from, fromSector) != SectorType.passaggio) return false;
    if (route == MoveRoute.ticket && tickets <= 0 && freeReturn != to) return false;
    final arrival = arrivalSector(to);
    return arrival != null && ok(arrival);
  }

  static Set<int> blockedSectors(List<Map<String, dynamic>> events, String zone, {String? shield}) => shield == zone
      ? <int>{}
      : {
        for (final e in events)
          if (e['zone'] == zone && e['status'] == 'active')
            for (final b in (e['blocked'] as List? ?? [])) _i(b),
      };

  /// Sposta la pedina. Restituisce un messaggio se succede qualcosa (trappola, incontro selvatico).
  ///  - Tra zone collegate (o nella stessa zona) si va a piedi e si sceglie il settore.
  ///  - Con Biglietto, treno o traghetto si parte da un settore di passaggio e si arriva nel settore di
  ///    passaggio della zona: [sector] viene ignorato.
  ///  - [visibleTrace]: "Lascia una traccia ben visibile" (forza +1).
  static Future<String?> moveTo({
    required String party,
    required String uid,
    required String zone,
    required int sector,
    bool useTicket = false,
    bool visibleTrace = false,
  }) async {
    final spec = zoneSpec(zone);
    final st = await loadLayout(party);
    if (!TableLayout.inPlay(zone)) throw Exception('${spec.name} non è in gioco in questa partita');
    final events = await activeEvents(party);
    final me = (await ItemService.userRef(uid).get()).data();
    if (me?['wildEncounter'] is Map) throw Exception('Prima affronta o sfuggi al Pokémon selvatico');
    if (me?['spotted'] is Map) throw Exception('Ti hanno notato: prima elùdili (azione o Fune di fuga)');
    final shield = ItemService.shieldZone(me);
    final cur = me?['pos'] as Map?;
    final from = cur?['zone'] as String?;
    final route = routeTo(st, events, from, zone);
    final travel = route != MoveRoute.direct; // Biglietto, treno o traghetto
    if (travel) {
      if (from != null && TableLayout.typeOf(from, _i(cur?['sector'])) != SectorType.passaggio) {
        throw Exception('Per ${route == MoveRoute.ticket ? 'usare il Biglietto' : 'salire su treno o traghetto'} '
            'devi partire dal settore di passaggio della tua zona');
      }
      final arrival = arrivalSector(zone);
      if (arrival == null) throw Exception('${spec.name} non ha un settore di passaggio dove arrivare');
      sector = arrival;
    }
    if (sector < 1 || sector > spec.sectors) throw Exception('Settore non valido');
    if (blockedSectors(events, zone, shield: shield).contains(sector)) {
      throw Exception('Il settore $sector di ${spec.name} è bloccato');
    }
    if (cur?['zone'] == zone && _i(cur?['sector']) == sector) throw Exception('Sei già in questo settore');
    final cost = moveCost(events, from, zone, shield: shield, sector: sector);
    var needTicket = false;
    final freeReturn = route == MoveRoute.ticket && freeReturnZone(me?['ticketReturn'] as Map?, cur) == zone;
    if (route == MoveRoute.ticket && !freeReturn) {
      if (!useTicket) throw Exception('${spec.name} non è collegata alla tua zona: serve un Biglietto');
      if ((ItemService.readInventory(me)['biglietto'] ?? 0) <= 0) throw Exception('Non hai Biglietti');
      needTicket = true;
    }
    await _spend(party, uid, cost, setPos: {'zone': zone, 'sector': sector});
    if (needTicket) {
      await ItemService.consume(uid, ItemId.biglietto);
      // andata con il Biglietto: il ritorno alla zona di partenza è gratis
      await ItemService.userRef(uid).set({'ticketReturn': {'from': from, 'at': zone}}, SetOptions(merge: true));
    } else if (zone != from && me?['ticketReturn'] != null) {
      // uscito dalla zona d'arrivo (anche usando il ritorno): il ritorno gratis non vale più
      await ItemService.userRef(uid).set({'ticketReturn': FieldValue.delete()}, SetOptions(merge: true));
    }
    final type = TableLayout.typeOf(zone, sector);
    final msgs = <String>[];
    if (!ItemService.isActive(me?['stealthUntil'])) {
      // Passo felpato: niente tracce, trappole, allarmi e nessuno ti nota
      await ItemService.addTrace(party, uid, {
        'kind': 'move',
        'fromZone': cur?['zone'],
        'fromSector': cur?['sector'],
        'zone': zone,
        'sector': sector,
        'strength': traceStrength(type, visible: visibleTrace),
      });
      await _checkAlarms(party, uid, zone, sector);
      if (await _checkSpotted(party, uid, zone, sector)) {
        msgs.add('Qualcuno nel settore ti ha notato! Per eluderlo usa $kEludeCost azione oppure una Fune di fuga.');
      }
      if (await _checkTrap(party, uid, zone, sector)) {
        msgs.add('Sei finito in una Trappola! Salterai il prossimo turno, a meno di usare una Fune di fuga.');
      }
    }
    if (msgs.isEmpty && type == SectorType.selvaggio && _rnd.nextDouble() < kWildEncounterChance) {
      final name = await _startWildEncounter(uid, zone, sector);
      msgs.add('Un $name selvatico ti sbarra la strada! Affrontalo o fuggi (costa $kWildFleeCost azione).');
    }
    return msgs.isEmpty ? null : msgs.join('\n');
  }

  // ------------------------------------------------------------- furtività

  /// Statistiche del Pokémon attivo di [uid] (per destrezza e percezione).
  static Future<Map<String, dynamic>?> _stats(String uid) async {
    final pk = await activePokemon(uid);
    if (pk == null) return null;
    return (await ItemService.userRef(uid).collection('Pokemon').doc(pk).get()).data();
  }

  /// Chi entra in un settore dove ci sono altri giocatori tira d20 + destrezza (Velocità) contro la CD
  /// del settore + la percezione (Difesa Speciale) del più attento. Se fallisce resta "notato"
  /// (`Users/{uid}.spotted`) finché non elude (1 azione o una Fune di fuga) e chi è nel settore riceve
  /// subito l'avviso. Se riesce non succede niente (e non sa se c'era qualcuno).
  static Future<bool> _checkSpotted(String party, String uid, String zone, int sector) async {
    final others = <String>[];
    var bestSpDef = 0;
    for (final p in (await PartyService.players(party).get()).docs) {
      if (p.id == uid) continue;
      final pos = (await ItemService.userRef(p.id).get()).data()?['pos'];
      if (pos is! Map || pos['zone'] != zone || _i(pos['sector']) != sector) continue;
      others.add(p.id);
      bestSpDef = max(bestSpDef, _i((await _stats(p.id))?['DefSpec']));
    }
    if (others.isEmpty) return false;
    final cd = stealthCd(TableLayout.typeOf(zone, sector), bestSpDef);
    final roll = _rnd.nextInt(20) + 1;
    final total = roll + dexterityBonus(_i((await _stats(uid))?['Vel']));
    debugPrint('Furtività: $uid entra in $zone/$sector con ${others.join(', ')}: '
        'tiro $roll, totale $total contro CD $cd → ${total >= cd ? 'non notato' : 'NOTATO'}');
    if (total >= cd) return false;
    await ItemService.userRef(uid).set({
      'spotted': {'zone': zone, 'sector': sector, 'by': others, 'roll': roll, 'total': total, 'cd': cd},
    }, SetOptions(merge: true));
    // avviso subito a chi è nel settore (a comparsa in GameWatcher e nella scheda "Avvistamenti")
    await PartyService.party(party).collection('events').add({
      'type': 'spotted',
      'uid': uid,
      'to': others,
      'zone': zone,
      'sector': sector,
      'round': TableClock.round,
      'at': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Avvistamenti ricevuti da [uid] (eventi 'spotted' che lo hanno come destinatario).
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchSightings(String party, String uid) => shared(
      'sightings:$party:$uid',
      () => PartyService.party(party).collection('events').where('to', arrayContains: uid).snapshots());

  /// Eludere chi ti ha notato (è già stato avvisato): con un'azione (se non ne hai più, la perdi al
  /// turno dopo) oppure con una Fune di fuga ([rope]).
  static Future<void> elude(String party, String uid, {bool rope = false}) async {
    final uref = ItemService.userRef(uid);
    final sp = (await uref.get()).data()?['spotted'];
    if (sp is! Map) throw Exception('Nessuno ti ha notato');
    if (rope) {
      await ItemService.consume(uid, ItemId.fune);
      await uref.set({'spotted': FieldValue.delete()}, SetOptions(merge: true));
      return;
    }
    final st = (await stateRef(party).get()).data();
    final mine = st?['order'] is List && List<String>.from(st!['order'] as List)[_i(st['idx'])] == uid;
    if (mine && _i(st['actionsLeft']) >= kEludeCost) {
      await _spend(party, uid, kEludeCost);
      await uref.set({'spotted': FieldValue.delete()}, SetOptions(merge: true));
    } else {
      await uref.set({'spotted': FieldValue.delete(), 'actionPenalty': FieldValue.increment(kEludeCost)},
          SetOptions(merge: true));
    }
  }

  // ------------------------------------------------- informazioni dai locali

  /// CD per avere informazioni dai locali nel settore del giocatore.
  static int localsCd(SectorType? type) => kLocalsBaseCd + (type?.localsCdModifier ?? 0);

  /// Dove si trova [uid] e quale modificatore di CD vale lì (per la finestra del Master).
  static Future<LocalsCheck> localsCheck(String party, String uid) async {
    await loadLayout(party);
    final pos = (await ItemService.userRef(uid).get()).data()?['pos'] as Map?;
    if (pos == null) throw Exception('$uid non è ancora sulla mappa');
    final zone = '${pos['zone']}';
    final type = TableLayout.typeOf(zone, _i(pos['sector']));
    final place = '${zoneSpec(zone).name}, settore ${pos['sector']}${type == null ? '' : ' (${type.label.toLowerCase()})'}';
    return LocalsCheck(uid, place, type);
  }

  /// Il Master ha visto il tiro al tavolo e dice se [uid] ha superato la CD. Il racconto dei locali
  /// (chi è passato nella zona di recente, eventi in arrivo, indizi nascosti) finisce su
  /// `Users/{uid}.localsInfo` e lo vede solo quel giocatore: il Master, che gioca, non lo legge.
  static Future<void> sendLocals(String party, String uid, {required bool success}) async {
    final check = await localsCheck(party, uid);
    final lines = success ? await _localsLines(party, uid) : const <String>[];
    await ItemService.userRef(uid).set({
      'localsInfo': {'place': check.place, 'success': success, 'lines': lines, 'round': TableClock.round},
    }, SetOptions(merge: true));
  }

  /// Il giocatore chiude il messaggio dei locali.
  static Future<void> dismissLocals(String uid) =>
      ItemService.userRef(uid).update({'localsInfo': FieldValue.delete()});

  static Future<List<String>> _localsLines(String party, String uid) async {
    final pos = (await ItemService.userRef(uid).get()).data()?['pos'] as Map?;
    final zone = '${pos?['zone']}';
    final lines = <String>[];
    final round = TableClock.round;
    final traces = (await PartyService.party(party).collection('traces').get()).docs.map((d) => d.data()).where((t) =>
        t['uid'] != uid && t['zone'] == zone && _i(t['round']) >= round - kLocalsRounds);
    for (final t in traces) {
      final s = _i(t['strength'], kTraceBaseStrength);
      lines.add('${t['uid']} è ${t['kind'] == 'search' ? 'stato visto cercare' : 'passato'} nel settore ${t['sector']} '
          '(giro ${t['round']}, traccia ${traceStrengthLabel(s)})');
    }
    if (traces.isEmpty) lines.add('Negli ultimi $kLocalsRounds giri non è passato nessuno da queste parti');
    for (final d in (await eventsCol(party).get()).docs) {
      final e = d.data();
      if (e['zone'] != zone || (e['status'] != 'announced' && e['status'] != 'scheduled')) continue;
      final start = _i(e['startRound']);
      if (start >= kManualStart || start - round > kWeatherLookahead + 1) continue;
      lines.add('Si dice che presto ci sarà: ${e['name']}');
    }
    final clues = (await PartyService.party(party).collection('clues').where('status', isEqualTo: 'hidden').get())
        .docs
        .where((d) => d.data()['ownerUid'] != uid && (d.data()['place'] as Map?)?['zone'] == zone)
        .length;
    lines.add(clues == 0 ? 'Nessuno ha visto nascondere qualcosa in zona' : 'Qualcuno ha nascosto qualcosa in zona ($clues)');
    return lines;
  }

  // ------------------------------------------------------------- rifugi

  /// Nessuno può sfidare chi è in un settore rifugio (solo tavolo; i capipalestra e i selvatici sì).
  static Future<void> assertNotInRefuge(String uid, {bool me = true}) async {
    if (!kTableMode) return;
    final party = await PartyService.actualParty(uid);
    if (party == null) return;
    await loadLayout(party);
    final pos = (await ItemService.userRef(uid).get()).data()?['pos'] as Map?;
    if (pos == null) return;
    if (TableLayout.typeOf('${pos['zone']}', _i(pos['sector'])) == SectorType.rifugio) {
      throw Exception(me ? 'Sei in un rifugio: qui non si combatte tra giocatori' : '$uid è in un rifugio: non può essere sfidato');
    }
  }

  // ------------------------------------------------------- incontri selvatici

  /// Genera il Pokémon selvatico (tipo della zona, forza simile alla tua) e lo mette in attesa
  /// su `Users/{uid}.wildEncounter` finché il giocatore non sceglie se affrontarlo o fuggire.
  static Future<String> _startWildEncounter(String uid, String zone, int sector) async {
    final spec = zoneSpec(zone);
    final pk = await activePokemon(uid);
    final mine = pk == null ? null : (await ItemService.userRef(uid).collection('Pokemon').doc(pk).get()).data();
    final myPoints = [for (final s in ['Atk', 'AtkSpec', 'Def', 'DefSpec', 'Vel']) _i(mine?[s])].fold<int>(0, (a, b) => a + b);
    final points = max(kStatPointsTotal ~/ 2, (myPoints == 0 ? kStatPointsTotal : myPoints) - kWildStatMalus);
    final leader = await GymService.generateLeader(spec.type, wild: true, statPoints: points);
    await ItemService.userRef(uid).set({
      'wildEncounter': {'zone': zone, 'sector': sector, 'type': spec.type, 'name': leader['pokemon'], 'leader': leader},
    }, SetOptions(merge: true));
    return '${leader['pokemon']}';
  }

  /// Fuga dall'incontro selvatico: costa [kWildFleeCost] azione (se non ne hai, la perdi al prossimo turno).
  static Future<void> fleeWild(String party, String uid) async {
    final uref = ItemService.userRef(uid);
    final u = (await uref.get()).data();
    if (u?['wildEncounter'] is! Map) throw Exception('Non c’è nessun Pokémon selvatico');
    final st = (await stateRef(party).get()).data();
    final mine = st?['order'] is List && List<String>.from(st!['order'] as List)[_i(st['idx'])] == uid;
    if (mine && _i(st['actionsLeft']) >= kWildFleeCost) {
      await _spend(party, uid, kWildFleeCost);
      await uref.set({'wildEncounter': FieldValue.delete()}, SetOptions(merge: true));
    } else {
      await uref.set({'wildEncounter': FieldValue.delete(), 'actionPenalty': FieldValue.increment(kWildFleeCost)},
          SetOptions(merge: true));
    }
  }

  /// Affronta il Pokémon selvatico: battaglia contro un NPC, come con i capipalestra.
  static Future<String> fightWild({required String party, required String uid, required String pk}) async {
    final uref = ItemService.userRef(uid);
    final w = (await uref.get()).data()?['wildEncounter'];
    if (w is! Map) throw Exception('Non c’è nessun Pokémon selvatico');
    final id = await BattleService.createGymBattle(
      party: party,
      gymId: 'wild-$uid',
      gym: {'name': '${w['name']} selvatico', 'type': w['type'], 'leader': w['leader']},
      uid: uid,
      pk: pk,
      extra: {'wild': true},
    );
    await uref.set({'wildEncounter': FieldValue.delete()}, SetOptions(merge: true));
    return id;
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
    if (kTableMode) await loadLayout(party); // numero e tipo dei settori della partita

    if (def.blockSectors > 0) {
      final all = List<int>.generate(spec.sectors, (i) => i + 1)..shuffle(_rnd);
      update['blocked'] = all.take(min(def.blockSectors, spec.sectors - 1)).toList()..sort();
    }
    if (def.legendary) {
      final name = spec.legendaries[_rnd.nextInt(spec.legendaries.length)];
      update['leader'] = await GymService.generateLeader(spec.type, legendary: true, pokemon: name);
      update['legendaryName'] = name;
      if (kTableMode) {
        // compare solo in un settore impervio (se la zona non ne ha, in uno qualsiasi)
        final rough = [
          for (var s = 1; s <= spec.sectors; s++)
            if (TableLayout.typeOf(zone, s) == SectorType.impervio) s,
        ];
        final pool = rough.isNotEmpty ? rough : [for (var s = 1; s <= spec.sectors; s++) s];
        update['sector'] = pool[_rnd.nextInt(pool.length)];
      }
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
    if (kTableMode && e['sector'] != null && _i(pos?['sector']) != _i(e['sector'])) {
      throw Exception('Il leggendario è nel settore ${e['sector']}: raggiungilo');
    }
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
