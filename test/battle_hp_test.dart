import 'package:companion2/constants.dart';
import 'package:companion2/services/battle_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('si entra in battaglia con i PS con cui si è finito lo scontro precedente', () {
    expect(BattleService.startHp({'currentHp': 17}), 17);
  });

  test('senza scontri precedenti (o per i capipalestra) si parte pieni', () {
    expect(BattleService.startHp({}), kBaseHp);
    expect(BattleService.startHp({'PkmLife': 25}), kBaseHp, reason: 'PkmLife dell’app originale non conta');
  });

  test('dopo una sconfitta (0 PS) e il recupero si riparte pieni', () {
    expect(BattleService.startHp({'currentHp': 0}), kBaseHp);
  });

  test('PS fuori dalla battaglia: 0 solo se ancora esausto', () {
    expect(BattleService.currentHp({'currentHp': 0}, ko: true), 0);
    expect(BattleService.currentHp({'currentHp': 0}), kBaseHp, reason: 'recupero finito');
    expect(BattleService.currentHp({'currentHp': 12}, ko: true), 12);
    expect(BattleService.currentHp(null), kBaseHp);
  });

  test('mai sopra il massimo', () {
    expect(BattleService.startHp({'currentHp': 99}), kBaseHp);
  });
}
