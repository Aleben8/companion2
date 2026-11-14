import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../geo.dart';
import '../items.dart';
import 'party_service.dart';

/// Un altro party individuato dal Radar.
class RadarContact {
  final String name;
  final double distance;
  final String direction;
  final Duration age;
  RadarContact(this.name, this.distance, this.direction, this.age);
}

/// Gestione di inventario ed effetti degli strumenti.
///
/// Campi su `Users/{uid}`:
///   inventory: { repellente: 1, caramella: 1, ... }
///   repellentUntil / koUntil / trappedUntil : Timestamp
///   fleeBlocks: { <uidAvversario>: Timestamp }
///   location: { lat, lng, acc, at }
/// Sotto `Party/{codice}`:
///   traps/{id}  -> { ownerUid, lat, lng, active, createdAt }
///   events/{id} -> { type: 'bell', uid, lat, lng, at }
class ItemService {
  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> userRef(String uid) =>
      _db.collection('Users').doc(uid);

  static Stream<Map<String, dynamic>?> watchUser(String uid) =>
      userRef(uid).snapshots().map((s) => s.data());

  // ---------------------------------------------------------- inventario

  static Map<String, int> startingInventory() =>
      {for (final e in kStartingInventory.entries) e.key.name: e.value};

  /// Legge l'inventario; se manca (utenti creati prima di questa funzione)
  /// vale la dotazione iniziale.
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

  static DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : null;
  static bool isActive(dynamic v) => _ts(v)?.isAfter(DateTime.now()) ?? false;
  static Timestamp _in(int minutes) =>
      Timestamp.fromDate(DateTime.now().add(Duration(minutes: minutes)));

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

  /// Consumo semplice (Pozione, Caramella, ecc. usati dal motore di battaglia).
  static Future<void> consume(String uid, ItemId id) => _consume(uid, id);

  // ------------------------------------------------------------ restrizioni

  /// Controlla che il giocatore (e l'eventuale avversario) possano combattere.
  static Future<void> assertCanFight(String uid, {String? opponentUid}) async {
    final me = (await userRef(uid).get()).data() ?? {};
    if (isActive(me['koUntil'])) {
      throw Exception('Il tuo Pokémon è esausto: aspetta il recupero o usa un Revitalizzante');
    }
    if (isActive(me['trappedUntil'])) {
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
    if (isActive(opp['koUntil']) || isActive(opp['trappedUntil'])) {
      throw Exception("L'avversario non è disponibile");
    }
    final blocks = me['fleeBlocks'];
    if (blocks is Map && isActive(blocks[opponentUid])) {
      throw Exception('Siete appena usciti da uno scontro: non potete affrontarvi subito');
    }
  }

  /// Sconfitta: il Pokémon è esausto per [kKoMinutes] minuti.
  static Future<void> setKo(String uid) =>
      userRef(uid).set({'koUntil': _in(kKoMinutes)}, SetOptions(merge: true));

  // -------------------------------------------------------------- oggetti

  static Future<void> useRepellent(String uid) => _consume(uid, ItemId.repellente, effect: (u) {
        if (isActive(u['repellentUntil'])) throw Exception('Il Repellente è già attivo');
        return {'repellentUntil': _in(kRepellentMinutes)};
      });

  static Future<void> useRevive(String uid) => _consume(uid, ItemId.revitalizzante, effect: (u) {
        if (!isActive(u['koUntil'])) throw Exception('Il tuo Pokémon non è esausto');
        return {'koUntil': FieldValue.delete()};
      });

  /// Fune di fuga contro la Trappola: annulla il blocco.
  static Future<void> useRopeOnTrap(String uid) => _consume(uid, ItemId.fune, effect: (u) {
        if (!isActive(u['trappedUntil'])) throw Exception('Non sei in una trappola');
        return {'trappedUntil': FieldValue.delete()};
      });

  /// Calmanella: pubblica la tua posizione come evento del party.
  static Future<void> useBell(String uid, String party, Position pos) async {
    await _consume(uid, ItemId.calmanella);
    await PartyService.party(party).collection('events').add({
      'type': 'bell',
      'uid': uid,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'at': FieldValue.serverTimestamp(),
    });
  }

  /// Radar: posizione attuale degli altri party (esclusi quelli con Repellente).
  static Future<List<RadarContact>> useRadar(String uid, String party, Position pos) async {
    await _consume(uid, ItemId.radar);
    final players = await PartyService.players(party).get();
    final out = <RadarContact>[];
    for (final p in players.docs) {
      if (p.id == uid) continue;
      final u = (await userRef(p.id).get()).data();
      final loc = u?['location'];
      if (u == null || loc is! Map || isActive(u['repellentUntil'])) continue;
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final at = _ts(loc['at']);
      out.add(RadarContact(
        p.id,
        distanceMeters(pos.latitude, pos.longitude, lat, lng),
        compass(pos.latitude, pos.longitude, lat, lng),
        at == null ? Duration.zero : DateTime.now().difference(at),
      ));
    }
    out.sort((a, b) => a.distance.compareTo(b.distance));
    return out;
  }

  /// Trappola: piazzata nella posizione attuale.
  static Future<void> placeTrap(String uid, String party, Position pos) async {
    await _consume(uid, ItemId.trappola);
    await PartyService.party(party).collection('traps').add({
      'ownerUid': uid,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Un giocatore entra nel raggio di una trappola altrui: scatta una sola volta
  /// (transazione) e lo blocca per [kTrapPenaltyMinutes] minuti, salvo Fune di fuga.
  static Future<bool> triggerTrap(String party, String trapId, String uid) {
    final ref = PartyService.party(party).collection('traps').doc(trapId);
    return _db.runTransaction<bool>((tx) async {
      final t = (await tx.get(ref)).data();
      if (t == null || t['active'] != true || t['ownerUid'] == uid) return false;
      tx.update(ref, {'active': false, 'triggeredBy': uid});
      tx.set(userRef(uid), {'trappedUntil': _in(kTrapPenaltyMinutes)}, SetOptions(merge: true));
      return true;
    });
  }
}
