import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/clue_service.dart';
import '../services/party_service.dart';
import '../services/shared_stream.dart';
import '../services/table_service.dart';
import '../table/sectors.dart';
import '../table/phases.dart';
import '../table/zones.dart';
import '../theme.dart';
import '../widgets/drop.dart';

int _i(dynamic v) => v is num ? v.toInt() : 0;

/// I settori della tua zona, dentro la scheda "La tua posizione": per ognuno tipo, stato
/// (eventi, settori bloccati, leggendario, avvistamenti, dove hai già cercato, le tue tracce,
/// i tuoi indizi, trappole e allarmi) e, se puoi andarci, il costo. Toccando un settore lo scegli
/// e lo confermi con un solo bottone.
class HereSectors extends StatefulWidget {
  final String party;
  final String me;
  final Map<String, dynamic> state;
  final List<Map<String, dynamic>> events; // tutti (con 'id')
  final Map pos;
  final String? shield;
  final bool myTurn; // puoi spostarti tra i settori adesso
  final String? blockReason; // se no, perché
  final int actionsLeft;
  final bool pending; // selvatico o "ti hanno notato" da risolvere
  final bool busy;
  final Future<void> Function(ZoneSpec zone, int sector, {required bool ticket, required bool visibleTrace}) onMove;

  const HereSectors({
    super.key,
    required this.party,
    required this.me,
    required this.state,
    required this.events,
    required this.pos,
    required this.shield,
    required this.myTurn,
    this.blockReason,
    required this.actionsLeft,
    required this.pending,
    required this.busy,
    required this.onMove,
  });

  @override
  State<HereSectors> createState() => _HereSectorsState();
}

class _HereSectorsState extends State<HereSectors> {
  int? _sector;
  bool _visible = false;

  String get _zone => '${widget.pos['zone']}';
  int get _here => _i(widget.pos['sector']);
  List<Map<String, dynamic>> get _active => [for (final e in widget.events) if (e['status'] == 'active') e];

  Stream<QuerySnapshot<Map<String, dynamic>>> _mine(String col, {bool active = false}) => shared(
        'here:$col:${widget.party}:${widget.me}',
        () {
          Query<Map<String, dynamic>> q = PartyService.party(widget.party)
              .collection(col)
              .where(col == 'traces' ? 'uid' : 'ownerUid', isEqualTo: widget.me);
          if (active) q = q.where('active', isEqualTo: true);
          return q.snapshots();
        },
      );

  @override
  Widget build(BuildContext context) {
    // stato dei settori raccolto da più fonti: ognuna aggiunge righe di testo a un settore
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _mine('traces'),
      builder: (context, tr) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _mine('traps', active: true),
        builder: (context, tp) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _mine('alarms', active: true),
          builder: (context, al) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ClueService.watchClues(widget.party),
            builder: (context, cl) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: TableService.watchSightings(widget.party, widget.me),
              builder: (context, si) => _body(
                traces: [for (final d in tr.data?.docs ?? const []) d.data()],
                traps: [for (final d in tp.data?.docs ?? const []) d.data()],
                alarms: [for (final d in al.data?.docs ?? const []) d.data()],
                clues: [
                  for (final d in cl.data?.docs ?? const [])
                    if (d.data()['ownerUid'] == widget.me) d.data(),
                ],
                sightings: [
                  for (final d in si.data?.docs ?? const [])
                    if (d.data()['type'] == 'spotted') d.data(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body({
    required List<Map<String, dynamic>> traces,
    required List<Map<String, dynamic>> traps,
    required List<Map<String, dynamic>> alarms,
    required List<Map<String, dynamic>> clues,
    required List<Map<String, dynamic>> sightings,
  }) {
    final z = zoneSpec(_zone);
    final round = _i(widget.state['round']);
    final blocked = TableService.blockedSectors(_active, _zone, shield: widget.shield);
    bool at(Map m, int s) => m['zone'] == _zone && _i(m['sector']) == s;
    bool atPlace(Map c, int s) {
      final p = c['place'];
      return p is Map && p['zone'] == _zone && _i(p['sector']) == s;
    }

    String blockerName(int s) => [
          for (final e in _active)
            if (e['zone'] == _zone && (e['blocked'] as List? ?? []).map(_i).contains(s)) '${e['name']}',
        ].join(', ');

    List<String> notes(int s) {
      final out = <String>[];
      if (blocked.contains(s)) out.add('⛔ Bloccato: ${blockerName(s)}');
      if (TableLayout.gymSector(_zone) == s) out.add('🏅 Qui c’è il capopalestra (${z.type})');
      for (final e in _active) {
        if (e['zone'] == _zone && e['legendary'] == true && e['defeatedBy'] == null && _i(e['sector']) == s) {
          out.add('⚡ Qui c’è ${e['legendaryName'] ?? 'il leggendario'}');
        }
      }
      for (final x in sightings) {
        if (at(x, s) && _i(x['round']) >= round - 1) out.add('👀 Hai visto ${x['uid']} (${roundRef(x['round'])})');
      }
      final searched = traces.where((t) => t['kind'] == 'search' && at(t, s)).map((t) => _i(t['round'])).toList()..sort();
      if (searched.isNotEmpty) out.add('🔍 Hai già cercato qui (${roundRef(searched.last)})');
      final passed = traces.where((t) => t['kind'] == 'move' && at(t, s)).toList()
        ..sort((a, b) => _i(a['round']).compareTo(_i(b['round'])));
      if (passed.isNotEmpty) {
        final t = passed.last;
        final str = _i(t['strength']) == 0 ? kTraceBaseStrength : _i(t['strength']);
        if (_i(t['round']) >= round - kTraceRoundsPerStrength * str) {
          out.add('👣 La tua traccia: ${traceStrengthLabel(str)} (${roundRef(t['round'])})');
        }
      }
      final mineClues = [for (final c in clues) if (atPlace(c, s)) '${c['symbol']}${c['number']}'];
      if (mineClues.isNotEmpty) out.add('🧩 Hai nascosto qui: ${mineClues.join(', ')}');
      if (traps.any((t) => at(t, s))) out.add('🪤 La tua Trappola è qui');
      if (alarms.any((a) => at(a, s))) out.add('🚨 Il tuo Allarme è qui');
      return out;
    }

    int cost(int s) => TableService.moveCost(_active, _zone, _zone, shield: widget.shield, sector: s);
    String? reason(int s) {
      if (s == _here) return null;
      if (blocked.contains(s)) return 'bloccato';
      if (!widget.myTurn) return null;
      if (widget.pending) return null;
      if (cost(s) > widget.actionsLeft) return 'azioni insufficienti';
      return null;
    }

    bool canGo(int s) => s != _here && widget.myTurn && !widget.pending && !blocked.contains(s) && cost(s) <= widget.actionsLeft;

    final sel = _sector != null && canGo(_sector!) ? _sector : null;
    final colors = typeColors(z.type);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Dove puoi andare in ${z.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
      if (!widget.myTurn && widget.blockReason != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(widget.blockReason!, style: const TextStyle(color: Pal.sub, fontSize: 12)),
        ),
      const SizedBox(height: 6),
      for (var s = 1; s <= z.sectors; s++) _row(s, notes(s), canGo(s), sel == s, cost(s), reason(s), colors),
      if (sel != null) ...[
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Lascia una traccia ben visibile', style: TextStyle(fontSize: 13)),
            value: _visible,
            onChanged: (v) => setState(() => _visible = v ?? false),
          ),
        ),
        DropButton(
          label: 'Vai: ${TableLayout.typeOf(_zone, sel)?.label ?? ''} $sel · ${cost(sel)} ${cost(sel) == 1 ? 'azione' : 'azioni'}',
          icon: Icons.directions_walk,
          colors: colors,
          height: 46,
          busy: widget.busy,
          onTap: () async {
            await widget.onMove(z, sel, ticket: false, visibleTrace: _visible);
            if (mounted) setState(() => _sector = null);
          },
        ),
      ],
    ]);
  }

  Widget _row(int s, List<String> notes, bool can, bool selected, int cost, String? reason, List<Color> colors) {
    final type = TableLayout.typeOf(_zone, s);
    final here = s == _here;
    final grey = !here && !can;
    return GestureDetector(
      onTap: can ? () => setState(() => _sector = selected ? null : s) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: here ? colors.first.withOpacity(0.15) : (grey ? const Color(0xFFF1F2F4) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Pal.ink : (here ? colors.first : (grey ? Pal.line : colors.first.withOpacity(0.6))),
            width: selected || here ? 2.5 : 1.2,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // numero (serve al tavolo per indizi, trappole, leggendario) e icona del tipo
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: grey ? Pal.line : colors.first),
            child: Text('$s', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: grey ? Pal.sub : Colors.white)),
          ),
          const SizedBox(width: 6),
          Icon(type?.icon ?? Icons.place, size: 22, color: grey ? Pal.sub : colors.first),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  // il settore del capopalestra ha il nome del suo punto (es. "Bordo del cratere")
                  child: Text(TableLayout.gymPlace(_zone, s) ?? type?.label ?? '$s',
                      style: TextStyle(fontWeight: FontWeight.w800, color: grey ? Pal.sub : Pal.ink)),
                ),
                if (here)
                  _chip('Sei qui', Pal.accent)
                else if (can)
                  _chip('$cost az.', Pal.ok)
                else if (reason != null)
                  _chip(reason, Pal.sub),
              ]),
              if (here && type != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(type.rules, style: const TextStyle(fontSize: 12, color: Pal.sub, height: 1.25)),
                ),
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(n, style: const TextStyle(fontSize: 12, height: 1.25)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}
