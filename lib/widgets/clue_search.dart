import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../mode.dart';
import '../services/clue_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import 'common.dart';
import 'drop.dart';

/// Pulsante "Cerca indizi qui", da mettere nella sezione dei movimenti.
/// Al tavolo costa 1 azione e cerca nel tuo settore; dal vivo cerca entro [kClueRadiusMeters].
class ClueSearchButton extends StatefulWidget {
  final String party;
  final String uid;
  final bool enabled; // es. al tavolo solo nel proprio turno
  const ClueSearchButton({super.key, required this.party, required this.uid, this.enabled = true});

  @override
  State<ClueSearchButton> createState() => _ClueSearchButtonState();
}

class _ClueSearchButtonState extends State<ClueSearchButton> {
  bool _busy = false;

  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      Position? pos;
      if (!kTableMode) pos = await context.read<LocationService>().current();
      final res = await ClueService.search(party: widget.party, uid: widget.uid, pos: pos);
      final found = res.clues;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(found.isEmpty
              ? (res.item != null ? 'Hai trovato qualcosa!' : 'Nessun indizio qui')
              : 'Hai trovato ${found.length == 1 ? 'un indizio' : '${found.length} indizi'}!'),
          content: found.isEmpty
              ? Text(res.item != null
                  ? '🎁 Frugando hai trovato uno strumento: ${res.item}'
                  : 'Non c’è niente da raccogliere in questo punto.')
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final c in found) ...[
                    Text('${c['symbol']}${c['number']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('${c['text']}', style: const TextStyle(fontStyle: FontStyle.italic)),
                    if (kTableMode)
                      Text('Prendi la carta ${c['symbol']}${c['number']} dal tavolo.',
                          style: const TextStyle(color: Pal.sub, fontSize: 12)),
                    const SizedBox(height: 10),
                  ],
                  const Text('Trovi i dettagli nella tab Party, dove puoi dichiararli.',
                      style: TextStyle(color: Pal.sub, fontSize: 12)),
                ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ok'))],
        ),
      );
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: ClueService.watchPhase(widget.party),
      builder: (context, snap) {
        final phase = snap.data;
        if (phase != 'playing' && phase != 'placing') return const SizedBox.shrink();
        final playing = phase == 'playing';
        final label = !playing
            ? 'Cerca indizi (piazzamento in corso)'
            : !widget.enabled
                ? 'Cerca indizi (non è il tuo turno)'
                : (kTableMode ? 'Cerca indizi qui (1 azione)' : 'Cerca indizi qui');
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: DropButton(
            label: label,
            icon: Icons.search,
            colors: const [Color(0xFF8E6BD8), Color(0xFFD08AE0)],
            busy: _busy,
            onTap: (playing && widget.enabled) ? _search : null,
          ),
        );
      },
    );
  }
}
