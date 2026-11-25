import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../geo.dart';
import '../gyms.dart';
import '../items.dart';
import '../mode.dart';
import '../services/item_service.dart';
import '../services/location_service.dart';
import '../table/zones.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/drop.dart';

/// Emporio e crafting. Al tavolo l'emporio si apre dalla tab Tavolo (scheda "La tua posizione") e dalla
/// Borsa solo il crafting ([craftOnly]); dal vivo resta anche nella Borsa.
///  - Al tavolo: ogni zona ha il suo emporio (assortimento base + la protezione del bioma);
///    l'Hub ha il mercato centrale con tutti gli strumenti.
///  - Dal vivo: dentro una zona come al tavolo, altrimenti vicino a una palestra (entro [kGymRadiusMeters]).
Future<void> showShop(BuildContext context, String uid, {bool craftOnly = false}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.88, child: _ShopBody(uid: uid, craftOnly: craftOnly)),
    );

/// Emporio aperto qui? Al tavolo solo nei settori cittadini (null = aperto, altrimenti il motivo).
String? tableShopClosedReason(Map? pos) {
  final zone = pos?['zone'] as String?;
  if (zone == null) return 'Non sei ancora sulla mappa';
  final sector = (pos?['sector'] as num?)?.toInt() ?? 0;
  if (TableLayout.typeOf(zone, sector) == SectorType.cittadino) return null;
  final city = TableLayout.firstOf(zone, SectorType.cittadino);
  return city == null
      ? 'In ${zoneSpec(zone).name} non c’è un emporio'
      : 'Emporio nel settore cittadino $city';
}

class _ShopBody extends StatefulWidget {
  final String uid;
  final bool craftOnly;
  const _ShopBody({required this.uid, this.craftOnly = false});
  @override
  State<_ShopBody> createState() => _ShopBodyState();
}

class _ShopBodyState extends State<_ShopBody> {
  Future<Position?>? _pos;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!kTableMode && !widget.craftOnly) _pos = context.read<LocationService>().current();
  }

  Future<void> _do(Future<void> Function() f, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) snack(context, ok);
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  List<ItemDef> get _generalStock =>
      [for (final i in kItems) if (i.zone == null && (kTableMode || !i.tableOnly)) i];

  /// (titolo, assortimento, motivo per cui è chiuso)
  ({String title, List<ItemDef> stock, String? closed}) _shop(Map<String, dynamic>? user, Position? pos) {
    final zone = (user?['pos'] as Map?)?['zone'] as String?;
    // emporio di zona: al tavolo sempre, dal vivo quando il GPS ti mette in una zona
    if (kTableMode || zone != null) {
      if (zone == null) return (title: 'Emporio', stock: const [], closed: 'Non sei ancora sulla mappa.');
      final spec = zoneSpec(zone);
      if (kTableMode) {
        // al tavolo l'emporio sta nei settori cittadini
        final sector = ((user?['pos'] as Map?)?['sector'] as num?)?.toInt() ?? 0;
        if (TableLayout.typeOf(zone, sector) != SectorType.cittadino) {
          final city = TableLayout.firstOf(zone, SectorType.cittadino);
          return (
            title: 'Emporio · ${spec.name}',
            stock: const [],
            closed: city == null
                ? 'In ${spec.name} non ci sono settori cittadini: qui non c’è un emporio.'
                : 'L’emporio è nei settori cittadini: spostati nel settore $city di ${spec.name}.',
          );
        }
      }
      if (zone == 'hub') return (title: 'Mercato centrale · ${spec.name}', stock: _generalStock, closed: null);
      final local = <ItemId>[
        ...kBasicStock,
        if (kZoneShield[zone] != null) kZoneShield[zone]!,
        if (kTableMode) ItemId.biglietto, // per le zone non collegate: in vendita in ogni emporio
      ];
      return (title: 'Emporio · ${spec.name}', stock: [for (final id in local) itemDef(id)], closed: null);
    }
    if (kGymTestMode) return (title: 'Emporio (modalità prova)', stock: _generalStock, closed: null);
    if (pos == null) return (title: 'Emporio', stock: const [], closed: 'Posizione non disponibile.');
    GymSpec? nearest;
    var best = double.infinity;
    for (final g in kGyms) {
      final d = distanceMeters(pos.latitude, pos.longitude, g.lat, g.lng);
      if (d < best) {
        best = d;
        nearest = g;
      }
    }
    if (nearest != null && best <= kGymRadiusMeters) {
      return (title: 'Emporio · ${nearest.name}', stock: _generalStock, closed: null);
    }
    return (
      title: 'Emporio',
      stock: const [],
      closed: 'Gli empori sono nelle zone di gioco e presso le palestre. '
          'La palestra più vicina (${nearest?.name}) è a ${formatDistance(best)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Position?>(
      future: _pos,
      builder: (context, posSnap) {
        return StreamBuilder<Map<String, dynamic>?>(
          stream: ItemService.watchUser(widget.uid),
          builder: (context, snap) {
            final user = snap.data;
            final inv = ItemService.readInventory(user);
            final coins = ItemService.coinsOf(user);
            final full = ItemService.bagCount(inv) >= kBagLimit;
            final waiting = !kTableMode && !widget.craftOnly && posSnap.connectionState != ConnectionState.done;
            final shop = _shop(user, posSnap.data);
            final showShop = !widget.craftOnly;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              Text(showShop ? shop.title : 'Crafting', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Pal.ink)),
              const SizedBox(height: 8),
              Row(children: [
                InfoChip('🪙 $coins', color: const Color(0xFFD08A00)),
                const SizedBox(width: 8),
                InfoChip('🎒 ${ItemService.bagCount(inv)}/$kBagLimit', color: full ? Pal.bad : Pal.accent),
              ]),
              const SizedBox(height: 12),
              if (!showShop)
                const SizedBox.shrink()
              else if (waiting)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (shop.closed != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(shop.closed!, style: const TextStyle(color: Pal.sub)),
                )
              else
                for (final item in shop.stock) _row(item, inv, coins, full),
              if (!showShop)
                const Text('L’emporio si apre dalla tab Tavolo, quando sei in un settore cittadino.',
                    style: TextStyle(color: Pal.sub, fontSize: 12)),
              const SizedBox(height: 16),
              const Text('Crafting', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Pal.ink)),
              const SizedBox(height: 4),
              const Text('Unisci strumenti che hai già in borsa (non serve l’emporio).',
                  style: TextStyle(color: Pal.sub, fontSize: 12)),
              const SizedBox(height: 8),
              for (final r in kRecipes) _recipe(r, inv),
              const SizedBox(height: 16),
              const Text('Come guadagnare monete e strumenti', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Vittorie contro altri giocatori (+$kCoinsPvpWin 🪙), capipalestra (+$kCoinsGymWin 🪙), '
                'leggendari (+$kCoinsLegendary 🪙), indizi dichiarati (+$kCoinsDeclare 🪙). '
                'Cercando indizi puoi trovare strumenti, e puoi scambiarli con gli altri giocatori.',
                style: const TextStyle(color: Pal.sub, fontSize: 12, height: 1.4),
              ),
            ]);
          },
        );
      },
    );
  }

  Widget _row(ItemDef item, Map<String, int> inv, int coins, bool full) {
    final can = coins >= item.price && !full && !_busy;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.colors.first, width: 2),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: item.colors)),
          child: Icon(item.icon, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item.name}  ×${inv[item.key] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(item.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: item.colors.first, visualDensity: VisualDensity.compact),
          onPressed: can ? () => _do(() => ItemService.buy(widget.uid, item.id), '${item.name} acquistato') : null,
          child: Text('${item.price} 🪙'),
        ),
      ]),
    );
  }

  Widget _recipe(Recipe r, Map<String, int> inv) {
    final ok = r.inputs.entries.every((e) => (inv[e.key.name] ?? 0) >= e.value) && !_busy;
    final out = itemDef(r.output);
    final ins = r.inputs.entries.map((e) => '${e.value}× ${itemDef(e.key).name}').join(' + ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Pal.line, width: 2),
      ),
      child: Row(children: [
        Icon(out.icon, color: out.colors.first),
        const SizedBox(width: 10),
        Expanded(child: Text('$ins  →  ${out.name}', style: const TextStyle(fontWeight: FontWeight.w700))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: out.colors.first, visualDensity: VisualDensity.compact),
          onPressed: ok ? () => _do(() => ItemService.craft(widget.uid, r), '${out.name} creato') : null,
          child: const Text('Crea'),
        ),
      ]),
    );
  }
}
