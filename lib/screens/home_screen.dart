import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../mode.dart';
import '../services/battle_service.dart';
import '../services/item_service.dart';
import '../services/mode_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/badge_row.dart';
import '../widgets/common.dart';
import '../widgets/drop.dart';
import '../widgets/game_status.dart';
import 'battle_tab.dart';
import 'gyms_screen.dart';
import 'inventory_screen.dart';
import 'party_tab.dart';
import 'settings_screen.dart';
import 'table_tab.dart';

enum HomeTab { stats, party, battle, bag, map }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeTab _tab = HomeTab.stats;
  String? _openBattleId; // battaglia aperta dalla sfida a un capopalestra
  late final ModeService _modes;

  @override
  void initState() {
    super.initState();
    _modes = context.read<ModeService>()..bind(context.read<Session>().userName!);
  }

  @override
  void dispose() {
    _modes.unbind();
    super.dispose();
  }

  void _openBattle(String id) => setState(() {
        _openBattleId = id;
        _tab = HomeTab.battle;
      });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    // Il Master può cambiare modalità in qualsiasi momento: la home si ricostruisce da capo.
    final mode = context.watch<ModeService>().mode;
    final pk = s.pokemon ?? {};
    final name = (pk['PkmName'] ?? s.pokemonId ?? '').toString();
    final prim = (pk['PkmTypePrim'] ?? '').toString();
    final sec = (pk['PkmTypeSec'] ?? '').toString();
    final level = (pk['PkmLv'] as num?)?.round() ?? 1;
    final color = s.color;

    return Scaffold(
      extendBody: true, // il contenuto scorre sotto il menu (che è di vetro)
      appBar: AppBar(
        title: const Text('Companion', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
              if (context.mounted) context.read<Session>().reload();
            },
          ),
        ],
      ),
      // copertina che si riduce scorrendo (resta una barra con nome e PS) e menu fisso in basso
      // Builder: il contesto dentro lo Scaffold conosce l'altezza del menu (extendBody), quello fuori no
      body: Builder(builder: (inner) => CustomScrollView(
        key: ValueKey(mode),
        slivers: [
          const SliverToBoxAdapter(child: ZoneEventsStrip()),
          // copertina aperta solo in Statistiche: nelle altre sezioni si ritira (animata) come scorrendo
          TweenAnimationBuilder<double>(
            tween: Tween(end: _tab == HomeTab.stats ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOut,
            builder: (context, open, _) => SliverPersistentHeader(
              pinned: true,
              delegate: _HeroHeader(
                hero: _Hero(color: color, name: name, prim: prim, sec: sec, level: level),
                name: name,
                color: color,
                bg: Theme.of(context).scaffoldBackgroundColor,
                open: open,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              // spazio sotto per non finire coperti dal menu di vetro
              // spazio in fondo = altezza del menu di vetro + margine: l'ultimo contenuto resta visibile
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.of(inner).padding.bottom),
              child: Column(children: [
                const GameWatcher(),
                const TableWatcher(), // turni al tavolo; orologio dei giri e zona GPS dal vivo
                const TurnBar(),
                const StatusBanner(),
                const SizedBox(height: 8),
                switch (_tab) {
                  HomeTab.stats => _StatsPanel(pk: pk, color: color),
                  HomeTab.party => const PartyTab(),
                  HomeTab.battle => BattleTab(key: ValueKey(_openBattleId), initialBattleId: _openBattleId),
                  HomeTab.bag => const InventoryTab(),
                  HomeTab.map => kTableMode
                      ? TableTab(onBattle: _openBattle)
                      // dal vivo: mappa con palestre e zone, poi la partita a zone (eventi, empori, leggendario)
                      : Column(children: [
                          GymsTab(onBattle: _openBattle),
                          TableTab(onBattle: _openBattle),
                        ]),
                },
              ]),
            ),
          ),
        ],
      )),
      // menu fisso in basso con effetto vetro: sfoca e schiarisce quello che ci scorre sotto
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withOpacity(0.55), Colors.white.withOpacity(0.35)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.2),
                ),
                child: _Tabs(color: color, tab: _tab, onTab: (t) => setState(() => _tab = t)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Copertina fissata in alto: grande all'inizio, scorrendo si riduce a una barra (come la fascia
/// degli eventi, ma del colore scelto dal giocatore) con il Pokémon, il nome e i PS.
class _HeroHeader extends SliverPersistentHeaderDelegate {
  final Widget hero;
  final String name;
  final Color color; // colore scelto dal giocatore
  final Color bg;
  final double open; // 1 = copertina aperta (Statistiche), 0 = solo la barra (altre sezioni)
  _HeroHeader({required this.hero, required this.name, required this.color, required this.bg, this.open = 1});

  static const double _max = 352; // copertina (340) + margine sopra
  static const double _min = 64;

  @override
  double get maxExtent => _min + (_max - _min) * open;
  @override
  double get minExtent => _min;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // quanto è chiusa (0 = copertina intera, 1 = solo barra), per scorrimento o perché la sezione la ritira
    final extent = (maxExtent - shrinkOffset).clamp(_min, _max);
    final t = (1 - (extent - _min) / (_max - _min)).clamp(0.0, 1.0);
    final bar = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
    return Stack(clipBehavior: Clip.hardEdge, children: [
      // la copertina scorre via (e sfuma)
      Positioned(
        top: extent - _max,
        left: 0,
        right: 0,
        height: _max,
        child: Opacity(opacity: (1 - t * 1.4).clamp(0.0, 1.0), child: hero),
      ),
      if (bar > 0)
        Positioned.fill(
          child: Opacity(
            opacity: bar,
            child: ColoredBox(
              color: bg,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, lighten(color, 0.3)]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Row(children: [
                  PokemonImage(name, size: 36),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  const _HpPill(),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  @override
  bool shouldRebuild(_HeroHeader old) => old.name != name || old.color != color || old.bg != bg || old.hero != hero || old.open != open;
}

/// Copertina con il Pokémon sul colore identificativo del giocatore.
class _Hero extends StatelessWidget {
  final Color color;
  final String name, prim, sec;
  final int level;
  const _Hero({required this.color, required this.name, required this.prim, required this.sec, required this.level});

  Widget _typePill(String t) => Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TypeIcon(t, size: 22),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final swirl = Colors.white.withOpacity(0.22);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      height: 340,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, lighten(color, 0.45)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(36),
        boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: Stack(children: [
          Positioned(
            left: -34,
            top: 24,
            child: Image.asset('assets/images/flame2.png', height: 230, color: swirl, colorBlendMode: BlendMode.srcIn),
          ),
          Positioned(
            right: -34,
            top: 24,
            child: Transform.flip(
              flipX: true,
              child: Image.asset('assets/images/flame2.png', height: 230, color: swirl, colorBlendMode: BlendMode.srcIn),
            ),
          ),
          Positioned(
            top: 22,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.28)),
                child: Center(child: PokemonImage(name, size: 176)),
              ),
            ),
          ),
          Positioned(
            bottom: 18,
            left: 12,
            right: 12,
            child: Column(children: [
              Text(name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
                if (prim.isNotEmpty) _typePill(prim),
                if (sec.isNotEmpty) _typePill(sec),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.22), borderRadius: BorderRadius.circular(20)),
                  child: Text('Livello $level',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                const _HpPill(),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// PS attuali del Pokémon (restano tra uno scontro e l'altro), in tempo reale.
class _HpPill extends StatefulWidget {
  const _HpPill();
  @override
  State<_HpPill> createState() => _HpPillState();
}

class _HpPillState extends State<_HpPill> {
  // stream creati una volta sola (non a ogni build)
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _pokemon;
  late final Stream<Map<String, dynamic>?> _user;

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    _pokemon = s.pokemonRef.snapshots();
    _user = ItemService.watchUser(s.userName!);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _user,
      builder: (context, uSnap) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _pokemon,
        builder: (context, pSnap) {
          if (!pSnap.hasData) return const SizedBox.shrink();
          final ko = ItemService.isActive(uSnap.data?['koUntil']);
          final hp = BattleService.currentHp(pSnap.data!.data(), ko: ko);
          final frac = hp / kBaseHp;
          final color = ko || frac <= 0.25 ? Pal.bad : (frac <= 0.5 ? Pal.warn : Pal.ok);
          return Container(
            padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ko ? Icons.heart_broken : Icons.favorite, size: 16, color: color),
              const SizedBox(width: 6),
              Text(ko ? 'Esausto' : 'PS $hp/$kBaseHp',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 42,
                  height: 6,
                  child: LinearProgressIndicator(value: frac.clamp(0.0, 1.0), color: color, backgroundColor: Pal.line),
                ),
              ),
              // energie e status alterato: restano tra uno scontro e l'altro
              if (!ko) ...[
                const SizedBox(width: 8),
                const Icon(Icons.bolt, size: 15, color: Color(0xFFE0A100)),
                Text('${BattleService.startEnergy(pSnap.data!.data() ?? const {})}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                if (BattleService.startStatus(pSnap.data!.data() ?? const {}) != null) ...[
                  const SizedBox(width: 6),
                  Text(BattleService.statusLabel(BattleService.startStatus(pSnap.data!.data() ?? const {})),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Pal.bad)),
                ],
              ],
            ]),
          );
        },
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final Color color;
  final HomeTab tab;
  final ValueChanged<HomeTab> onTab;
  const _Tabs({required this.color, required this.tab, required this.onTab});

  /// [asset] per le icone dell'originale, [icon] per quelle Material.
  Widget _btn(HomeTab t, String label, {String? asset, IconData? icon}) {
    final sel = tab == t;
    final fg = sel ? Colors.white : Pal.ink;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTab(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          height: 58,
          decoration: BoxDecoration(
            gradient: sel ? LinearGradient(colors: [color, lighten(color, 0.3)]) : null,
            color: sel ? null : Colors.white.withOpacity(0.35),
            border: sel ? null : Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              bottomRight: Radius.circular(22),
              topRight: Radius.circular(8),
              bottomLeft: Radius.circular(8),
            ),
            boxShadow: sel ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))] : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (asset != null)
              Image.asset(asset, width: 24, height: 24, color: fg, errorBuilder: (_, __, ___) => const Icon(Icons.circle))
            else
              Icon(icon, size: 24, color: fg),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        _btn(HomeTab.stats, 'Statistiche', asset: 'assets/images/stats.png'),
        _btn(HomeTab.party, 'Party', asset: 'assets/images/party.png'),
        _btn(HomeTab.battle, 'Battaglia', asset: 'assets/images/battle.png'),
        _btn(HomeTab.bag, 'Borsa', asset: 'assets/images/borsa.png'),
        kTableMode
            ? _btn(HomeTab.map, 'Tavolo', icon: Icons.casino_outlined)
            : _btn(HomeTab.map, 'Mappa', icon: Icons.map_outlined),
      ]);
}

class _StatsPanel extends StatelessWidget {
  final Map<String, dynamic> pk;
  final Color color;
  const _StatsPanel({required this.pk, required this.color});

  Widget _bar(int v, List<Color> cs) => LayoutBuilder(builder: (context, cons) {
        final w = cons.maxWidth * (v.clamp(0, kStatMax) / kStatMax);
        return SizedBox(
          height: 16,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              top: 2,
              bottom: 2,
              child: Container(decoration: BoxDecoration(color: Pal.line, borderRadius: BorderRadius.circular(8))),
            ),
            Positioned(
              left: 0,
              top: 2,
              bottom: 2,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                width: w,
                decoration: BoxDecoration(gradient: LinearGradient(colors: cs), borderRadius: BorderRadius.circular(8)),
              ),
            ),
            if (v > 0)
              Positioned(
                left: (w - 8).clamp(0.0, cons.maxWidth - 16).toDouble(),
                top: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.last, width: 3),
                  ),
                ),
              ),
          ]),
        );
      });

  Widget _types(String title, dynamic list, List<Color> cs) {
    final l = list is List ? list.map((e) => e.toString()).where((e) => e != 'N/A').toList() : <String>[];
    return DropCard(
      colors: cs,
      label: title,
      labelOnTop: true,
      child: l.isEmpty
          ? const Text('Nessuna', style: TextStyle(color: Pal.sub))
          : Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in l)
                Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: Pal.bg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Pal.line),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    TypeIcon(t, size: 24),
                    const SizedBox(width: 6),
                    Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = [color, lighten(color, 0.4)];
    return Column(children: [
      DropCard(
        colors: c,
        label: 'Statistiche',
        labelOnTop: true,
        child: Column(children: [
          for (final e in kStatLabels.entries) ...[
            Row(children: [
              Text(e.value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              GradientText('${(pk[e.key] as num?)?.round() ?? 0}',
                  colors: kStatGradients[e.key]!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            _bar((pk[e.key] as num?)?.round() ?? 0, kStatGradients[e.key]!),
            const SizedBox(height: 12),
          ],
        ]),
      ),
      _types('Debolezze', pk['Debolezze'], const [Pal.bad, Color(0xFFF3A0A0)]),
      _types('Resistenze', pk['Resistenze'], const [Pal.ok, Color(0xFF9BDFA0)]),
      DropCard(colors: Pal.gold, label: 'Badge', labelOnTop: true, child: const BadgeRow()),
    ]);
  }
}
