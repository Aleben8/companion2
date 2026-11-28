import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/item_service.dart';
import '../services/table_service.dart';
import '../table/phases.dart';
import '../table/sectors.dart';
import '../table/zones.dart';
import '../theme.dart';
import '../widgets/clue_search.dart';
import '../widgets/common.dart';
import '../widgets/drop.dart';
import 'here_sectors.dart';
import 'inventory_screen.dart';
import 'shop_sheet.dart';
import 'table_map.dart';

int _i(dynamic v) => v is num ? v.toInt() : 0;

/// Campi di `Users/{uid}` che servono al Tavolo e ai suoi pannelli.
const List<String> kTableUserFields = [
  'pos', 'shield', 'busyUntil', 'searchReadyAt', 'wildEncounter', 'spotted', 'inventory', 'localsInfo',
  'ticketReturn', 'lastKind', 'waitUntilAction', 'zoneMoves', 'freeAction',
];

/// Perché [me] non può fare un'azione di tipo [kind] adesso (null = può): con le fasi del giorno
/// le regole di [actBlock], con i turni "non è il tuo turno".
String? tableBlock(Map<String, dynamic>? st, Map<String, dynamic>? user, String me, String kind) {
  if (kTableTurns) {
    final mine = st?['order'] is List && List<String>.from(st!['order'] as List)[_i(st['idx'])] == me;
    return mine ? null : 'Non è il tuo turno';
  }
  return actBlock(state: st, user: user, uid: me, kind: kind);
}

/// I tre pannelli del Tavolo: Movimento, Strumenti, Esplorazione.
enum TableSheet { movement, tools, explore }

Future<void> showTableSheet(BuildContext context, TableSheet which, {required String party, required String me}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: switch (which) {
          TableSheet.movement => _MovementSheet(party: party, me: me),
          TableSheet.tools => _ToolsSheet(party: party, me: me),
          TableSheet.explore => _ExploreSheet(party: party, me: me),
        },
      ),
    );

/// Stato della partita, eventi e giocatore sempre aggiornati (stream condivisi: nessun listener in più).
class _TableLive extends StatelessWidget {
  final String party, me;
  final Widget Function(BuildContext context, Map<String, dynamic> st, List<Map<String, dynamic>> events,
      Map<String, dynamic> user) builder;
  const _TableLive({required this.party, required this.me, required this.builder});

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, dynamic>?>(
        stream: TableService.watchState(party),
        builder: (context, stSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: TableService.watchEvents(party),
          builder: (context, evSnap) => StreamBuilder<Map<String, dynamic>>(
            stream: ItemService.watchUserFields(me, kTableUserFields),
            builder: (context, uSnap) {
              final st = stSnap.data;
              if (st == null || uSnap.data == null) {
                return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
              }
              final events = <Map<String, dynamic>>[
                for (final d in evSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  {...d.data(), 'id': d.id},
              ];
              return builder(context, st, events, uSnap.data!);
            },
          ),
        ),
      );
}

Widget _title(String t, String sub) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Pal.ink)),
        Text(sub, style: const TextStyle(color: Pal.sub, fontSize: 12)),
      ]),
    );

String _err(Object e) => '$e'.replaceFirst('Exception: ', '');

// ----------------------------------------------------------------------- Movimento

class _MovementSheet extends StatefulWidget {
  final String party, me;
  const _MovementSheet({required this.party, required this.me});
  @override
  State<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends State<_MovementSheet> {
  bool _busy = false;

  /// Sposta la pedina; se va a buon fine chiude il pannello.
  Future<void> _move(ZoneSpec z, int sector, {required bool ticket, required bool visibleTrace}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final msg = await TableService.moveTo(
        party: widget.party,
        uid: widget.me,
        zone: z.id,
        sector: sector,
        useTicket: ticket,
        visibleTrace: visibleTrace,
      );
      if (!mounted) return;
      Navigator.pop(context);
      snack(context, msg ?? 'Sei in ${z.name}', error: msg != null);
      return;
    } catch (e) {
      if (mounted) snack(context, _err(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => _TableLive(
        party: widget.party,
        me: widget.me,
        builder: (context, st, events, user) {
          final pos = user['pos'] as Map?;
          final shield = ItemService.shieldZone(user);
          final pending = user['wildEncounter'] != null || user['spotted'] != null;
          final moveBlock = tableBlock(st, user, widget.me, ActKind.move);
          final zoneBlock = tableBlock(st, user, widget.me, ActKind.zone);
          final actionsLeft = kTableTurns ? _i(st['actionsLeft']) : 99;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            _title('Movimento', 'Spostati in un altro settore della tua zona o in un’altra zona.'),
            if (pos != null)
              HereSectors(
                party: widget.party,
                me: widget.me,
                state: st,
                events: events,
                pos: pos,
                shield: shield,
                myTurn: moveBlock == null,
                blockReason: moveBlock,
                actionsLeft: actionsLeft,
                pending: pending,
                busy: _busy,
                onMove: _move,
              ),
            const SizedBox(height: 16),
            const Text('Altre zone', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            TableMap(
              state: st,
              events: events,
              pos: pos,
              shield: shield,
              myTurn: zoneBlock == null,
              blockReason: zoneBlock,
              actionsLeft: actionsLeft,
              wildPending: pending,
              ticketCount: ItemService.readInventory(user)['biglietto'] ?? 0,
              freeReturn: TableService.freeReturnZone(user['ticketReturn'] as Map?, pos),
              busy: _busy,
              onMove: _move,
            ),
          ]);
        },
      );
}

// ----------------------------------------------------------------------- Strumenti

class _ToolsSheet extends StatelessWidget {
  final String party, me;
  const _ToolsSheet({required this.party, required this.me});

  @override
  Widget build(BuildContext context) => _TableLive(
        party: party,
        me: me,
        builder: (context, st, events, user) {
          final closed = tableShopClosedReason(user['pos'] as Map?);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            _title('Strumenti', 'La tua borsa e, nei settori cittadini, l’emporio.'),
            if (closed == null)
              DropButton(
                label: 'Emporio',
                icon: Icons.storefront,
                colors: Pal.gold,
                height: 44,
                onTap: () => showShop(context, me),
              )
            else
              Row(children: [
                const Icon(Icons.storefront, size: 16, color: Pal.sub),
                const SizedBox(width: 6),
                Expanded(child: Text('Emporio chiuso qui · $closed', style: const TextStyle(color: Pal.sub, fontSize: 12))),
              ]),
            const InventoryTab(),
          ]);
        },
      );
}

// -------------------------------------------------------------------- Esplorazione

class _ExploreSheet extends StatefulWidget {
  final String party, me;
  const _ExploreSheet({required this.party, required this.me});
  @override
  State<_ExploreSheet> createState() => _ExploreSheetState();
}

class _ExploreSheetState extends State<_ExploreSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) snack(context, _err(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _tracks() => _run(() async {
        final lines = await TableService.searchTracks(widget.party, widget.me);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(lines.isEmpty ? 'Nessuna traccia qui' : 'Tracce nel tuo settore'),
            content: lines.isEmpty
                ? const Text('Non si vedono tracce recenti di altri giocatori.')
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(l)),
                  ]),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ok'))],
          ),
        );
      });

  Future<void> _sectorAction(String id) => _run(() async {
        final msg = await TableService.sectorAction(widget.party, widget.me, id);
        if (mounted) snack(context, msg);
      });

  Future<void> _locals() => _run(() async {
        await TableService.requestLocals(widget.party, widget.me);
        if (mounted) snack(context, 'Richiesta inviata al Master: ti dirà se hai superato la CD');
      });

  /// Bottone di un'azione con il motivo per cui non si può fare (se non si può).
  Widget _action(String label, IconData icon, List<Color> colors, String? block, VoidCallback onTap, String help) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropButton(
            label: block == null ? label : '$label · ${block.toLowerCase()}',
            icon: icon,
            colors: colors,
            height: 48,
            busy: _busy,
            onTap: block == null ? onTap : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(help, style: const TextStyle(color: Pal.sub, fontSize: 12)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => _TableLive(
        party: widget.party,
        me: widget.me,
        builder: (context, st, events, user) {
          final pending = user['wildEncounter'] != null || user['spotted'] != null;
          String? block(String kind) =>
              pending ? 'Prima risolvi quello che ti è successo' : tableBlock(st, user, widget.me, kind);
          final searchBlock = block(ActKind.search);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            _title('Esplorazione', 'Cosa puoi fare nel settore in cui ti trovi.'),
            ClueSearchButton(party: widget.party, uid: widget.me, enabled: searchBlock == null, disabledReason: searchBlock),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text('1 azione: trovi gli indizi nascosti qui e, a volte, uno strumento.',
                  style: TextStyle(color: Pal.sub, fontSize: 12)),
            ),
            _action('Cerca tracce', Icons.pets, const [Color(0xFF6B7A8F), Color(0xFFADB9C9)], block(ActKind.tracks), _tracks,
                '1 azione: chi è passato da questo settore di recente, da dove è arrivato e dove è andato.'),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: TableService.watchLocalsRequests(widget.party),
              builder: (context, snap) {
                // una prova alla volta: finché il Master non risponde le altre aspettano
                final waiting = (snap.data?.docs ?? const []).any((d) => d.data()['uid'] == widget.me);
                const waitText = 'in attesa del Master';
                final pos = user['pos'] as Map?;
                final type = pos == null ? null : TableLayout.typeOf('${pos['zone']}', _i(pos['sector']));
                final here = [for (final id in SectorAction.all) if (SectorAction.allowed(id, type)) id];
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _action(
                    'Parla con i locali',
                    Icons.record_voice_over,
                    Pal.gold,
                    waiting ? waitText : block(ActKind.locals),
                    _locals,
                    '1 azione: il Master ti chiede un tiro al tavolo; se superi la CD i locali ti raccontano '
                    'chi è passato, gli eventi in arrivo e se c’è qualcosa di nascosto in zona.',
                  ),
                  if (here.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text('Azioni di questo settore${type == null ? '' : ' (${type.label.toLowerCase()})'}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    for (final id in here)
                      _action(
                        SectorAction.needsCheck(id)
                            ? '${SectorAction.label(id)} · ${SectorAction.fixedCd(id) == null ? 'CD dalle tracce' : 'CD ${SectorAction.fixedCd(id)}'}'
                            : SectorAction.label(id),
                        SectorAction.icon(id),
                        const [Color(0xFF3F9F72), Color(0xFF8CD0A8)],
                        SectorAction.needsCheck(id) && waiting ? waitText : block(id),
                        () => _sectorAction(id),
                        '1 azione. ${SectorAction.help(id)}',
                      ),
                  ],
                ]);
              },
            ),
          ]);
        },
      );
}
