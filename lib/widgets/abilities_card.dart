import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../abilities.dart';
import '../mode.dart';
import '../services/ability_service.dart';
import '../services/item_service.dart';
import '../services/session.dart';
import '../services/table_service.dart';
import '../table/zones.dart';
import '../theme.dart';
import 'common.dart';
import 'drop.dart';

int _i(dynamic v, [int d = 0]) => v is num ? v.toInt() : d;

String _err(Object e) => '$e'.replaceFirst('Exception: ', '');

/// Il Pokémon del giocatore, il party e lo stato della partita (per il giro corrente), sempre aggiornati.
class _AbilityLive extends StatelessWidget {
  final Widget Function(BuildContext context, Map<String, dynamic> pokemon, String? party, Map<String, dynamic>? state) builder;
  const _AbilityLive({required this.builder});

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final uid = s.userName!, pk = s.pokemonId!;
    return StreamBuilder<Map<String, dynamic>?>(
      stream: AbilityService.watchPokemon(uid, pk),
      builder: (context, pSnap) => StreamBuilder<String?>(
        stream: ItemService.watchActualParty(uid),
        builder: (context, partySnap) {
          final party = partySnap.data;
          if (pSnap.data == null) return const SizedBox.shrink();
          if (party == null) return builder(context, pSnap.data!, null, null);
          return StreamBuilder<Map<String, dynamic>?>(
            stream: TableService.watchState(party),
            builder: (context, stSnap) => builder(context, pSnap.data!, party, stSnap.data),
          );
        },
      ),
    );
  }
}

/// Riga di un'abilità: icona del tipo, nome, attiva/passiva e ricarica, testo.
class AbilityTile extends StatelessWidget {
  final AbilityDef def;
  final bool dense;
  const AbilityTile(this.def, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TypeIcon(def.type, size: dense ? 22 : 28),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(def.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: dense ? 14 : 16)),
            Text(
              def.active ? 'Attiva · ${def.type} · ricarica ${def.cooldown} giri' : 'Passiva · ${def.type}',
              style: TextStyle(color: typeColors(def.type).first, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            if (!dense || !def.active) ...[
              const SizedBox(height: 2),
              Text(def.text, style: const TextStyle(fontSize: 12, height: 1.3)),
            ],
          ]),
        ),
      ]);
}

/// "Nuova abilità": dopo una palestra vinta, le due carte estratte (resta in cima finché non scegli),
/// oppure "Hai sbloccato…" quando le abilità arrivano direttamente.
class AbilityOfferCard extends StatefulWidget {
  const AbilityOfferCard({super.key});
  @override
  State<AbilityOfferCard> createState() => _AbilityOfferCardState();
}

class _AbilityOfferCardState extends State<AbilityOfferCard> {
  bool _busy = false;
  StreamSubscription? _sub;
  String? _shown; // ultima offerta/notifica già mostrata nel popup (una volta sola)
  bool _open = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    // appena arriva una nuova offerta (fine della lotta in palestra) si apre il popup di scelta
    _sub = AbilityService.watchPokemon(s.userName!, s.pokemonId!).listen((pk) {
      final offer = [for (final k in (pk?['abilityOffer'] as List? ?? const [])) '$k'];
      final notice = [for (final k in (pk?['abilityNotice'] as List? ?? const [])) '$k'];
      if (offer.isEmpty && notice.isEmpty) return;
      final key = offer.isNotEmpty ? 'o:${offer.join(',')}' : 'n:${notice.join(',')}';
      if (key == _shown || _open) return;
      _shown = key;
      WidgetsBinding.instance.addPostFrameCallback((_) => _popup(s.userName!, offer, notice));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Popup "Nuova abilità" (o "Hai sbloccato…"). Se lo chiudi senza scegliere resta la scheda in cima.
  Future<void> _popup(String uid, List<String> offerKeys, List<String> noticeKeys) async {
    if (!mounted) return;
    final offer = [for (final k in offerKeys) if (abilityDef(k) != null) abilityDef(k)!];
    final notice = [for (final k in noticeKeys) if (abilityDef(k) != null) abilityDef(k)!];
    _open = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(offer.isNotEmpty ? 'Nuova abilità!' : 'Hai sbloccato…'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (offer.isNotEmpty)
              const Text('Hai vinto un badge: scegli una delle due abilità per il tuo Pokémon.',
                  style: TextStyle(color: Pal.sub, fontSize: 12)),
            for (final d in offer.isNotEmpty ? offer : notice)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: typeColors(d.type).first, width: 1.5),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AbilityTile(d),
                  if (offer.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DropButton(
                      label: 'Scegli ${d.name}',
                      colors: typeColors(d.type),
                      height: 40,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _run(() async {
                          await AbilityService.choose(uid, d.key);
                          if (mounted) snack(context, 'Hai scelto ${d.name}');
                        });
                      },
                    ),
                  ],
                ]),
              ),
          ]),
        ),
        actions: [
          if (offer.isNotEmpty)
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Più tardi'))
          else
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _run(() => AbilityService.dismissNotice(uid));
              },
              child: const Text('Ok'),
            ),
        ],
      ),
    );
    _open = false;
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) snack(context, _err(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => _AbilityLive(builder: (context, pk, party, st) {
        final uid = context.read<Session>().userName!;
        final offer = [for (final k in (pk['abilityOffer'] as List? ?? const [])) if (abilityDef('$k') != null) abilityDef('$k')!];
        final notice = [for (final k in (pk['abilityNotice'] as List? ?? const [])) if (abilityDef('$k') != null) abilityDef('$k')!];
        if (offer.isEmpty && notice.isEmpty) return const SizedBox.shrink();
        if (offer.isEmpty) {
          return DropCard(
            colors: Pal.gold,
            label: 'Hai sbloccato…',
            labelOnTop: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final d in notice) Padding(padding: const EdgeInsets.only(bottom: 10), child: AbilityTile(d)),
              DropButton(
                label: 'Ok',
                colors: Pal.gold,
                height: 40,
                busy: _busy,
                onTap: () => _run(() => AbilityService.dismissNotice(uid)),
              ),
            ]),
          );
        }
        return DropCard(
          colors: Pal.gold,
          label: 'Nuova abilità',
          labelOnTop: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Hai vinto un badge: scegli una delle due abilità per il tuo Pokémon.',
                style: TextStyle(color: Pal.sub, fontSize: 12)),
            for (final d in offer)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: typeColors(d.type).first, width: 1.5),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AbilityTile(d),
                  const SizedBox(height: 8),
                  DropButton(
                    label: 'Scegli ${d.name}',
                    colors: typeColors(d.type),
                    height: 40,
                    busy: _busy,
                    onTap: () => _run(() async {
                      await AbilityService.choose(uid, d.key);
                      if (mounted) snack(context, 'Hai scelto ${d.name}');
                    }),
                  ),
                ]),
              ),
          ]),
        );
      });
}

/// Le abilità del Pokémon: bottoni delle attive (grigi con il motivo se non si possono usare),
/// passive come etichette con il testo, slot vuoti "Si sblocca con il prossimo badge".
/// [compact]: versione per la scheda "La tua posizione" del Tavolo.
class AbilitiesCard extends StatefulWidget {
  final bool compact;
  final ValueChanged<String>? onBattle; // Sfida/Imboscata aprono la battaglia
  const AbilitiesCard({super.key, this.compact = false, this.onBattle});
  @override
  State<AbilitiesCard> createState() => _AbilitiesCardState();
}

class _AbilitiesCardState extends State<AbilitiesCard> {
  bool _busy = false;

  Future<T?> _pick<T>(String title, List<(T, String)> options) => showDialog<T>(
        context: context,
        builder: (ctx) => SimpleDialog(title: Text(title), children: [
          for (final o in options) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, o.$1), child: Text(o.$2)),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla', style: TextStyle(color: Pal.sub))),
        ]),
      );

  Future<bool> _confirm(AbilityDef d) async {
    final cost = d.reaction ? 'Non costa azioni.' : (kTableMode ? 'Costa $kAbilityActionCost azione.' : 'Poi aspetti $kLiveAbilityWaitMinutes minuto.');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(d.name),
        content: Text('${d.text}\n\n$cost Ricarica: ${d.cooldown} giri.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usa')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _use(AbilityDef d, String party, Map<String, dynamic>? st) async {
    if (_busy) return;
    final uid = context.read<Session>().userName!;
    setState(() => _busy = true);
    try {
      String? target;
      int? sector, recipe;
      switch (d.key) {
        case Ab.sfida:
        case Ab.spavento:
          final here = await AbilityService.playersNear(party, uid);
          if (here.isEmpty) throw Exception('Non c’è nessun altro giocatore nel tuo settore');
          if (!mounted) break;
          target = await _pick<String>('Chi?', [for (final p in here) (p, p)]);
          if (target == null) throw const _Cancel();
        case Ab.sismo:
          final pos = (await ItemService.userRef(uid).get()).data()?['pos'] as Map?;
          if (pos == null) throw Exception('Non sei in una zona');
          final zone = '${pos['zone']}';
          final options = await AbilityService.quakeSectors(party, uid);
          if (options.isEmpty) throw Exception('Non ci sono altri settori da bloccare');
          if (!mounted) break;
          sector = await _pick<int>('Quale settore blocchi?', [for (final s in options) (s, _sectorName(zone, s))]);
          if (sector == null) throw const _Cancel();
        case Ab.forgia:
          final inv = ItemService.readInventory((await ItemService.userRef(uid).get()).data());
          final opts = AbilityService.forgeOptions();
          final can = [for (var i = 0; i < opts.length; i++) if ((inv[opts[i].pay.name] ?? 0) > 0) i];
          if (can.isEmpty) throw Exception('Non hai ingredienti per nessuna ricetta');
          if (!mounted) break;
          recipe = await _pick<int>('Quale ricetta?', [for (final i in can) (i, AbilityService.forgeLabel(opts[i]))]);
          if (recipe == null) throw const _Cancel();
      }
      if (!mounted || !await _confirm(d)) throw const _Cancel();
      final r = await AbilityService.use(party: party, uid: uid, key: d.key, target: target, sector: sector, recipe: recipe);
      if (!mounted) return;
      if (r.battleId != null) widget.onBattle?.call(r.battleId!);
      if (r.lines.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(d.name),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (r.message.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(r.message)),
                for (final l in r.lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $l')),
              ]),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ok'))],
          ),
        );
      } else if (mounted) {
        snack(context, r.message);
      }
    } on _Cancel {
      // annullato: nessun costo
    } catch (e, st) {
      debugPrint('Abilità ${d.key}: errore $e\n$st');
      if (mounted) snack(context, _err(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  static String _sectorName(String zone, int s) =>
      kTableMode ? TableLayout.title(zone, s) : const ['Nord', 'Est', 'Sud', 'Ovest'][(s - 1).clamp(0, 3)];

  Widget _slot(String text) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Pal.line, width: 1.5),
        ),
        child: Row(children: [
          const Icon(Icons.lock_outline, size: 18, color: Pal.sub),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Pal.sub, fontSize: 12))),
        ]),
      );

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, dynamic>>(
      // regole del tavolo per agire (mai due volte di fila, fermo...) e attese dal vivo
      stream: ItemService.watchUserFields(context.read<Session>().userName!, const [
        'lastKind', 'waitUntilAction', 'zoneMoves', 'freeAction', 'wildEncounter', 'spotted', 'busyUntil', 'priority',
      ]),
      builder: (context, uSnap) => _AbilityLive(builder: (context, pk, party, st) {
        final me = context.read<Session>().userName!;
        final started = st?['started'] == true;
        final round = _i(st?['round']);
        final have = [for (final k in unlockedAbilities(pk)) abilityDef(k)!];
        final actives = have.where((d) => d.active).toList();
        final passives = have.where((d) => !d.active).toList();
        // la versione compatta (Tavolo) non c'è finché il Pokémon non ha abilità
        if (widget.compact && have.isEmpty) return const SizedBox.shrink();
        final complete = kitComplete(pk);
        final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final d in actives)
            Builder(builder: (_) {
              final block = !started || party == null
                  ? 'La partita non è ancora iniziata'
                  : abilityBlock(pk, d.key, round) ?? AbilityService.abilityActBlock(st, uSnap.data, me, d);
              final running = activeAbility(pk, round) == d.key;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DropButton(
                    label: block == null ? d.name : '${d.name} · ${running ? 'in corso' : block.toLowerCase()}',
                    colors: typeColors(d.type),
                    height: widget.compact ? 40 : 46,
                    busy: _busy,
                    onTap: block == null ? () => _use(d, party!, st) : null,
                  ),
                  if (!widget.compact)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, left: 4),
                      child: Text('${d.text} Ricarica ${d.cooldown} giri.', style: const TextStyle(color: Pal.sub, fontSize: 12)),
                    ),
                ]),
              );
            }),
          if (!widget.compact) ...[
            for (var i = actives.length; i < kMaxActives; i++)
              if (!complete) _slot('Attiva: si sblocca con il prossimo badge'),
            for (final d in passives)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: typeColors(d.type).first.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: AbilityTile(d, dense: true),
              ),
            for (var i = passives.length; i < kMaxPassives; i++)
              if (!complete) _slot('Passiva: si sblocca con il prossimo badge'),
          ] else
            for (final d in passives)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InfoChip('${d.name} (passiva)', color: typeColors(d.type).first),
              ),
        ]);
        if (widget.compact) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Abilità', style: TextStyle(fontWeight: FontWeight.w800)),
              body,
            ]),
          );
        }
        return DropCard(
          colors: typeColors(pokemonTypes(pk).firstOrNull),
          label: 'Abilità',
          labelOnTop: true,
          child: have.isEmpty
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Il tuo Pokémon non ha ancora abilità: a ogni palestra vinta in questa partita ne sblocchi una.',
                      style: TextStyle(color: Pal.sub, fontSize: 12)),
                  body,
                ])
              : body,
        );
      }));
}

class _Cancel implements Exception {
  const _Cancel();
}
