import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../abilities.dart';
import '../constants.dart';
import '../items.dart';
import '../mode.dart';
import '../table/phases.dart';
import '../table/zones.dart';
import 'battle_service.dart';
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
    final ok = await _db.runTransaction<bool>((tx) async {
      final p = (await tx.get(ref)).data() ?? {};
      final offer = [for (final k in (p['abilityOffer'] as List? ?? const [])) '$k'];
      if (!offer.contains(key)) return false;
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
      return true;
    });
    if (!ok) throw Exception('Questa abilità non è più tra quelle offerte');
  }

  /// Perché, per le regole del tavolo o perché c'è qualcosa da risolvere, non puoi usare un'attiva adesso
  /// (null = puoi). Le reazioni non costano azioni e non passano da actBlock.
  static String? abilityActBlock(Map<String, dynamic>? st, Map<String, dynamic>? user, String uid, AbilityDef def) {
    if (user?['wildEncounter'] is Map || user?['spotted'] is Map) return 'Prima risolvi quello che ti è successo';
    if (!kTableMode) {
      final d = LiveService.left(user?['busyUntil']);
      return d == null ? null : 'In attesa: ${LiveService.fmt(d)}';
    }
    if (def.reaction || kTableTurns) return null;
    return actBlock(state: st, user: user, uid: uid, kind: ActKind.ability);
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
    // regole del tavolo (mai due volte di fila, fermo...): controllate qui, fuori dalle transazioni, perché sul web
    // un errore lanciato dentro una transazione arriva come "Dart exception thrown from converted Future"
    final rule = abilityActBlock(st, me, uid, def);
    if (rule != null) throw Exception(rule);
    // bersaglio, settore, ingredienti: si controlla prima di pagare
    await _precheck(party: party, uid: uid, def: def, me: me, target: target, sector: sector, recipe: recipe);

    // il costo: al tavolo un'azione, dal vivo un'attesa breve (le reazioni non costano nulla)
    if (!def.reaction) {
      if (kTableMode) {
        await TableService.spendAction(party, uid, kind: ActKind.ability);
      } else {
        await ItemService.userRef(uid).set(LiveService.addBusy(me, kLiveAbilityWaitMinutes), SetOptions(merge: true));
      }
    }
    final again = await _db.runTransaction<String?>((tx) async {
      final cur = (await tx.get(pref)).data() ?? {};
      final why = abilityBlock(cur, key, round);
      if (why != null) return why; // niente throw dentro la transazione (vedi sopra)
      tx.set(pref, {
        'abilityUsedRound': {key: round},
        if (def.effectRounds > 0) 'abilityActiveUntil': round + def.effectRounds - 1,
        if (def.effectRounds > 0) 'abilityActiveKey': key,
      }, SetOptions(merge: true));
      return null;
    });
    if (again != null) throw Exception(again);
    return _apply(party: party, uid: uid, def: def, me: me, round: round, target: target, sector: sector, recipe: recipe);
  }

  // ------------------------------------------------------------- controlli prima di pagare

  /// Controlla che l'attiva si possa davvero fare (bersaglio, settore, ingredienti...) prima di pagare l'azione.
  static Future<void> _precheck({
    required String party,
    required String uid,
    required AbilityDef def,
    required Map<String, dynamic> me,
    String? target,
    int? sector,
    int? recipe,
  }) async {
    final pos = me['pos'] as Map?;
    const needsPlace = {
      Ab.distrazione, Ab.fiammata, Ab.pioggia, Ab.rovi, Ab.impulso, Ab.gelata, Ab.sfida, Ab.escaTossica, Ab.scavo,
      Ab.sismo, Ab.vedetta, Ab.fiuto, Ab.sciame, Ab.barricata, Ab.spavento, Ab.borseggio, Ab.imboscata, Ab.sonda,
      Ab.benedizione,
    };
    if (needsPlace.contains(def.key) && pos == null) {
      throw Exception(kTableMode ? 'Non sei ancora sulla mappa' : 'Devi essere dentro una zona di gioco');
    }
    const heal = {Ab.idratazione, Ab.sintesi, Ab.ibernazione, Ab.benedizione};
    if (heal.contains(def.key) && ItemService.isActive(me['koUntil'])) {
      throw Exception('Il tuo Pokémon è esausto: serve il recupero o un Revitalizzante');
    }
    switch (def.key) {
      case Ab.sfida:
      case Ab.spavento:
        if (target == null) throw Exception('Scegli un giocatore');
        if (!(await playersNear(party, uid)).contains(target)) throw Exception('$target non è nel tuo settore');
        if (def.key == Ab.sfida) await assertCanChallenge(party, uid, target);
      case Ab.sismo:
        if (sector == null || !(await quakeSectors(party, uid)).contains(sector)) throw Exception('Scegli un altro settore');
      case Ab.forgia:
        final opts = forgeOptions();
        if (recipe == null || recipe < 0 || recipe >= opts.length) throw Exception('Scegli una ricetta');
        final inv = ItemService.readInventory(me);
        if ((inv[opts[recipe].pay.name] ?? 0) <= 0) throw Exception('Ti serve 1 ${itemDef(opts[recipe].pay).name}');
      case Ab.impulso:
      case Ab.fiuto:
        await ItemService.assertNoSwarm(party, uid, me);
    }
  }

  // --------------------------------------------------------------------- effetti

  /// Effetto dell'attiva. Quelle "per la prossima lotta" (e Ardore) le legge la battaglia (fase 9.D).
  static Future<AbilityResult> _apply({
    required String party,
    required String uid,
    required AbilityDef def,
    required Map<String, dynamic> me,
    required int round,
    String? target,
    int? sector,
    int? recipe,
  }) async {
    final pos = me['pos'] as Map?;
    final zone = pos == null ? null : '${pos['zone']}';
    final here = pos == null ? null : _i(pos['sector']);
    final place = zone == null ? '' : _place(zone, here!);
    Future<void> map(String kind, {int? at, bool wholeZone = false}) => addEffect(party,
        kind: kind, owner: uid, zone: zone, sector: wholeZone ? null : (at ?? here), rounds: def.duration);
    switch (def.key) {
      case Ab.racimolare:
        await ItemService.userRef(uid).set({'coins': FieldValue.increment(kGatherCoins)}, SetOptions(merge: true));
        return const AbilityResult('+$kGatherCoins 🪙');
      case Ab.distrazione:
        await map(Ab.distrazione);
        return AbilityResult('Per 1 giro nessun altro può cercare in $place');
      case Ab.fiammata:
        await map(Ab.fiammata, wholeZone: true);
        return AbilityResult('${zoneSpec(zone!).name} è rovente: per 1 giro chi entra paga +1 azione');
      case Ab.pioggia:
        await map(Ab.pioggia, wholeZone: true);
        var n = 0;
        for (final d in (await PartyService.party(party).collection('traces').where('zone', isEqualTo: zone).get()).docs) {
          if (_i(d.data()['strength'], 1) > 1) {
            await d.reference.update({'strength': 1});
            n++;
          }
        }
        return AbilityResult('Piove su ${zoneSpec(zone!).name}: ${n == 0 ? 'nessuna traccia da lavare' : '$n tracce ora deboli'}; '
            'per 1 giro niente bonus Fuoco degli eventi');
      case Ab.idratazione:
        final r = await _heal(uid, hp: kHydrateHp, clearStatus: true);
        return AbilityResult('Idratazione: +${r.hp} PS, nessuno status alterato');
      case Ab.sintesi:
        final r = await _heal(uid, hp: kSynthesisHp, energy: kSynthesisEnergy);
        return AbilityResult('Sintesi: +${r.hp} PS, +${r.energy} energie');
      case Ab.rovi:
        await map(Ab.rovi);
        return AbilityResult('Rovi in $place per 2 giri: chi entra perde $kBrambleDamage PS e lascia una traccia evidente');
      case Ab.impulso:
        final found = await ItemService.radarScan(uid, party, null, zoneOnly: true, consume: false);
        return AbilityResult('Impulso su ${zoneSpec(zone!).name}',
            lines: found.isEmpty ? ['Nessuno nella tua zona.'] : [for (final c in found) '${c.name}: ${c.place ?? 'qui vicino'}']);
      case Ab.gelata:
        await map(Ab.gelata);
        return AbilityResult('$place è ghiacciato per 2 giri: chi entra paga +1 azione e tu lo saprai');
      case Ab.ibernazione:
        await addEffect(party, kind: Ab.ibernazione, owner: uid, rounds: def.duration);
        final r = await _heal(uid, hp: kHibernateHp);
        return AbilityResult('Ibernazione: +${r.hp} PS; per 1 giro nessuno può sfidarti (e tu non puoi sfidare)');
      case Ab.sfida:
        final id = await challenge(party: party, uid: uid, target: target!);
        return AbilityResult('Sfida lanciata a $target: si combatte!', battleId: id);
      case Ab.escaTossica:
        await map(Ab.escaTossica);
        return AbilityResult('Esca tossica in $place per 2 giri: il primo che entra sarà avvelenato');
      case Ab.scavo:
        if (_rnd.nextDouble() >= kDigChance) return const AbilityResult('Hai scavato, ma non hai trovato niente');
        final txt = await ItemService.grant(uid, items: await ItemService.luckyDrops(uid, [ItemService.randomDrop(rnd: _rnd)]));
        return AbilityResult('Scavando hai trovato: $txt');
      case Ab.sismo:
        await map(Ab.sismo, at: sector);
        return AbilityResult('Sismo: ${_place(zone!, sector!)} è bloccato per 1 giro');
      case Ab.ricognizione:
        return AbilityResult('Ricognizione', lines: await _recon(party));
      case Ab.vedetta:
        await map(Ab.vedetta, wholeZone: true);
        return AbilityResult('Vedetta su ${zoneSpec(zone!).name} per 2 giri: saprai chi entra');
      case Ab.preveggenza:
        final rows = await ItemService.weatherRows(party);
        return AbilityResult('Preveggenza', lines: rows.isEmpty ? ['Nessun evento previsto nei prossimi 2 giri.'] : rows);
      case Ab.depistaggio:
        await addEffect(party, kind: Ab.depistaggio, owner: uid, rounds: def.duration);
        return const AbilityResult('Depistaggio per 2 giri: chi ti cerca con Radar o Calmanella vede una zona a caso');
      case Ab.fiuto:
        final rep = await ItemService.useLens(uid, party, null, consume: false, sectorOnly: true);
        final lines = [...rep.searched, ...rep.moves];
        return AbilityResult('Fiuto', lines: lines.isEmpty ? ['Nessuna traccia recente nel tuo settore.'] : lines);
      case Ab.sciame:
        await map(Ab.sciame, wholeZone: true);
        return AbilityResult('Sciame su ${zoneSpec(zone!).name}: per 1 giro nessun altro può usare Radar, Lente o Sensore');
      case Ab.barricata:
        await map(Ab.barricata);
        return AbilityResult('Barricata: $place è chiuso agli altri per 1 giro');
      case Ab.svanire:
        await addEffect(party, kind: Ab.svanire, owner: uid, rounds: def.duration);
        return const AbilityResult('Svanisci per 2 giri: invisibile al Radar, nessuna traccia');
      case Ab.spavento:
        await _scare(party, target!);
        await notice(party, [target], '👻 $uid ti ha spaventato: perdi ${kTableMode ? '1 azione' : '$kLivePenaltyMinutes minuti'}');
        return AbilityResult('Hai spaventato $target');
      case Ab.borseggio:
        return AbilityResult(await _pickpocket(party, uid));
      case Ab.imboscata:
        await map(Ab.imboscata);
        return AbilityResult('Imboscata in $place per 2 giri: se qualcuno entra potrai sfidarlo');
      case Ab.forgia:
        final o = forgeOptions()[recipe!];
        await ItemService.craftWith(uid, o.recipe, o.pay);
        return AbilityResult('Forgia: ${itemDef(o.recipe.output).name} creato con 1 ${itemDef(o.pay).name}');
      case Ab.sonda:
        final lines = await _probe(party, uid, zone!, here!);
        return AbilityResult('Sonda su $place', lines: lines.isEmpty ? ['Non c’era niente da disattivare.'] : lines);
      case Ab.benedizione:
        final mine = await _heal(uid, hp: kBlessingHp, clearStatus: true);
        final others = await playersNear(party, uid);
        for (final o in others) {
          if (ItemService.isActive((await ItemService.userRef(o).get()).data()?['koUntil'])) continue;
          await _heal(o, hp: kBlessingHp, clearStatus: true);
          await notice(party, [o], '✨ $uid ti ha benedetto: +$kBlessingHp PS e niente status alterati');
        }
        return AbilityResult('Benedizione: +${mine.hp} PS${others.isEmpty ? '' : ' a te e a ${others.join(', ')}'}');
    }
    // per la prossima lotta (e Ardore): li applica la battaglia
    return AbilityResult(def.nextBattle
        ? '${def.name}: vale nella prossima lotta entro $kNextBattleRounds giri'
        : '${def.name} attiva per ${def.duration} ${def.duration == 1 ? 'giro' : 'giri'}');
  }

  static String _place(String zone, int sector) => kTableMode
      ? '${zoneSpec(zone).name}, ${TableLayout.title(zone, sector)}'
      : '${zoneSpec(zone).name}, ${LiveService.sectorLabel(zone, sector)}';

  /// Cura fuori dalla lotta (PS, energie, status). Restituisce quanto ha recuperato.
  static Future<({int hp, int energy})> _heal(String uid, {int hp = 0, int energy = 0, bool clearStatus = false}) async {
    final ref = await pokemonRef(uid);
    if (ref == null) return (hp: 0, energy: 0);
    return _db.runTransaction<({int hp, int energy})>((tx) async {
      final p = (await tx.get(ref)).data() ?? {};
      final h = BattleService.startHp(p), e = BattleService.startEnergy(p);
      final nh = min(kBaseHp, h + hp), ne = min(kBaseEnergy, e + energy);
      tx.set(ref, {
        'currentHp': nh,
        'currentEnergy': ne,
        if (clearStatus) 'currentStatus': FieldValue.delete(),
      }, SetOptions(merge: true));
      return (hp: nh - h, energy: ne - e);
    });
  }

  /// Fotosintesi: +2 PS a ogni nuovo giro, ovunque (non da esausto).
  static Future<void> photosynthesis(String uid) async {
    final u = (await ItemService.userRef(uid).get()).data();
    if (ItemService.isActive(u?['koUntil'])) return;
    final ref = await pokemonRef(uid, u);
    if (ref == null) return;
    final p = (await ref.get()).data();
    if (!passivesOf(p).contains(Ab.fotosintesi)) return;
    final hp = BattleService.startHp(p ?? const {});
    if (hp < kBaseHp) await ref.set({'currentHp': min(kBaseHp, hp + kPhotosynthesisHp)}, SetOptions(merge: true));
  }

  /// Spavento: il bersaglio perde 1 azione (dal vivo: 2 minuti di attesa).
  static Future<void> _scare(String party, String target) async {
    final ref = ItemService.userRef(target);
    final u = (await ref.get()).data();
    if (!kTableMode) {
      await ref.set(LiveService.addBusy(u, kLivePenaltyMinutes), SetOptions(merge: true));
    } else if (kTableTurns) {
      await ref.set({'actionPenalty': FieldValue.increment(1)}, SetOptions(merge: true));
    } else {
      // fasi del giorno: perde un'azione (conta come usata)
      await TableService.loseActions(party, target, 1);
    }
  }

  /// Borseggio: un giocatore a caso nel tuo settore ti passa uno strumento a caso (non la MT).
  static Future<String> _pickpocket(String party, String uid) async {
    final near = await playersNear(party, uid)..shuffle(_rnd);
    if (near.isEmpty) return 'Non c’era nessuno da borseggiare: l’abilità è andata sprecata';
    final victim = near.first;
    final myLimit = bagLimitFor(await passives(uid), kBagLimit);
    final got = await _db.runTransaction<String?>((tx) async {
      final vRef = ItemService.userRef(victim), mRef = ItemService.userRef(uid);
      final vi = ItemService.readInventory((await tx.get(vRef)).data());
      final mi = ItemService.readInventory((await tx.get(mRef)).data());
      final pool = [for (final e in vi.entries) if (e.value > 0 && _tradable(e.key)) e.key];
      if (pool.isEmpty) return null;
      final key = pool[_rnd.nextInt(pool.length)];
      if (!ItemService.addItem(mi, key, 1, myLimit)) return '';
      vi[key] = vi[key]! - 1;
      tx.set(vRef, {'inventory': vi}, SetOptions(merge: true));
      tx.set(mRef, {'inventory': mi}, SetOptions(merge: true));
      return key;
    });
    if (got == null) return '$victim non aveva niente da rubare';
    if (got.isEmpty) return 'La tua borsa è piena: non riesci a prendere niente';
    final name = itemDef(ItemId.values.byName(got)).name;
    await notice(party, [victim], '🫳 Qualcuno ti ha borseggiato: ti manca un $name');
    return 'Hai borseggiato $victim: $name';
  }

  static bool _tradable(String key) {
    for (final i in kItems) {
      if (i.key == key) return i.tradable;
    }
    return false;
  }

  /// Ricognizione: zone con eventi in corso o annunciati e quanti giocatori ci sono in ogni zona (senza nomi).
  static Future<List<String>> _recon(String party) async {
    final events = (await TableService.eventsCol(party).get()).docs.map((d) => d.data());
    final counts = <String, int>{};
    for (final p in (await PartyService.players(party).get()).docs) {
      final z = ((await ItemService.userRef(p.id).get()).data()?['pos'] as Map?)?['zone'];
      if (z != null) counts['$z'] = (counts['$z'] ?? 0) + 1;
    }
    return [
      for (final z in TableLayout.zonesInPlay)
        '${z.name}: ${counts[z.id] ?? 0} ${(counts[z.id] ?? 0) == 1 ? 'giocatore' : 'giocatori'}'
            '${[
          for (final e in events)
            if (e['zone'] == z.id && (e['status'] == 'active' || e['status'] == 'announced'))
              ' · ${e['status'] == 'active' ? 'in corso' : 'in arrivo'}: ${e['name']}',
        ].join()}',
    ];
  }

  /// Sonda: disattiva nel tuo settore Trappole, Allarmi, Gelata ed Esca tossica e dice di chi erano.
  static Future<List<String>> _probe(String party, String uid, String zone, int sector) async {
    final out = <String>[];
    final live = kTableMode ? null : await LiveService.zones(party);
    bool here(Map<String, dynamic> d) {
      if (d['zone'] != null) return d['zone'] == zone && _i(d['sector']) == sector;
      if (live == null || d['lat'] is! num) return false;
      final at = LiveService.locate(live, (d['lat'] as num).toDouble(), (d['lng'] as num).toDouble());
      return at?['zone'] == zone && _i(at?['sector']) == sector;
    }

    for (final (col, label) in [('traps', 'Trappola'), ('alarms', 'Allarme')]) {
      for (final d in (await PartyService.party(party).collection(col).where('active', isEqualTo: true).get()).docs) {
        if (d.data()['ownerUid'] == uid || !here(d.data())) continue;
        await d.reference.update({'active': false, 'disabledBy': uid});
        out.add('$label di ${d.data()['ownerUid']} disattivata');
      }
    }
    for (final e in await activeEffects(party)) {
      if ((e['kind'] != Ab.gelata && e['kind'] != Ab.escaTossica) || e['owner'] == uid) continue;
      if (e['zone'] != zone || _i(e['sector']) != sector) continue;
      await effectsCol(party).doc(e['id'] as String).update({'active': false, 'disabledBy': uid});
      out.add('${abilityDef('${e['kind']}')!.name} di ${e['owner']} disattivata');
    }
    return out;
  }

  // ------------------------------------------------------------------ ingressi

  /// Qualcuno ([uid]) è entrato in [zone]/[sector] (al tavolo con `moveTo`, dal vivo dal GPS):
  /// Rovi, Esca tossica, Gelata (avviso al proprietario), Imboscata (avviso con Sfida) e Vedetta.
  /// Restituisce i messaggi per chi è entrato.
  static Future<List<String>> onEnter({
    required String party,
    required String uid,
    required String? fromZone,
    required String zone,
    required int sector,
  }) async {
    final fx = await activeEffects(party);
    if (fx.isEmpty) return const [];
    final msgs = <String>[];
    final user = (await ItemService.userRef(uid).get()).data();
    final pas = await passives(uid, user);
    final where = _place(zone, sector);
    if (effectsAt(fx, Ab.rovi, zone, sector: sector, notOwner: uid).isNotEmpty && !ItemService.isActive(user?['koUntil'])) {
      final ref = await pokemonRef(uid, user);
      if (ref != null) {
        final hp = BattleService.startHp((await ref.get()).data() ?? const {});
        await ref.set({'currentHp': max(1, hp - kBrambleDamage)}, SetOptions(merge: true));
        msgs.add('Rovi! Il tuo Pokémon perde $kBrambleDamage PS e lasci una traccia evidente.');
      }
    }
    for (final e in effectsAt(fx, Ab.escaTossica, zone, sector: sector, notOwner: uid)) {
      if (pas.contains(Ab.immunita)) break; // Immunità: il Danno nel tempo non ti colpisce
      final ref = effectsCol(party).doc(e['id'] as String);
      final hit = await _db.runTransaction<bool>((tx) async {
        final cur = (await tx.get(ref)).data();
        if (cur == null || cur['active'] == false) return false;
        tx.update(ref, {'active': false, 'triggeredBy': uid});
        return true;
      });
      if (!hit) continue;
      final pref = await pokemonRef(uid, user);
      await pref?.set({'currentStatus': BattleService.poisonStatus()}, SetOptions(merge: true));
      msgs.add('Esca tossica! Il tuo Pokémon è avvelenato.');
      break;
    }
    for (final e in effectsAt(fx, Ab.gelata, zone, sector: sector, notOwner: uid)) {
      await notice(party, ['${e['owner']}'], '❄️ $uid è entrato nel tuo settore ghiacciato ($where)');
    }
    for (final e in effectsAt(fx, Ab.imboscata, zone, sector: sector, notOwner: uid)) {
      final owner = '${e['owner']}';
      await ItemService.userRef(owner).set({
        'ambush': {'target': uid, 'zone': zone, 'sector': sector, 'round': TableClock.round, 'effect': e['id']},
      }, SetOptions(merge: true));
      await notice(party, [owner], '🌑 $uid è arrivato nel tuo settore ($where): puoi sfidarlo con l’Imboscata');
    }
    if (fromZone != zone) {
      for (final e in effectsAt(fx, Ab.vedetta, zone, notOwner: uid)) {
        await notice(party, ['${e['owner']}'], '🦅 Vedetta: $uid è entrato in ${zoneSpec(zone).name}');
      }
    }
    return msgs;
  }

  /// Avviso segreto a [to] (a comparsa nella Home; vedi GameWatcher).
  static Future<void> notice(String party, List<String> to, String text) =>
      PartyService.party(party).collection('events').add({
        'type': 'notice',
        'to': to,
        'text': text,
        'round': TableClock.round,
        'at': FieldValue.serverTimestamp(),
      });

  // ------------------------------------------------------------- effetti personali

  /// [uid] ha in corso l'effetto personale [kind] (Svanire, Depistaggio, Ibernazione)?
  static bool personal(List<Map<String, dynamic>> effects, String kind, String uid) =>
      effects.any((e) => e['kind'] == kind && e['owner'] == uid && e['zone'] == null);

  static Future<bool> hasPersonal(String party, String kind, String uid) async => personal(await activeEffects(party), kind, uid);

  /// Movimento di [uid]: protezioni, passive ed effetti delle abilità in corso.
  static Future<Mobility> mobility(String party, String uid, [Map<String, dynamic>? user]) async {
    final u = user ?? (await ItemService.userRef(uid).get()).data();
    return Mobility(
      uid: uid,
      itemShield: ItemService.shieldZone(u),
      passives: await passives(uid, u),
      effects: await activeEffects(party),
    );
  }

  /// Zone i cui eventi non toccano [uid]: protezione di bioma attiva + passive (Sangue caldo, Nuotatore...).
  static Future<Set<String>> shieldedZones(String uid, [Map<String, dynamic>? user]) async {
    final u = user ?? (await ItemService.userRef(uid).get()).data();
    return {if (ItemService.shieldZone(u) != null) ItemService.shieldZone(u)!, ...immuneZones(await passives(uid, u))};
  }

  // ------------------------------------------------------------------- lotta

  /// Modificatori di [uid] per la lotta che sta per cominciare: le passive che contano in lotta, Ardore se è in
  /// corso e l'effetto "per la prossima lotta entro 2 giri", che qui si consuma (Aura del drago solo contro un
  /// altro giocatore: contro capipalestra, selvatici e leggendario resta per la prossima).
  static Future<List<String>> battleMods(String uid, {required bool pvp}) async {
    final ref = await pokemonRef(uid);
    if (ref == null) return const [];
    final p = (await ref.get()).data() ?? {};
    final party = await PartyService.actualParty(uid);
    final st = party == null ? null : (await TableService.stateRef(party).get()).data();
    final round = st?['started'] == true ? _i(st!['round'], 1) : -1;
    final mods = [for (final k in passivesOf(p)) if (kBattleAbilities.contains(k)) k];
    final running = round < 1 ? null : activeAbility(p, round);
    final def = running == null ? null : abilityDef(running);
    if (def != null && kBattleAbilities.contains(def.key)) {
      if (def.key == Ab.ardore) {
        mods.add(def.key); // per 2 giri, in tutte le lotte
      } else if (def.nextBattle && (pvp || def.key != Ab.auraDrago)) {
        mods.add(def.key);
        // si consuma alla prima lotta
        await ref.set({'abilityActiveUntil': FieldValue.delete(), 'abilityActiveKey': FieldValue.delete()}, SetOptions(merge: true));
      }
    }
    return mods;
  }

  // ------------------------------------------------------------- sfide tra giocatori

  /// Sfida e Imboscata: niente rifugi, Repellente, Ibernazione o giocatori non disponibili.
  static Future<void> assertCanChallenge(String party, String uid, String target) async {
    await ItemService.assertCanFight(uid, opponentUid: target);
    await TableService.assertNotInRefuge(uid);
    await TableService.assertNotInRefuge(target, me: false);
    final fx = await activeEffects(party);
    if (personal(fx, Ab.ibernazione, uid)) throw Exception('Sei in Ibernazione: non puoi sfidare');
    if (personal(fx, Ab.ibernazione, target)) throw Exception('$target è in Ibernazione: non può essere sfidato');
  }

  /// Lotta obbligata tra [uid] e [target] (Sfida, Imboscata): parte subito e il bersaglio non può rifiutare.
  static Future<String> challenge({required String party, required String uid, required String target, int firstTurnDice = 0}) async {
    await assertCanChallenge(party, uid, target);
    final id = await BattleService.createForcedBattle(party: party, uid: uid, target: target, firstTurnDice: firstTurnDice);
    await ItemService.userRef(target).set({'forcedBattle': {'id': id, 'by': uid}}, SetOptions(merge: true));
    await notice(party, [target], '⚔️ $uid ti ha sfidato: la lotta è iniziata!');
    return id;
  }

  /// Imboscata scattata: [uid] sfida chi è entrato nel suo settore (reazione: non costa azioni),
  /// con +[kAmbushDice] al dado nel primo turno.
  static Future<String> ambushChallenge(String party, String uid) async {
    final u = (await ItemService.userRef(uid).get()).data();
    final a = u?['ambush'];
    if (a is! Map) throw Exception('Nessuno è caduto nella tua imboscata');
    await ItemService.userRef(uid).set({'ambush': FieldValue.delete()}, SetOptions(merge: true));
    final target = '${a['target']}';
    final fx = await activeEffects(party);
    if (!fx.any((e) => e['id'] == a['effect'])) throw Exception('L’imboscata è finita');
    final tpos = (await ItemService.userRef(target).get()).data()?['pos'] as Map?;
    if (tpos?['zone'] != a['zone'] || _i(tpos?['sector']) != _i(a['sector'])) throw Exception('$target se n’è già andato');
    return challenge(party: party, uid: uid, target: target, firstTurnDice: kAmbushDice);
  }

  static Future<void> dismissAmbush(String uid) =>
      ItemService.userRef(uid).set({'ambush': FieldValue.delete()}, SetOptions(merge: true));

  static Future<void> dismissForcedBattle(String uid) =>
      ItemService.userRef(uid).set({'forcedBattle': FieldValue.delete()}, SetOptions(merge: true));
}
