import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../geo.dart';
import '../mode.dart';
import '../items.dart';
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
          if (!await _confirm('Clessidra', 'Ottieni subito altre azioni per questo turno.')) break;
          final partyC = await _party();
          await ItemService.useHourglass(_uid, partyC);
          if (mounted) snack(context, '⏳ Azioni aggiunte al turno');
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
          if (!await _confirm(item.name, '${item.description}')) break;
          await ItemService.useShield(_uid, item.id);
          if (mounted) snack(context, '${item.name} attivo');
        case ItemId.caramella:
        case ItemId.fune:
        case ItemId.pozione:
        case ItemId.superPozione:
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: ItemService.watchUser(_uid),
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
                label: 'Emporio',
                icon: Icons.storefront,
                height: 44,
                colors: Pal.gold,
                onTap: () => showShop(context, _uid),
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
          for (final cat in ItemCategory.values) ...[
            if (visible.any((i) => i.category == cat)) SectionTitle(cat.label),
            for (final item in visible.where((i) => i.category == cat))
              ItemCard(item: item, qty: inv[item.key] ?? 0, onUse: () => _use(item)),
          ],
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
                    child: Text(_battleOnly(item) ? 'In battaglia' : 'Usa'),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Image.asset(
                  item.asset,
                  width: 64,
                  height: 64,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: item.colors)),
                    child: Icon(item.icon, color: Colors.white, size: 34),
                  ),
                ),
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

bool _battleOnly(ItemDef i) => const {
      ItemId.caramella, ItemId.fune, ItemId.pozione, ItemId.superPozione,
      ItemId.elisir, ItemId.antidoto, ItemId.amuleto, ItemId.guanto,
    }.contains(i.id);
