import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../items.dart';
import '../table/sectors.dart';
import 'ability_service.dart';
import 'gym_service.dart';
import 'item_service.dart';
import 'table_service.dart';
import 'party_service.dart';
import 'shared_stream.dart';

int _i(dynamic v, [int def = 0]) => v is num ? v.round() : def;

List<String> _lowerList(dynamic v) => v is List
    ? v.map((e) => e.toString().trim().toLowerCase()).toList()
    : <String>[];

Map<String, dynamic> _copy(dynamic m) => m is Map
    ? m.map((k, v) => MapEntry(k.toString(),
        v is Map ? _copy(v) : (v is List ? List<dynamic>.from(v) : v)))
    : <String, dynamic>{};

/// Risultato del tiro di un attacco.
class AttackRoll {
  final int dice;
  final String category; // Nullo, Debole, Medio, Forte, Forte e Imbloccabile
  final int bonus;
  final int elementalModifier;
  final bool unblockable;
  final bool statusTriggered;
  final Map<String, dynamic>? status;
  final int rawDice; // tiro del dado prima di eventuali bonus (Caramella Rara)
  AttackRoll(this.dice, this.category, this.bonus, this.elementalModifier,
      this.unblockable, this.statusTriggered, this.status, this.rawDice);
}

class BattleService {
  static final _db = FirebaseFirestore.instance;
  static final _rnd = Random();

  static DocumentReference<Map<String, dynamic>> battleRef(String id) =>
      _db.collection('Battles').doc(id);

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String id) =>
      shared('battle:$id', () => battleRef(id).snapshots());

  // ---------------------------------------------------------------- dati

  static Stream<Map<String, Map<String, dynamic>>> watchMoves(String uid, String pk) =>
      shared('moves:$uid/$pk', () => _db.collection('Users').doc(uid).collection('Pokemon').doc(pk)
          .collection('MoveSet').snapshots().map((s) => {
                for (final d in s.docs) d.id: d.data(),
              }));

  static Future<Map<String, Map<String, dynamic>>> loadMoves(String uid, String pk) async {
    final s = await _db.collection('Users').doc(uid).collection('Pokemon').doc(pk)
        .collection('MoveSet').get();
    return {for (final d in s.docs) d.id: d.data()};
  }

  /// PS con cui il Pokémon entra in battaglia: quelli con cui è finito lo scontro precedente
  /// (`currentHp` sul documento del Pokémon). Se era stato sconfitto (0 PS) ed è qui, il recupero
  /// è finito o ha usato un Revitalizzante: riparte con tutti i PS. Il capopalestra e il leggendario
  /// non hanno `currentHp` e partono sempre pieni.
  static int startHp(Map<String, dynamic> pokemon) {
    final hp = (pokemon['currentHp'] as num?)?.toInt();
    if (hp == null || hp <= 0) return kBaseHp;
    return min(hp, kBaseHp);
  }

  /// Energie con cui il Pokémon entra in battaglia: quelle con cui è finito lo scontro precedente
  /// (`currentEnergy`), piene se non ce ne sono o se era stato sconfitto (dopo il recupero riparte pieno).
  static int startEnergy(Map<String, dynamic> pokemon) {
    final hp = (pokemon['currentHp'] as num?)?.toInt();
    final en = (pokemon['currentEnergy'] as num?)?.toInt();
    if (en == null || (hp != null && hp <= 0)) return kBaseEnergy;
    return en.clamp(0, kBaseEnergy);
  }

  /// Status alterato che il Pokémon si porta dietro (`currentStatus`: dot, slow, debuff con i turni rimasti).
  /// Dopo una sconfitta (recupero) sparisce.
  static Map<String, dynamic>? startStatus(Map<String, dynamic> pokemon) {
    final hp = (pokemon['currentHp'] as num?)?.toInt();
    final s = pokemon['currentStatus'];
    if (s is! Map || (hp != null && hp <= 0)) return null;
    return Map<String, dynamic>.from(s);
  }

  /// Nome leggibile di uno status alterato.
  static String statusLabel(Map? s) => switch (s?['type']) {
        'dot' => 'Avvelenato',
        'slow' => 'Rallentato',
        'debuff' => 'Indebolito',
        null => '',
        _ => '${s?['type']}',
      };

  /// PS attuali fuori dalla battaglia. Con [ko] (sconfitto e ancora in recupero) sono 0.
  static int currentHp(Map<String, dynamic>? pokemon, {bool ko = false}) =>
      ko && ((pokemon?['currentHp'] as num?)?.toInt() ?? kBaseHp) <= 0 ? 0 : startHp(pokemon ?? const {});

  /// Pozione / Super Pozione dalla Borsa: cura il Pokémon fuori dalla battaglia.
  /// Restituisce i PS recuperati.
  static Future<int> healOutsideBattle({required String uid, required String pk, required ItemId item}) {
    final heal = switch (item) {
      ItemId.pozione => kPotionHeal,
      ItemId.superPozione => kSuperPotionHeal,
      _ => throw Exception('Questo strumento non cura'),
    };
    final uref = ItemService.userRef(uid);
    final pref = uref.collection('Pokemon').doc(pk);
    return _db.runTransaction<int>((tx) async {
      final u = (await tx.get(uref)).data() ?? {};
      final p = (await tx.get(pref)).data() ?? {};
      final ko = ItemService.isActive(u['koUntil']);
      final hp = currentHp(p, ko: ko);
      if (ko && hp <= 0) throw Exception('Il tuo Pokémon è esausto: serve un Revitalizzante');
      if (hp >= kBaseHp) throw Exception('Il tuo Pokémon ha già tutti i PS');
      final inv = ItemService.readInventory(u);
      if ((inv[item.name] ?? 0) <= 0) throw Exception('Non hai più ${itemDef(item).name}');
      inv[item.name] = inv[item.name]! - 1;
      final healed = min(heal, kBaseHp - hp);
      tx.set(uref, {'inventory': inv}, SetOptions(merge: true));
      tx.set(pref, {'currentHp': hp + healed}, SetOptions(merge: true));
      return healed;
    });
  }

  /// Elisir (energie) e Antidoto (status alterato) dalla Borsa, fuori dalla battaglia.
  /// Restituisce un breve testo con l'effetto.
  static Future<String> useOutsideBattle({required String uid, required String pk, required ItemId item}) {
    if (item != ItemId.elisir && item != ItemId.antidoto) throw Exception('Questo strumento si usa in battaglia');
    final uref = ItemService.userRef(uid);
    final pref = uref.collection('Pokemon').doc(pk);
    return _db.runTransaction<String>((tx) async {
      final u = (await tx.get(uref)).data() ?? {};
      final p = (await tx.get(pref)).data() ?? {};
      if (ItemService.isActive(u['koUntil'])) throw Exception('Il tuo Pokémon è esausto: serve un Revitalizzante');
      final inv = ItemService.readInventory(u);
      if ((inv[item.name] ?? 0) <= 0) throw Exception('Non hai più ${itemDef(item).name}');
      final update = <String, dynamic>{};
      late String msg;
      if (item == ItemId.elisir) {
        final en = startEnergy(p);
        if (en >= kBaseEnergy) throw Exception('Il tuo Pokémon ha già tutte le energie');
        final gained = min(kEnergyElixir, kBaseEnergy - en);
        update['currentEnergy'] = en + gained;
        msg = '⚡ +$gained energie';
      } else {
        if (startStatus(p) == null) throw Exception('Il tuo Pokémon non ha status alterati');
        update['currentStatus'] = FieldValue.delete();
        msg = 'Status alterato rimosso';
      }
      inv[item.name] = inv[item.name]! - 1;
      tx.set(uref, {'inventory': inv}, SetOptions(merge: true));
      tx.set(pref, update, SetOptions(merge: true));
      return msg;
    });
  }

  /// A fine scontro (vittoria, sconfitta, pareggio o fuga) PS, energie e status alterato restano
  /// quelli finali e il Pokémon se li porta allo scontro successivo.
  static Future<void> _saveHp(Map? player) async {
    final uid = player?['uid'] as String?;
    final pk = player?['pokemon_doc_id'] as String?;
    if (uid == null || pk == null || uid.startsWith('gym:')) return;
    final stato = player!['stato'];
    await _db.collection('Users').doc(uid).collection('Pokemon').doc(pk).set(
      {
        'currentHp': _i(player['current_hp']).clamp(0, _i(player['max_hp'], kBaseHp)),
        'currentEnergy': _i(player['current_energies'], kBaseEnergy).clamp(0, _i(player['max_energies'], kBaseEnergy)),
        'currentStatus': stato is Map ? stato : FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
  }

  static Map<String, dynamic> _combatant(String uid, String pk,
      Map<String, dynamic> d, Map<String, Map<String, dynamic>> moves) {
    List<String> list(dynamic v) =>
        v is List && v.isNotEmpty ? v.map((e) => e.toString()).toList() : ['N/A'];
    return {
      'uid': uid,
      'pokemon_doc_id': pk,
      'pokemon_name': pk,
      'type': (d['PkmTypePrim'] ?? d['typePrim'] ?? '').toString(),
      'resistenze': list(d['Resistenze']),
      'debolezze': list(d['Debolezze']),
      'current_hp': startHp(d),
      'max_hp': kBaseHp,
      // energie e status restano tra uno scontro e l'altro (capipalestra e leggendari partono pieni)
      'current_energies': startEnergy(d),
      'max_energies': kBaseEnergy,
      if (startStatus(d) != null) 'stato': startStatus(d),
      'last_action': 'none',
      'turn_ready': false,
      'moveset_data': moves,
      'Atk': d['Atk'] ?? 0,
      'AtkSpec': d['AtkSpec'] ?? 0,
      'Def': d['Def'] ?? 0,
      'DefSpec': d['DefSpec'] ?? 0,
      'Vel': d['Vel'] ?? 0,
    };
  }

  static Future<Map<String, dynamic>> _pokemonData(String uid, String pk) async {
    final snap = await _db.collection('Users').doc(uid).collection('Pokemon').doc(pk).get();
    if (!snap.exists || snap.data() == null) {
      throw Exception('Statistiche non trovate per $pk');
    }
    return snap.data()!;
  }

  // -------------------------------------------------- creazione / ingresso

  static String _randomCode(int n) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(n, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }

  /// Bonus di danno dovuti agli eventi attivi nella zona del giocatore (tavolo e dal vivo).
  static Future<Map<String, dynamic>> _zoneFields(String uid) async {
    final party = await PartyService.actualParty(uid);
    final bonus = await TableService.zoneBonusFor(party, uid);
    return bonus.isEmpty ? {} : {'zoneBonus': bonus};
  }

  /// Crea una battaglia in attesa. Codice: `{utente}-{3 caratteri}-{HHmm}`.
  static Future<String> createBattle(String uid, String pk) async {
    await ItemService.assertCanFight(uid);
    await TableService.assertNotInRefuge(uid); // nei rifugi non si combatte tra giocatori
    final moves = await loadMoves(uid, pk);
    final d = await _pokemonData(uid, pk);
    final now = DateTime.now();
    final hhmm = now.hour.toString().padLeft(2, '0') + now.minute.toString().padLeft(2, '0');
    final id = '$uid-${_randomCode(3)}-$hhmm';
    await battleRef(id).set({
      'status': 'pending',
      'turn_number': 0,
      'playerA': _combatant(uid, pk, d, moves),
      'playerB': null,
      'last_turn_log': 'In attesa del secondo giocatore...',
      ...await _zoneFields(uid),
    });
    return id;
  }

  static Future<void> joinBattle(String id, String uid, String pk) async {
    final moves = await loadMoves(uid, pk);
    final d = await _pokemonData(uid, pk);
    final ref = battleRef(id);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Battaglia non trovata');
    final data = snap.data()!;
    if (data['status'] != 'pending') throw Exception('Battaglia già iniziata');
    if ((data['playerA'] as Map?)?['uid'] == uid) {
      throw Exception('Non puoi sfidare te stesso');
    }
    final creator = (data['playerA'] as Map?)?['uid'] as String?;
    await ItemService.assertCanFight(uid, opponentUid: creator);
    await TableService.assertNotInRefuge(uid);
    if (creator != null) await TableService.assertNotInRefuge(creator, me: false);
    await ref.update({
      'status': 'in_progress',
      'playerB': _combatant(uid, pk, d, moves),
      'last_turn_log': 'La battaglia è iniziata! Scegli la tua mossa.',
    });
  }

  /// Registra la scelta del turno. `action`: attack | attackSpec | defense | dodge.
  static Future<void> chooseAction({
    required String battleId,
    required String playerKey, // playerA | playerB
    required String action,
    String? moveName,
    String? itemKey,
  }) async {
    final ref = battleRef(battleId);
    await ref.update({
      '$playerKey.last_item': action == 'item' ? itemKey : null,
      '$playerKey.last_action': action,
      '$playerKey.last_move_used': (action == 'attack' || action == 'attackSpec') ? moveName : null,
      '$playerKey.turn_ready': true,
    });
    // Contro un capopalestra l'avversario risponde subito, in modo casuale ma coerente col tipo.
    final d = (await ref.get()).data();
    if (d == null || d['npc'] != true || d['status'] != 'in_progress') return;
    final npcKey = playerKey == 'playerA' ? 'playerB' : 'playerA';
    final npc = d[npcKey] as Map?;
    if (npc == null || npc['turn_ready'] == true) return;
    final dec = npcDecision(Map<String, dynamic>.from(npc));
    await ref.update({
      '$npcKey.last_action': dec.action,
      '$npcKey.last_move_used': dec.move,
      '$npcKey.turn_ready': true,
    });
  }

  /// Scelta del capopalestra: Difesa/Schiva con le probabilità del suo tipo
  /// (es. Volante schiva spesso, Roccia si difende), altrimenti una mossa che
  /// può permettersi, con preferenza per quelle più forti quando ha energia.
  static ({String action, String? move}) npcDecision(Map<String, dynamic> npc, {Random? rnd}) {
    final r = rnd ?? _rnd;
    final energy = _i(npc['current_energies']);
    final moves = (npc['moveset_data'] as Map? ?? {}).entries
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .where((m) => energyCostForDmg(_i(m['Dmg'], 1)) <= energy)
        .toList();
    if (moves.isEmpty) return (action: 'defense', move: null); // recupera energie
    final ai = npc['ai'] as Map? ?? {};
    final pDef = (ai['defense'] as num?)?.toDouble() ?? 0.15;
    final pDodge = (ai['dodge'] as num?)?.toDouble() ?? 0.1;
    final roll = r.nextDouble();
    if (roll < pDef) return (action: 'defense', move: null);
    if (roll < pDef + pDodge) return (action: 'dodge', move: null);
    // Mossa pesata sul danno (le più forti sono più probabili)
    final weights = moves.map((m) => 1 + _i(m['Dmg'], 1)).toList();
    var pick = r.nextInt(weights.fold<int>(0, (a, b) => a + b));
    var chosen = moves.first;
    for (var i = 0; i < moves.length; i++) {
      pick -= weights[i];
      if (pick < 0) {
        chosen = moves[i];
        break;
      }
    }
    return (
      action: chosen['MoveTypo'] == 'Speciale' ? 'attackSpec' : 'attack',
      move: chosen['MoveName'] as String,
    );
  }

  /// Sfida a un capopalestra: la battaglia parte subito, contro un combattente NPC.
  static Future<String> createGymBattle({
    required String party,
    required String gymId,
    required Map<String, dynamic> gym,
    required String uid,
    required String pk,
    Map<String, dynamic>? extra,
  }) async {
    await ItemService.assertCanFight(uid);
    final moves = await loadMoves(uid, pk);
    final d = await _pokemonData(uid, pk);
    final l = Map<String, dynamic>.from(gym['leader'] as Map);
    final npcMoves = (l['moves'] as Map).map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
    final npc = _combatant('gym:$gymId', l['pokemon'] as String, l, npcMoves)
      ..['npc'] = true
      ..['trainer'] = l['trainer']
      ..['ai'] = l['ai'];
    final id = '$uid-$gymId-${_randomCode(3)}';
    await battleRef(id).set({
      'status': 'in_progress',
      'turn_number': 0,
      'npc': true,
      'gymId': gymId,
      'gymName': gym['name'],
      'gymType': gym['type'],
      'party': party,
      'playerA': _combatant(uid, pk, d, moves),
      'playerB': npc,
      'last_turn_log': l['trainer'] != null
          ? 'Il capopalestra ${l['trainer']} ti sfida con ${l['pokemon']}! Scegli la tua mossa.'
          : '${l['pokemon']} leggendario ti sfida! Scegli la tua mossa.',
      ...await _zoneFields(uid),
      ...?extra,
    });
    return id;
  }

  // -------------------------------------------------------------- oggetti

  /// Strumenti curativi usabili in battaglia (consumano il turno).
  static const kBattleConsumables = [ItemId.pozione, ItemId.superPozione, ItemId.elisir, ItemId.antidoto];

  /// Usa un curativo in battaglia: consuma l'oggetto e il turno.
  static Future<void> useBattleItem({
    required String battleId,
    required String playerKey,
    required String uid,
    required ItemId item,
  }) async {
    if (!kBattleConsumables.contains(item)) throw Exception('Questo strumento non si usa così');
    await ItemService.consume(uid, item);
    await chooseAction(battleId: battleId, playerKey: playerKey, action: 'item', itemKey: item.name);
  }

  /// Compatibilità: Pozione.
  static Future<void> usePotion({required String battleId, required String playerKey, required String uid}) =>
      useBattleItem(battleId: battleId, playerKey: playerKey, uid: uid, item: ItemId.pozione);

  /// Oggetti da dichiarare prima del primo turno -> campo sul combattente.
  static const _prefight = {
    ItemId.caramella: 'candy',
    ItemId.amuleto: 'amulet',
    ItemId.guanto: 'glove',
  };

  static Future<void> declarePrefight({
    required String battleId,
    required String playerKey,
    required String uid,
    required ItemId item,
  }) async {
    final field = _prefight[item];
    if (field == null) throw Exception('Questo strumento non si dichiara');
    final ref = battleRef(battleId);
    final d = (await ref.get()).data();
    if (d == null) throw Exception('Battaglia non trovata');
    if ((d['turn_number'] as num? ?? 0) > 0 || (d['status'] != 'pending' && d['status'] != 'in_progress')) {
      throw Exception('${itemDef(item).name}: va dichiarato prima dello scontro');
    }
    if ((d[playerKey] as Map?)?[field] == true) throw Exception('${itemDef(item).name} già attivo');
    await ItemService.consume(uid, item);
    await ref.update({'$playerKey.$field': true});
  }

  /// Caramella Rara: va dichiarata prima del primo turno; +[kCandyBonus] ai tiri del giocatore.
  static Future<void> declareCandy({required String battleId, required String playerKey, required String uid}) async {
    final ref = battleRef(battleId);
    final snap = await ref.get();
    final d = snap.data();
    if (d == null) throw Exception('Battaglia non trovata');
    if ((d['turn_number'] as num? ?? 0) > 0 || (d['status'] != 'pending' && d['status'] != 'in_progress')) {
      throw Exception('La Caramella Rara va dichiarata prima dello scontro');
    }
    if ((d[playerKey] as Map?)?['candy'] == true) throw Exception('Caramella Rara già attiva');
    await ItemService.consume(uid, ItemId.caramella);
    await ref.update({'$playerKey.candy': true});
  }

  /// Fune di fuga: la battaglia termina all'istante; direzione casuale e
  /// blocco temporaneo dello scontro tra le due squadre. Restituisce la direzione.
  static Future<String> flee({required String battleId, required String playerKey}) async {
    const dirs = ['nord', 'nord-est', 'est', 'sud-est', 'sud', 'sud-ovest', 'ovest', 'nord-ovest'];
    final dir = dirs[_rnd.nextInt(dirs.length)];
    final ref = battleRef(battleId);
    final fighters = <Map>[];
    await _db.runTransaction<void>((tx) async {
      final b = (await tx.get(ref)).data();
      if (b == null || b['status'] != 'in_progress') throw Exception('La battaglia non è in corso');
      final me = Map<String, dynamic>.from(b[playerKey] as Map);
      final opp = Map<String, dynamic>.from(b[playerKey == 'playerA' ? 'playerB' : 'playerA'] as Map);
      fighters
        ..clear()
        ..addAll([me, opp]);
      final meRef = ItemService.userRef(me['uid'] as String);
      final oppRef = ItemService.userRef(opp['uid'] as String);
      final inv = ItemService.readInventory((await tx.get(meRef)).data());
      if ((inv['fune'] ?? 0) <= 0) throw Exception('Non hai Funi di fuga');
      inv['fune'] = inv['fune']! - 1;
      final until = ItemService.fleeUntil();
      final oppIsNpc = (opp['uid'] as String).startsWith('gym:');
      tx.set(meRef, {'inventory': inv, if (!oppIsNpc) 'fleeBlocks': {opp['uid']: until}}, SetOptions(merge: true));
      if (!oppIsNpc) tx.set(oppRef, {'fleeBlocks': {me['uid']: until}}, SetOptions(merge: true));
      tx.update(ref, {
        'status': 'fled',
        'fledBy': me['uid'],
        'fleeDirection': dir,
        'processing': FieldValue.delete(),
        'last_turn_log':
            '${me['pokemon_name']} usa la Fune di fuga! La battaglia termina: allontanatevi verso $dir.',
      });
    });
    // anche fuggendo si resta con i PS che si avevano
    for (final p in fighters) {
      await _saveHp(p);
    }
    return dir;
  }

  // ------------------------------------------------------------ regole

  /// Tiro d20 + categoria + modificatore elementale + eventuale stato alterato.
  static AttackRoll rollAttack({
    required String? altEffect,
    required double altPerc,
    required String? targetStat,
    required int atk,
    required int atkSpec,
    required int dmg,
    required List<String> targetWeak,
    required String moveType,
    required String action,
    required List<String> targetRes,
    int diceBonus = 0,
    Random? rnd,
  }) {
    final r = rnd ?? _rnd;
    final rawDice = r.nextInt(20) + 1;
    final dice = rawDice + diceBonus; // il bonus sposta il tiro verso le categorie più forti
    final stat = (action == 'attack' ? atk : atkSpec) * 0.3;
    final tWeak = (9 - stat).clamp(2, 9).toDouble();
    final tMed = (14 - stat).clamp(5, 14).toDouble();
    final tStrong = (18 - stat).clamp(10, 18).toDouble();

    String category;
    int idx;
    var bonus = 0;
    var unblockable = false;
    if (rawDice == 1) {
      category = 'Nullo'; // un 1 naturale resta Nullo anche con la Caramella
      idx = 0;
    } else if (dice <= tWeak) {
      category = 'Debole';
      idx = 1;
    } else if (dice <= tMed) {
      category = 'Medio';
      idx = 2;
      bonus = 2;
    } else if (dice <= tStrong) {
      category = 'Forte';
      idx = 3;
      bonus = 3;
    } else {
      category = 'Forte e Imbloccabile';
      idx = 4;
      bonus = 3;
      unblockable = true;
    }

    // Effetto alterato
    Map<String, dynamic>? status;
    var triggered = false;
    if (altEffect != null && altPerc > 0) {
      triggered = r.nextDouble() <= altPerc;
      if (triggered) {
        final e = altEffect.toLowerCase();
        if (e == 'danno' || e == 'dot') {
          status = {
            'type': 'dot',
            'damage_per_turn': (0.15 * exp(0.35 * dmg)).round().clamp(1, 10),
            'remaining_turns': 2,
          };
        } else if (e == 'rallentamento' || e == 'slow') {
          status = {'type': 'slow', 'value': -2, 'remaining_turns': 3};
        } else if (e == 'debuff') {
          status = {
            'type': 'debuff',
            'stat': targetStat ?? 'Atk',
            'value': -1,
            'remaining_turns': 3,
          };
        }
      }
    }

    // Modificatore elementale: debolezza = +categoria, resistenza = -categoria
    final t = moveType.trim().toLowerCase();
    var elem = targetWeak.contains(t) ? idx : 0;
    if (targetRes.contains(t)) elem -= idx;

    return AttackRoll(dice, category, bonus, elem, unblockable, triggered, status, rawDice);
  }

  /// Il client che vede entrambi i giocatori pronti prova a risolvere il turno.
  /// Una transazione assicura che un solo client lo elabori.
  static Future<void> processTurn(String battleId) async {
    final ref = battleRef(battleId);
    bool skip;
    try {
      skip = await _db.runTransaction<bool>((tx) async {
        final d = (await tx.get(ref)).data() ?? {};
        if (d['status'] != 'in_progress' || d['processing'] == true) return true;
        final a = d['playerA'] as Map?;
        final b = d['playerB'] as Map?;
        final ready = a != null && a['turn_ready'] == true && b != null && b['turn_ready'] == true;
        if (!ready) return true;
        tx.update(ref, {'processing': true});
        return false;
      });
    } catch (e) {
      debugPrint('processBattleTurn: transaction lock fallita: $e');
      return;
    }
    if (skip) return;

    final data = (await ref.get()).data()!;
    final result = computeTurn(data);
    await ref.update(result.updates);

    // Fine scontro: i PS finali restano al Pokémon (non si ricaricano).
    if (result.status != 'in_progress') {
      for (final k in ['playerA', 'playerB']) {
        final p = data[k] as Map?;
        if (p == null) continue;
        final st = result.updates['$k.stato'];
        await _saveHp({
          ...p,
          'current_hp': result.updates['$k.current_hp'],
          'current_energies': result.updates['$k.current_energies'],
          'stato': st is Map ? st : null,
        });
      }
    }

    // Sconfitta: il Pokémon perdente è esausto per qualche minuto.
    final loserKey = result.status == 'playerA_win'
        ? 'playerB'
        : (result.status == 'playerB_win' ? 'playerA' : null);
    if (loserKey != null) {
      final loserUid = (data[loserKey] as Map?)?['uid'] as String?;
      if (loserUid != null && !loserUid.startsWith('gym:')) await ItemService.setKo(loserUid);
    }

    if (result.winnerUid != null) {
      if (data['npc'] != true && !result.winnerUid!.startsWith('gym:')) {
        // Vittoria PvP: monete e, a volte, uno strumento.
        final drop = _rnd.nextDouble() < kPvpDropChance ? [ItemService.randomDrop(rnd: _rnd)] : <ItemId>[];
        final txt = await ItemService.grant(result.winnerUid!, coins: kCoinsPvpWin, items: drop);
        await ref.update({'rewardText': txt, 'rewardFor': result.winnerUid});
      }
      if (data['npc'] == true) {
        if (data['wild'] == true) {
          // Pokémon selvatico (settore selvaggio): monete e, a volte, uno strumento. Niente badge.
          if (!result.winnerUid!.startsWith('gym:')) {
            final drop = _rnd.nextDouble() < kWildDropChance ? [ItemService.randomDrop(rnd: _rnd)] : <ItemId>[];
            final txt = await ItemService.grant(result.winnerUid!, coins: kCoinsWild, items: drop);
            await ref.update({'rewardText': txt, 'rewardFor': result.winnerUid});
          }
        } else if (data['legendary'] == true) {
          // Leggendario: ricompensa al primo che lo batte.
          if (!result.winnerUid!.startsWith('gym:')) {
            final txt = await TableService.rewardLegendary(
                data['party'] as String, data['eventId'] as String, result.winnerUid!);
            if (txt != null) await ref.update({'rewardText': txt, 'rewardFor': result.winnerUid});
          }
        } else if (!result.winnerUid!.startsWith('gym:')) {
          // Vittoria contro un capopalestra: badge (solo la prima volta).
          final isNew = await GymService.awardBadge(
            result.winnerUid!,
            data['gymId'] as String,
            data['gymName'] as String,
            data['gymType'] as String,
          );
          final parts = <String>[];
          if (isNew) {
            parts.add(await ItemService.grant(result.winnerUid!,
                coins: kCoinsGymWin, items: [ItemService.randomDrop(rnd: _rnd)]));
          }
          // badge della partita in corso: sblocca un'abilità del Pokémon (la prima volta in questa partita)
          if (await GymService.awardGameBadge(result.winnerUid!, data['gymId'] as String)) {
            final ab = await AbilityService.onBadge(result.winnerUid!);
            if (ab != null) parts.add(ab);
          }
          if (parts.isNotEmpty) {
            await ref.update({
              if (isNew) 'badgeEarned': data['gymName'],
              'rewardText': parts.join(' · '),
              'rewardFor': result.winnerUid,
            });
          }
        }
      }
    }
  }

  /// Funzione pura: dato lo stato della battaglia calcola gli aggiornamenti.
  static ({Map<String, dynamic> updates, String? winnerUid, String status}) computeTurn(
      Map<String, dynamic> data, {Random? rnd}) {
    final a = _copy(data['playerA']);
    final b = _copy(data['playerB']);
    final log = StringBuffer('Turno ${_i(data['turn_number']) + 1}:\n');
    final updates = <String, dynamic>{};

    // Difesa: recupera 3 energie
    for (final p in [a, b]) {
      if (p['last_action'] == 'defense') {
        p['current_energies'] =
            min(_i(p['max_energies']), _i(p['current_energies']) + 3);
      }
    }

    // Strumenti: usano il turno (prima che arrivino i danni)
    for (final p in [a, b]) {
      if (p['last_action'] != 'item') continue;
      final name = p['pokemon_name'];
      switch (p['last_item']) {
        case 'superPozione':
          final healedS = max(0, min(kSuperPotionHeal, _i(p['max_hp']) - _i(p['current_hp'])));
          p['current_hp'] = _i(p['current_hp']) + healedS;
          log.write('$name usa una Super Pozione e recupera $healedS PS.\n');
        case 'elisir':
          final gained = max(0, min(kEnergyElixir, _i(p['max_energies']) - _i(p['current_energies'])));
          p['current_energies'] = _i(p['current_energies']) + gained;
          log.write('$name usa un Elisir e recupera $gained energie.\n');
        case 'antidoto':
          if (p['stato'] != null) {
            p.remove('stato');
            log.write('$name usa un Antidoto: gli status alterati sono rimossi.\n');
          } else {
            log.write('$name usa un Antidoto, ma non aveva status alterati.\n');
          }
        default: // pozione
          final healedP = max(0, min(kPotionHeal, _i(p['max_hp']) - _i(p['current_hp'])));
          p['current_hp'] = _i(p['current_hp']) + healedP;
          log.write('$name usa una Pozione e recupera $healedP PS.\n');
      }
    }

    final zoneBonus = (data['zoneBonus'] as Map?)?.map((k, v) => MapEntry(k.toString().toLowerCase(), (v as num).toInt())) ??
        <String, int>{};

    void attack(Map<String, dynamic> atk, Map<String, dynamic> def) {
      final action = atk['last_action'];
      if (action != 'attack' && action != 'attackSpec') return;
      final moveName = (atk['last_move_used'] ?? '').toString();
      final move = (atk['moveset_data'] as Map?)?[moveName] as Map?;
      final dmg = _i(move?['Dmg'], 1);
      final cost = energyCostForDmg(dmg);
      final energy = _i(atk['current_energies']);
      if (energy < cost) {
        log.write('${atk['pokemon_name']} non ha abbastanza energie!\n');
        return;
      }
      atk['current_energies'] = energy - cost;

      final roll = rollAttack(
        altEffect: move?['AltEffect'] as String?,
        altPerc: (move?['AltStatusPerc'] as num?)?.toDouble() ?? 0,
        targetStat: move?['targetStat'] as String?,
        atk: _i(atk['Atk']),
        atkSpec: _i(atk['AtkSpec']),
        dmg: dmg,
        targetWeak: _lowerList(def['debolezze']),
        moveType: (move?['MoveType'] ?? '').toString(),
        action: action as String,
        targetRes: _lowerList(def['resistenze']),
        diceBonus: atk['candy'] == true ? kCandyBonus : 0,
        rnd: rnd,
      );
      var total = max(0, dmg + roll.bonus + roll.elementalModifier);
      if (roll.category == 'Nullo') total = 0; // tiro 1 = attacco Nullo
      final zb = zoneBonus[(move?['MoveType'] ?? '').toString().trim().toLowerCase()] ?? 0;
      if (total > 0 && zb > 0) total += zb; // bonus di zona (evento attivo)
      final glove = total > 0 && atk['glove'] == true;
      if (glove) total += kGloveDamage; // Guanto

      log.write('${atk['pokemon_name']} lancia $moveName '
          '(${roll.category}, Dado: ${roll.rawDice}${roll.dice != roll.rawDice ? '+${roll.dice - roll.rawDice}' : ''}).\n');
      if (zb > 0 && total > 0) log.write('Bonus di zona: +$zb.\n');
      if (glove) log.write('Il Guanto aggiunge +$kGloveDamage al danno.\n');
      if (roll.elementalModifier > 0) {
        log.write('È super efficace! (+${roll.elementalModifier})\n');
      } else if (roll.elementalModifier < 0) {
        log.write('Non è molto efficace... (${roll.elementalModifier})\n');
      }

      final defAction = def['last_action'];
      if (total == 0) {
        log.write("L'attacco è risultato Nullo!\n");
      } else if (defAction == 'dodge' && !roll.unblockable) {
        log.write('${def['pokemon_name']} schiva abilmente!\n');
      } else if (defAction == 'defense' && !roll.unblockable) {
        final half = (total / 2).round();
        def['current_hp'] = _i(def['current_hp']) - half;
        log.write('${def['pokemon_name']} dimezza il danno a $half!\n');
      } else {
        def['current_hp'] = _i(def['current_hp']) - total;
        log.write(roll.unblockable
            ? 'È un attacco IMBLOCCABILE! Danno: $total.\n'
            : 'Danno inflitto: $total.\n');
      }

      if (roll.statusTriggered && defAction != 'dodge' && roll.status != null) {
        if (def['amulet'] == true) {
          def['amulet'] = false; // l'Amuleto blocca il primo status
          log.write("L'Amuleto di ${def['pokemon_name']} blocca lo status alterato!\n");
        } else {
        def['stato'] = _copy(roll.status);
        log.write('${def['pokemon_name']} è stato affetto da ${roll.status!['type']}.\n');
        }
      }
    }

    attack(a, b);
    attack(b, a);

    // Effetti di stato a fine turno
    void tick(Map<String, dynamic> p) {
      final s = p['stato'];
      if (s is! Map) return;
      switch (s['type']) {
        case 'dot':
          final d = _i(s['damage_per_turn'], 2);
          p['current_hp'] = _i(p['current_hp']) - d;
          log.write('${p['pokemon_name']} subisce $d danni DOT.\n');
          break;
        case 'slow':
          p['Vel'] = _i(p['Vel']) + _i(s['value']);
          break;
        case 'debuff':
          final st = (s['stat'] ?? 'Atk').toString();
          p[st] = _i(p[st]) + _i(s['value']);
          break;
      }
      final left = _i(s['remaining_turns'], 1) - 1;
      if (left <= 0) {
        p.remove('stato');
      } else {
        s['remaining_turns'] = left;
      }
    }

    tick(a);
    tick(b);

    final hpA = _i(a['current_hp']);
    final hpB = _i(b['current_hp']);
    String status;
    String? winner;
    if (hpA <= 0 && hpB <= 0) {
      log.write('\nPareggio!');
      status = 'draw';
    } else if (hpA <= 0) {
      log.write('\n${b['pokemon_name']} vince!');
      status = 'playerB_win';
      winner = b['uid'] as String?;
    } else if (hpB <= 0) {
      log.write('\n${a['pokemon_name']} vince!');
      status = 'playerA_win';
      winner = a['uid'] as String?;
    } else {
      status = 'in_progress';
    }

    for (final e in {'playerA': a, 'playerB': b}.entries) {
      final p = e.value;
      final k = e.key;
      updates['$k.current_hp'] = _i(p['current_hp']).clamp(0, _i(p['max_hp']));
      updates['$k.current_energies'] = _i(p['current_energies']).clamp(0, _i(p['max_energies']));
      updates['$k.last_action'] = 'none';
      updates['$k.turn_ready'] = false;
      for (final s in ['Atk', 'AtkSpec', 'Def', 'DefSpec', 'Vel']) {
        updates['$k.$s'] = _i(p[s]);
      }
      updates['$k.stato'] = p['stato'] ?? FieldValue.delete();
      if (p['amulet'] == false) updates['$k.amulet'] = false;
    }
    updates['turn_number'] = FieldValue.increment(1);
    updates['last_turn_log'] = log.toString();
    updates['status'] = status;
    updates['winnerUid'] = winner;
    updates['processing'] = FieldValue.delete();

    return (updates: updates, winnerUid: winner, status: status);
  }
}
