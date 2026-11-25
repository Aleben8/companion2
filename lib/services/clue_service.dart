import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../geo.dart';
import '../items.dart';
import '../mode.dart';
import '../table/sectors.dart';
import 'item_service.dart';
import 'live_service.dart';
import 'party_service.dart';
import 'shared_stream.dart';
import 'table_service.dart';

/// Raggio (dal vivo) entro cui si trova un indizio. Il GPS ha un'incertezza di qualche metro:
/// se la ricerca fallisce spesso, alzalo (es. 15).
const double kClueRadiusMeters = 10;
const int kCluesPerPlayer = 3;

/// Un simbolo per giocatore: identifica chi ha piazzato l'indizio (carte sul tavolo).
const List<String> kClueSymbols = ['▲', '●', '■', '◆', '★', '✚', '☾', '❖', '♥', '♣'];

/// Indizi: ogni giocatore ne assegna [kCluesPerPlayer] a un altro giocatore e li
/// nasconde sulla mappa all'inizio della partita. Li trova chi ci passa (non per forza il destinatario).
///
/// Firestore:
///   Party/{codice}                      -> { cluePhase: 'placing' | 'playing' }
///   Party/{codice}/players/{uid}        -> { symbol, cluesReady }
///   Party/{codice}/clues/{id}           -> { ownerUid, targetUid, symbol, number, text,
///                                            place: {zone, sector} | {lat, lng},
///                                            status: 'hidden' | 'found', foundBy, declared, declaredAt }
class ClueService {
  static final _db = FirebaseFirestore.instance;
  static final _rnd = Random();

  static CollectionReference<Map<String, dynamic>> clues(String party) =>
      PartyService.party(party).collection('clues');

  static Stream<String?> watchPhase(String party) =>
      shared('cluePhase:$party', () => PartyService.watchParty(party).map((d) => d?['cluePhase'] as String?));

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchClues(String party) =>
      shared('clues:$party', () => clues(party).snapshots());

  static String symbolFor(int i) {
    final base = kClueSymbols[i % kClueSymbols.length];
    final n = i ~/ kClueSymbols.length;
    return n == 0 ? base : '$base${n + 1}';
  }

  // ---------------------------------------------------------------- Master

  /// Apre il piazzamento: assegna a caso un simbolo a ogni giocatore e azzera gli indizi.
  static Future<void> openPlacement(String party) async {
    final players = await PartyService.players(party).get();
    if (players.docs.length < 2) throw Exception('Servono almeno 2 giocatori nel party');
    final batch = _db.batch();
    await resetPlacement(batch, party, players.docs.map((d) => d.id).toList());
    await batch.commit();
  }

  /// Aggiunge a [batch] la riapertura del piazzamento: cancella tutti gli indizi, nuovi simboli e
  /// tutti "non pronti". La usa anche il (ri)avvio della partita, così ognuno li ridispone.
  static Future<void> resetPlacement(WriteBatch batch, String party, List<String> players) async {
    final ids = [...players]..shuffle(_rnd);
    final placement = DateTime.now().millisecondsSinceEpoch; // identifica questo piazzamento
    for (final d in (await clues(party).get()).docs) {
      batch.delete(d.reference);
    }
    for (var i = 0; i < ids.length; i++) {
      batch.set(
        PartyService.players(party).doc(ids[i]),
        {'symbol': symbolFor(i), 'cluesReady': false, 'cluePlacement': placement},
        SetOptions(merge: true),
      );
    }
    batch.set(PartyService.party(party), {'cluePhase': 'placing'}, SetOptions(merge: true));
  }

  /// Al primo avvio al tavolo: chi ha nascosto un indizio in un bioma che non è in gioco deve
  /// ridisporre i suoi (vengono cancellati e il piazzamento si riapre). Restituisce chi deve rifarli.
  static Future<List<String>> dropOutOfPlay(WriteBatch batch, String party, Set<String> inPlay) async {
    final redo = <String>{};
    final all = (await clues(party).get()).docs;
    for (final d in all) {
      final z = (d.data()['place'] as Map?)?['zone'];
      if (z != null && !inPlay.contains(z)) redo.add('${d.data()['ownerUid']}');
    }
    if (redo.isEmpty) return const [];
    for (final d in all) {
      if (redo.contains(d.data()['ownerUid'])) batch.delete(d.reference);
    }
    for (final uid in redo) {
      batch.set(PartyService.players(party).doc(uid), {'cluesReady': false}, SetOptions(merge: true));
    }
    batch.set(PartyService.party(party), {'cluePhase': 'placing'}, SetOptions(merge: true));
    return redo.toList();
  }

  /// Chiude il piazzamento: da qui gli indizi si possono cercare.
  static Future<void> closePlacement(String party) =>
      PartyService.party(party).set({'cluePhase': 'playing'}, SetOptions(merge: true));

  // ------------------------------------------------------------ Giocatori

  /// Salva i 3 indizi del giocatore (sostituisce quelli già piazzati).
  /// [places]: {zone, sector} al tavolo, {lat, lng} dal vivo.
  static Future<void> placeClues({
    required String party,
    required String uid,
    required String targetUid,
    required List<String> texts,
    required List<Map<String, dynamic>> places,
  }) async {
    final p = (await PartyService.party(party).get()).data();
    if (p?['cluePhase'] != 'placing') throw Exception('Il piazzamento degli indizi non è aperto');
    if (targetUid == uid) throw Exception('Scegli un altro giocatore come destinatario');
    if (texts.length != kCluesPerPlayer || places.length != kCluesPerPlayer) {
      throw Exception('Servono esattamente $kCluesPerPlayer indizi');
    }
    if (texts.any((t) => t.trim().isEmpty)) throw Exception('Scrivi il testo di tutti gli indizi');
    for (final pl in places) {
      final ok = kTableMode ? pl['zone'] != null && pl['sector'] != null : pl['lat'] != null && pl['lng'] != null;
      if (!ok) throw Exception('Scegli dove piazzare tutti gli indizi');
    }
    final me = (await PartyService.players(party).doc(uid).get()).data();
    final symbol = (me?['symbol'] ?? '?').toString();

    final batch = _db.batch();
    final old = await clues(party).where('ownerUid', isEqualTo: uid).get();
    for (final d in old.docs) {
      batch.delete(d.reference);
    }
    for (var i = 0; i < kCluesPerPlayer; i++) {
      batch.set(clues(party).doc(), {
        'ownerUid': uid,
        'targetUid': targetUid,
        'symbol': symbol,
        'number': i + 1,
        'text': texts[i].trim(),
        'place': places[i],
        'status': 'hidden',
        'declared': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    batch.set(PartyService.players(party).doc(uid), {'cluesReady': true}, SetOptions(merge: true));
    await batch.commit();
  }

  /// Cerca gli indizi nascosti qui: al tavolo nel tuo settore (costa 1 azione),
  /// dal vivo entro [kClueRadiusMeters]. Gli indizi trovati passano a te (i tuoi non si trovano).
  static Future<SearchResult> search({
    required String party,
    required String uid,
    Position? pos,
  }) async {
    final phase = (await PartyService.party(party).get()).data()?['cluePhase'];
    if (phase != 'playing') throw Exception('Gli indizi non sono ancora in gioco');
    Map? myPos;
    SectorType? sectorType;
    if (kTableMode) {
      final me = (await ItemService.userRef(uid).get()).data();
      myPos = me?['pos'] as Map?;
      if (myPos == null) throw Exception('Non sei ancora sulla mappa');
      if (me?['wildEncounter'] is Map) throw Exception('Prima affronta o sfuggi al Pokémon selvatico');
      if (me?['spotted'] is Map) throw Exception('Ti hanno notato: prima elùdili (azione o Fune di fuga)');
      await TableService.loadLayout(party);
      sectorType = TableLayout.typeOf('${myPos['zone']}', (myPos['sector'] as num).toInt());
      await TableService.spendAction(party, uid); // cercare è un'azione
    } else {
      if (pos == null) throw Exception('Posizione non disponibile');
      // dal vivo cercare non costa azioni ma un'attesa
      final ref = ItemService.userRef(uid);
      final u = (await ref.get()).data();
      LiveService.assertNotBusy(u);
      final wait = LiveService.left(u?['searchReadyAt']);
      if (wait != null) throw Exception('Hai appena cercato: puoi riprovare tra ${LiveService.fmt(wait)}');
      final here = u?['pos'] as Map?;
      if (here != null) {
        final blocked = TableService.blockedSectors(await TableService.activeEvents(party), here['zone'] as String,
            shield: ItemService.shieldZone(u));
        if (blocked.contains((here['sector'] as num?)?.toInt())) {
          throw Exception('Questo settore è bloccato da un evento: spostati o usa una Chiave');
        }
      }
      await ref.set({
        'searchReadyAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: kLiveSearchCooldownMinutes))),
      }, SetOptions(merge: true));
    }

    // Traccia per la Lente: dove hai cercato.
    await ItemService.addTrace(
      party,
      uid,
      kTableMode
          ? {'kind': 'search', 'zone': myPos!['zone'], 'sector': myPos['sector'], 'strength': traceStrength(sectorType)}
          : {'kind': 'search', 'lat': pos!.latitude, 'lng': pos.longitude},
    );

    final q = await clues(party).where('status', isEqualTo: 'hidden').get();
    final found = <Map<String, dynamic>>[];
    for (final d in q.docs) {
      final c = d.data();
      if (c['ownerUid'] == uid) continue;
      final place = c['place'] as Map?;
      if (place == null) continue;
      final here = kTableMode
          ? place['zone'] == myPos!['zone'] && place['sector'] == myPos['sector']
          : distanceMeters(pos!.latitude, pos.longitude, (place['lat'] as num).toDouble(), (place['lng'] as num).toDouble()) <=
              kClueRadiusMeters;
      if (!here) continue;
      final ok = await _db.runTransaction<bool>((tx) async {
        final cur = (await tx.get(d.reference)).data();
        if (cur == null || cur['status'] != 'hidden') return false;
        tx.update(d.reference, {'status': 'found', 'foundBy': uid, 'foundAt': FieldValue.serverTimestamp()});
        return true;
      });
      if (ok) found.add({...c, 'id': d.id});
    }

    // Nessun indizio: con una piccola probabilità trovi invece uno strumento.
    String? item;
    // nei settori impervi si trova qualcosa più spesso
    final itemChance = sectorType == SectorType.impervio ? kImperviousSearchItemChance : kSearchItemChance;
    if (found.isEmpty && _rnd.nextDouble() < itemChance) {
      final id = ItemService.randomDrop(rnd: _rnd);
      final txt = await ItemService.grant(uid, items: [id]);
      item = txt;
    }
    return SearchResult(found, item);
  }

  /// "Ho preso la carta": dichiara di avere l'indizio (lo vedono tutti, senza il testo).
  /// Se l'indizio NON era destinato a te, ricevi uno strumento a caso come bonus
  /// (è il premio per aver rischiato di diventare un bersaglio). Restituisce il nome dello strumento, o null.
  static Future<String?> declare(String party, String clueId, String uid) {
    final ref = clues(party).doc(clueId);
    final uref = ItemService.userRef(uid);
    return _db.runTransaction<String?>((tx) async {
      final c = (await tx.get(ref)).data();
      final u = (await tx.get(uref)).data() ?? {};
      if (c == null || c['foundBy'] != uid) throw Exception('Non hai questo indizio');
      if (c['declared'] == true) return null;
      final bonus = c['targetUid'] != uid;
      tx.update(ref, {'declared': true, 'declaredAt': FieldValue.serverTimestamp(), 'bonusGiven': bonus});
      final inv = ItemService.readInventory(u);
      String? name;
      if (bonus) {
        final id = ItemService.randomDrop(rnd: _rnd);
        name = ItemService.addItem(inv, id.name) ? itemDef(id).name : '${itemDef(id).name} (borsa piena: perso)';
      }
      tx.set(uref, {'inventory': inv, 'coins': ItemService.coinsOf(u) + kCoinsDeclare}, SetOptions(merge: true));
      return name ?? '';
    });
  }
}

/// Esito di una ricerca: indizi trovati e, se non c'erano indizi, l'eventuale strumento trovato.
class SearchResult {
  final List<Map<String, dynamic>> clues;
  final String? item; // testo del premio ("Pozione")
  const SearchResult(this.clues, this.item);
}
