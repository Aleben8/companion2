import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../items.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../mode.dart';
import '../services/clue_service.dart';
import '../services/location_service.dart';
import '../services/party_service.dart';
import '../services/table_service.dart';
import '../table/sectors.dart';
import '../table/zones.dart';
import '../theme.dart';
import 'common.dart';
import 'drop.dart';

const _cluesColors = [Color(0xFF8E6BD8), Color(0xFFD08AE0)];

/// Indizi sulla mappa: piazzamento a inizio partita, ricerca, indizi trovati e dichiarati.
/// Funziona uguale dal vivo (posizione GPS) e al tavolo (zona e settore).
class CluesCard extends StatefulWidget {
  final String party;
  final String uid;
  const CluesCard({super.key, required this.party, required this.uid});
  @override
  State<CluesCard> createState() => _CluesCardState();
}

class _CluesCardState extends State<CluesCard> {
  bool _master = false;
  bool _busy = false;
  bool _editing = false;
  String? _target;
  final _ctrls = List.generate(kCluesPerPlayer, (_) => TextEditingController());
  final List<Map<String, dynamic>?> _places = List.filled(kCluesPerPlayer, null);

  @override
  void initState() {
    super.initState();
    PartyService.isMaster(widget.party, widget.uid).then((m) {
      if (mounted) setState(() => _master = m);
    });
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

  String _placeLabel(Map? p) {
    if (p == null) return 'Dove?';
    if (p['zone'] != null) return '${zoneSpec('${p['zone']}').name} · settore ${p['sector']}';
    return '${(p['lat'] as num).toStringAsFixed(5)}, ${(p['lng'] as num).toStringAsFixed(5)}';
  }

  Future<Map<String, dynamic>?> _pickPlace() async {
    if (!kTableMode) {
      final Position? p = await context.read<LocationService>().current();
      if (p == null) {
        if (mounted) snack(context, 'Posizione non disponibile: controlla il permesso', error: true);
        return null;
      }
      return {'lat': p.latitude, 'lng': p.longitude};
    }
    // solo i biomi in gioco (se la partita è già avviata) e i settori della disposizione in uso
    await TableService.loadLayout(widget.party);
    final zones = TableLayout.zonesInPlay;
    var zone = zones.first.id;
    var sector = 1;
    if (!mounted) return null;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final z = zoneSpec(zone);
        return AlertDialog(
          title: const Text('Dove piazzi l’indizio?'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButton<String>(
                isExpanded: true,
                value: zone,
                items: [for (final x in zones) DropdownMenuItem(value: x.id, child: Text(x.name))],
                onChanged: (v) => setS(() {
                  zone = v!;
                  sector = 1;
                }),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (var n = 1; n <= z.sectors; n++)
                  ChoiceChip(
                    avatar: TableLayout.typeOf(zone, n) == null ? null : Icon(TableLayout.typeOf(zone, n)!.icon, size: 16),
                    label: Text('$n'),
                    tooltip: TableLayout.typeOf(zone, n)?.label,
                    selected: sector == n,
                    onSelected: (_) => setS(() => sector = n),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, {'zone': zone, 'sector': sector}), child: const Text('Scegli')),
          ],
        );
      }),
    );
  }

  Future<void> _save() => _run(() async {
        await ClueService.placeClues(
          party: widget.party,
          uid: widget.uid,
          targetUid: _target ?? '',
          texts: [for (final c in _ctrls) c.text],
          places: [for (final p in _places) p ?? {}],
        );
        if (mounted) setState(() => _editing = false);
      }, ok: 'Indizi piazzati!');

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: ClueService.watchPhase(widget.party),
      builder: (context, phSnap) {
        final phase = phSnap.data;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ClueService.watchClues(widget.party),
          builder: (context, cSnap) {
            final clues = <Map<String, dynamic>>[
              for (final d in cSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {...d.data(), 'id': d.id},
            ];
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: PartyService.watchPlayers(widget.party),
              builder: (context, pSnap) {
                final players = pSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                Map<String, dynamic>? mine;
                var ready = 0;
                for (final d in players) {
                  if (d.data()['cluesReady'] == true) ready++;
                  if (d.id == widget.uid) mine = d.data();
                }
                return DropCard(
                  colors: _cluesColors,
                  label: 'Indizi sulla mappa',
                  labelOnTop: true,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (phase == 'placing') ..._placing(clues, players, mine, ready)
                    else if (phase == 'playing') ..._playing(clues, mine)
                    else ..._notOpen(),
                  ]),
                );
              },
            );
          },
        );
      },
    );
  }

  List<Widget> _notOpen() => [
        const Text('Il piazzamento degli indizi non è ancora aperto.', style: TextStyle(color: Pal.sub)),
        if (_master) ...[
          const SizedBox(height: 12),
          DropButton(
            label: 'Apri il piazzamento degli indizi',
            icon: Icons.flag,
            colors: _cluesColors,
            busy: _busy,
            onTap: () => _run(() => ClueService.openPlacement(widget.party), ok: 'Piazzamento aperto: ogni giocatore ha il suo simbolo'),
          ),
        ],
      ];

  List<Widget> _placing(List<Map<String, dynamic>> clues, List<QueryDocumentSnapshot<Map<String, dynamic>>> players, Map<String, dynamic>? mine, int ready) {
    final symbol = (mine?['symbol'] ?? '?').toString();
    final isReady = mine?['cluesReady'] == true;
    final mineClues = clues.where((c) => c['ownerUid'] == widget.uid).toList()
      ..sort((a, b) => ((a['number'] as num?) ?? 0).compareTo((b['number'] as num?) ?? 0));
    final others = players.where((d) => d.id != widget.uid).toList();
    return [
      Row(children: [
        const Text('Il tuo simbolo: ', style: TextStyle(color: Pal.sub)),
        Text(symbol, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const Spacer(),
        InfoChip('$ready/${players.length} pronti', color: ready == players.length ? Pal.ok : Pal.warn),
      ]),
      const SizedBox(height: 10),
      if (isReady && !_editing) ...[
        const Text('Hai piazzato i tuoi indizi:', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final c in mineClues)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('$symbol${c['number']} · ${c['text']}\n    📍 ${_placeLabel(c['place'] as Map?)}', style: const TextStyle(height: 1.3)),
          ),
        const SizedBox(height: 6),
        DropButton(
          label: 'Modifica i miei indizi',
          icon: Icons.edit,
          colors: Pal.neutral,
          height: 44,
          onTap: () => setState(() => _editing = true),
        ),
      ] else ...[
        const Text(
          'Scegli a chi assegnare i tuoi indizi, scrivili e nascondili sulla mappa. Non li vede nessun altro.',
          style: TextStyle(color: Pal.sub, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: Pal.bg, borderRadius: BorderRadius.circular(14)),
          child: DropdownButton<String>(
            isExpanded: true,
            underline: const SizedBox(),
            value: others.any((d) => d.id == _target) ? _target : null,
            hint: const Text('Destinatario degli indizi', style: TextStyle(color: Pal.sub)),
            items: [for (final d in others) DropdownMenuItem(value: d.id, child: Text(d.id))],
            onChanged: (v) => setState(() => _target = v),
          ),
        ),
        for (var i = 0; i < kCluesPerPlayer; i++) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _ctrls[i],
            maxLength: 90,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Indizio $symbol${i + 1}',
              filled: true,
              fillColor: Pal.bg,
              counterText: '',
              border: const OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(14))),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final p = await _pickPlace();
                      if (p != null && mounted) setState(() => _places[i] = p);
                    },
              icon: Icon(_places[i] == null ? Icons.add_location_alt_outlined : Icons.place, size: 18),
              label: Text(_places[i] == null ? (kTableMode ? 'Scegli dove' : 'Piazza qui (GPS)') : _placeLabel(_places[i])),
            ),
          ),
        ],
        const SizedBox(height: 12),
        DropButton(
          label: 'Conferma i miei indizi',
          icon: Icons.check,
          colors: _cluesColors,
          busy: _busy,
          onTap: (_target == null || _ctrls.any((c) => c.text.trim().isEmpty) || _places.any((p) => p == null)) ? null : _save,
        ),
      ],
      if (_master) ...[
        const SizedBox(height: 14),
        const Divider(color: Pal.line),
        DropButton(
          label: 'Chiudi il piazzamento e inizia',
          icon: Icons.play_arrow,
          colors: Pal.gold,
          height: 44,
          busy: _busy,
          onTap: () async {
            if (ready < players.length &&
                !await _confirm('Non tutti sono pronti', 'Solo $ready su ${players.length} hanno piazzato gli indizi. Chiudere comunque?', 'Chiudi')) {
              return;
            }
            await _run(() => ClueService.closePlacement(widget.party), ok: 'Piazzamento chiuso: ora si cerca!');
          },
        ),
      ],
    ];
  }

  List<Widget> _playing(List<Map<String, dynamic>> clues, Map<String, dynamic>? mine) {
    final symbol = (mine?['symbol'] ?? '?').toString();
    final placedByMe = clues.where((c) => c['ownerUid'] == widget.uid).toList()
      ..sort((a, b) => ((a['number'] as num?) ?? 0).compareTo((b['number'] as num?) ?? 0));
    final foundByMe = clues.where((c) => c['foundBy'] == widget.uid).toList();
    final declared = clues.where((c) => c['declared'] == true).toList();
    return [
      Text(
        kTableMode
            ? 'Per cercare gli indizi vai nella tab Tavolo, nella sezione Mappa.'
            : 'Per cercare gli indizi vai nella tab Mappa.',
        style: const TextStyle(color: Pal.sub, fontSize: 12),
      ),
      if (foundByMe.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('Indizi che hai trovato', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final c in foundByMe)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Pal.bg, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c['symbol']}${c['number']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('${c['text']}', style: const TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
              if (c['declared'] == true)
                const InfoChip('Dichiarato', color: Pal.ok)
              else
                DropButton(
                  label: kTableMode ? 'Ho preso la carta (dichiara)' : 'Dichiara l’indizio',
                  icon: Icons.campaign,
                  height: 40,
                  colors: Pal.gold,
                  onTap: _busy
                      ? null
                      : () => _run(() async {
                            final bonus = await ClueService.declare(widget.party, c['id'] as String, widget.uid);
                            if (!mounted) return;
                            snack(
                              context,
                              bonus != null && bonus.isNotEmpty
                                  ? '🎁 Indizio dichiarato! +$kCoinsDeclare 🪙 e strumento bonus: $bonus'
                                  : 'Indizio dichiarato: +$kCoinsDeclare 🪙 (era destinato a te: nessuno strumento bonus)',
                            );
                          }),
                ),
            ]),
          ),
      ],
      if (declared.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Indizi dichiarati da tutti', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in declared) InfoChip('${c['foundBy']} · ${c['symbol']}${c['number']}', color: _cluesColors.first),
        ]),
      ],
      const SizedBox(height: 14),
      const Divider(color: Pal.line),
      Text('I tuoi indizi nascosti ($symbol)', style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final c in placedByMe)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Expanded(child: Text('$symbol${c['number']} · ${c['text']}', style: const TextStyle(fontSize: 13))),
            InfoChip(c['status'] == 'found' ? 'Trovato' : 'Nascosto', color: c['status'] == 'found' ? Pal.warn : Pal.sub),
          ]),
        ),
    ];
  }
}
