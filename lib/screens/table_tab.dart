import 'dart:async';
import 'dart:math';

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
import '../items.dart';
import '../table/events.dart';
import '../table/sectors.dart';
import '../table/zones.dart';
import 'shop_sheet.dart';
import 'here_sectors.dart';
import 'table_map.dart';
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
  bool _masterOpen = false; // scheda Master aperta o chiusa
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
    if (kTableMode) return _startTable(started);
    final go = await _confirm(
      started ? 'Riavvia la partita' : 'Avvia la partita',
      started
          ? 'Giro, posizioni, trappole, eventi e indizi ripartono da zero: ognuno ridispone i suoi indizi (strumenti e badge restano).'
          : 'Parte l’orologio dei giri (uno ogni ${await TableService.roundMinutes(_party!)} minuti) e vengono '
              'pianificati gli eventi di zona. La zona di ognuno la decide il GPS.',
      started ? 'Riavvia' : 'Avvia',
    );
    if (go) await _run(() => TableService.startGame(_party!, manualEvents: _manualNext), ok: 'Partita avviata!');
  }

  /// Tavolo: "Nuova partita". Il Master vede i biomi estratti (Hub + giocatori + 1) e può cambiarli.
  Future<void> _startTable(bool started) async {
    final players = (await PartyService.players(_party!).get()).docs.length;
    if (!mounted) return;
    if (players > kMaxTablePlayers) {
      snack(context, 'Al tavolo si gioca al massimo in $kMaxTablePlayers (ora siete $players)', error: true);
      return;
    }
    final links = await TableService.partyLinks(_party!);
    var sel = TableService.drawBiomes(players).toSet();
    if (!mounted) return;
    final biomes = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final isolated = TableService.unreachableBiomes(sel, links);
        return AlertDialog(
          title: Text(started ? 'Riavvia la partita' : 'Nuova partita'),
          content: SizedBox(
            width: 380,
            child: ListView(shrinkWrap: true, children: [
              Text(
                '$players giocatori: l’Hub più ${min(7, players + 1)} biomi estratti a caso. Puoi cambiarli. '
                '${started ? 'Giro, posizioni, trappole, eventi e indizi ripartono da zero: ognuno ridispone i suoi indizi (strumenti e badge restano). ' : ''}'
                'Tutti partono dall’Hub e l’ordine dei turni è sorteggiato.',
                style: const TextStyle(fontSize: 12, color: Pal.sub),
              ),
              for (final z in kZones)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(z.name),
                  subtitle: z.id == 'hub' ? const Text('C’è sempre') : null,
                  value: sel.contains(z.id),
                  onChanged: z.id == 'hub' ? null : (v) => set(() => v == true ? sel.add(z.id) : sel.remove(z.id)),
                ),
              if (isolated.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Pal.warn.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '⚠️ Dall’Hub non si arriva a piedi in: ${isolated.map((z) => zoneSpec(z).name).join(', ')}. '
                    'Si potrà andarci solo con Biglietto, treno o traghetto (puoi avviare lo stesso, '
                    'oppure cambiare i collegamenti).',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => set(() => sel = TableService.drawBiomes(players).toSet()), child: const Text('Riestrai')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, sel.toList()), child: Text(started ? 'Riavvia' : 'Avvia')),
          ],
        );
      }),
    );
    if (biomes == null) return;
    await _run(() => TableService.startGame(_party!, manualEvents: _manualNext, biomes: biomes), ok: 'Partita avviata!');
  }

  /// Master: tipo e numero dei settori di ogni zona.
  Future<void> _editSectors(Map<String, dynamic>? st) async {
    final partyDoc = (await PartyService.party(_party!).get()).data();
    final work = {for (final e in TableService.sectorsOf(st, partyDoc).entries) e.key: [...e.value]};
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Settori delle zone'),
          content: SizedBox(
            width: 420,
            child: ListView(shrinkWrap: true, children: [
              Text(
                'Scegli quanti settori ha ogni zona e di che tipo sono (${work.values.fold<int>(0, (a, l) => a + l.length)} '
                'settori in tutto). Se togli dei settori a partita in corso, quello che c’era (giocatori, tracce, '
                'indizi, trappole) finisce nell’ultimo settore rimasto.',
                style: const TextStyle(fontSize: 12, color: Pal.sub),
              ),
              for (final z in kZones) ...[
                Row(children: [
                  Expanded(child: Text(z.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                  IconButton(
                    tooltip: 'Togli un settore',
                    onPressed: work[z.id]!.length <= kMinSectors ? null : () => set(() => work[z.id]!.removeLast()),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('${work[z.id]!.length}'),
                  IconButton(
                    tooltip: 'Aggiungi un settore',
                    onPressed: work[z.id]!.length >= kMaxSectors ? null : () => set(() => work[z.id]!.add(SectorType.cittadino)),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ]),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (var i = 0; i < work[z.id]!.length; i++)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.sub)),
                      const SizedBox(width: 4),
                      DropdownButton<SectorType>(
                        value: work[z.id]![i],
                        isDense: true,
                        items: [
                          for (final t in SectorType.values)
                            DropdownMenuItem(
                              value: t,
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(t.icon, size: 16),
                                const SizedBox(width: 4),
                                Text(t.label, style: const TextStyle(fontSize: 13)),
                              ]),
                            ),
                        ],
                        onChanged: (t) => t == null ? null : set(() => work[z.id]![i] = t),
                      ),
                    ]),
                ]),
                const Divider(),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => set(() {
                work
                  ..clear()
                  ..addAll({for (final e in kDefaultSectors.entries) e.key: [...e.value]});
              }),
              child: const Text('Proposta'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
          ],
        ),
      ),
    );
    if (save == true) await _run(() => TableService.setSectorTypes(_party!, work), ok: 'Settori salvati');
  }

  /// Master: un giocatore chiede informazioni ai locali (in qualsiasi settore). La finestra dice solo
  /// il modificatore di CD del settore; il tiro si fa al tavolo e il Master dice se è riuscito.
  /// Il racconto dei locali lo vede solo il giocatore (il Master, che gioca, non lo legge).
  Future<void> _askLocals(Map<String, dynamic> st) async {
    final order = st['order'] is List ? List<String>.from(st['order'] as List) : <String>[];
    final who = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Chi chiede ai locali?'), children: [
        for (final p in order) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p), child: Text(p)),
      ]),
    );
    if (who == null || !mounted) return;
    LocalsCheck check;
    try {
      check = await TableService.localsCheck(_party!, who);
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
      return;
    }
    if (!mounted) return;
    final m = check.cdModifier;
    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Informazioni dai locali · $who'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(check.place, style: const TextStyle(color: Pal.sub, fontSize: 12)),
          const SizedBox(height: 10),
          Text('Modificatore di CD: ${m == 0 ? 'nessuno' : (m > 0 ? '+$m' : '−${-m}')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text('$who ha superato la CD?', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Quello che raccontano i locali lo vedrà solo il giocatore.',
              style: TextStyle(color: Pal.sub, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sì')),
        ],
      ),
    );
    if (success == null) return;
    await _run(() => TableService.sendLocals(_party!, who, success: success), ok: 'Inviato a $who');
  }

  /// Il messaggio dei locali (lo vede solo chi ha chiesto).
  Widget _localsCard(Map info, String me) {
    final ok = info['success'] == true;
    final lines = [for (final l in (info['lines'] as List? ?? [])) '$l'];
    return DropCard(
      colors: Pal.gold,
      label: 'I locali ti raccontano',
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${info['place']}', style: const TextStyle(color: Pal.sub, fontSize: 12)),
        const SizedBox(height: 6),
        if (!ok) const Text('I locali non sanno nulla (o non vogliono parlare).'),
        for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $l')),
        const SizedBox(height: 6),
        DropButton(
          label: 'Ho letto',
          colors: Pal.neutral,
          height: 40,
          onTap: _busy ? null : () => _run(() => TableService.dismissLocals(me)),
        ),
      ]),
    );
  }

  /// Qualcuno nel settore ti ha notato entrando (è già stato avvisato): elùdilo con un'azione o una Fune di fuga.
  Widget _spottedCard(Map sp, int ropes) {
    final z = zoneSpec('${sp['zone']}');
    return DropCard(
      colors: const [Color(0xFF5B6B8C), Color(0xFF9AA8C7)],
      label: 'Ti hanno notato!',
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Entrando in ${z.name}, settore ${sp['sector']}, qualcuno ti ha visto.',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('Tiro ${sp['roll']} + destrezza = ${sp['total']}, serviva ${sp['cd']}.',
            style: const TextStyle(color: Pal.sub, fontSize: 12)),
        const SizedBox(height: 6),
        const Text(
          'Chi è nel settore è stato avvisato. Per eluderlo usa $kEludeCost azione oppure una Fune di fuga.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropButton(
              label: 'Eludi ($kEludeCost azione)',
              icon: Icons.directions_run,
              height: 44,
              onTap: _busy ? null : () => _run(() => TableService.elude(_party!, _s.userName!), ok: 'Ti sei allontanato'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropButton(
              label: 'Fune di fuga ×$ropes',
              icon: Icons.logout,
              colors: Pal.neutral,
              height: 44,
              onTap: _busy || ropes <= 0
                  ? null
                  : () => _run(() => TableService.elude(_party!, _s.userName!, rope: true), ok: 'Ti sei allontanato con la Fune di fuga'),
            ),
          ),
        ]),
      ]),
    );
  }

  /// Chi hai notato entrare nel tuo settore (questo giro e il precedente). Resta visibile anche se
  /// l'avviso a comparsa è passato mentre la app era chiusa.
  Widget _sightings(String me, int round) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: TableService.watchSightings(_party!, me),
        builder: (context, snap) {
          final rows = [
            for (final d in snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              if (d.data()['type'] == 'spotted' && _i(d.data()['round']) >= round - 1) d.data(),
          ]..sort((a, b) => _i(b['round']).compareTo(_i(a['round'])));
          if (rows.isEmpty) return const SizedBox.shrink();
          return DropCard(
            colors: const [Color(0xFF5B6B8C), Color(0xFF9AA8C7)],
            label: 'Avvistamenti',
            labelOnTop: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final r in rows.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('👀 ${r['uid']} è entrato nel tuo settore '
                      '(${zoneSpec('${r['zone']}').name}, settore ${r['sector']}) · giro ${r['round']}'),
                ),
            ]),
          );
        },
      );

  /// Incontro selvatico (settore selvaggio): affrontarlo o fuggire.
  Future<void> _wild(bool fight) => _run(() async {
        if (fight) {
          final id = await TableService.fightWild(party: _party!, uid: _s.userName!, pk: _s.pokemonId!);
          if (mounted) widget.onBattle(id);
        } else {
          await TableService.fleeWild(_party!, _s.userName!);
          if (mounted) snack(context, 'Sei fuggito (−$kWildFleeCost azione)');
        }
      });

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
      // al tavolo compare in un settore impervio: si propongono i biomi in gioco che ne hanno uno
      zone = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(title: const Text('In quale zona?'), children: [
          for (final z in TableService.legendaryZones())
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, z), child: Text(zoneSpec(z).name)),
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

  /// Dal vivo le schede zona sono solo informative: ci si sposta camminando.
  void _move(ZoneSpec z, int sector, Map<String, dynamic> st, List<Map<String, dynamic>> events, Map? pos) =>
      snack(context, 'Dal vivo ti sposti camminando: zona e settore li decide il GPS');

  /// Tavolo: conferma dal pannello dei settori della mappa (il costo è già scritto sul bottone).
  Future<void> _moveTo(ZoneSpec z, int sector, {required bool ticket, required bool visibleTrace}) => _run(() async {
        final msg = await TableService.moveTo(
          party: _party!,
          uid: _s.userName!,
          zone: z.id,
          sector: sector,
          useTicket: ticket,
          visibleTrace: visibleTrace,
        );
        if (msg != null && mounted) snack(context, msg, error: true);
      });

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
              stream: PartyService.watchParty(_party!),
              builder: (context, pSnap) => StreamBuilder<Map<String, dynamic>>(
              stream: ItemService.watchUserFields(
                  me, const ['pos', 'shield', 'busyUntil', 'searchReadyAt', 'wildEncounter', 'spotted', 'inventory', 'localsInfo', 'ticketReturn']),
              builder: (context, uSnap) {
                final pos = uSnap.data?['pos'] as Map?;
                _shield = ItemService.shieldZone(uSnap.data);
                final table = kTableMode;
                if (table) {
                  // settori e biomi della partita (o, prima dell'avvio, quelli scelti per il party)
                  TableLayout.sectors = TableService.sectorsOf(st, pSnap.data);
                  TableLayout.biomes = started ? TableService.biomesOf(st) : null;
                }
                final myTurn = st?['order'] is List && List<String>.from(st!['order'] as List)[_i(st['idx'])] == me;
                final wild = uSnap.data?['wildEncounter'] as Map?;
                final locals = uSnap.data?['localsInfo'] as Map?;
                final spotted = uSnap.data?['spotted'] as Map?;
                final ropes = ItemService.readInventory(uSnap.data)['fune'] ?? 0;
                return Column(children: [
                  SectionTitle(table ? 'Tavolo' : 'Partita'),
                  // al tavolo gli strumenti del Master stanno in fondo (prima dell'avvio restano in cima)
                  if (_master && (!table || !started)) _masterTools(started, st, events),
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
                    // prima quello che va risolto subito, poi dove sei e cosa puoi fare
                    if (table && spotted != null) _spottedCard(spotted, ropes),
                    if (table && wild != null) _wildCard(wild),
                    if (table && locals != null) _localsCard(locals, me),
                    if (table) _sightings(me, _i(st!['round'])),
                    if (table)
                      _positionCard(pos, st: st, events: events, me: me, myTurn: myTurn, pending: wild != null || spotted != null)
                    else
                      _positionCard(pos),
                    // al tavolo gli eventi delle altre zone stanno sui pulsanti della mappa e nella fascia in alto
                    if (!table) ..._eventCards(events, st!, pos, me),
                    SectionTitle(table ? 'Altre zone' : 'Zone'),
                    if (table) ...[
                      TableMap(
                        state: st!,
                        events: events,
                        pos: pos,
                        shield: _shield,
                        myTurn: myTurn,
                        actionsLeft: _i(st['actionsLeft']),
                        wildPending: wild != null || spotted != null,
                        ticketCount: ItemService.readInventory(uSnap.data)['biglietto'] ?? 0,
                        freeReturn: TableService.freeReturnZone(uSnap.data?['ticketReturn'] as Map?, pos),
                        busy: _busy,
                        onMove: _moveTo,
                      ),
                    ] else
                      for (final z in kZones) _zoneCard(z, pos, events, st!, me),
                    if (_master && table) ...[const SizedBox(height: 16), _masterTools(started, st, events)],
                  ],
                ]);
              },
            ),
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
        // fuori dalla parte comprimibile: è l'unico strumento che si usa spesso durante la partita
        if (kTableMode && started) ...[
          DropButton(
            label: 'Informazioni dai locali',
            icon: Icons.record_voice_over,
            colors: Pal.gold,
            height: 44,
            onTap: _busy ? null : () => _askLocals(st!),
          ),
          const SizedBox(height: 4),
        ],
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(_masterOpen ? 'Nascondi strumenti del Master' : 'Strumenti del Master',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            trailing: Icon(_masterOpen ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _masterOpen = !_masterOpen),
          ),
        ),
        if (_masterOpen) ...[
        const Text(
          'Solo per preparare la partita: dopo l’avvio tutti giocano alla pari.',
          style: TextStyle(color: Pal.sub, fontSize: 12),
        ),
        const SizedBox(height: 8),
        // Material trasparente: la scheda ha uno sfondo che altrimenti nasconde il tocco (e in debug dà errore)
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
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
        if (kTableMode) ...[
          DropButton(
            label: 'Collegamenti tra zone',
            icon: Icons.alt_route,
            colors: Pal.neutral,
            height: 44,
            onTap: _busy ? null : () => _editLinks(st),
          ),
          const SizedBox(height: 8),
          DropButton(
            label: 'Settori delle zone',
            icon: Icons.grid_view,
            colors: Pal.neutral,
            height: 44,
            onTap: _busy ? null : () => _editSectors(st),
          ),
        ] else
          _liveMasterTools(st),
        const SizedBox(height: 12),
        DropButton(
          label: started ? 'Riavvia la partita' : (kTableMode ? 'Nuova partita' : 'Avvia la partita'),
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
        ],
      ]),
    );
  }

  /// Pokémon selvatico che ti sbarra la strada (resta finché non scegli).
  Widget _wildCard(Map wild) {
    final z = zoneSpec('${wild['zone']}');
    return DropCard(
      colors: typeColors('${wild['type']}'),
      label: 'Incontro selvatico',
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Un ${wild['name']} selvatico!', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text('${z.name}, settore ${wild['sector']}', style: const TextStyle(color: Pal.sub, fontSize: 12)),
        const SizedBox(height: 6),
        Text('Se vinci: +$kCoinsWild 🪙 e ${(kWildDropChance * 100).round()}% di uno strumento. '
            'Fuggire costa $kWildFleeCost azione.', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: DropButton(label: 'Affronta', icon: Icons.bolt, height: 44, onTap: _busy ? null : () => _wild(true))),
          const SizedBox(width: 10),
          Expanded(child: DropButton(label: 'Fuggi', colors: Pal.neutral, height: 44, onTap: _busy ? null : () => _wild(false))),
        ]),
      ]),
    );
  }

  /// Master dal vivo: durata del giro e posizione delle zone sulla mappa.
  Widget _liveMasterTools(Map<String, dynamic>? st) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: PartyService.watchParty(_party!),
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

  /// "La tua posizione": dove sei, che settore è e tutto quello che puoi fare qui
  /// (cercare indizi, emporio, eventi della zona con le loro azioni). Per spostarti c'è la mappa sotto.
  Widget _positionCard(Map? pos,
      {Map<String, dynamic>? st, List<Map<String, dynamic>> events = const [], String? me, bool myTurn = false, bool pending = false}) {
    final z = pos == null ? null : zoneSpec('${pos['zone']}');
    final type = kTableMode && z != null ? TableLayout.typeOf(z.id, _i(pos!['sector'])) : null;
    final table = kTableMode && st != null && me != null;
    final shopClosed = kTableMode ? tableShopClosedReason(pos) : null;
    return DropCard(
      colors: typeColors(z?.type),
      label: 'La tua posizione',
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (type != null) ...[Icon(type.icon, size: 26, color: Pal.ink), const SizedBox(width: 8)],
          Expanded(
            child: Text(
              z == null
                  ? (kTableMode ? 'Non ancora sulla mappa' : 'Fuori dalle zone di gioco')
                  : '${z.name} · ${kTableMode ? 'settore ${pos!['sector']}' : LiveService.sectorLabel(z.id, pos!['sector'])}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        if (!kTableMode)
          const Text('La aggiorna il GPS mentre cammini.', style: TextStyle(color: Pal.sub, fontSize: 12))
        else if (type != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${type.label}: ${type.rules}', style: const TextStyle(color: Pal.sub, fontSize: 12)),
          ),
        if (table && z != null) ...[
          // eventi della tua zona (con le loro azioni)
          ..._eventCards(events, st, pos, me, onlyHere: true, inCard: true),
          const SizedBox(height: 12),
          HereSectors(
            party: _party!,
            me: me,
            state: st,
            events: events,
            pos: pos!,
            shield: _shield,
            myTurn: myTurn,
            actionsLeft: _i(st['actionsLeft']),
            pending: pending,
            busy: _busy,
            onMove: _moveTo,
          ),
          const SizedBox(height: 8),
          Text('Cosa puoi fare nel settore ${pos['sector']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ClueSearchButton(party: _party!, uid: me, enabled: myTurn),
          if (shopClosed == null)
            DropButton(
              label: 'Emporio',
              icon: Icons.storefront,
              colors: Pal.gold,
              height: 44,
              onTap: () => showShop(context, me),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                const Icon(Icons.storefront, size: 16, color: Pal.sub),
                const SizedBox(width: 6),
                Expanded(child: Text('Emporio chiuso qui · $shopClosed', style: const TextStyle(color: Pal.sub, fontSize: 12))),
              ]),
            ),
          const SizedBox(height: 8),
          const Text('Per andare in un’altra zona usa la mappa qui sotto.', style: TextStyle(color: Pal.sub, fontSize: 12)),
        ] else if (!kTableMode) ...[
          const SizedBox(height: 10),
          DropButton(
            label: 'Emporio',
            icon: Icons.storefront,
            colors: Pal.gold,
            height: 44,
            onTap: () => showShop(context, _s.userName!),
          ),
        ],
      ]),
    );
  }

  /// Eventi di zona con le loro azioni (prendi uno strumento, sfida il leggendario).
  /// [onlyHere]: solo quelli della tua zona; [inCard]: riquadri semplici da mettere dentro "La tua posizione".
  List<Widget> _eventCards(List<Map<String, dynamic>> events, Map<String, dynamic> st, Map? pos, String me,
      {bool onlyHere = false, bool inCard = false}) {
    final round = _i(st['round']);
    final shown = events
        .where((e) => e['status'] == 'announced' || e['status'] == 'active')
        .where((e) => !onlyHere || e['zone'] == pos?['zone'])
        .toList()
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
          final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (inCard)
                Text(active ? 'EVENTO IN CORSO' : 'EVENTO IN ARRIVO',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: active ? Pal.bad : Pal.warn)),
              Text(title, style: TextStyle(fontSize: inCard ? 16 : 18, fontWeight: FontWeight.w800)),
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
                Builder(builder: (_) {
                  // al tavolo il leggendario sta in un settore preciso (impervio)
                  final sec = kTableMode && e['sector'] != null ? _i(e['sector']) : null;
                  final there = here && (sec == null || _i(pos?['sector']) == sec);
                  return DropButton(
                  label: defeated
                      ? 'Già sconfitto'
                      : (there
                          ? 'Sfida ${e['legendaryName']}'
                          : 'Devi essere in ${z.name}${sec == null ? '' : ', settore $sec'}'),
                  icon: Icons.bolt,
                  colors: Pal.gold,
                  height: 44,
                  onTap: (_busy || defeated || !there)
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
                  );
                }),
              ],
            ]);
          if (inCard) {
            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? Pal.bad : Pal.warn, width: 1.5),
              ),
              child: body,
            );
          }
          return DropCard(
            colors: typeColors(z.type),
            label: active ? 'IN CORSO' : 'IN ARRIVO',
            labelOnTop: true,
            child: body,
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
    return StreamBuilder<Map<String, dynamic>>(
      stream: ItemService.watchUserFields(uid, const ['actualParty', 'pos', 'busyUntil']),
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
  StreamSubscription? _userSub, _stateSub, _evSub, _zoneSub, _partySub;
  Map<String, dynamic>? _lastState, _partyDoc;
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
    _partySub?.cancel();
    _lastState = _partyDoc = null;
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
    // settori e biomi sempre aggiornati (servono anche fuori dalla tab Tavolo, es. all'Emporio)
    _partySub = PartyService.watchParty(party).listen((p) {
      _partyDoc = p;
      _syncLayout();
    });
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

  void _syncLayout() {
    if (!kTableMode) return;
    TableLayout.sectors = TableService.sectorsOf(_lastState, _partyDoc);
    TableLayout.biomes = _lastState?['started'] == true ? TableService.biomesOf(_lastState) : null;
  }

  void _onState(Map<String, dynamic>? st) {
    _lastState = st;
    _syncLayout();
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
    _partySub?.cancel();
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
    return StreamBuilder<String?>(
      stream: ItemService.watchActualParty(uid),
      builder: (context, uSnap) {
        final p = uSnap.data;
        if (p == null) return const SizedBox.shrink();
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
