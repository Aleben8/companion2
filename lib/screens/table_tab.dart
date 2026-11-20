import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../mode.dart';
import '../services/battle_service.dart';
import '../services/item_service.dart';
import '../services/party_service.dart';
import '../services/session.dart';
import '../services/table_service.dart';
import '../table/events.dart';
import '../table/zones.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/drop.dart';

int _i(dynamic v) => v is num ? v.toInt() : 0;

/// Tab "Tavolo": turni, azioni, posizione, eventi di zona e mappa a settori.
class TableTab extends StatefulWidget {
  /// Chiamata quando si sfida un leggendario (apre la battaglia).
  final ValueChanged<String> onBattle;
  const TableTab({super.key, required this.onBattle});
  @override
  State<TableTab> createState() => _TableTabState();
}

class _TableTabState extends State<TableTab> {
  String? _party;
  bool _master = false;
  bool _loading = true;
  bool _busy = false;

  Session get _s => context.read<Session>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _party = await PartyService.actualParty(_s.userName!);
      if (_party != null) _master = await PartyService.isMaster(_party!, _s.userName!);
    } catch (e) {
      debugPrint('Errore caricamento tavolo: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await f();
      if (ok != null && mounted) snack(context, ok);
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _confirm(String title, String text, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  // ------------------------------------------------------------------ azioni

  Future<void> _start(bool started) async {
    final go = await _confirm(
      started ? 'Riavvia la partita' : 'Avvia la partita',
      started
          ? 'Giro, posizioni, trappole ed eventi ripartono da zero (strumenti e badge restano).'
          : 'Verrà sorteggiato l’ordine dei turni, tutti partono dall’Hub e vengono pianificati gli eventi di zona.',
      started ? 'Riavvia' : 'Avvia',
    );
    if (go) await _run(() => TableService.startGame(_party!), ok: 'Partita avviata!');
  }

  Future<void> _endTurn(Map<String, dynamic> st) async {
    final left = _i(st['actionsLeft']);
    if (left > 0) {
      final go = await _confirm('Fine turno', 'Hai ancora $left ${left == 1 ? 'azione' : 'azioni'}. Vuoi finire il turno?', 'Fine turno');
      if (!go) return;
    }
    await _run(() => TableService.endTurn(_party!, _s.userName!));
  }

  Future<void> _move(ZoneSpec z, int sector, Map<String, dynamic> st, List<Map<String, dynamic>> events, Map? pos) async {
    final me = _s.userName!;
    final order = List<String>.from(st['order'] as List);
    if (order[_i(st['idx'])] != me) {
      snack(context, 'Non è il tuo turno');
      return;
    }
    if (TableService.blockedSectors(events, z.id).contains(sector)) {
      snack(context, 'Questo settore è bloccato');
      return;
    }
    final cost = TableService.moveCost(events, pos?['zone'] as String?, z.id);
    final go = await _confirm('Spostamento', 'Vai in ${z.name}, settore $sector?\nCosto: $cost ${cost == 1 ? 'azione' : 'azioni'}.', 'Vai');
    if (!go) return;
    await _run(() async {
      final msg = await TableService.moveTo(party: _party!, uid: me, zone: z.id, sector: sector);
      if (msg != null && mounted) snack(context, msg, error: true);
    });
  }

  // ---------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    if (_party == null) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: Text('Entra prima in un party (tab Party)', style: TextStyle(color: Pal.sub))),
      );
    }
    final me = _s.userName!;
    return StreamBuilder<Map<String, dynamic>?>(
      stream: TableService.watchState(_party!),
      builder: (context, stSnap) {
        final st = stSnap.data;
        final started = st?['started'] == true;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: TableService.watchEvents(_party!),
          builder: (context, evSnap) {
            final events = <Map<String, dynamic>>[
              for (final d in evSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {...d.data(), 'id': d.id},
            ];
            return StreamBuilder<Map<String, dynamic>?>(
              stream: ItemService.watchUser(me),
              builder: (context, uSnap) {
                final pos = uSnap.data?['pos'] as Map?;
                return Column(children: [
                  const SectionTitle('Tavolo'),
                  if (_master) _masterTools(started),
                  if (!started)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'La partita non è ancora iniziata. Quando tutti sono nel party, chi ha il ruolo di Master la avvia da qui.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Pal.sub, height: 1.4),
                      ),
                    )
                  else ...[
                    _turnCard(st!, me),
                    _positionCard(pos),
                    ..._eventCards(events, st, pos, me),
                    const SectionTitle('Mappa'),
                    for (final z in kZones) _zoneCard(z, pos, events, st, me),
                  ],
                ]);
              },
            );
          },
        );
      },
    );
  }

  Widget _masterTools(bool started) {
    return DropCard(
      colors: const [Pal.accent, Color(0xFF9C7BE0)],
      label: 'Master',
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
          'Solo per preparare la partita: dopo l’avvio tutti giocano alla pari.',
          style: TextStyle(color: Pal.sub, fontSize: 12),
        ),
        const SizedBox(height: 12),
        DropButton(
          label: started ? 'Riavvia la partita' : 'Avvia la partita',
          icon: Icons.rocket_launch,
          busy: _busy,
          onTap: () => _start(started),
        ),
        const SizedBox(height: 10),
        DropButton(
          label: 'Carica i tipi nel database',
          icon: Icons.cloud_upload_outlined,
          colors: Pal.neutral,
          height: 44,
          onTap: _busy ? null : () => _run(TableService.seedTypesIfMissing, ok: 'Tipi pronti (se mancavano, sono stati creati)'),
        ),
      ]),
    );
  }

  Widget _turnCard(Map<String, dynamic> st, String me) {
    final order = List<String>.from(st['order'] as List);
    final current = order[_i(st['idx'])];
    final mine = current == me;
    final left = _i(st['actionsLeft']);
    final per = _i(st['actionsPerTurn']);
    return DropCard(
      colors: mine ? Pal.gold : Pal.neutral,
      label: 'Giro ${_i(st['round'])}',
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(mine ? 'Tocca a te!' : 'Tocca a $current', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < per; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(i < left ? Icons.circle : Icons.circle_outlined, size: 20, color: i < left ? Pal.warn : Pal.line),
            ),
          const SizedBox(width: 6),
          Text('$left/$per azioni', style: const TextStyle(color: Pal.sub, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        const SizedBox(height: 12),
        if (mine)
          Row(children: [
            Expanded(
              child: DropButton(
                label: 'Ho usato un’azione',
                colors: Pal.neutral,
                height: 44,
                onTap: _busy || left == 0 ? null : () => _run(() => TableService.spendAction(_party!, me)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropButton(label: 'Fine turno', icon: Icons.skip_next, height: 44, onTap: _busy ? null : () => _endTurn(st)),
            ),
          ])
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in order) InfoChip(p, color: p == current ? Pal.accent : Pal.sub),
          ]),
      ]),
    );
  }

  Widget _positionCard(Map? pos) {
    final z = pos == null ? null : zoneSpec('${pos['zone']}');
    return DropCard(
      colors: typeColors(z?.type),
      label: 'La tua posizione',
      labelOnTop: true,
      child: Text(
        z == null ? 'Non ancora sulla mappa' : '${z.name} · settore ${pos!['sector']}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    );
  }

  List<Widget> _eventCards(List<Map<String, dynamic>> events, Map<String, dynamic> st, Map? pos, String me) {
    final round = _i(st['round']);
    final shown = events.where((e) => e['status'] == 'announced' || e['status'] == 'active').toList()
      ..sort((a, b) => _i(a['startRound']).compareTo(_i(b['startRound'])));
    return [
      for (final e in shown)
        Builder(builder: (_) {
          final def = eventDef(e['defId'] as String);
          final z = zoneSpec(e['zone'] as String);
          final active = e['status'] == 'active';
          final text = (active ? def.active : def.announce).replaceAll('{zone}', z.name);
          final title = def.legendary && active ? 'Leggendario: ${e['legendaryName']}' : def.name;
          final blocked = [for (final b in (e['blocked'] as List? ?? [])) _i(b)];
          final here = pos?['zone'] == e['zone'];
          final claimed = (e['claimedBy'] as List? ?? []).contains(me);
          final defeated = e['defeatedBy'] != null;
          final when = active
              ? 'Ancora ${_i(e['endRound']) - round + 1} ${_i(e['endRound']) - round + 1 == 1 ? 'giro' : 'giri'}'
              : (_i(e['startRound']) - round <= 1 ? 'Parte al prossimo giro' : 'Parte tra ${_i(e['startRound']) - round} giri');
          return DropCard(
            colors: typeColors(z.type),
            label: active ? 'IN CORSO' : 'IN ARRIVO',
            labelOnTop: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('${z.name} · $when', style: const TextStyle(color: Pal.sub, fontSize: 12)),
              const SizedBox(height: 8),
              Text(text, style: const TextStyle(height: 1.35)),
              if (active) ...[
                const SizedBox(height: 6),
                Text(def.table, style: const TextStyle(color: Pal.sub, fontStyle: FontStyle.italic, fontSize: 12)),
              ],
              if (blocked.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final b in blocked) InfoChip('Settore $b bloccato', color: Pal.bad)]),
              ],
              if (active && def.claimItem) ...[
                const SizedBox(height: 10),
                DropButton(
                  label: claimed ? 'Strumento già preso' : (here ? 'Prendi uno strumento' : 'Devi essere in ${z.name}'),
                  icon: Icons.card_giftcard,
                  height: 44,
                  onTap: (_busy || claimed || !here)
                      ? null
                      : () => _run(() async {
                            final name = await TableService.claimEventItem(_party!, e['id'] as String, me);
                            if (mounted) snack(context, 'Hai ottenuto: $name');
                          }),
                ),
              ],
              if (active && def.legendary) ...[
                const SizedBox(height: 10),
                DropButton(
                  label: defeated ? 'Già sconfitto' : (here ? 'Sfida ${e['legendaryName']}' : 'Devi essere in ${z.name}'),
                  icon: Icons.bolt,
                  colors: Pal.gold,
                  height: 44,
                  onTap: (_busy || defeated || !here)
                      ? null
                      : () => _run(() async {
                            final s = _s;
                            final id = await TableService.challengeLegendary(
                              party: _party!,
                              eventId: e['id'] as String,
                              uid: s.userName!,
                              pk: s.pokemonId!,
                              createBattle: (gym, extra) => BattleService.createGymBattle(
                                party: _party!,
                                gymId: 'legendary-${e['id']}',
                                gym: gym,
                                uid: s.userName!,
                                pk: s.pokemonId!,
                                extra: extra,
                              ),
                            );
                            if (mounted) widget.onBattle(id);
                          }),
                ),
              ],
            ]),
          );
        }),
    ];
  }

  Widget _zoneCard(ZoneSpec z, Map? pos, List<Map<String, dynamic>> events, Map<String, dynamic> st, String me) {
    final colors = typeColors(z.type);
    final mineZone = pos?['zone'] == z.id;
    final blocked = TableService.blockedSectors(events, z.id);
    final zoneEvents = events.where((e) => e['zone'] == z.id && (e['status'] == 'active' || e['status'] == 'announced')).toList();
    return DropCard(
      colors: colors,
      label: mineZone ? '${z.name} · sei qui' : z.name,
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (zoneEvents.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in zoneEvents)
              InfoChip(
                e['status'] == 'active' ? eventDef(e['defId'] as String).name : 'In arrivo: ${eventDef(e['defId'] as String).name}',
                color: e['status'] == 'active' ? Pal.bad : Pal.warn,
              ),
          ]),
          const SizedBox(height: 10),
        ],
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var s = 1; s <= z.sectors; s++) _sector(z, s, colors, mineZone && _i(pos!['sector']) == s, blocked.contains(s), st, events, pos),
        ]),
      ]),
    );
  }

  Widget _sector(ZoneSpec z, int s, List<Color> colors, bool here, bool blocked, Map<String, dynamic> st, List<Map<String, dynamic>> events, Map? pos) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _move(z, s, st, events, pos);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: here ? LinearGradient(colors: colors) : null,
          color: here ? null : (blocked ? Pal.line : Colors.white),
          border: Border.all(color: blocked ? Pal.sub : colors.first, width: 2),
        ),
        child: here
            ? const Icon(Icons.person_pin_circle, color: Colors.white)
            : blocked
                ? const Icon(Icons.block, color: Pal.sub, size: 20)
                : Text('$s', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: colors.first)),
      ),
    );
  }
}

// =============================================================================
//  Barra dei turni e osservatore (usati dalla home in modalità Tavolo)
// =============================================================================

/// Barra compatta sempre visibile: giro, chi gioca, azioni rimaste.
class TurnBar extends StatelessWidget {
  const TurnBar({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().userName!;
    return StreamBuilder<Map<String, dynamic>?>(
      stream: ItemService.watchUser(uid),
      builder: (context, uSnap) {
        final p = uSnap.data?['actualParty'];
        if (p is! String || p.isEmpty) return const SizedBox.shrink();
        return StreamBuilder<Map<String, dynamic>?>(
          stream: TableService.watchState(p),
          builder: (context, snap) {
            final st = snap.data;
            if (st == null || st['started'] != true) return const SizedBox.shrink();
            final order = List<String>.from(st['order'] as List);
            final current = order[_i(st['idx'])];
            final mine = current == uid;
            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? const Color(0xFFFFF4D6) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: mine ? Pal.warn : Pal.line, width: 2),
              ),
              child: Row(children: [
                Icon(Icons.casino_outlined, color: mine ? Pal.warn : Pal.sub),
                const SizedBox(width: 10),
                Text('Giro ${_i(st['round'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(mine ? 'Tocca a te!' : 'Tocca a $current',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700, color: mine ? Pal.ink : Pal.sub)),
                ),
                Text('${_i(st['actionsLeft'])}/${_i(st['actionsPerTurn'])} azioni',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Pal.sub)),
              ]),
            );
          },
        );
      },
    );
  }
}

/// Osservatore invisibile: tiene aggiornato il giro corrente, avvisa quando
/// tocca a te e quando un evento di zona viene annunciato, parte o finisce.
class TableWatcher extends StatefulWidget {
  const TableWatcher({super.key});
  @override
  State<TableWatcher> createState() => _TableWatcherState();
}

class _TableWatcherState extends State<TableWatcher> {
  StreamSubscription? _userSub, _stateSub, _evSub;
  String? _party;
  String? _turnKey;
  bool _evFirst = true;
  final Map<String, String> _statuses = {};
  late final String _uid;

  @override
  void initState() {
    super.initState();
    _uid = context.read<Session>().userName!;
    _userSub = ItemService.watchUser(_uid).listen((u) {
      final p = u?['actualParty'];
      final party = p is String && p.isNotEmpty ? p : null;
      if (party != _party) _subscribe(party);
    });
  }

  void _subscribe(String? party) {
    _stateSub?.cancel();
    _evSub?.cancel();
    _party = party;
    _turnKey = null;
    _evFirst = true;
    _statuses.clear();
    if (party == null) return;
    _stateSub = TableService.watchState(party).listen(_onState);
    _evSub = TableService.watchEvents(party).listen(_onEvents);
  }

  void _onState(Map<String, dynamic>? st) {
    if (st == null) return;
    TableClock.round = _i(st['round']);
    if (st['started'] != true) return;
    final order = List<String>.from(st['order'] as List);
    final key = '${_i(st['round'])}_${_i(st['idx'])}';
    if (_turnKey != null && key != _turnKey && order[_i(st['idx'])] == _uid && mounted) {
      HapticFeedback.heavyImpact();
      snack(context, '🎲 Tocca a te! Hai ${_i(st['actionsLeft'])} azioni');
    }
    _turnKey = key;
  }

  void _onEvents(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final d in snap.docs) {
      final e = d.data();
      final status = e['status'] as String? ?? 'scheduled';
      final prev = _statuses[d.id];
      _statuses[d.id] = status;
      if (_evFirst || prev == status || !mounted) continue;
      final def = eventDef(e['defId'] as String);
      final z = zoneSpec(e['zone'] as String).name;
      if (status == 'announced') {
        snack(context, '⚠️ ${def.announce.replaceAll('{zone}', z)}');
      } else if (status == 'active') {
        snack(context, '🌋 ${def.name}: ${def.active.replaceAll('{zone}', z)}');
      } else if (status == 'ended') {
        snack(context, 'L’evento “${def.name}” è terminato');
      }
    }
    _evFirst = false;
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _stateSub?.cancel();
    _evSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
