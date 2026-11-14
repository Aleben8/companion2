import 'package:cloud_firestore/cloud_firestore.dart';

/// Struttura Firestore:
///   Party/{codice}                      -> { riddleView: bool }
///   Party/{codice}/players/{userId}     -> { userId, number, joinedAt, numberVisibility,
///                                            assignedNumber, riddle, isMaster }
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

  /// Entra in un party: crea il giocatore con il primo numero libero (>= 10)
  /// e imposta il party corrente.
  static Future<void> join(String uid, String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;
    final me = players(code).doc(uid);
    if (!(await me.get()).exists) {
      final last =
          await players(code).orderBy('number', descending: true).limit(1).get();
      var next = 10;
      if (last.docs.isNotEmpty) {
        next = ((last.docs.first.data()['number'] as num?)?.toInt() ?? 9) + 1;
      }
      await me.set({
        'userId': uid,
        'number': next,
        'joinedAt': FieldValue.serverTimestamp(),
        'numberVisibility': false,
      });
    }
    await _db.collection('Users').doc(uid).set({
      'actualParty': code,
      'parties': FieldValue.arrayUnion([code]),
    }, SetOptions(merge: true));
  }

  static Future<void> switchParty(String uid, String code) =>
      _db.collection('Users').doc(uid).set({'actualParty': code}, SetOptions(merge: true));

  /// Il giocatore `targetUid` riceve un numero (assegnato) e un indizio.
  /// Il numero resta nascosto finché `numberVisibility` non diventa true.
  static Future<void> assignNumberAndRiddle({
    required String code,
    required String targetUid,
    required int number,
    required String riddle,
  }) =>
      players(code).doc(targetUid).update({
        'assignedNumber': number,
        'numberVisibility': false,
        'riddle': riddle.trim(),
      });

  /// Ricompensa: sblocca il numero del vincitore.
  static Future<void> unlockNumber(String code, String uid) =>
      players(code).doc(uid).set({'numberVisibility': true}, SetOptions(merge: true));

  static Future<bool> isMaster(String code, String uid) async {
    final d = await players(code).doc(uid).get();
    return d.data()?['isMaster'] == true;
  }

  static Future<void> setRiddleView(String code, bool visible) =>
      party(code).set({'riddleView': visible}, SetOptions(merge: true));

  /// Solo Master: ridistribuisce a tutti i giocatori numeri unici da 10 a 99.
  static Future<void> assignRandomNumbers(String code) async {
    final snap = await players(code).get();
    if (snap.docs.isEmpty) return;
    if (snap.docs.length > 90) {
      throw Exception('Troppi player per il range 10–99');
    }
    final nums = List<int>.generate(90, (i) => i + 10)..shuffle();
    final batch = _db.batch();
    for (var i = 0; i < snap.docs.length; i++) {
      batch.update(snap.docs[i].reference, {'number': nums[i]});
    }
    await batch.commit();
  }
}
