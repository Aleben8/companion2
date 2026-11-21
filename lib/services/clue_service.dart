import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../geo.dart';
import '../mode.dart';
import 'item_service.dart';
import 'party_service.dart';
import 'table_service.dart';

/// Raggio (dal vivo) entro cui si trova un indizio.
const double kClueRadiusMeters = 25;
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
      PartyService.party(party).snapshots().map((s) => s.data()?['cluePhase'] as String?);

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchClues(String party) => clues(party).snapshots();

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
    final ids = players.docs.map((d) => d.id).toList()..shuffle(_rnd);
    final batch = _db.batch();
    for (final d in (await clues(party).get()).docs) {
      batch.delete(d.reference);
    }
    for (var i = 0; i < ids.length; i++) {
      batch.set(
        PartyService.players(party).doc(ids[i]),
        {'symbol': symbolFor(i), 'cluesReady': false},
        SetOptions(merge: true),
      );
    }
    batch.set(PartyService.party(party), {'cluePhase': 'placing'}, SetOptions(merge: true));
    await batch.commit();
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
  static Future<List<Map<String, dynamic>>> search({
    required String party,
    required String uid,
    Position? pos,
  }) async {
    final phase = (await PartyService.party(party).get()).data()?['cluePhase'];
    if (phase != 'playing') throw Exception('Gli indizi non sono ancora in gioco');
    Map? myPos;
    if (kTableMode) {
      myPos = (await ItemService.userRef(uid).get()).data()?['pos'] as Map?;
      if (myPos == null) throw Exception('Non sei ancora sulla mappa');
      await TableService.spendAction(party, uid); // cercare è un'azione
    } else if (pos == null) {
      throw Exception('Posizione non disponibile');
    }

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
    return found;
  }

  /// "Ho preso la carta": dichiara di avere l'indizio (lo vedono tutti, senza il testo).
  static Future<void> declare(String party, String clueId, String uid) {
    final ref = clues(party).doc(clueId);
    return _db.runTransaction<void>((tx) async {
      final c = (await tx.get(ref)).data();
      if (c == null || c['foundBy'] != uid) throw Exception('Non hai questo indizio');
      if (c['declared'] == true) return;
      tx.update(ref, {'declared': true, 'declaredAt': FieldValue.serverTimestamp()});
    });
  }
}
