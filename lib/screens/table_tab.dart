import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../mode.dart';
import '../services/battle_service.dart';
import '../services/item_service.dart';
import '../services/live_service.dart';
import '../services/location_service.dart';
import '../services/party_service.dart';
import '../services/session.dart';
import '../services/table_service.dart';
import '../table/events.dart';
import '../table/zones.dart';
import '../theme.dart';
import '../widgets/clue_search.dart';
import '../widgets/common.dart';
import '../widgets/drop.dart';
import '../widgets/game_status.dart';

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
  bool _manualNext = false; // modalità eventi scelta prima dell'avvio
  String? _shield; // zona protetta da un'Ombrello di bioma attivo

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
          : kTableMode
              ? 'Verrà sorteggiato l’ordine dei turni, tutti partono dall’Hub e vengono pianificati gli eventi di zona.'
              : 'Parte l’orologio dei giri (uno ogni ${await TableService.roundMinutes(_party!)} minuti) e vengono '
                  'pianificati gli eventi di zona. La zona di ognuno la decide il GPS.',
      started ? 'Riavvia' : 'Avvia',
    );
    if (go) await _run(() => TableService.startGame(_party!, manualEvents: _manualNext), ok: 'Partita avviata!');
  }

  /// Master: decide quali zone sono collegate tra loro.
  Future<void> _editLinks(Map<String, dynamic>? st) async {
    final started = st != null && st['started'] == true;
    final current = started ? TableService.linksOf(st) : await TableService.partyLinks(_party!);
    final work = {...current};
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Collegamenti tra zone'),
          content: SizedBox(
            width: 380,
            child: ListView(shrinkWrap: true, children: [
              const Text(
                'Spunta le coppie di zone che confinano: ci si sposta solo tra zone collegate '
                '(altrimenti serve un Biglietto o un treno/traghetto).',
                style: TextStyle(fontSize: 12, color: Pal.sub),
              ),
              for (var i = 0; i < kZones.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(kZones[i].name, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                for (var j = i + 1; j < kZones.length; j++)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('↔ ${kZones[j].name}'),
                    value: work.contains(TableService.linkKey(kZones[i].id, kZones[j].id)),
                    onChanged: (v) => set(() {
                      final k = TableService.linkKey(kZones[i].id, kZones[j].id);
                      v == true ? work.add(k) : work.remove(k);
                    }),
                  ),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => set(() {
                work
                  ..clear()
                  ..addAll(TableService.defaultLinks);
              }),
              child: const Text('Proposta'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
          ],
        ),
      ),
    );
    if (save == true) {
      await _run(() => TableService.setLinks(_party!, work), ok: 'Collegamenti salvati');
    }
  }

  /// Master, eventi manuali: sceglie l'evento della carta pescata (e la zona per il leggendario).
  Future<void> _addManualEvent() async {
    final defs = [...TableService.availableEvents, kLegendaryDef];
    final def = await showDialog<ZoneEventDef>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Quale evento hai pescato?'), children: [
        for (final d in defs)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, d),
            child: Text(d.legendary ? d.name : '${d.name} · ${zoneSpec(d.zone).name}'),
          ),
      ]),
    );
    if (def == null || !mounted) return;
    String? zone;
    if (def.legendary) {
      zone = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(title: const Text('In quale zona?'), children: [
          for (final z in kZones.where((z) => z.id != 'hub'))
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, z.id), child: Text(z.name)),
        ]),
      );
      if (zone == null || !mounted) return;
    }
    final now = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(def.name),
        content: const Text('Vuoi annunciarlo (parte quando lo attivi tu) o farlo partire subito?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuncia')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Attiva ora')),
        ],
      ),
    );
    if (now == null) return;
    await _run(() => TableService.createManualEvent(_party!, def.id, zone: zone, activateNow: now),
        ok: now ? 'Evento attivato' : 'Evento annunciato');
  }

  Future<void> _endTurn(Map<String, dynamic> st) async {
    final left = _i(st['actionsLeft']);
    if (left > 0) {
      final go = await _confirm('Fine turno', 'Hai ancora $left ${left == 1 ? 'azione' : 'azioni'}. Vuoi finire il turno?', 'Fine turno');
      if (!go) return;
    }
    await _run(() => TableService.endTurn(_party!, _s.userName!));
  }

  /// Master, dal vivo: centra la zona nella posizione GPS attuale.
  Future<void> _placeZoneHere(ZoneSpec z, LiveZone? cur) => _run(() async {
        final p = await context.read<LocationService>().current();
        if (p == null) throw Exception('Posizione non disponibile');
        await LiveService.setZone(_party!, z.id, p.latitude, p.longitude, cur?.radius ?? kDefaultZoneRadius);
      }, ok: '${z.name} posizionata qui');

  Future<void> _move(ZoneSpec z, int sector, Map<String, dynamic> st, List<Map<String, dynamic>> events, Map? pos) async {
    if (!kTableMode) {
      snack(context, 'Dal vivo ti sposti camminando: zona e settore li decide il GPS');
      return;
    }
    final me = _s.userName!;
    final order = List<String>.from(st['order'] as List);
    if (order[_i(st['idx'])] != me) {
      snack(context, 'Non è il tuo turno');
      return;
    }
    if (TableService.blockedSectors(events, z.id, shield: _shield).contains(sector)) {
      snack(context, 'Questo settore è bloccato');
      return;
    }
    final cost = TableService.moveCost(events, pos?['zone'] as String?, z.id, shield: _shield);
    final route = TableService.routeTo(st, events, pos?['zone'] as String?, z.id);
    var ticket = false;
    if (route == MoveRoute.ticket) {
      final qty = ItemService.readInventory((await ItemService.userRef(me).get()).data())['biglietto'] ?? 0;
      if (qty <= 0) {
        snack(context, '${z.name} non è collegata alla tua zona: serve un Biglietto (o un treno/traghetto).', error: true);
        return;
      }
      ticket = true;
    }
    final go = await _confirm(
      'Spostamento',
      'Vai in ${z.name}, settore $sector?\nCosto: $cost ${cost == 1 ? 'azione' : 'azioni'}.'
          '${ticket ? '\nZona non collegata: usi 1 Biglietto.' : ''}'
          '${route == MoveRoute.passage ? '\nViaggi con il treno/traghetto: niente Biglietto.' : ''}',
      'Vai',
    );
    if (!go) return;
    await _run(() async {
      final msg = await TableService.moveTo(party: _party!, uid: me, zone: z.id, sector: sector, useTicket: ticket);
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
                _shield = ItemService.shieldZone(uSnap.data);
                final table = kTableMode;
                return Column(children: [
                  SectionTitle(table ? 'Tavolo' : 'Partita'),
                  if (_master) _masterTools(started, st, events),
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
                    if (table && st!['order'] is List) _turnCard(st, me) else if (!table) _clockCard(st!, uSnap.data),
                    _positionCard(pos),
                    ..._eventCards(events, st!, pos, me),
                    SectionTitle(table ? 'Mappa' : 'Zone'),
                    if (table)
                      ClueSearchButton(
                        party: _party!,
                        uid: me,
                        enabled: st['order'] is List && List<String>.from(st['order'] as List)[_i(st['idx'])] == me,
                      ),
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

  Widget _masterTools(bool started, Map<String, dynamic>? st, List<Map<String, dynamic>> events) {
    final manual = started ? TableService.isManual(st) : _manualNext;
    final live = events.where((e) => e['status'] == 'announced' || e['status'] == 'active').toList();
    return DropCard(
      colors: const [Pal.accent, Color(0xFF9C7BE0)],
      label: 'Master',
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
          'Solo per preparare la partita: dopo l’avvio tutti giocano alla pari.',
          style: TextStyle(color: Pal.sub, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Eventi di zona manuali', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            manual
                ? 'Pesca la carta dal mazzo e inserisci tu l’evento.'
                : 'La app pianifica e fa partire gli eventi da sola.',
            style: const TextStyle(fontSize: 12),
          ),
          value: manual,
          onChanged: _busy
              ? null
              : (v) => started
                  ? _run(() => TableService.setEventMode(_party!, manual: v),
                      ok: v ? 'Eventi manuali: li inserisci tu' : 'Eventi automatici ripianificati')
                  : setState(() => _manualNext = v),
        ),
        if (started && manual) ...[
          DropButton(
            label: 'Inserisci evento (carta pescata)',
            icon: Icons.add_circle_outline,
            colors: Pal.gold,
            height: 44,
            onTap: _busy ? null : _addManualEvent,
          ),
          for (final e in live)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '${e['name']} · ${zoneSpec(e['zone'] as String).name} (${e['status'] == 'active' ? 'in corso' : 'annunciato'})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (e['status'] != 'active')
                  TextButton(
                    onPressed: _busy ? null : () => _run(() => TableService.activateEvent(_party!, e['id'] as String)),
                    child: const Text('Attiva'),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => _run(() => TableService.endEvent(_party!, e['id'] as String)),
                  child: Text(e['status'] == 'active' ? 'Termina' : 'Annulla'),
                ),
              ]),
            ),
        ],
        const SizedBox(height: 8),
        if (kTableMode)
          DropButton(
            label: 'Collegamenti tra zone',
            icon: Icons.alt_route,
            colors: Pal.neutral,
            height: 44,
            onTap: _busy ? null : () => _editLinks(st),
          )
        else
          _liveMasterTools(st),
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

  /// Master dal vivo: durata del giro e posizione delle zone sulla mappa.
  Widget _liveMasterTools(Map<String, dynamic>? st) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: PartyService.party(_party!).snapshots().map((s) => s.data()),
      builder: (context, snap) {
        final zones = LiveService.zonesOf(snap.data);
        final mins = (snap.data?['roundMinutes'] as num?)?.toInt() ?? kDefaultRoundMinutes;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('Durata di un giro', style: TextStyle(fontWeight: FontWeight.w700))),
            DropdownButton<int>(
              value: kRoundMinuteChoices.contains(mins) ? mins : null,
              hint: Text('$mins min'),
              items: [for (final m in kRoundMinuteChoices) DropdownMenuItem(value: m, child: Text('$m min'))],
              onChanged: _busy ? null : (m) => m == null ? null : _run(() => TableService.setRoundMinutes(_party!, m)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Zone sulla mappa (${zones.length}/${kZones.length}). Mettiti sul posto e premi "Qui", '
            'oppure tieni premuto sulla mappa qui sopra. I settori sono i 4 spicchi Nord, Est, Sud e Ovest.',
            style: const TextStyle(color: Pal.sub, fontSize: 12),
          ),
          for (final z in kZones)
            Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: z.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                    text: zones[z.id] == null ? '  da posizionare' : '  ✓',
                    style: TextStyle(color: zones[z.id] == null ? Pal.warn : Pal.ok, fontSize: 12),
                  ),
                ])),
              ),
              if (zones[z.id] != null)
                DropdownButton<double>(
                  value: kZoneRadiusChoices.contains(zones[z.id]!.radius) ? zones[z.id]!.radius : null,
                  hint: Text('${zones[z.id]!.radius.round()} m'),
                  underline: const SizedBox.shrink(),
                  items: [for (final r in kZoneRadiusChoices) DropdownMenuItem(value: r, child: Text('${r.round()} m'))],
                  onChanged: _busy ? null : (r) => r == null ? null : _run(() => LiveService.setRadius(_party!, z.id, r)),
                ),
              TextButton(onPressed: _busy ? null : () => _placeZoneHere(z, zones[z.id]), child: const Text('Qui')),
            ]),
        ]);
      },
    );
  }

  /// Dal vivo: giro corrente e conto alla rovescia al prossimo, più l'eventuale attesa in corso.
  Widget _clockCard(Map<String, dynamic> st, Map<String, dynamic>? user) {
    final next = TableService.nextRoundAt(st);
    final busy = LiveService.left(user?['busyUntil']);
    final search = LiveService.left(user?['searchReadyAt']);
    return DropCard(
      colors: Pal.gold,
      label: 'Giro ${_i(st['round'])}',
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Prossimo giro tra ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (next != null) Countdown(next, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Text('Un giro ogni ${_i(st['roundMinutes']) == 0 ? kDefaultRoundMinutes : _i(st['roundMinutes'])} minuti. '
            'Niente turni: si gioca tutti insieme.', style: const TextStyle(color: Pal.sub, fontSize: 12)),
        if (busy != null || search != null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (busy != null) InfoChip('In attesa: ${LiveService.fmt(busy)}', color: Pal.bad),
            if (search != null) InfoChip('Nuova ricerca tra ${LiveService.fmt(search)}', color: Pal.warn),
          ]),
        ],
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          z == null
              ? (kTableMode ? 'Non ancora sulla mappa' : 'Fuori dalle zone di gioco')
              : '${z.name} · ${kTableMode ? 'settore ${pos!['sector']}' : LiveService.sectorLabel(z.id, pos!['sector'])}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        if (!kTableMode)
          const Text('La aggiorna il GPS mentre cammini.', style: TextStyle(color: Pal.sub, fontSize: 12)),
      ]),
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
              : (_i(e['startRound']) >= TableService.kManualStart
                  ? 'Il Master lo attiverà a breve'
                  : (_i(e['startRound']) - round <= 1 ? 'Parte al prossimo giro' : 'Parte tra ${_i(e['startRound']) - round} giri'));
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
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final b in blocked)
                    InfoChip(
                      '${kTableMode ? 'Settore $b' : LiveService.sectorLabel(z.id, b).replaceFirst('settore', 'Settore')} bloccato',
                      color: Pal.bad,
                    ),
                ]),
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
    final blocked = TableService.blockedSectors(events, z.id, shield: _shield);
    final zoneEvents = events.where((e) => e['zone'] == z.id && (e['status'] == 'active' || e['status'] == 'announced')).toList();
    final links = TableService.linksOf(st);
    final linked = [
      for (final o in kZones)
        if (o.id != z.id && links.contains(TableService.linkKey(z.id, o.id))) o.name,
    ];
    return DropCard(
      colors: colors,
      label: mineZone ? '${z.name} · sei qui' : z.name,
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (kTableMode) ...[
          Text(
            linked.isEmpty ? 'Nessun collegamento diretto' : 'Collegata a: ${linked.join(', ')}',
            style: const TextStyle(color: Pal.sub, fontSize: 12),
          ),
          const SizedBox(height: 6),
        ],
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
                : Text(
                    // dal vivo i settori sono i punti cardinali
                    !kTableMode && z.sectors == 4 ? const ['N', 'E', 'S', 'O'][s - 1] : '$s',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: colors.first),
                  ),
      ),
    );
  }
}

// =============================================================================
//  Barra dei turni e osservatore (usati dalla home in modalità Tavolo)
// =============================================================================

/// Barra compatta sempre visibile: giro, chi gioca, azioni rimaste.
/// Dal vivo: giro, conto alla rovescia al prossimo e zona in cui ti trovi.
class TurnBar extends StatelessWidget {
  const TurnBar({super.key});

  Widget _liveBar(Map<String, dynamic> st, Map<String, dynamic>? user) {
    final next = TableService.nextRoundAt(st);
    final pos = user?['pos'] as Map?;
    final busy = LiveService.left(user?['busyUntil']) != null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: busy ? const Color(0xFFFFE9E9) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: busy ? Pal.bad : Pal.line, width: 2),
      ),
      child: Row(children: [
        const Icon(Icons.timer_outlined, color: Pal.sub),
        const SizedBox(width: 10),
        Text('Giro ${_i(st['round'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            pos == null ? 'Fuori dalle zone' : zoneSpec('${pos['zone']}').name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.sub),
          ),
        ),
        if (next != null) ...[
          const Text('prossimo ', style: TextStyle(fontSize: 12, color: Pal.sub)),
          Countdown(next, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ]),
    );
  }

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
            if (!kTableMode) return _liveBar(st, uSnap.data);
            if (st['order'] is! List) return const SizedBox.shrink();
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
/// Dal vivo fa anche avanzare l'orologio dei giri e ricava zona e settore dal GPS.
class TableWatcher extends StatefulWidget {
  const TableWatcher({super.key});
  @override
  State<TableWatcher> createState() => _TableWatcherState();
}

class _TableWatcherState extends State<TableWatcher> {
  StreamSubscription? _userSub, _stateSub, _evSub, _zoneSub;
  Timer? _clock;
  String? _party;
  String? _turnKey;
  int? _lastRound;
  bool _evFirst = true;
  bool _started = false;
  final Map<String, String> _statuses = {};
  Map<String, LiveZone> _zones = {};
  String? _posKey; // ultima zona/settore scritta dal GPS
  String? _startKey; // avvio della partita (per accorgersi di un riavvio)
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
    if (!kTableMode) {
      // dal vivo: chi ha la app aperta controlla l'orologio (lo fa avanzare uno solo, con una transazione)
      _clock = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    }
  }

  Future<void> _tick() async {
    if (_party == null || !_started) return;
    try {
      await TableService.tickLive(_party!);
    } catch (e) {
      debugPrint('Errore orologio: $e');
    }
  }

  void _subscribe(String? party) {
    _stateSub?.cancel();
    _evSub?.cancel();
    _zoneSub?.cancel();
    _party = party;
    _turnKey = null;
    _lastRound = null;
    _evFirst = true;
    _posKey = null;
    _zones = {};
    _statuses.clear();
    if (party == null) return;
    _stateSub = TableService.watchState(party).listen(_onState);
    _evSub = TableService.watchEvents(party).listen(_onEvents);
    if (!kTableMode) {
      _zoneSub = LiveService.watchZones(party).listen((z) {
        _zones = z;
        _syncPos(context.read<LocationService>());
      });
    }
  }

  /// Dal vivo: zona e settore in base al GPS (null = fuori dalle zone).
  void _syncPos(LocationService loc) {
    final p = loc.position;
    if (kTableMode || _party == null || p == null) return;
    final pos = LiveService.locate(_zones, p.latitude, p.longitude);
    final key = pos == null ? '-' : '${pos['zone']}/${pos['sector']}';
    if (key == _posKey) return;
    final prevZone = _posKey?.split('/').first;
    _posKey = key;
    TableService.updateLivePos(_uid, pos, party: _started ? _party : null).catchError((e) {
      _posKey = null; // si riprova alla prossima posizione
      debugPrint('Errore posizione di zona: $e');
    });
    if (pos != null && prevZone != null && prevZone != pos['zone']) {
      // può essere chiamata durante il build: l'avviso va al frame successivo
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) snack(context, '📍 Sei entrato in ${zoneSpec('${pos['zone']}').name}');
      });
    }
  }

  void _onState(Map<String, dynamic>? st) {
    if (st == null) return;
    TableClock.round = _i(st['round']);
    _started = st['started'] == true;
    if (!_started) return;
    if (!kTableMode) {
      // (ri)avvio: la partita ha azzerato le posizioni, il GPS deve riscriverle
      final startKey = '${st['startedAt']}';
      if (startKey != _startKey) {
        _startKey = startKey;
        _posKey = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncPos(context.read<LocationService>());
        });
      }
      final r = _i(st['round']);
      if (_lastRound != null && r != _lastRound && mounted) snack(context, '⏱ Inizia il giro $r');
      _lastRound = r;
      return;
    }
    if (st['order'] is! List) return;
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
    _zoneSub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // dal vivo si ricostruisce a ogni nuova posizione GPS
    if (!kTableMode) _syncPos(context.watch<LocationService>());
    return const SizedBox.shrink();
  }
}

/// Fascia scura in cima alla home (tavolo e dal vivo): eventi di zona in corso o annunciati,
/// con quanti giri mancano alla fine (in corso) o all'inizio (in arrivo).
class ZoneEventsStrip extends StatelessWidget {
  const ZoneEventsStrip({super.key});

  static String _giri(int n) => n == 1 ? '1 giro' : '$n giri';

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
          builder: (context, stSnap) {
            final st = stSnap.data;
            if (st == null || st['started'] != true) return const SizedBox.shrink();
            final round = _i(st['round']);
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: TableService.watchEvents(p),
              builder: (context, evSnap) {
                final events = [
                  for (final d in evSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    if (d.data()['status'] == 'active' || d.data()['status'] == 'announced') d.data(),
                ]..sort((a, b) {
                    final byStatus = (a['status'] == 'active' ? 0 : 1).compareTo(b['status'] == 'active' ? 0 : 1);
                    return byStatus != 0 ? byStatus : _i(a['startRound']).compareTo(_i(b['startRound']));
                  });
                if (events.isEmpty) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Pal.ink, borderRadius: BorderRadius.circular(18)),
                  child: Column(children: [
                    for (var i = 0; i < events.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: Colors.white.withOpacity(0.12)),
                      _row(events[i], round),
                    ],
                  ]),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _row(Map<String, dynamic> e, int round) {
    final active = e['status'] == 'active';
    final zone = zoneSpec(e['zone'] as String? ?? '');
    final legendary = e['legendary'] == true;
    final name = legendary && active && e['legendaryName'] != null
        ? 'Leggendario: ${e['legendaryName']}'
        : (e['name'] as String? ?? eventDef(e['defId'] as String).name);
    final start = _i(e['startRound']);
    final String when;
    if (active) {
      when = 'finisce tra ${_giri(_i(e['endRound']) - round + 1)}';
    } else if (start >= TableService.kManualStart) {
      when = 'inizio deciso dal Master';
    } else {
      when = 'inizia tra ${_giri((start - round).clamp(1, 999))}';
    }
    final tagColor = active ? Pal.bad : Pal.warn;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tagColor.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
          child: Text(active ? 'IN CORSO' : 'IN ARRIVO',
              style: TextStyle(color: tagColor, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            Text(zone.name, style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(when,
            textAlign: TextAlign.right,
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
