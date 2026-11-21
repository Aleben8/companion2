import 'package:cloud_firestore/cloud_firestore.dart';

/// Struttura Firestore:
///   Party/{codice}                      -> { cluePhase, gameStarted, ... }
///   Party/{codice}/players/{userId}     -> { userId, joinedAt, isMaster, symbol, cluesReady }
///   Users/{userId}                      -> { actualParty, parties[] }
class PartyService {
  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> party(String code) =>
      _db.collection('Party').doc(code);
  static CollectionReference<Map<String, dynamic>> players(String code) =>
      party(code).collection('players');

  static Future<String?> actualParty(String uid) async {
    final d = await _db.collection('Users').doc(uid).get();
    final v = d.data()?['actualParty'];
    return v is String && v.isNotEmpty ? v : null;
  }

  static Future<List<String>> myParties(String uid) async {
    final d = await _db.collection('Users').doc(uid).get();
    final v = d.data()?['parties'];
    return v is List ? v.map((e) => e.toString()).toList() : <String>[];
  }

  /// Entra in un party: crea il giocatore (se non c'è) e imposta il party corrente.
  static Future<void> join(String uid, String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;
    final me = players(code).doc(uid);
    if (!(await me.get()).exists) {
      await me.set({'userId': uid, 'joinedAt': FieldValue.serverTimestamp()});
    }
    await _db.collection('Users').doc(uid).set({
      'actualParty': code,
      'parties': FieldValue.arrayUnion([code]),
    }, SetOptions(merge: true));
  }

  static Future<void> switchParty(String uid, String code) =>
      _db.collection('Users').doc(uid).set({'actualParty': code}, SetOptions(merge: true));

  static Future<bool> isMaster(String code, String uid) async {
    final d = await players(code).doc(uid).get();
    return d.data()?['isMaster'] == true;
  }
}
