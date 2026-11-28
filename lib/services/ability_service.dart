import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../abilities.dart';
import '../items.dart';
import '../mode.dart';
import '../table/phases.dart';
import '../table/zones.dart';
import 'item_service.dart';
import 'live_service.dart';
import 'party_service.dart';
import 'shared_stream.dart';
import 'table_service.dart';

int _i(dynamic v, [int d = 0]) => v is num ? v.toInt() : d;

/// Esito dell'uso di un'attiva: messaggio breve, righe da mostrare (Impulso, Ricognizione...) e,
/// per Sfida e Imboscata, la battaglia da aprire.
class AbilityResult {
  final String message;
  final List<String> lines;
  final String? battleId;
  const AbilityResult(this.message, {this.lines = const [], this.battleId});
}

/// Abilità dei Pokémon: sblocco con i badge, scelta, uso delle attive ed effetti di settore.
///
/// Firestore:
///   Users/{uid}.gameBadges                  -> [gymId, ...]   palestre vinte in QUESTA partita (si azzera a ogni
///                                              nuova partita; `badges` resta lo storico)
///   Users/{uid}/Pokemon/{pk}                -> abilities, abilityOffer, abilityNotice, abilityOfferNext,
///                                              abilityUsedRound, abilityActiveUntil, abilityActiveKey (vedi abilities.dart)
///   Party/{codice}/sectorEffects/{id}       -> { kind, zone, sector, owner, untilRound, active }
///       effetti delle abilità sulla mappa (Gelata, Esca tossica, Rovi, Barricata, Sismo...): si leggono negli stessi
///       punti di trappole, allarmi e settori bloccati. [sector] null = tutta la zona; [zone] null = effetto personale.
class AbilityService {
  static final _db = FirebaseFirestore.instance;
  static final _rnd = Random();

  /// Campi del Pokémon da azzerare a ogni nuova partita.
  static Map<String, dynamic> resetFields() => {
        'abilities': FieldValue.delete(),
        'abilityOffer': FieldValue.delete(),
        'abilityNotice': FieldValue.delete(),
        'abilityOfferNext': FieldValue.delete(),
        'abilityUsedRound': FieldValue.delete(),
        'abilityActiveUntil': FieldValue.delete(),
        'abilityActiveKey': FieldValue.delete(),
      };

  // ------------------------------------------------------------------- dati

  static Future<DocumentReference<Map<String, dynamic>>?> pokemonRef(String uid, [Map<String, dynamic>? user]) async {
    final pk = await TableService.activePokemon(uid, user);
    return pk == null ? null : ItemService.userRef(uid).collection('Pokemon').doc(pk);
  }

  /// Documento del Pokémon con cui [uid] gioca (null se non ne ha).
  static Future<Map<String, dynamic>?> pokemonOf(String uid, [Map<String, dynamic>? user]) async {
    final ref = await pokemonRef(uid, user);
    return ref == null ? null : (await ref.get()).data();
  }

  /// Passive sbloccate da [uid].
  static Future<Set<String>> passives(String uid, [Map<String, dynamic>? user]) async => passivesOf(await pokemonOf(uid, user));

  static Stream<Map<String, dynamic>?> watchPokemon(String uid, String pk) => shared(
      'abilityPk:$uid/$pk', () => ItemService.userRef(uid).collection('Pokemon').doc(pk).snapshots().map((s) => s.data()));

  // ------------------------------------------------------------ effetti di settore

  static CollectionReference<Map<String, dynamic>> effectsCol(String party) =>
      PartyService.party(party).collection('sectorEffects');

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchEffects(String party) =>
      shared('sectorEffects:$party', () => effectsCol(party).snapshots());

  /// Un effetto è in corso se non è stato consumato/tolto e il suo ultimo giro non è passato.
  static bool effectLive(Map<String, dynamic> e, int round) => e['active'] != false && _i(e['untilRound'], -1) >= round;

  /// Effetti in corso nel party (con 'id').
  static Future<List<Map<String, dynamic>>> activeEffects(String party, {int? round}) async {
    final r = round ?? TableClock.round;
    return [
      for (final d in (await effectsCol(party).get()).docs)
        if (effectLive(d.data(), r)) {...d.data(), 'id': d.id},
    ];
  }

  /// Aggiunge un effetto di settore/zona/personale che dura [rounds] giri da quello corrente.
  static Future<void> addEffect(String party,
      {required String kind, required String owner, String? zone, int? sector, required int rounds, Map<String, dynamic>? extra}) =>
      effectsCol(party).add({
        'kind': kind,
        'owner': owner,
        'zone': zone,
        'sector': sector,
        'untilRound': TableClock.round + rounds - 1,
        'active': true,
        'at': FieldValue.serverTimestamp(),
        ...?extra,
      });

  /// Gli altri giocatori nella stessa zona (e, se [sameSector], nello stesso settore) di [uid].
  static Future<List<String>> playersNear(String party, String uid, {bool sameSector = true}) async {
    final pos = (await ItemService.userRef(uid).get()).data()?['pos'] as Map?;
    if (pos == null) return const [];
    final out = <String>[];
    for (final p in (await PartyService.players(party).get()).docs) {
      if (p.id == uid) continue;
      final o = (await ItemService.userRef(p.id).get()).data()?['pos'] as Map?;
      if (o == null || o['zone'] != pos['zone']) continue;
      if (sameSector && _i(o['sector']) != _i(pos['sector'])) continue;
      out.add(p.id);
    }
    return out;
  }

  /// Sismo: i settori della tua zona che puoi bloccare (non il tuo, non quello del leggendario, non già bloccati).
  static Future<List<int>> quakeSectors(String party, String uid) async {
    await TableService.loadLayout(party);
    final pos = (await ItemService.userRef(uid).get()).data()?['pos'] as Map?;
    if (pos == null) return const [];
    final zone = '${pos['zone']}';
    final events = await TableService.activeEvents(party);
    final legendary = {
      for (final e in events)
        if (e['zone'] == zone && e['legendary'] == true && e['sector'] != null) _i(e['sector']),
    };
    final blocked = TableService.blockedSectors(events, zone);
    return [
      for (var s = 1; s <= TableLayout.count(zone); s++)
        if (s != _i(pos['sector']) && !legendary.contains(s) && !blocked.contains(s)) s,
    ];
  }

  /// Forgia: ogni ricetta fatta con uno solo dei suoi ingredienti (per Pozione + Elisir si sceglie quale dare).
  static List<({Recipe recipe, ItemId pay})> forgeOptions() => [
        for (final r in kRecipes)
          for (final id in r.inputs.keys) (recipe: r, pay: id),
      ];

  static String forgeLabel(({Recipe recipe, ItemId pay}) o) => '${itemDef(o.recipe.output).name} con 1 ${itemDef(o.pay).name}';

  // ------------------------------------------------------------------- sblocco

  /// Nuovo badge nella partita in corso: estrae le abilità da offrire (o le sblocca subito).
  /// Restituisce un testo per il premio (null se il kit è già completo).
  static Future<String?> onBadge(String uid) async {
    final ref = await pokemonRef(uid);
    if (ref == null) return null;
    return _db.runTransaction<String?>((tx) async {
      final p = (await tx.get(ref)).data() ?? {};
      if (p['abilityOffer'] is List && (p['abilityOffer'] as List).isNotEmpty) {
        // c'è già una scelta in sospeso: questa si apre dopo
        tx.set(ref, {'abilityOfferNext': FieldValue.increment(1)}, SetOptions(merge: true));
        return 'Nuova abilità in arrivo dopo la scelta in sospeso';
      }
      final r = badgeReward(p, rnd: _rnd);
      if (r.offer.isNotEmpty) {
        tx.set(ref, {'abilityOffer': r.offer}, SetOptions(merge: true));
        return 'Nuova abilità: scegline una';
      }
      if (r.unlock.isNotEmpty) {
        tx.set(ref, {
          'abilities': FieldValue.arrayUnion(r.unlock),
          'abilityNotice': FieldValue.arrayUnion(r.unlock),
        }, SetOptions(merge: true));
        return 'Hai sbloccato: ${r.unlock.map((k) => abilityDef(k)!.name).join(' e ')}';
      }
      return null;
    });
  }

  /// Il giocatore sceglie una delle abilità offerte.
  static Future<void> choose(String uid, String key) async {
    final ref = await pokemonRef(uid);
    if (ref == null) throw Exception('Nessun Pokémon');
    await _db.runTransaction<void>((tx) async {
      final p = (await tx.get(ref)).data() ?? {};
      final offer = [for (final k in (p['abilityOffer'] as List? ?? const [])) '$k'];
      if (!offer.contains(key)) throw Exception('Questa abilità non è tra quelle offerte');
      final after = {...p, 'abilities': [...unlockedAbilities(p), key]};
      final update = <String, dynamic>{
        'abilities': FieldValue.arrayUnion([key]),
        'abilityOffer': FieldValue.delete(),
      };
      // badge vinti mentre la scelta era in sospeso
      final next = _i(p['abilityOfferNext']);
      if (next > 0) {
        update['abilityOfferNext'] = next - 1 > 0 ? next - 1 : FieldValue.delete();
        final r = badgeReward(after, rnd: _rnd);
        if (r.offer.isNotEmpty) update['abilityOffer'] = r.offer;
        if (r.unlock.isNotEmpty) {
          update['abilities'] = FieldValue.arrayUnion([key, ...r.unlock]);
          update['abilityNotice'] = FieldValue.arrayUnion(r.unlock);
        }
      }
      tx.set(ref, update, SetOptions(merge: true));
    });
  }

  /// Chiude la finestra "Hai sbloccato…".
  static Future<void> dismissNotice(String uid) async {
    final ref = await pokemonRef(uid);
    if (ref != null) await ref.set({'abilityNotice': FieldValue.delete()}, SetOptions(merge: true));
  }

  // ------------------------------------------------------------------------ uso

  /// Usa l'attiva [key]. Al tavolo costa [kAbilityActionCost] azione (regole di actBlock), dal vivo
  /// un'attesa breve. [target] = giocatore scelto (Sfida, Spavento); [sector] = settore scelto (Sismo);
  /// [recipe] = indice della ricetta (Forgia).
  static Future<AbilityResult> use({
    required String party,
    required String uid,
    required String key,
    String? target,
    int? sector,
    int? recipe,
  }) async {
    final def = abilityDef(key);
    if (def == null || !def.active) throw Exception('Abilità sconosciuta');
    final pref = await pokemonRef(uid);
    if (pref == null) throw Exception('Nessun Pokémon');
    final st = (await TableService.stateRef(party).get()).data();
    if (st == null || st['started'] != true) throw Exception('La partita non è ancora iniziata');
    final round = _i(st['round'], 1);
    TableClock.round = round;
    final me = (await ItemService.userRef(uid).get()).data() ?? {};
    final pk = (await pref.get()).data() ?? {};
    final why = abilityBlock(pk, key, round);
    if (why != null) throw Exception(why);
    if (me['wildEncounter'] is Map) throw Exception('Prima affronta o sfuggi al Pokémon selvatico');
    if (me['spotted'] is Map) throw Exception('Ti hanno notato: prima elùdili (azione o Fune di fuga)');
    if (!kTableMode) LiveService.assertNotBusy(me);

    // il costo: al tavolo un'azione, dal vivo un'attesa breve (le reazioni non costano nulla)
    if (!def.reaction) {
      if (kTableMode) {
        await TableService.spendAction(party, uid, kind: ActKind.ability);
      } else {
        await ItemService.userRef(uid).set(LiveService.addBusy(me, kLiveAbilityWaitMinutes), SetOptions(merge: true));
      }
    }
    await _db.runTransaction<void>((tx) async {
      final cur = (await tx.get(pref)).data() ?? {};
      final again = abilityBlock(cur, key, round);
      if (again != null) throw Exception(again);
      tx.set(pref, {
        'abilityUsedRound': {key: round},
        if (def.effectRounds > 0) 'abilityActiveUntil': round + def.effectRounds - 1,
        if (def.effectRounds > 0) 'abilityActiveKey': key,
      }, SetOptions(merge: true));
    });
    return _apply(party: party, uid: uid, def: def, me: me, round: round);
  }

  /// Effetto dell'attiva (le singole abilità sono implementate nelle fasi 9.C e 9.D).
  static Future<AbilityResult> _apply({
    required String party,
    required String uid,
    required AbilityDef def,
    required Map<String, dynamic> me,
    required int round,
  }) async {
    return AbilityResult('${def.name} usata');
  }
}
