import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants.dart';
import '../gyms.dart';
import '../table/events.dart';
import 'item_service.dart';
import 'party_service.dart';
import 'shared_stream.dart';

/// Palestre e capipalestra.
///
/// Struttura Firestore:
///   Party/{codice}                 -> { gameStarted, startedAt }
///   Party/{codice}/gyms/{gymId}    -> { name, type, address, lat, lng, calibrated,
///                                       leader: { trainer, pokemon, typePrim, typeSec,
///                                                 Atk, AtkSpec, Def, DefSpec, Vel,
///                                                 Resistenze[], Debolezze[],
///                                                 ai: { defense, dodge },
///                                                 moves: { <nome>: {...come MoveSet...} } } }
///   Users/{uid}.badges             -> { <gymId>: { name, type, at } }
class GymService {
  static final _db = FirebaseFirestore.instance;
  static final _rnd = Random();

  static CollectionReference<Map<String, dynamic>> gyms(String party) =>
      PartyService.party(party).collection('gyms');

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchGyms(String party) =>
      shared('gyms:$party', () => gyms(party).snapshots());

  static Stream<bool> watchStarted(String party) =>
      shared('gameStarted:$party', () => PartyService.watchParty(party).map((d) => d?['gameStarted'] == true));

  // ------------------------------------------------------------- generazione

  static T _pick<T>(List<T> l) => l[_rnd.nextInt(l.length)];

  /// Distribuisce [total] punti sulle 5 statistiche (max [kStatMax] ciascuna),
  /// con probabilità proporzionali ai pesi del tipo.
  static Map<String, int> _randomStats(Map<String, int> weights, int total) {
    final stats = {for (final k in kStatLabels.keys) k: 0};
    for (var i = 0; i < total; i++) {
      final open = stats.keys.where((k) => stats[k]! < kStatMax).toList();
      if (open.isEmpty) break;
      final sum = open.fold<int>(0, (s, k) => s + (weights[k] ?? 1));
      var r = _rnd.nextInt(sum);
      for (final k in open) {
        r -= weights[k] ?? 1;
        if (r < 0) {
          stats[k] = stats[k]! + 1;
          break;
        }
      }
    }
    return stats;
  }

  static Map<String, dynamic> _buildMove(String type, MoveTemplate t, int dmg, EffectPref e) {
    final effect = e.effect;
    String? target;
    if (effect == 'Danno') target = 'PkmLife';
    if (effect == 'Rallentamento') target = 'Vel';
    if (effect == 'Debuff') target = e.stat ?? 'Atk';
    return {
      'MoveName': t.name,
      'MoveType': type,
      'MoveTypo': t.special ? 'Speciale' : 'Fisico',
      'Dmg': dmg,
      'Description': t.description,
      'AltEffect': effect,
      'targetStat': target,
      'AltDmg': dmg,
      'AltStatusPerc': effect == null ? 0.0 : altStatusChanceForDmg(dmg),
      'altStatus': '',
      'altStatusName': '',
    };
  }

  /// Crea un capopalestra casuale ma coerente con il tipo.
  /// [legendary]: più forte (kLegendaryStatPoints), mosse più potenti e nessun allenatore.
  /// [wild]: Pokémon selvatico (nessun allenatore); [statPoints] adatta la forza (es. a quella del giocatore).
  static Future<Map<String, dynamic>> generateLeader(String type,
      {bool legendary = false, bool wild = false, String? pokemon, int? statPoints}) async {
    final profile = kTypeProfiles[type] ?? kTypeProfiles['Normale']!;
    final pokemonName = pokemon ?? _pick(profile.pokemon);
    final String? trainer = legendary || wild ? null : _pick(profile.trainers);
    final stats = _randomStats(profile.statWeights, statPoints ?? (legendary ? kLegendaryStatPoints : kGymStatPoints));

    // Due mosse: una leggera (Dmg 1-3) e una forte (Dmg 3-5), diverse tra loro.
    final templates = [...profile.moves]..shuffle(_rnd);
    final dmgs = (legendary ? [2 + _rnd.nextInt(3), 4 + _rnd.nextInt(3)] : [1 + _rnd.nextInt(3), 3 + _rnd.nextInt(3)])..shuffle(_rnd);
    final moves = <String, dynamic>{};
    for (var i = 0; i < 2; i++) {
      final m = _buildMove(type, templates[i], dmgs[i], _pick(profile.effects));
      moves[m['MoveName'] as String] = m;
    }

    // Debolezze e resistenze dal DB ("Tipi"); se mancano, valori di riserva.
    var weak = <String>[...?kFallbackWeak[type]];
    var resist = <String>[...?kFallbackResist[type]];
    try {
      final t = await _db.collection('Tipi').doc(type).get();
      if (t.exists) {
        final w = t.data()?['Debolezze'];
        final r = t.data()?['Resistenze'];
        if (w is List && w.isNotEmpty) weak = w.map((e) => e.toString()).toList();
        if (r is List) resist = r.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    return {
      'trainer': trainer,
      'pokemon': pokemonName,
      'typePrim': type,
      'typeSec': '',
      ...stats,
      'Resistenze': resist,
      'Debolezze': weak,
      'ai': {'defense': profile.defenseChance, 'dodge': profile.dodgeChance},
      'moves': moves,
    };
  }

  /// Avvio del gioco: crea (o rigenera) i capipalestra nelle location prestabilite.
  /// Le posizioni già calibrate vengono mantenute; i badge dei giocatori restano.
  static Future<void> launch(String party) async {
    final existing = await gyms(party).get();
    final saved = {for (final d in existing.docs) d.id: d.data()};
    final batch = _db.batch();
    for (final g in kGyms) {
      final old = saved[g.id];
      final calibrated = old?['calibrated'] == true;
      batch.set(gyms(party).doc(g.id), {
        'name': g.name,
        'type': g.type,
        'address': g.address,
        'lat': calibrated ? old!['lat'] : g.lat,
        'lng': calibrated ? old!['lng'] : g.lng,
        'calibrated': calibrated,
        'leader': await generateLeader(g.type),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    batch.set(PartyService.party(party), {
      'gameStarted': true,
      'startedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  /// Il Master, sul posto, imposta la posizione reale della palestra.
  static Future<void> calibrate(String party, String gymId, double lat, double lng) =>
      gyms(party).doc(gymId).set({'lat': lat, 'lng': lng, 'calibrated': true}, SetOptions(merge: true));

  // ------------------------------------------------------------------ badge

  /// Assegna il badge se non lo hai già. Restituisce true se è nuovo.
  static Future<bool> awardBadge(String uid, String gymId, String name, String type) async {
    final ref = ItemService.userRef(uid);
    final badges = (await ref.get()).data()?['badges'];
    if (badges is Map && badges[gymId] != null) return false;
    await ref.set({
      'badges': {
        gymId: {'name': name, 'type': type, 'at': FieldValue.serverTimestamp()},
      },
    }, SetOptions(merge: true));
    return true;
  }
}
