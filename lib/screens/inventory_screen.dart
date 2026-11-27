import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../geo.dart';
import '../mode.dart';
import '../items.dart';
import '../services/battle_service.dart';
import '../services/item_service.dart';
import '../services/location_service.dart';
import '../services/party_service.dart';
import '../services/session.dart';
import '../services/table_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/drop.dart';
import 'shop_sheet.dart';

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

  Future<Position?> _maybePos() async => kTableMode ? null : await _position();

  Future<void> _info(String title, List<String> lines, {String empty = 'Niente da segnalare.'}) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: lines.isEmpty
              ? Text(empty)
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $l')),
                ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ok'))],
        ),
      );

  Future<void> _use(ItemDef item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (item.id) {
        case ItemId.repellente:
          if (!await _confirm('Repellente', 'Sarai nascosto per ${kTableMode ? '$kRepellentRounds giri' : '$kRepellentMinutes minuti'}, ma non potrai combattere.')) break;
          await ItemService.useRepellent(_uid);
          if (mounted) snack(context, 'Repellente attivato!');
        case ItemId.revitalizzante:
          if (!await _confirm('Revitalizzante', 'Il tuo Pokémon recupera subito tutti i PS.')) break;
          await ItemService.useRevive(_uid);
          if (mounted) snack(context, 'Pokémon rivitalizzato!');
        case ItemId.calmanella:
          if (!await _confirm('Calmanella', 'Gli altri giocatori sapranno dove sei in questo momento.')) break;
          final partyB = await _party();
          await ItemService.useBell(_uid, partyB, await _maybePos());
          if (mounted) snack(context, '🔔 Hai rivelato la tua posizione');
        case ItemId.trappola:
          if (!await _confirm('Trappola', 'Verrà piazzata qui, nella tua posizione attuale.')) break;
          final partyT = await _party();
          await ItemService.placeTrap(_uid, partyT, await _maybePos());
          if (mounted) snack(context, 'Trappola piazzata!');
        case ItemId.allarme:
          if (!await _confirm('Allarme', 'Verrà piazzato qui. Non blocca nessuno: ti avvisa in segreto quando qualcuno passa.')) break;
          final partyA = await _party();
          await ItemService.placeAlarm(_uid, partyA, await _maybePos());
          if (mounted) snack(context, 'Allarme piazzato!');
        case ItemId.radar:
          final partyR = await _party();
          final contacts = await ItemService.useRadar(_uid, partyR, await _maybePos());
          if (mounted) _showRadar(contacts);
        case ItemId.lente:
          final partyL = await _party();
          final rep = await ItemService.useLens(_uid, partyL, await _maybePos());
          if (!mounted) break;
          await _info('Lente', [
            if (rep.searched.isNotEmpty) '— Già battuto —',
            ...rep.searched,
            if (rep.moves.isNotEmpty) '— Tracce di passaggio —',
            ...rep.moves,
          ], empty: 'Nessuna traccia recente da queste parti.');
        case ItemId.sensore:
          final partyS = await _party();
          final n = await ItemService.useSensor(_uid, partyS, await _maybePos());
          if (!mounted) break;
          await _info('Sensore', [
            n == 0 ? 'Nessun indizio nascosto qui.' : (n == 1 ? 'C’è 1 indizio nascosto qui.' : 'Ci sono $n indizi nascosti qui.'),
          ]);
        case ItemId.meteo:
          final partyM = await _party();
          final rows = await ItemService.useWeather(_uid, partyM);
          if (mounted) await _info('Radar meteo', rows, empty: 'Nessun evento previsto nei prossimi $kWeatherLookahead giri.');
        case ItemId.passoFelpato:
          if (!await _confirm('Passo felpato', 'Ignori Trappole e Allarmi, non lasci tracce e sei invisibile al Radar finché dura.')) break;
          await ItemService.useStealth(_uid);
          if (mounted) snack(context, 'Passo felpato attivo');
        case ItemId.clessidra:
          if (!await _confirm('Clessidra', kTableMode ? 'Ottieni subito altre azioni per questo turno.' : 'Azzeri subito tutte le attese.')) break;
          final partyC = await _party();
          await ItemService.useHourglass(_uid, partyC);
          if (mounted) snack(context, kTableMode ? '⏳ Azioni aggiunte al turno' : '⏳ Attese azzerate');
        case ItemId.chiave:
          final partyK = await _party();
          final pos = (await ItemService.userRef(_uid).get()).data()?['pos'] as Map?;
          final events = await TableService.activeEvents(partyK);
          final blocked = <int>{
            for (final e in events)
              if (e['zone'] == pos?['zone']) ...[for (final b in (e['blocked'] as List? ?? [])) (b as num).toInt()],
          }.toList()
            ..sort();
          if (blocked.isEmpty) throw Exception('Nella tua zona non ci sono settori bloccati');
          if (!mounted) break;
          final pick = await showDialog<int>(
            context: context,
            builder: (ctx) => SimpleDialog(title: const Text('Quale settore sblocchi?'), children: [
              for (final b in blocked) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, b), child: Text('Settore $b')),
            ]),
          );
          if (pick == null) break;
          await ItemService.useKey(_uid, partyK, pick);
          if (mounted) snack(context, 'Settore $pick sbloccato!');
        case ItemId.corda:
        case ItemId.bussola:
        case ItemId.tutaNeve:
        case ItemId.tutaIgnifuga:
        case ItemId.zattera:
        case ItemId.parafulmine:
          if (!await _confirm(item.name, item.description)) break;
          await ItemService.useShield(_uid, item.id);
          if (mounted) snack(context, '${item.name} attivo');
        case ItemId.pozione:
        case ItemId.superPozione:
          // fuori dalla battaglia: cura il Pokémon (i PS restano tra uno scontro e l'altro)
          final pk = context.read<Session>().pokemonId!;
          if (!await _confirm(item.name, 'Il tuo Pokémon recupera fino a ${item.id == ItemId.pozione ? kPotionHeal : kSuperPotionHeal} PS.')) break;
          final healed = await BattleService.healOutsideBattle(uid: _uid, pk: pk, item: item.id);
          if (mounted) snack(context, '💊 +$healed PS');
        case ItemId.biglietto:
        case ItemId.caramella:
        case ItemId.fune:
        case ItemId.elisir:
        case ItemId.antidoto:
        case ItemId.amuleto:
        case ItemId.guanto:
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
                subtitle: Text(c.place ?? '${formatDistance(c.distance)} verso ${c.direction}',
                    style: const TextStyle(color: Pal.sub)),
                trailing: c.place != null ? null : Text(formatAge(c.age), style: const TextStyle(color: Pal.sub, fontSize: 12)),
              ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------- scambi

  Future<void> _trade(Map<String, int> inv) async {
    try {
      final party = await _party();
      final players = [for (final d in (await PartyService.players(party).get()).docs) if (d.id != _uid) d.id];
      if (players.isEmpty) throw Exception('Non ci sono altri giocatori nel party');
      if (!mounted) return;
      final owned = [for (final i in kItems) if ((inv[i.key] ?? 0) > 0) i];
      if (owned.isEmpty) throw Exception('La borsa è vuota');
      String to = players.first;
      ItemId give = owned.first.id;
      ItemId? want;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
            title: const Text('Scambia uno strumento'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('A chi', style: TextStyle(fontWeight: FontWeight.w700)),
                DropdownButton<String>(
                  isExpanded: true,
                  value: to,
                  items: [for (final p in players) DropdownMenuItem(value: p, child: Text(p))],
                  onChanged: (v) => set(() => to = v ?? to),
                ),
                const SizedBox(height: 8),
                const Text('Offri', style: TextStyle(fontWeight: FontWeight.w700)),
                DropdownButton<ItemId>(
                  isExpanded: true,
                  value: give,
                  items: [for (final i in owned) DropdownMenuItem(value: i.id, child: Text('${i.name}  ×${inv[i.key]}'))],
                  onChanged: (v) => set(() => give = v ?? give),
                ),
                const SizedBox(height: 8),
                const Text('In cambio di', style: TextStyle(fontWeight: FontWeight.w700)),
                DropdownButton<ItemId?>(
                  isExpanded: true,
                  value: want,
                  items: [
                    const DropdownMenuItem<ItemId?>(value: null, child: Text('Niente (regalo)')),
                    for (final i in kItems)
                      if (kTableMode || !i.tableOnly) DropdownMenuItem<ItemId?>(value: i.id, child: Text(i.name)),
                  ],
                  onChanged: (v) => set(() => want = v),
                ),
                if (kTableMode)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Al tavolo dovete essere nella stessa zona.', style: TextStyle(fontSize: 12, color: Pal.sub)),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Proponi')),
            ],
          ),
        ),
      );
      if (ok != true) return;
      await ItemService.offerTrade(party: party, from: _uid, to: to, give: give, want: want);
      if (mounted) snack(context, 'Proposta inviata a $to');
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Widget _incomingTrades() {
    return FutureBuilder<String?>(
      future: PartyService.actualParty(_uid),
      builder: (context, ps) {
        final party = ps.data;
        if (party == null) return const SizedBox.shrink();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ItemService.watchIncomingTrades(party, _uid),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            return Column(children: [
              for (final d in docs)
                Builder(builder: (_) {
                  final t = d.data();
                  final give = itemDef(ItemId.values.byName(t['give'] as String)).name;
                  final want = t['want'] == null ? null : itemDef(ItemId.values.byName(t['want'] as String)).name;
                  Future<void> answer(bool accept) async {
                    try {
                      await ItemService.answerTrade(party, d.id, _uid, accept: accept);
                      if (mounted) snack(context, accept ? 'Scambio concluso!' : 'Offerta rifiutata');
                    } catch (e) {
                      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
                    }
                  }

                  return DropCard(
                    colors: Pal.gold,
                    label: 'Proposta di scambio',
                    labelOnTop: true,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(want == null
                          ? '${t['from']} ti regala: $give'
                          : '${t['from']} ti offre $give in cambio di $want'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: DropButton(label: 'Accetta', icon: Icons.check, height: 40, colors: Pal.gold, onTap: () => answer(true))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropButton(
                              label: 'Rifiuta', icon: Icons.close, height: 40, colors: Pal.neutral, onTap: () => answer(false)),
                        ),
                      ]),
                    ]),
                  );
                }),
            ]);
          },
        );
      },
    );
  }

  /// Scheda di un oggetto: immagine, nome, descrizione, come si usa e il bottone "Usa".
  Future<void> _details(ItemDef item, int qty) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                ItemImage(item, size: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Pal.ink)),
                    Text('Ne hai $qty', style: TextStyle(color: item.colors.first, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Text(item.description, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 15, height: 1.35)),
              const SizedBox(height: 8),
              Text(item.usage, style: const TextStyle(fontSize: 13, color: Pal.sub)),
              const SizedBox(height: 16),
              DropButton(
                label: _battleOnly(item) ? 'Si usa in battaglia' : 'Usa',
                icon: _battleOnly(item) ? Icons.sports_mma : Icons.check_circle_outline,
                colors: item.colors,
                height: 48,
                onTap: _battleOnly(item) || qty <= 0
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _use(item);
                      },
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: ItemService.watchUserFields(_uid, const ['inventory', 'coins']),
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
        }
        final inv = ItemService.readInventory(snap.data);
        final coins = ItemService.coinsOf(snap.data);
        final count = ItemService.bagCount(inv);
        final visible = [for (final i in kItems) if ((kTableMode || !i.tableOnly) && (inv[i.key] ?? 0) > 0) i];
        return Column(children: [
          const SectionTitle('Borsa'),
          Row(children: [
            InfoChip('🎒 $count/$kBagLimit', color: count >= kBagLimit ? Pal.bad : Pal.accent),
            const SizedBox(width: 8),
            InfoChip('🪙 $coins', color: const Color(0xFFD08A00)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropButton(
                // al tavolo l'emporio sta nella tab Tavolo (si apre nei settori cittadini): qui solo il crafting
                label: kTableMode ? 'Crafting' : 'Emporio',
                icon: kTableMode ? Icons.handyman : Icons.storefront,
                height: 44,
                colors: Pal.gold,
                onTap: () => showShop(context, _uid, craftOnly: kTableMode),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropButton(
                label: 'Scambia',
                icon: Icons.swap_horiz,
                height: 44,
                colors: const [Pal.accent, Color(0xFF9C7BE0)],
                onTap: () => _trade(inv),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _incomingTrades(),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('La borsa è vuota: passa all’Emporio, cerca indizi o sfida una palestra.',
                  textAlign: TextAlign.center, style: TextStyle(color: Pal.sub)),
            ),
          // griglia: solo l'oggetto e la quantità; toccandolo si apre la scheda con descrizione e "Usa"
          for (final cat in ItemCategory.values)
            if (visible.any((i) => i.category == cat)) ...[
              SectionTitle(cat.label),
              SizedBox(
                width: double.infinity, // la griglia parte da sinistra
                child: Wrap(spacing: 12, runSpacing: 14, children: [
                  for (final item in visible.where((i) => i.category == cat))
                    ItemTile(item: item, qty: inv[item.key] ?? 0, onTap: () => _details(item, inv[item.key] ?? 0)),
                ]),
              ),
            ],
        ]);
      },
    );
  }
}

/// Immagine dello strumento (o, se manca, l'icona su un cerchio con i suoi colori).
class ItemImage extends StatelessWidget {
  final ItemDef item;
  final double size;
  const ItemImage(this.item, {super.key, this.size = 56});

  @override
  Widget build(BuildContext context) => Image.asset(
        item.asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: item.colors)),
          child: Icon(item.icon, color: Colors.white, size: size * 0.55),
        ),
      );
}

/// Casella della Borsa: solo l'oggetto e quante ne hai. Toccandola si apre la scheda con
/// descrizione e "Usa".
class ItemTile extends StatelessWidget {
  final ItemDef item;
  final int qty;
  final VoidCallback onTap;
  const ItemTile({super.key, required this.item, required this.qty, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: item.name,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: item.colors.first, width: 2),
              boxShadow: [BoxShadow(color: item.colors.first.withOpacity(0.18), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              Center(child: ItemImage(item, size: 52)),
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.colors.first,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text('$qty',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// Strumenti che si usano solo in battaglia (Pozione e Super Pozione curano anche fuori).
bool _battleOnly(ItemDef i) => const {
      ItemId.caramella, ItemId.fune,
      ItemId.elisir, ItemId.antidoto, ItemId.amuleto, ItemId.guanto,
    }.contains(i.id);
