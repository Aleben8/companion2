import 'package:flutter/material.dart';

import '../services/table_service.dart';
import '../table/events.dart';
import '../table/phases.dart';
import '../table/sectors.dart';
import '../table/zones.dart';
import '../theme.dart';
import '../widgets/drop.dart';

int _i(dynamic v) => v is num ? v.toInt() : 0;

/// Mappa del Tavolo a pulsanti: un pulsante per ogni zona in gioco, con le miniature dei suoi settori
/// (tipo di settore, settori bloccati, dove sei tu, dove è il leggendario).
/// Le zone dove puoi andare adesso sono colorate, le altre grigie e non si toccano.
/// Toccando una zona compare il pannello dei settori con un solo bottone di conferma.
class TableMap extends StatefulWidget {
  final Map<String, dynamic> state;
  final List<Map<String, dynamic>> events; // tutti gli eventi (con 'id')
  final Map? pos;
  final String? shield;
  final bool myTurn; // puoi cambiare zona adesso
  final String? blockReason; // se no, perché
  final int actionsLeft;
  final int ticketCount;
  final String? freeReturn; // zona dove puoi tornare gratis (andata con il Biglietto)
  final bool wildPending; // incontro selvatico o "ti hanno notato" da risolvere
  final bool busy;
  final Future<void> Function(ZoneSpec zone, int sector, {required bool ticket, required bool visibleTrace}) onMove;

  const TableMap({
    super.key,
    required this.state,
    required this.events,
    required this.pos,
    required this.shield,
    required this.myTurn,
    this.blockReason,
    required this.actionsLeft,
    required this.ticketCount,
    this.freeReturn,
    required this.wildPending,
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

  bool _reachable(String to) =>
      widget.myTurn &&
      !widget.wildPending &&
      TableService.canReach(
        state: widget.state,
        events: _active,
        pos: widget.pos,
        to: to,
        actionsLeft: widget.actionsLeft,
        tickets: widget.ticketCount,
        shield: widget.shield,
        freeReturn: widget.freeReturn,
      );

  String get _hint {
    if (!widget.myTurn) return '${widget.blockReason ?? 'Non è il tuo turno'}: le zone sono in grigio.';
    if (widget.wildPending) return 'Prima risolvi quello che ti è successo entrando (scheda qui sopra).';
    if (widget.actionsLeft <= 0) return 'Hai finito le azioni: termina il turno.';
    if (!kTableTurns) {
      return 'Colorate le zone dove puoi andare adesso. Al massimo $kZoneMovesPerDay cambi di zona al giorno, '
          'distanziati (se cambi zona la sera, la mattina dopo no).';
    }
    return 'Colorate le zone dove puoi andare adesso. Tocca una zona per scegliere il settore d’arrivo. '
        'I settori della tua zona sono nella scheda qui sopra.';
  }

  @override
  Widget build(BuildContext context) {
    final zones = TableLayout.zonesInPlay;
    // la zona aperta si chiude se non è più raggiungibile (ad esempio dopo lo spostamento)
    // la tua zona ha i suoi settori nella scheda "La tua posizione": qui si aprono solo le altre
    final open = _zone != null && _zone != _from && _reachable(_zone!) ? _zone : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_hint, style: const TextStyle(color: Pal.sub, fontSize: 12)),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 640 ? 3 : 2;
        const gap = 10.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final z in zones) SizedBox(width: w, child: _zoneButton(z, open == z.id)),
        ]);
      }),
      if (open != null) ...[
        const SizedBox(height: 12),
        _sectorPanel(zoneSpec(open)),
      ],
    ]);
  }

  // ------------------------------------------------------------ pulsanti zona

  Widget _zoneButton(ZoneSpec z, bool selected) {
    final mine = _from == z.id;
    final reachable = _reachable(z.id);
    final colored = reachable || mine;
    final colors = colored ? typeColors(z.type) : const [Color(0xFFB7BCC4), Color(0xFFD5D9DE)];
    final hasEvent = _active.any((e) => e['zone'] == z.id);
    final legendaryEv = _active.any((e) => e['zone'] == z.id && e['legendary'] == true && e['defeatedBy'] == null);
    final route = _route(z.id);
    String? tag;
    if (mine) {
      tag = 'Tu';
    } else if (_from != null) {
      tag = switch (route) {
        MoveRoute.direct => '${TableService.moveCost(_active, _from, z.id, shield: widget.shield)} az.',
        MoveRoute.passage => 'Treno/traghetto',
        MoveRoute.ticket => widget.freeReturn == z.id ? 'Ritorno gratis' : 'Biglietto',
      };
    }
    final blocked = TableService.blockedSectors(_active, z.id, shield: widget.shield);
    final legendarySectors = {
      for (final e in _active)
        if (e['zone'] == z.id && e['legendary'] == true && e['sector'] != null) _i(e['sector']),
    };
    final fg = colored ? Colors.white : const Color(0xFF6B717A);
    return GestureDetector(
      onTap: colored && !mine
          ? () => setState(() {
                _zone = selected ? null : z.id;
                _sector = null;
              })
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Pal.ink : Colors.transparent, width: 3),
          boxShadow: colored ? [BoxShadow(color: colors.first.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (hasEvent)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(legendaryEv ? Icons.bolt : Icons.warning_amber_rounded, size: 16, color: fg),
              ),
            Expanded(
              child: Text(
                z.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg),
              ),
            ),
            if (tag != null) _Badge(tag, mine ? Pal.accent : (colored ? Colors.black26 : Colors.black12), fg),
          ]),
          for (final line in _eventLines(z.id))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
                child: Text(line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg, height: 1.2)),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var s = 1; s <= z.sectors; s++)
              _SectorThumb(
                number: s,
                type: TableLayout.typeOf(z.id, s),
                blocked: blocked.contains(s),
                here: mine && _fromSector == s,
                legendary: legendarySectors.contains(s),
                colored: colored,
              ),
          ]),
        ]),
      ),
    );
  }

  /// Eventi della zona scritti sul pulsante: quelli in corso (con i giri che mancano) e quelli annunciati.
  List<String> _eventLines(String zone) {
    final round = _i(widget.state['round']);
    final out = <String>[];
    for (final e in widget.events) {
      if (e['zone'] != zone) continue;
      if (e['status'] == 'active') {
        final left = _i(e['endRound']) - round + 1;
        final name = e['legendary'] == true && e['legendaryName'] != null ? '${e['legendaryName']}' : '${e['name']}';
        final until = kTableTurns ? (left <= 1 ? 'ultimo giro' : 'ancora $left giri') : untilLabel(_i(e['endRound']), round);
        out.add('${e['legendary'] == true ? '⚡' : '⚠️'} $name · $until');
      } else if (e['status'] == 'announced') {
        final start = _i(e['startRound']);
        out.add('🔜 ${e['name']}${kTableTurns || start >= TableService.kManualStart ? ' in arrivo' : ' ${whenLabel(start, round)}'}');
      }
    }
    return out;
  }

  // --------------------------------------------------------- pannello settori

  Widget _sectorPanel(ZoneSpec z) {
    final route = _route(z.id);
    final travel = z.id != _from && route != MoveRoute.direct;
    final freeReturn = route == MoveRoute.ticket && widget.freeReturn == z.id;
    final useTicket = travel && route == MoveRoute.ticket && !freeReturn;
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
    int cost(int s) => TableService.moveCost(_active, _from, z.id, shield: widget.shield, sector: s);
    bool selectable(int s) =>
        !travel && !blocked.contains(s) && !(z.id == _from && s == _fromSector) && cost(s) <= widget.actionsLeft;

    String? problem;
    if (!widget.myTurn) problem = 'Non è il tuo turno';
    if (problem == null && sector == null) problem = 'Scegli il settore di arrivo';
    if (problem == null && cost(sector!) > widget.actionsLeft) problem = 'Azioni insufficienti';

    return DropCard(
      colors: colors,
      label: z.id == _from ? '${z.name} · sei qui' : z.name,
      labelOnTop: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (travel)
          Text(
            freeReturn
                ? 'Ritorno gratis: sei arrivato qui con il Biglietto, tornare costa solo le azioni. '
                    'Arrivi nel settore di passaggio${arrival == null ? '' : ' ($arrival)'}.'
                : route == MoveRoute.ticket
                ? 'Non collegata: con un Biglietto arrivi nel settore di passaggio${arrival == null ? '' : ' ($arrival)'}. '
                    'Il ritorno qui da là sarà gratis.'
                : 'Con il treno/traghetto arrivi nel settore di passaggio${arrival == null ? '' : ' ($arrival)'}.',
            style: const TextStyle(color: Pal.sub, fontSize: 12),
          ),
        if (travel) const SizedBox(height: 8),
        // eventi della zona: cosa succede lì
        for (final e in widget.events)
          if (e['zone'] == z.id && (e['status'] == 'active' || e['status'] == 'announced'))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: e['status'] == 'active' ? '⚠️ ${e['name']}: ' : '🔜 ${e['name']} (in arrivo): ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: (e['status'] == 'active' ? eventDef('${e['defId']}').active : eventDef('${e['defId']}').announce)
                        .replaceAll('{zone}', z.name),
                  ),
                ]),
                style: const TextStyle(fontSize: 12, height: 1.3),
              ),
            ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var s = 1; s <= z.sectors; s++)
            _sectorChip(
              z,
              s,
              selected: sector == s,
              here: z.id == _from && _fromSector == s,
              blocked: blocked.contains(s),
              legendary: legendarySector.contains(s),
              enabled: selectable(s),
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
              'Vai: ${z.name}, settore $sector · ${cost(sector!)} ${cost(sector) == 1 ? 'azione' : 'azioni'}'
                  '${useTicket ? ' + Biglietto' : (freeReturn ? ' · ritorno gratis' : '')}',
          icon: problem == null ? Icons.directions_walk : null,
          colors: colors,
          height: 46,
          busy: widget.busy,
          onTap: problem != null
              ? null
              : () async {
                  await widget.onMove(z, sector!, ticket: useTicket, visibleTrace: _visible);
                  if (mounted) {
                    setState(() {
                      _sector = null;
                      _zone = null;
                    });
                  }
                },
        ),
      ]),
    );
  }

  Widget _sectorChip(ZoneSpec z, int s,
      {required bool selected, required bool here, required bool blocked, required bool legendary, required bool enabled}) {
    final type = TableLayout.typeOf(z.id, s);
    final colors = typeColors(z.type);
    final grey = !enabled && !selected;
    return GestureDetector(
      onTap: enabled ? () => setState(() => _sector = s) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: grey ? Pal.line : (selected ? colors.first : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Pal.ink : (grey ? Pal.sub : colors.first), width: selected ? 2.5 : 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(blocked ? Icons.block : (type?.icon ?? Icons.place), size: 18, color: selected ? Colors.white : (grey ? Pal.sub : colors.first)),
          const SizedBox(width: 6),
          Text(
            '$s · ${blocked ? 'bloccato' : (type?.label ?? '')}${here ? ' · Tu' : ''}${legendary ? ' · ⚡' : ''}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : (grey ? Pal.sub : Pal.ink),
              decoration: blocked ? TextDecoration.lineThrough : null,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Miniatura di un settore sul pulsante della zona: icona del tipo e numero.
class _SectorThumb extends StatelessWidget {
  final int number;
  final SectorType? type;
  final bool blocked, here, legendary, colored;
  const _SectorThumb({
    required this.number,
    required this.type,
    required this.blocked,
    required this.here,
    required this.legendary,
    required this.colored,
  });

  @override
  Widget build(BuildContext context) {
    final ink = colored ? Pal.ink : const Color(0xFF7A8088);
    return Tooltip(
      message: '$number · ${blocked ? 'bloccato' : (type?.label ?? '')}${here ? ' · sei qui' : ''}',
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: blocked ? Colors.black26 : Colors.white.withOpacity(colored ? 0.92 : 0.6),
          borderRadius: BorderRadius.circular(9),
          border: here ? Border.all(color: Pal.accent, width: 2.5) : null,
        ),
        child: Stack(children: [
          Center(child: Icon(blocked ? Icons.block : (legendary ? Icons.bolt : (type?.icon ?? Icons.place)), size: 18, color: ink)),
          Positioned(
            right: 3,
            bottom: 1,
            child: Text('$number', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: ink)),
          ),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color, fg;
  const _Badge(this.text, this.color, this.fg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}
