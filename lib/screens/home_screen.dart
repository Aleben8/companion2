import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
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

enum HomeTab { stats, party, battle }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeTab _tab = HomeTab.stats;
  String? _openBattleId; // battaglia aperta dalla sfida a un capopalestra

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final pk = s.pokemon ?? {};
    final name = (pk['PkmName'] ?? s.pokemonId ?? '').toString();
    final prim = (pk['PkmTypePrim'] ?? '').toString();
    final sec = (pk['PkmTypeSec'] ?? '').toString();
    final level = (pk['PkmLv'] as num?)?.round() ?? 1;
    final color = s.color;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Companion', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Palestre',
            icon: const Icon(Icons.map_outlined),
            onPressed: () async {
              final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const GymsScreen()));
              if (id != null && mounted) {
                setState(() {
                  _openBattleId = id;
                  _tab = HomeTab.battle;
                });
              }
            },
          ),
          IconButton(
            tooltip: 'Zaino',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryScreen())),
          ),
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
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Hero(color: color, name: name, prim: prim, sec: sec, level: level),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            child: Column(children: [
              const GameWatcher(),
              const StatusBanner(),
              const SizedBox(height: 8),
              _Tabs(color: color, tab: _tab, onTab: (t) => setState(() => _tab = t)),
              const SizedBox(height: 6),
              switch (_tab) {
                HomeTab.stats => _StatsPanel(pk: pk, color: color),
                HomeTab.party => const PartyTab(),
                HomeTab.battle => BattleTab(key: ValueKey(_openBattleId), initialBattleId: _openBattleId),
              },
            ]),
          ),
        ],
      ),
    );
  }
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
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final Color color;
  final HomeTab tab;
  final ValueChanged<HomeTab> onTab;
  const _Tabs({required this.color, required this.tab, required this.onTab});

  Widget _btn(HomeTab t, String label, String asset) {
    final sel = tab == t;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTab(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
          height: 68,
          decoration: BoxDecoration(
            gradient: sel ? LinearGradient(colors: [color, lighten(color, 0.3)]) : null,
            color: sel ? null : Colors.white,
            border: sel ? null : Border.all(color: Pal.line, width: 2),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
              topRight: Radius.circular(8),
              bottomLeft: Radius.circular(8),
            ),
            boxShadow: sel ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))] : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Image.asset(asset,
                width: 26, height: 26, color: sel ? Colors.white : Pal.ink, errorBuilder: (_, __, ___) => const Icon(Icons.circle)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: sel ? Colors.white : Pal.ink)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        _btn(HomeTab.stats, 'Statistiche', 'assets/images/stats.png'),
        _btn(HomeTab.party, 'Party', 'assets/images/party.png'),
        _btn(HomeTab.battle, 'Battaglia', 'assets/images/battle.png'),
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
      DropCard(colors: Pal.gold, label: 'Badge', child: const BadgeRow()),
    ]);
  }
}
