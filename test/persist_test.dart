import 'package:companion2/constants.dart';
import 'package:companion2/services/battle_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('energie e status restano tra gli scontri; dopo una sconfitta si riparte pieni', () {
    expect(BattleService.startEnergy({}), kBaseEnergy);
    expect(BattleService.startEnergy({'currentEnergy': 6, 'currentHp': 20}), 6);
    expect(BattleService.startEnergy({'currentEnergy': 6, 'currentHp': 0}), kBaseEnergy);
    final dot = {'type': 'dot', 'damage_per_turn': 2, 'remaining_turns': 2};
    expect(BattleService.startStatus({'currentStatus': dot, 'currentHp': 10}), dot);
    expect(BattleService.startStatus({'currentStatus': dot, 'currentHp': 0}), isNull);
    expect(BattleService.statusLabel(dot), 'Avvelenato');
  });
}
