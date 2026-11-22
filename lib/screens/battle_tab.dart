import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../items.dart';
import '../services/battle_service.dart';
import '../services/item_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/drop.dart';

/// Tab "Battaglia".
///
/// Ogni turno ha 3 fasi sempre visibili:
///  1. SCEGLI   – tocchi un'azione (si evidenzia, puoi cambiarla) e premi "Conferma";
///  2. ATTESA   – la scelta è inviata e bloccata, vedi se l'avversario ha scelto;
///  3. RISOLUZIONE – entrambi pronti: il turno viene calcolato e compare il resoconto.
class BattleTab extends StatefulWidget {
  /// Se valorizzato (sfida a un capopalestra) apre direttamente quella battaglia.
  final String? initialBattleId;
  const BattleTab({super.key, this.initialBattleId});
  @override
  State<BattleTab> createState() => _BattleTabState();
}

class _BattleTabState extends State<BattleTab> {
  final _joinCtrl = TextEditingController();
  String? _battleId;
  String? _processedKey;
  bool _busy = false;

  // selezione locale del turno (prima della conferma)
  String? _selAction; // attack | attackSpec | defense | dodge | potion
  String? _selMove;
  bool _sending = false;
  int _turnSeen = -1;

  Session get _s => context.read<Session>();

  @override
  void initState() {
    super.initState();
    _battleId = widget.initialBattleId;
  }

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    try {
      await f();
      if (ok != null && mounted) snack(context, ok);
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    await _run(() async {
      final id = await BattleService.createBattle(_s.userName!, _s.pokemonId!);
      if (mounted) setState(() => _battleId = id);
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _join() async {
    final id = _joinCtrl.text.trim();
    if (id.isEmpty) {
      snack(context, 'Inserisci il codice della battaglia');
      return;
    }
    setState(() => _busy = true);
    await _run(() async {
      await BattleService.joinBattle(id, _s.userName!, _s.pokemonId!);
      if (mounted) setState(() => _battleId = id);
    });
    if (mounted) setState(() => _busy = false);
  }

  void _leave() => setState(() {
        _battleId = null;
        _selAction = null;
        _selMove = null;
        _sending = false;
        _turnSeen = -1;
      });

  @override
  Widget build(BuildContext context) {
    if (_battleId == null) return _lobby();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: BattleService.watch(_battleId!),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data!.data();
        if (data == null) {
          return DropCard(
            child: Column(children: [
              const Text('Battaglia non trovata'),
              TextButton(onPressed: _leave, child: const Text('Indietro')),
            ]),
          );
        }
        final status = data['status'] as String? ?? 'pending';
        if (status == 'pending') return _waiting(_battleId!, data);
        _maybeProcess(data);
        return _arena(data);
      },
    );
  }

  /// Quando entrambi i giocatori sono pronti, un client risolve il turno.
  void _maybeProcess(Map<String, dynamic> d) {
    if (d['status'] != 'in_progress' || d['processing'] == true) return;
    final a = d['playerA'] as Map?;
    final b = d['playerB'] as Map?;
    if (a?['turn_ready'] == true && b?['turn_ready'] == true) {
      final key = '${_battleId}_${d['turn_number']}';
      if (_processedKey == key) return;
      _processedKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) => BattleService.processTurn(_battleId!));
    }
  }

  // ------------------------------------------------------------- lobby

  Widget _lobby() {
    final s = context.watch<Session>();
    final c = [s.color, lighten(s.color)];
    return Column(
      children: [
        DropCard(
          colors: c,
          label: 'Crea',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Inizia una nuova battaglia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Riceverai un codice da dare al tuo sfidante.',
                style: TextStyle(color: Pal.sub, fontStyle: FontStyle.italic, fontSize: 13)),
            const SizedBox(height: 14),
            DropButton(label: 'Crea battaglia', icon: Icons.add, colors: c, busy: _busy, onTap: _create),
          ]),
        ),
        DropCard(
          colors: const [Color(0xFF2845F5), Color(0xFF64B5F6)],
          label: 'Unisciti',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hai un codice?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: _joinCtrl,
              decoration: const InputDecoration(
                hintText: 'es. Selfenid-k4b-1121',
                filled: true,
                fillColor: Pal.bg,
                border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(14))),
              ),
            ),
            const SizedBox(height: 12),
            DropButton(
              label: 'Unisciti',
              icon: Icons.login,
              colors: const [Color(0xFF2845F5), Color(0xFF64B5F6)],
              busy: _busy,
              onTap: _join,
            ),
          ]),
        ),
        const SectionTitle('Le tue mosse'),
        StreamBuilder<Map<String, Map<String, dynamic>>>(
          stream: BattleService.watchMoves(s.userName!, s.pokemonId!),
          builder: (context, snap) => Column(children: [
            for (final m in (snap.data ?? {}).values) MoveCard(move: m),
          ]),
        ),
      ],
    );
  }

  Widget _waiting(String id, Map<String, dynamic> data) {
    return DropCard(
      colors: const [Pal.accent, Color(0xFF9C7BE0)],
      child: Column(children: [
        const SizedBox(height: 6),
        const Text('In attesa di un avversario…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Pal.bg, borderRadius: BorderRadius.circular(14)),
          child: SelectableText(id, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: id));
            snack(context, 'Codice copiato');
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copia codice'),
        ),
        const SizedBox(height: 8),
        const CircularProgressIndicator(strokeWidth: 5),
        const SizedBox(height: 18),
        _prefight(id, 'playerA', data['playerA'] as Map?),
        TextButton(onPressed: _leave, child: const Text('Esci')),
      ]),
    );
  }

  /// Strumenti da dichiarare prima del primo turno (Caramella, Amuleto, Guanto).
  Widget _prefight(String id, String key, Map? mine) {
    const items = {ItemId.caramella: 'candy', ItemId.amuleto: 'amulet', ItemId.guanto: 'glove'};
    return StreamBuilder<Map<String, dynamic>?>(
      stream: ItemService.watchUser(_s.userName!),
      builder: (context, snap) {
        final inv = ItemService.readInventory(snap.data);
        final children = <Widget>[];
        items.forEach((item, field) {
          final def = itemDef(item);
          if (mine?[field] == true) {
            children.add(Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InfoChip('${def.name} attivo', color: def.colors.first),
            ));
          } else if ((inv[item.name] ?? 0) > 0) {
            children.add(Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: DropButton(
                label: 'Usa ${def.name}  ×${inv[item.name]}',
                icon: def.icon,
                colors: def.colors,
                onTap: () => _run(
                  () => BattleService.declarePrefight(battleId: id, playerKey: key, uid: _s.userName!, item: item),
                  ok: '${def.name} dichiarato',
                ),
              ),
            ));
          }
        });
        if (children.isEmpty) return const SizedBox.shrink();
        return Column(children: children);
      },
    );
  }

  // ------------------------------------------------------------- arena

  void _select(String action, {String? move}) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selAction == action && _selMove == move) {
        _selAction = null; // secondo tocco = deseleziona
        _selMove = null;
      } else {
        _selAction = action;
        _selMove = move;
      }
    });
  }

  Future<void> _confirm(String myKey, String me) async {
    if (_selAction == null || _sending) return;
    HapticFeedback.mediumImpact();
    setState(() => _sending = true);
    try {
      if (_selAction == 'item') {
        await BattleService.useBattleItem(
            battleId: _battleId!, playerKey: myKey, uid: me, item: ItemId.values.byName(_selMove!));
      } else {
        await BattleService.chooseAction(
            battleId: _battleId!, playerKey: myKey, action: _selAction!, moveName: _selMove);
      }
    } catch (e) {
      if (mounted) {
        snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _flee(String myKey) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fune di fuga'),
        content: const Text('La battaglia termina subito e dovrete allontanarvi in una direzione casuale.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fuggi')),
        ],
      ),
    );
    if (go == true) _run(() => BattleService.flee(battleId: _battleId!, playerKey: myKey));
  }

  String _actionName(String? action, String? move) {
    switch (action) {
      case 'attack':
      case 'attackSpec':
        return move ?? 'Attacco';
      case 'defense':
        return 'Difesa';
      case 'dodge':
        return 'Schiva';
      case 'potion':
        return 'Pozione';
    }
    return '';
  }

  Widget _arena(Map<String, dynamic> d) {
    final me = _s.userName!;
    final myKey = (d['playerA'] as Map?)?['uid'] == me ? 'playerA' : 'playerB';
    final oppKey = myKey == 'playerA' ? 'playerB' : 'playerA';
    final mine = Map<String, dynamic>.from(d[myKey] as Map);
    final opp = Map<String, dynamic>.from(d[oppKey] as Map);
    final status = d['status'] as String;
    final over = status != 'in_progress';
    final turn = (d['turn_number'] as num?)?.toInt() ?? 0;

    // Nuovo turno: la selezione riparte da zero.
    if (_turnSeen != turn) {
      _turnSeen = turn;
      _selAction = null;
      _selMove = null;
      _sending = false;
    }

    final mineReady = mine['turn_ready'] == true;
    final oppReady = opp['turn_ready'] == true;
    final locked = mineReady || _sending;
    final resolving = !over && mineReady && oppReady;
    final chosenAction = mineReady ? mine['last_action'] as String? : _selAction;
    final chosenMove = mineReady ? mine['last_move_used'] as String? : _selMove;
    final isNpc = d['npc'] == true;
    final oppLabel = isNpc ? 'Capopalestra' : 'Avversario';

    final moves = (mine['moveset_data'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map))) ??
        <String, Map<String, dynamic>>{};

    final myColors = typeColors(mine['type'] as String?);
    final oppColors = typeColors(opp['type'] as String?);

    return Column(
      children: [
        _TurnHeader(
          turn: turn + 1,
          over: over,
          resolving: resolving,
          mineReady: mineReady || _sending,
          oppReady: oppReady,
          oppLabel: oppLabel,
        ),
        Combatant(player: opp, colors: oppColors, tag: oppLabel),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 2),
          child: Text('VS', style: TextStyle(color: Pal.sub, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ),
        Combatant(player: mine, colors: myColors, tag: 'Tu'),
        _LogCard(log: (d['last_turn_log'] ?? '').toString(), turn: turn),
        if (over)
          _ResultCard(data: d, me: me, onNew: _leave)
        else
          StreamBuilder<Map<String, dynamic>?>(
            stream: ItemService.watchUser(me),
            builder: (context, snap) {
              final inv = ItemService.readInventory(snap.data);
              final energy = (mine['current_energies'] as num?)?.round() ?? 0;
              final hp = (mine['current_hp'] as num?)?.round() ?? 0;
              final maxHp = (mine['max_hp'] as num?)?.round() ?? kBaseHp;

              bool isSel(String a, [String? m]) => chosenAction == a && chosenMove == m;

              // Sezione che si apre sotto l'opzione selezionata: Conferma / stato dell'invio.
              Widget? footer(bool sel, List<Color> cs) => sel
                  ? _ChoiceFooter(
                      locked: locked,
                      sending: _sending && !mineReady,
                      resolving: resolving,
                      oppReady: oppReady,
                      oppLabel: oppLabel,
                      colors: cs,
                      onConfirm: () => _confirm(myKey, me),
                    )
                  : null;

              return Column(children: [
                const SectionTitle('Scegli la tua azione'),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 2),
                  child: Text("Tocca un'azione: sotto si apre il pulsante Conferma.",
                      style: TextStyle(color: Pal.sub, fontSize: 12)),
                ),
                for (final e in moves.entries)
                  Builder(builder: (_) {
                    final dmg = (e.value['Dmg'] as num?)?.round() ?? 1;
                    final cost = energyCostForDmg(dmg);
                    final act = e.value['MoveTypo'] == 'Speciale' ? 'attackSpec' : 'attack';
                    final sel = isSel(act, e.key);
                    final noEnergy = energy < cost;
                    return MoveCard(
                      move: e.value,
                      selected: sel,
                      dimmed: locked && !sel,
                      disabledReason: noEnergy ? 'Energia insufficiente (hai $energy, servono $cost)' : null,
                      expanded: footer(sel, typeColors(e.value['MoveType'] as String?)),
                      onTap: locked
                          ? null
                          : () => noEnergy
                              ? snack(context, 'Energia insufficiente per usare questa mossa')
                              : _select(act, move: e.key),
                    );
                  }),
                _ActionTile(
                  title: 'Difesa',
                  subtitle: 'Danno dimezzato, +3 energie',
                  icon: Icons.shield,
                  colors: const [Color(0xFF5BC236), Color(0xFFA6E08C)],
                  selected: isSel('defense'),
                  dimmed: locked && !isSel('defense'),
                  expanded: footer(isSel('defense'), const [Color(0xFF5BC236), Color(0xFFA6E08C)]),
                  onTap: locked ? null : () => _select('defense'),
                ),
                _ActionTile(
                  title: 'Schiva',
                  subtitle: 'Evita i colpi non imbloccabili',
                  icon: Icons.speed,
                  colors: const [Color(0xFF757575), Color(0xFFBDBDBD)],
                  selected: isSel('dodge'),
                  dimmed: locked && !isSel('dodge'),
                  expanded: footer(isSel('dodge'), const [Color(0xFF757575), Color(0xFFBDBDBD)]),
                  onTap: locked ? null : () => _select('dodge'),
                ),
                for (final it in BattleService.kBattleConsumables)
                  if ((inv[it.name] ?? 0) > 0)
                    Builder(builder: (_) {
                      final def = itemDef(it);
                      final qty = inv[it.name] ?? 0;
                      final sel = isSel('item', it.name);
                      final String? why = switch (it) {
                        ItemId.pozione => hp >= maxHp ? 'I PS sono già al massimo' : null,
                        ItemId.superPozione => hp >= maxHp ? 'I PS sono già al massimo' : null,
                        ItemId.elisir => energy >= ((mine['max_energies'] as num?)?.round() ?? energy)
                            ? "L'energia è già al massimo"
                            : null,
                        ItemId.antidoto => mine['stato'] == null ? 'Nessuno status da rimuovere' : null,
                        _ => null,
                      };
                      final sub = switch (it) {
                        ItemId.pozione => '+$kPotionHeal PS, richiede il turno',
                        ItemId.superPozione => '+$kSuperPotionHeal PS, richiede il turno',
                        ItemId.elisir => '+$kEnergyElixir energie, richiede il turno',
                        _ => 'Rimuove DOT e malus, richiede il turno',
                      };
                      return _ActionTile(
                        title: '${def.name}  ×$qty',
                        subtitle: sub,
                        icon: def.icon,
                        colors: def.colors,
                        selected: sel,
                        dimmed: (locked && !sel) || why != null,
                        expanded: footer(sel, def.colors),
                        onTap: locked ? null : () => why != null ? snack(context, why) : _select('item', move: it.name),
                      );
                    }),
                const SectionTitle('Uso immediato'),
                if (turn == 0) _prefight(_battleId!, myKey, mine),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: _ActionTile(
                      title: 'Fune  ×${inv['fune'] ?? 0}',
                      subtitle: 'Termina subito lo scontro',
                      icon: Icons.logout,
                      colors: itemDef(ItemId.fune).colors,
                      dimmed: (inv['fune'] ?? 0) <= 0,
                      onTap: (inv['fune'] ?? 0) <= 0 ? null : () => _flee(myKey),
                    ),
                  ),
                ]),
              ]);
            },
          ),
      ],
    );
  }
}

// ======================================================================
//  Widget di supporto
// ======================================================================

/// Testata del turno: numero, fase e chi ha già scelto.
class _TurnHeader extends StatelessWidget {
  final int turn;
  final bool over, resolving, mineReady, oppReady;
  final String oppLabel;
  const _TurnHeader({
    required this.turn,
    required this.over,
    required this.resolving,
    required this.mineReady,
    required this.oppReady,
    required this.oppLabel,
  });

  Widget _pill(String who, bool ready, String waiting, String done) {
    final c = ready ? Pal.ok : Pal.warn;
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          ready
              ? Icon(Icons.check_circle, size: 20, color: c)
              : SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2.5, color: c)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(who, style: const TextStyle(fontSize: 11, color: Pal.sub, fontWeight: FontWeight.w700)),
              Text(ready ? done : waiting,
                  style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phase = over
        ? 'Scontro concluso'
        : resolving
            ? 'Risoluzione del turno…'
            : mineReady
                ? "Attendi l'avversario"
                : 'Tocca a te: scegli e conferma';
    return DropCard(
      leaf: false,
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          Text('Turno $turn', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(phase,
                  key: ValueKey(phase),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Pal.sub, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
        ]),
        if (!over) ...[
          const SizedBox(height: 10),
          Row(children: [
            _pill('TU', mineReady, 'sta scegliendo…', 'ha scelto'),
            const SizedBox(width: 8),
            _pill(oppLabel.toUpperCase(), oppReady, 'sta scegliendo…', 'ha scelto'),
          ]),
        ],
      ]),
    );
  }
}

/// Scheda di un combattente: PS animati, energia a gocce, stato alterato.
class Combatant extends StatelessWidget {
  final Map<String, dynamic> player;
  final List<Color> colors;
  final String tag;
  const Combatant({super.key, required this.player, required this.colors, required this.tag});

  static String _statoText(Map s) {
    final turns = (s['remaining_turns'] as num?)?.round() ?? 0;
    switch (s['type']) {
      case 'dot':
        return 'Danno nel tempo · $turns t';
      case 'slow':
        return 'Rallentato · $turns t';
      case 'debuff':
        return 'Debuff ${kStatLabels[s['stat']] ?? s['stat']} · $turns t';
    }
    return '${s['type']} · $turns t';
  }

  @override
  Widget build(BuildContext context) {
    final hp = (player['current_hp'] as num?)?.round() ?? 0;
    final maxHp = (player['max_hp'] as num?)?.round() ?? kBaseHp;
    final en = (player['current_energies'] as num?)?.round() ?? 0;
    final maxEn = (player['max_energies'] as num?)?.round() ?? kBaseEnergy;
    final stato = player['stato'] as Map?;
    final name = (player['pokemon_name'] ?? '').toString();
    final trainer = player['trainer'];

    return DropCard(
      colors: colors,
      label: tag,
      child: Row(children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [lighten(colors.first, 0.75), lighten(colors.last, 0.6)]),
          ),
          child: Center(child: PokemonImage(name, size: 68)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (trainer != null)
              Text('Capopalestra $trainer',
                  style: const TextStyle(color: Pal.sub, fontStyle: FontStyle.italic, fontSize: 12)),
            const SizedBox(height: 8),
            HpBar(current: hp, max: maxHp),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$en', style: TextStyle(fontWeight: FontWeight.w800, color: colors.first)),
              const SizedBox(width: 6),
              Expanded(child: EnergyPips(current: en, max: maxEn, color: colors.first)),
            ]),
            if (stato != null || player['candy'] == true) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (stato != null) InfoChip(_statoText(stato), color: Pal.bad),
                if (player['candy'] == true) InfoChip('🍬 +$kCandyBonus ai tiri', color: const Color(0xFFE56B8F)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Scheda mossa. Può essere selezionabile (in battaglia) o solo informativa.
class MoveCard extends StatelessWidget {
  final Map<String, dynamic> move;
  final bool selected;
  final bool dimmed;
  final String? disabledReason;
  final Widget? expanded;
  final VoidCallback? onTap;
  const MoveCard({
    super.key,
    required this.move,
    this.selected = false,
    this.dimmed = false,
    this.disabledReason,
    this.expanded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final type = cap((move['MoveType'] ?? 'Normale').toString());
    final colors = typeColors(type);
    final dmg = (move['Dmg'] as num?)?.round() ?? 1;
    final cost = energyCostForDmg(dmg);
    final speciale = move['MoveTypo'] == 'Speciale';
    final effect = move['AltEffect'] as String?;
    final perc = (move['AltStatusPerc'] as num?)?.toDouble() ?? 0;
    final desc = (move['Description'] ?? '').toString();

    return DropCard(
      colors: colors,
      label: type,
      selected: selected,
      expanded: expanded,
      dimmed: dimmed || disabledReason != null,
      onTap: onTap ?? (disabledReason != null ? () {} : null),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((move['MoveName'] ?? '').toString(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (desc.isNotEmpty)
              Text(desc, style: const TextStyle(color: Pal.sub, fontStyle: FontStyle.italic, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              InfoChip('Danno $dmg', color: colors.first),
              InfoChip(speciale ? 'Speciale' : 'Fisico', color: Pal.sub),
              InfoChip('$cost', color: colors.first, leading: EnergyGlyph(height: 14, color: colors.first)),
            ]),
            if (effect != null) ...[
              const SizedBox(height: 6),
              Text('Effetto: $effect · prob. ${(perc * 100).round()}%'
                  '${move['targetStat'] != null ? ' · ${move['targetStat']}' : ''}',
                  style: const TextStyle(fontSize: 12, color: Pal.sub)),
            ],
            if (disabledReason != null) ...[
              const SizedBox(height: 6),
              Text(disabledReason!, style: const TextStyle(fontSize: 12, color: Pal.bad, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        Container(
          width: 58,
          height: 58,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: colors)),
          child: TypeIcon(type, size: 38),
        ),
      ]),
    );
  }
}

/// Riquadro azione (Difesa, Schiva, Pozione, Caramella, Fune).
class _ActionTile extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final List<Color> colors;
  final bool selected, dimmed;
  final Widget? expanded;
  final VoidCallback? onTap;
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    this.selected = false,
    this.dimmed = false,
    this.expanded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => DropCard(
        colors: colors,
        leaf: false,
        expanded: expanded,
        selected: selected,
        dimmed: dimmed,
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: colors)),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(subtitle, style: const TextStyle(color: Pal.sub, fontSize: 11)),
            ]),
          ),
        ]),
      );
}

/// Sezione che si apre sotto l'opzione scelta: pulsante "Conferma" e, dopo
/// l'invio, lo stato dell'attesa.
class _ChoiceFooter extends StatelessWidget {
  final bool locked, sending, resolving, oppReady;
  final String oppLabel;
  final List<Color> colors;
  final VoidCallback onConfirm;
  const _ChoiceFooter({
    required this.locked,
    required this.sending,
    required this.resolving,
    required this.oppReady,
    required this.oppLabel,
    required this.colors,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (resolving) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: const [
        Text('⚔️  Risoluzione del turno…', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        SizedBox(height: 8),
        LinearProgressIndicator(minHeight: 5),
      ]);
    } else if (locked) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.lock, size: 16, color: Pal.ok),
          const SizedBox(width: 6),
          Text(sending ? 'Invio della scelta…' : 'Scelta inviata',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Pal.ok)),
        ]),
        const SizedBox(height: 4),
        Text(oppReady ? '$oppLabel ha scelto' : '$oppLabel sta ancora scegliendo…',
            style: const TextStyle(color: Pal.sub, fontSize: 12)),
        const SizedBox(height: 8),
        const LinearProgressIndicator(minHeight: 5),
      ]);
    } else {
      body = DropButton(
        label: 'Conferma',
        icon: Icons.check,
        colors: [colors.first, lighten(colors.first, 0.25)],
        height: 44,
        onTap: onConfirm,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Divider(height: 1, color: Pal.line),
        const SizedBox(height: 12),
        body,
      ]),
    );
  }
}

/// Resoconto dell'ultimo turno (con animazione quando cambia).
class _LogCard extends StatelessWidget {
  final String log;
  final int turn;
  const _LogCard({required this.log, required this.turn});

  @override
  Widget build(BuildContext context) {
    if (log.isEmpty) return const SizedBox.shrink();
    return DropCard(
      colors: const [Pal.accent, Color(0xFF9C7BE0)],
      label: turn == 0 ? 'Inizio' : 'Turno $turn',
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a), child: c),
        ),
        child: Align(
          key: ValueKey('$turn$log'),
          alignment: Alignment.centerLeft,
          child: Text(log, style: const TextStyle(fontSize: 14, height: 1.4)),
        ),
      ),
    );
  }
}

/// Esito dello scontro.
class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String me;
  final VoidCallback onNew;
  const _ResultCard({required this.data, required this.me, required this.onNew});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String;
    String title;
    String emoji;
    List<Color> colors;
    if (status == 'fled') {
      final mine = data['fledBy'] == me;
      title = mine ? 'Sei fuggito!' : "L'avversario è fuggito!";
      emoji = '🏃';
      colors = const [Color(0xFFB5694F), Color(0xFFD9A07A)];
    } else if (status == 'draw') {
      title = 'Pareggio!';
      emoji = '🤝';
      colors = Pal.neutral;
    } else if (data['winnerUid'] == me) {
      title = 'Vittoria!';
      emoji = '🏆';
      colors = Pal.gold;
    } else {
      title = 'Sconfitta';
      emoji = '💤';
      colors = const [Color(0xFF6B6B80), Color(0xFFB0B0C0)];
    }
    return DropCard(
      colors: colors,
      margin: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 44)),
        Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        if (data['badgeEarned'] != null) ...[
          const SizedBox(height: 8),
          InfoChip('🏅 Badge ottenuto: ${data['badgeEarned']}', color: const Color(0xFFD08A00)),
        ],
        if (data['rewardText'] != null && (data['rewardFor'] == null || data['rewardFor'] == me)) ...[
          const SizedBox(height: 8),
          InfoChip('🎁 ${data['rewardText']}', color: const Color(0xFFD08A00)),
        ],
        const SizedBox(height: 14),
        DropButton(label: 'Nuova battaglia', icon: Icons.refresh, colors: colors, onTap: onNew),
      ]),
    );
  }
}
