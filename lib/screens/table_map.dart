import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../services/table_service.dart';
import '../table/sectors.dart';
import '../table/zones.dart';
import '../theme.dart';
import '../widgets/drop.dart';

int _i(dynamic v) => v is num ? v.toInt() : 0;

/// Mappa disegnata del Tavolo: zone in gioco (rettangoli arrotondati) e collegamenti.
/// La tua zona è evidenziata ("Tu"), sopra le zone raggiungibili c'è il costo in azioni, quelle non
/// collegate sono tratteggiate (Biglietto / treno / traghetto). Toccando una zona compare il pannello
/// dei suoi settori e un solo bottone di conferma.
///
/// Le posizioni delle zone sono in `kZoneMapPos` (lib/table/zones.dart): per usare l'immagine del
/// tabellone basta metterla come sfondo dello Stack in [_board] e regolare quelle coordinate.
class TableMap extends StatefulWidget {
  final Map<String, dynamic> state;
  final List<Map<String, dynamic>> events; // tutti gli eventi (con 'id')
  final Map? pos;
  final String? shield;
  final bool myTurn;
  final int ticketCount;
  final bool busy;
  final Future<void> Function(ZoneSpec zone, int sector, {required bool ticket, required bool visibleTrace}) onMove;

  const TableMap({
    super.key,
    required this.state,
    required this.events,
    required this.pos,
    required this.shield,
    required this.myTurn,
    required this.ticketCount,
    required this.busy,
    required this.onMove,
  });

  @override
  State<TableMap> createState() => _TableMapState();
}

class _TableMapState extends State<TableMap> {
  String? _zone; // zona selezionata
  int? _sector; // settore selezionato
  bool _visible = false; // "Lascia una traccia ben visibile"

  String? get _from => widget.pos?['zone'] as String?;
  int get _fromSector => _i(widget.pos?['sector']);
  List<Map<String, dynamic>> get _active => [for (final e in widget.events) if (e['status'] == 'active') e];

  MoveRoute _route(String to) => TableService.routeTo(widget.state, _active, _from, to);

  @override
  Widget build(BuildContext context) {
    final zones = TableLayout.zonesInPlay;
    final selected = _zone ?? _from ?? 'hub';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, c) => _board(zones, selected, c.maxWidth)),
      const SizedBox(height: 10),
      _sectorPanel(zoneSpec(selected)),
    ]);
  }

  // ------------------------------------------------------------------ mappa

  Widget _board(List<ZoneSpec> zones, String selected, double w) {
    final h = (w * 1.2).clamp(420.0, 640.0);
    final boxW = (w * 0.27).clamp(84.0, 150.0);
    const boxH = 54.0;
    Offset center(String id) {
      final p = kZoneMapPos[id] ?? (0.5, 0.5);
      return Offset(boxW / 2 + p.$1 * (w - boxW), boxH / 2 + 14 + p.$2 * (h - boxH - 20));
    }

    final links = TableService.linksOf(widget.state);
    final segments = <(Offset, Offset, bool)>[];
    for (var i = 0; i < zones.length; i++) {
      for (var j = i + 1; j < zones.length; j++) {
        if (!links.contains(TableService.linkKey(zones[i].id, zones[j].id))) continue;
        final fromMine = zones[i].id == _from || zones[j].id == _from;
        segments.add((center(zones[i].id), center(zones[j].id), fromMine));
      }
    }
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3EC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Pal.line, width: 2),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: CustomPaint(painter: _LinksPainter(segments))),
        for (final z in zones)
          Positioned(
            left: center(z.id).dx - boxW / 2,
            top: center(z.id).dy - boxH / 2,
            width: boxW,
            height: boxH,
            child: _zoneBox(z, selected == z.id),
          ),
      ]),
    );
  }

  Widget _zoneBox(ZoneSpec z, bool selected) {
    final mine = _from == z.id;
    final route = _route(z.id);
    final linked = mine || route == MoveRoute.direct;
    final colors = typeColors(z.type);
    final hasEvent = _active.any((e) => e['zone'] == z.id);
    final legendary = _active.any((e) => e['zone'] == z.id && e['legendary'] == true && e['defeatedBy'] == null);
    // etichetta sopra la zona: costo a piedi, oppure il mezzo per arrivarci
    String? tag;
    if (!mine && _from != null) {
      tag = switch (route) {
        MoveRoute.direct => '${TableService.moveCost(_active, _from, z.id, shield: widget.shield)} az.',
        MoveRoute.passage => 'Treno/traghetto',
        MoveRoute.ticket => 'Biglietto',
      };
    }
    final box = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [lighten(colors.first, mine ? 0.15 : 0.55), lighten(colors.last, mine ? 0.3 : 0.7)]),
        borderRadius: BorderRadius.circular(14),
        border: linked ? Border.all(color: selected ? Pal.ink : colors.first, width: selected ? 3 : 1.5) : null,
        boxShadow: mine ? [BoxShadow(color: colors.first.withOpacity(0.45), blurRadius: 12)] : null,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (hasEvent)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(legendary ? Icons.bolt : Icons.warning_amber_rounded, size: 16, color: Pal.bad),
          ),
        Flexible(
          child: Text(
            z.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: mine ? Colors.white : Pal.ink, height: 1.1),
          ),
        ),
      ]),
    );
    return GestureDetector(
      onTap: () => setState(() {
        _zone = z.id;
        _sector = null;
      }),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: linked ? box : CustomPaint(foregroundPainter: _DashedBorder(selected ? Pal.ink : Pal.sub, selected ? 2.5 : 1.5), child: box),
        ),
        if (mine) const Positioned(top: -10, right: -6, child: _Badge('Tu', Pal.accent)),
        if (tag != null) Positioned(top: -10, left: 6, child: _Badge(tag, linked ? Pal.ok : Pal.sub)),
      ]),
    );
  }

  // --------------------------------------------------------- pannello settori

  Widget _sectorPanel(ZoneSpec z) {
    final route = _route(z.id);
    final travel = z.id != _from && route != MoveRoute.direct;
    final arrival = TableService.arrivalSector(z.id);
    final blocked = TableService.blockedSectors(_active, z.id, shield: widget.shield);
    final legendarySector = {
      for (final e in _active)
        if (e['zone'] == z.id && e['legendary'] == true && e['sector'] != null) _i(e['sector']),
    };
    // con Biglietto/treno/traghetto il settore di arrivo è obbligato
    final sector = travel ? arrival : _sector;
    final type = sector == null ? null : TableLayout.typeOf(z.id, sector);
    final colors = typeColors(z.type);

    String? problem;
    if (!widget.myTurn) problem = 'Non è il tuo turno';
    if (problem == null && travel) {
      final fromType = _from == null ? null : TableLayout.typeOf(_from!, _fromSector);
      if (arrival == null) {
        problem = '${z.name} non ha un settore di passaggio';
      } else if (fromType != SectorType.passaggio) {
        final p = _from == null ? null : TableService.arrivalSector(_from!);
        problem = 'Per ${route == MoveRoute.ticket ? 'il Biglietto' : 'treno o traghetto'} parti dal settore di passaggio'
            '${p == null ? '' : ' (settore $p)'}';
      } else if (route == MoveRoute.ticket && widget.ticketCount <= 0) {
        problem = 'Zona non collegata: serve un Biglietto';
      }
    }
    if (problem == null && sector == null) problem = 'Scegli il settore di arrivo';
    if (problem == null && blocked.contains(sector)) problem = 'Settore bloccato';
    if (problem == null && z.id == _from && sector == _fromSector) problem = 'Sei già qui';
    final cost = sector == null ? 0 : TableService.moveCost(_active, _from, z.id, shield: widget.shield, sector: sector);

    return DropCard(
      colors: colors,
      label: z.id == _from ? '${z.name} · sei qui' : z.name,
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (travel)
          Text(
            route == MoveRoute.ticket
                ? 'Non collegata: con un Biglietto arrivi nel settore di passaggio${arrival == null ? '' : ' ($arrival)'}.'
                : 'Con il treno/traghetto arrivi nel settore di passaggio${arrival == null ? '' : ' ($arrival)'}.',
            style: const TextStyle(color: Pal.sub, fontSize: 12),
          ),
        if (travel) const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var s = 1; s <= z.sectors; s++)
            _sectorChip(
              z,
              s,
              selected: sector == s,
              here: z.id == _from && _fromSector == s,
              blocked: blocked.contains(s),
              legendary: legendarySector.contains(s),
              enabled: !travel && !blocked.contains(s),
            ),
        ]),
        if (type != null) ...[
          const SizedBox(height: 8),
          Text('${type.label}: ${type.rules}', style: const TextStyle(fontSize: 12, height: 1.3)),
        ],
        const SizedBox(height: 4),
        // Material trasparente: la scheda ha uno sfondo colorato che altrimenti nasconde il tocco
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Lascia una traccia ben visibile', style: TextStyle(fontSize: 13)),
            subtitle: const Text('La Lente e i locali la notano di più e più a lungo', style: TextStyle(fontSize: 11)),
            value: _visible,
            onChanged: (v) => setState(() => _visible = v ?? false),
          ),
        ),
        DropButton(
          label: problem ??
              'Vai: ${z.name}, settore $sector · $cost ${cost == 1 ? 'azione' : 'azioni'}'
                  '${route == MoveRoute.ticket && travel ? ' + Biglietto' : ''}',
          icon: problem == null ? Icons.directions_walk : null,
          colors: colors,
          height: 46,
          busy: widget.busy,
          onTap: problem != null
              ? null
              : () async {
                  await widget.onMove(z, sector!, ticket: travel && route == MoveRoute.ticket, visibleTrace: _visible);
                  if (mounted) setState(() => _sector = null);
                },
        ),
      ]),
    );
  }

  Widget _sectorChip(ZoneSpec z, int s,
      {required bool selected, required bool here, required bool blocked, required bool legendary, required bool enabled}) {
    final type = TableLayout.typeOf(z.id, s);
    final colors = typeColors(z.type);
    return GestureDetector(
      onTap: enabled ? () => setState(() => _sector = s) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: blocked ? Pal.line : (selected ? colors.first : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Pal.ink : (blocked ? Pal.sub : colors.first), width: selected ? 2.5 : 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(blocked ? Icons.block : (type?.icon ?? Icons.place), size: 18, color: selected ? Colors.white : (blocked ? Pal.sub : colors.first)),
          const SizedBox(width: 6),
          Text(
            '$s · ${blocked ? 'bloccato' : (type?.label ?? '')}${here ? ' · Tu' : ''}${legendary ? ' · ⚡' : ''}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : Pal.ink,
              decoration: blocked ? TextDecoration.lineThrough : null,
            ),
          ),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}

/// Linee dei collegamenti tra le zone (più marcate quelle che partono dalla tua zona).
class _LinksPainter extends CustomPainter {
  final List<(Offset, Offset, bool)> segments;
  _LinksPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    for (final (a, b, mine) in segments) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = mine ? Pal.accent : Pal.sub.withOpacity(0.45)
          ..strokeWidth = mine ? 3.5 : 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_LinksPainter old) => old.segments != segments;
}

/// Bordo tratteggiato per le zone non collegate.
class _DashedBorder extends CustomPainter {
  final Color color;
  final double width;
  _DashedBorder(this.color, this.width);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final PathMetric m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, (d + 5).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.width != width;
}
