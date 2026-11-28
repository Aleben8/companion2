import 'dart:math';

import 'package:companion2/abilities.dart';
import 'package:companion2/services/battle_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dado truccato: ogni tiro d20 vale [roll], ogni probabilità riesce.
class _Fixed implements Random {
  final int roll;
  _Fixed(this.roll);
  @override
  int nextInt(int max) => (roll - 1).clamp(0, max - 1);
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => true;
}

Map<String, dynamic> _fighter(String name, {String action = 'none', List<String> mods = const [], Map? move}) => {
      'uid': name,
      'pokemon_name': name,
      'current_hp': 40,
      'max_hp': 40,
      'current_energies': 10,
      'max_energies': 15,
      'last_action': action,
      'last_move_used': move == null ? null : 'Colpo',
      'moveset_data': {'Colpo': move ?? {'Dmg': 2, 'MoveType': 'Normale'}},
      'Atk': 0,
      'AtkSpec': 0,
      'Def': 0,
      'DefSpec': 0,
      'Vel': 0,
      'debolezze': <String>[],
      'resistenze': <String>[],
      'mods': mods,
    };

Map<String, dynamic> _turn(Map<String, dynamic> a, Map<String, dynamic> b, int roll) =>
    BattleService.computeTurn({'turn_number': 0, 'playerA': a, 'playerB': b}, rnd: _Fixed(roll)).updates;

void main() {
  const hit = {'Dmg': 2, 'MoveType': 'Normale', 'MoveTypo': 'Fisico'};
  const poison = {'Dmg': 2, 'MoveType': 'Veleno', 'AltEffect': 'Danno', 'AltStatusPerc': 1.0};

  test('Pugno di ferro: il primo colpo a segno conta come Forte', () {
    final plain = _turn(_fighter('A', action: 'attack', move: hit), _fighter('B'), 5);
    expect(plain['playerB.current_hp'], 38); // Debole: 2
    final fist = _turn(_fighter('A', action: 'attack', move: hit, mods: [Ab.pugnoDiFerro]), _fighter('B'), 5);
    expect(fist['playerB.current_hp'], 35); // Forte: 2 + 3
    expect(fist['playerA.used_pugno'], true);
  });

  test('Rinforzo: il primo colpo subito è dimezzato senza Difesa', () {
    final u = _turn(_fighter('A', action: 'attack', move: {'Dmg': 4, 'MoveType': 'Normale'}), _fighter('B', mods: [Ab.rinforzo]), 5);
    expect(u['playerB.current_hp'], 38); // 4 / 2
    expect(u['playerB.used_rinforzo'], true);
  });

  test('Corazza: Difesa dà +2 energie in più', () {
    final u = _turn(_fighter('A', action: 'defense', mods: [Ab.corazza]), _fighter('B', action: 'defense'), 5);
    expect(u['playerA.current_energies'], 15);
    expect(u['playerB.current_energies'], 13);
  });

  test('Immunità blocca il Danno nel tempo, Incanto lo rimanda indietro', () {
    final imm = _turn(_fighter('A', action: 'attack', move: poison), _fighter('B', mods: [Ab.immunita]), 5);
    expect(imm['playerB.stato'] is Map, isFalse);
    final back = _turn(_fighter('A', action: 'attack', move: poison), _fighter('B', mods: [Ab.incanto]), 5);
    expect(back['playerA.stato'] is Map, isTrue);
    expect(back['playerB.stato'] is Map, isFalse);
  });

  test('Riflessi: la prima Schiva riesce anche contro un imbloccabile', () {
    final plain = _turn(_fighter('A', action: 'attack', move: hit), _fighter('B', action: 'dodge'), 20);
    expect(plain['playerB.current_hp'], lessThan(40));
    final reflex = _turn(_fighter('A', action: 'attack', move: hit), _fighter('B', action: 'dodge', mods: [Ab.riflessi]), 20);
    expect(reflex['playerB.current_hp'], 40);
  });

  test('Statico e Aura del drago: l’avversario parte con −2 energie', () {
    final a = _fighter('A'), b = _fighter('B');
    BattleService.applyStartMods(a, b, [Ab.statico, Ab.auraDrago], const []);
    expect(b['current_energies'], 6);
    expect(a['current_energies'], 10);
  });
}
