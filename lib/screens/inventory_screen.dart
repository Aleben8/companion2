import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../geo.dart';
import '../items.dart';
import '../services/item_service.dart';
import '../services/location_service.dart';
import '../services/party_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/drop.dart';

/// Borsa: elenco degli strumenti con quantità e pulsante "Usa" (tab della home).
class InventoryTab extends StatefulWidget {
  const InventoryTab({super.key});
  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  bool _busy = false;

  String get _uid => context.read<Session>().userName!;

  Future<bool> _confirm(String title, String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usa')),
        ],
      ),
    );
    return ok == true;
  }

  Future<Position> _position() async {
    final p = await context.read<LocationService>().current();
    if (p == null) {
      throw Exception('Posizione non disponibile: controlla il permesso di localizzazione');
    }
    return p;
  }

  Future<String> _party() async {
    final p = await PartyService.actualParty(_uid);
    if (p == null) throw Exception('Entra prima in un party');
    return p;
  }

  Future<void> _use(ItemDef item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (item.id) {
        case ItemId.repellente:
          if (!await _confirm('Repellente', 'Sarai nascosto per $kRepellentMinutes minuti, ma non potrai combattere.')) break;
          await ItemService.useRepellent(_uid);
          if (mounted) snack(context, 'Repellente attivato!');
        case ItemId.revitalizzante:
          if (!await _confirm('Revitalizzante', 'Il tuo Pokémon recupera subito tutti i PS.')) break;
          await ItemService.useRevive(_uid);
          if (mounted) snack(context, 'Pokémon rivitalizzato!');
        case ItemId.calmanella:
          if (!await _confirm('Calmanella', 'Gli altri giocatori sapranno dove sei in questo momento.')) break;
          final partyB = await _party();
          final posB = await _position();
          await ItemService.useBell(_uid, partyB, posB);
          if (mounted) snack(context, '🔔 Hai rivelato la tua posizione');
        case ItemId.trappola:
          if (!await _confirm('Trappola', 'Verrà piazzata qui, nella tua posizione attuale.')) break;
          final partyT = await _party();
          final posT = await _position();
          await ItemService.placeTrap(_uid, partyT, posT);
          if (mounted) snack(context, 'Trappola piazzata!');
        case ItemId.radar:
          final partyR = await _party();
          final posR = await _position();
          final contacts = await ItemService.useRadar(_uid, partyR, posR);
          if (mounted) _showRadar(contacts);
        case ItemId.caramella:
        case ItemId.fune:
        case ItemId.pozione:
          if (mounted) snack(context, item.usage);
      }
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _showRadar(List<RadarContact> contacts) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Radar', style: TextStyle(color: Pal.ink, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (contacts.isEmpty)
            const Text('Nessun altro party individuato.', style: TextStyle(color: Pal.sub))
          else
            for (final c in contacts)
              ListTile(
                leading: const Icon(Icons.radar, color: Color(0xFF7FBCD0)),
                title: Text(c.name, style: const TextStyle(color: Pal.ink, fontWeight: FontWeight.w700)),
                subtitle: Text('${formatDistance(c.distance)} verso ${c.direction}',
                    style: const TextStyle(color: Pal.sub)),
                trailing: Text(formatAge(c.age), style: const TextStyle(color: Pal.sub, fontSize: 12)),
              ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: ItemService.watchUser(_uid),
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
        }
        final inv = ItemService.readInventory(snap.data);
        return Column(children: [
          const SectionTitle('Borsa'),
          const SizedBox(height: 6),
          for (final item in kItems) ItemCard(item: item, qty: inv[item.key] ?? 0, onUse: () => _use(item)),
        ]);
      },
    );
  }
}

/// Scheda strumento, come nel tuo schema: etichetta colorata a sinistra,
/// descrizione in corsivo e sprite a destra.
class ItemCard extends StatelessWidget {
  final ItemDef item;
  final int qty;
  final VoidCallback onUse;
  const ItemCard({super.key, required this.item, required this.qty, required this.onUse});

  @override
  Widget build(BuildContext context) {
    final empty = qty <= 0;
    return Opacity(
      opacity: empty ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: item.colors.first, width: 2),
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: item.colors),
              ),
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(item.name,
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.description,
                      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 14, color: Colors.black87)),
                  const SizedBox(height: 6),
                  Text(item.usage, style: const TextStyle(fontSize: 12, color: Colors.black45)),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: item.colors.first,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: empty ? null : onUse,
                    child: const Text('Usa'),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Image.asset(item.asset, width: 64, height: 64, fit: BoxFit.contain),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: item.colors.first, borderRadius: BorderRadius.circular(12)),
                  child: Text('×$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
