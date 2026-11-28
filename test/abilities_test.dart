import 'dart:math';

import 'package:companion2/abilities.dart';
import 'package:companion2/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('54 abilità: per ogni tipo 2 attive e 1 passiva, chiavi uniche', () {
    expect(kAbilities.length, 54);
    expect(kAbilities.map((a) => a.key).toSet().length, 54);
    for (final t in kTypes) {
      final l = abilitiesOfType(t);
      expect(l.where((a) => a.active).length, 2, reason: t);
      expect(l.where((a) => !a.active).length, 1, reason: t);
    }
    for (final a in kAbilities.where((a) => a.active)) {
      expect([2, 4, 8].contains(a.cooldown), isTrue, reason: a.key);
    }
  });

  test('riserva: tipo singolo 3 abilità, tipo doppio 6', () {
    expect(abilityPool({'PkmTypePrim': 'Fuoco', 'PkmTypeSec': ''}).length, 3);
    expect(abilityPool({'PkmTypePrim': 'Fuoco', 'PkmTypeSec': 'Volante'}).length, 6);
  });

  test('tipo singolo: sceglie tra 2 al 1º badge, riceve le 2 rimaste al 2º', () {
    final pk = <String, dynamic>{'PkmTypePrim': 'Acqua', 'PkmTypeSec': ''};
    final r1 = badgeReward(pk, rnd: Random(1));
    expect(r1.offer.length, kAbilityChoices);
    pk['abilities'] = [r1.offer.first];
    final r2 = badgeReward(pk);
    expect(r2.offer, isEmpty);
    expect(r2.unlock.length, 2);
    pk['abilities'] = [...pk['abilities'] as List, ...r2.unlock];
    expect(kitComplete(pk), isTrue);
    expect(badgeReward(pk).unlock, isEmpty);
  });

  test('tipo doppio: kit completo in 3 badge, max 2 attive e 1 passiva', () {
    final pk = <String, dynamic>{'PkmTypePrim': 'Drago', 'PkmTypeSec': 'Buio', 'abilities': <String>[]};
    for (var i = 0; i < 3; i++) {
      final r = badgeReward(pk, rnd: Random(i));
      final got = r.offer.isNotEmpty ? r.offer.first : r.unlock.first;
      pk['abilities'] = [...pk['abilities'] as List, got];
    }
    final have = unlockedAbilities(pk).map((k) => abilityDef(k)!).toList();
    expect(have.where((a) => a.active).length, kMaxActives);
    expect(have.where((a) => !a.active).length, kMaxPassives);
    expect(kitComplete(pk), isTrue);
  });

  test('ricarica, una alla volta, una per giro', () {
    final pk = <String, dynamic>{
      'abilities': [Ab.svanire, Ab.spavento],
      'abilityUsedRound': {Ab.svanire: 5},
      'abilityActiveUntil': 6,
      'abilityActiveKey': Ab.svanire,
    };
    expect(abilityBlock(pk, Ab.svanire, 5), isNotNull);
    expect(abilityBlock(pk, Ab.spavento, 6), 'Un’altra abilità è in corso');
    expect(abilityBlock(pk, Ab.spavento, 7), isNull);
    expect(abilityBlock(pk, Ab.svanire, 6), 'Pronta tra 1 giro');
    expect(abilityBlock(pk, Ab.svanire, 7), isNull);
    expect(abilityBlock(pk, Ab.racimolare, 7), 'Si sblocca con il prossimo badge');
    pk['abilityUsedRound'] = {Ab.svanire: 5, Ab.spavento: 7};
    pk['abilityActiveUntil'] = 6;
    expect(abilityBlock(pk, Ab.svanire, 7), 'Hai già usato un’abilità in questo giro');
  });

  test('Mobility: Fiammata, Gelata, Barricata, Sismo, Passo sicuro e immunità', () {
    final fx = [
      {'kind': Ab.fiammata, 'zone': 'vulcano', 'sector': null, 'owner': 'B'},
      {'kind': Ab.gelata, 'zone': 'hub', 'sector': 2, 'owner': 'B'},
      {'kind': Ab.barricata, 'zone': 'hub', 'sector': 3, 'owner': 'B'},
      {'kind': Ab.sismo, 'zone': 'canyon', 'sector': 1, 'owner': 'B'},
    ];
    final a = Mobility(uid: 'A', effects: fx);
    expect(a.abilityExtra('hub', 'vulcano', 1), 1); // entra nella zona rovente
    expect(a.abilityExtra('vulcano', 'vulcano', 2), 0); // già dentro
    expect(Mobility(uid: 'A', itemShield: 'vulcano', effects: fx).abilityExtra('hub', 'vulcano', 1), 0); // Tuta ignifuga
    expect(a.abilityExtra('hub', 'hub', 2), 1); // Gelata
    expect(Mobility(uid: 'B', effects: fx).abilityExtra('hub', 'hub', 2), 0); // il proprietario no
    expect(a.abilityBlocked('hub'), {3});
    expect(a.abilityBlocked('canyon'), {1});
    expect(Mobility(uid: 'A', passives: {Ab.corazza}, effects: fx).abilityBlocked('canyon'), isEmpty);
    expect(Mobility(passives: {Ab.nuotatore}).shielded('isola'), isTrue);
    expect(Mobility(passives: {Ab.passoSicuro}).sureFooted, isTrue);
    expect(bagLimitFor({Ab.lega}, 12), 14);
  });
}
