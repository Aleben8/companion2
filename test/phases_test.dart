import 'package:companion2/table/phases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> st({int actions = 0, int round = 1, String? last}) =>
      {'started': true, 'actions': actions, 'round': round, 'lastUid': last, 'phaseActions': 5};

  test('fasi: 4 al giorno, il giro è la fase', () {
    expect(phaseLabel(1), 'Giorno 1 · Mattina');
    expect(phaseLabel(4), 'Giorno 1 · Notte');
    expect(phaseLabel(5), 'Giorno 2 · Mattina');
    expect(roundAfter(0, 5), 1);
    expect(roundAfter(4, 5), 1);
    expect(roundAfter(5, 5), 2);
    expect(roundAfter(21, 5), 5);
    expect(suggestedPhaseActions(4), 5);
  });

  test('quando: "nel pomeriggio", "domani mattina"', () {
    expect(whenLabel(2, 1), 'nel pomeriggio');
    expect(whenLabel(3, 1), 'stasera');
    expect(whenLabel(5, 3), 'domani mattina');
    expect(untilLabel(4, 2), 'fino a stanotte');
  });

  test('mai due volte di fila e mai due azioni uguali di fila', () {
    expect(actBlock(state: st(last: 'ash'), user: {}, uid: 'ash', kind: ActKind.search), isNotNull);
    expect(actBlock(state: st(last: 'misty'), user: {}, uid: 'ash', kind: ActKind.search), isNull);
    expect(actBlock(state: st(last: 'misty'), user: {'lastKind': 'search'}, uid: 'ash', kind: ActKind.search), isNotNull);
    expect(actBlock(state: st(last: 'misty'), user: {'lastKind': 'search'}, uid: 'ash', kind: ActKind.move), isNull);
    // spostarsi tra i settori della stessa zona è libero anche dopo uno spostamento
    expect(actBlock(state: st(last: 'misty'), user: {'lastKind': 'move'}, uid: 'ash', kind: ActKind.move), isNull);
    // cambiare zona due volte di fila no
    expect(actBlock(state: st(last: 'misty'), user: {'lastKind': 'zone'}, uid: 'ash', kind: ActKind.zone), isNotNull);
    // Clessidra: una volta si può
    expect(actBlock(state: st(last: 'ash'), user: {'lastKind': 'search', 'freeAction': true}, uid: 'ash', kind: ActKind.search),
        isNull);
    // le reazioni obbligate (eludere, fuggire) si fanno sempre
    expect(actBlock(state: st(last: 'ash'), user: {}, uid: 'ash', kind: ActKind.forced), isNull);
  });

  test('cambi di zona: 2 al giorno, con una fase in mezzo', () {
    // cambiato zona la sera (fase 3): la notte (4) e la mattina dopo (5) no, il pomeriggio (6) sì
    final u = {'zoneMoves': [3]};
    expect(actBlock(state: st(round: 4, last: 'x'), user: u, uid: 'ash', kind: ActKind.zone), isNotNull);
    expect(actBlock(state: st(round: 5, last: 'x'), user: u, uid: 'ash', kind: ActKind.zone), isNotNull);
    expect(actBlock(state: st(round: 6, last: 'x'), user: u, uid: 'ash', kind: ActKind.zone), isNull);
    // già 2 oggi (mattina e sera del giorno 1): stanotte no
    expect(actBlock(state: st(round: 4, last: 'x'), user: {'zoneMoves': [1, 3]}, uid: 'ash', kind: ActKind.zone),
        contains('2 volte oggi'));
  });

  test('Trappola: fermo finché il gruppo non fa altre azioni', () {
    final u = {'waitUntilAction': 7};
    expect(actBlock(state: st(actions: 5, last: 'x'), user: u, uid: 'ash', kind: ActKind.move), contains('2 azioni'));
    expect(actBlock(state: st(actions: 7, last: 'x'), user: u, uid: 'ash', kind: ActKind.move), isNull);
  });

  test('azioni a testa: la fase passa quando tutti hanno usato le loro', () {
    final st = {'started': true, 'round': 1, 'actionsPerPlayer': 2, 'order': ['ash', 'misty'], 'used': {'ash': 2, 'misty': 1}};
    expect(actionsLeft(st, 'ash'), 0);
    expect(actionsLeft(st, 'misty'), 1);
    expect(waitingFor(st), ['misty']);
    expect(actBlock(state: st, user: {}, uid: 'ash', kind: ActKind.search), contains('aspetta gli altri'));
    // se gli altri hanno finito, "mai due volte di fila" non blocca
    final solo = {...st, 'used': {'ash': 2, 'misty': 0}, 'lastUid': 'misty'};
    expect(actBlock(state: solo, user: {}, uid: 'misty', kind: ActKind.search), isNull);
    final done = settlePhase(st, 1, {'ash': 2, 'misty': 2}, {});
    expect(done.round, 2);
    expect(done.used, isEmpty);
  });

  test('azioni perse: contano come usate e passano alla fase dopo', () {
    final st = {'started': true, 'round': 1, 'actionsPerPlayer': 2, 'order': ['ash', 'misty']};
    // Trappola: ash perde 3 azioni con 2 a disposizione -> 2 ora, 1 nella fase dopo
    final r = settlePhase(st, 1, {'misty': 2}, {'ash': 3});
    expect(r.round, 2);
    expect(r.lost, {'ash': 1});
    expect(usedActions({...st, 'lost': r.lost}, 'ash'), 1);
    expect(lostActions({...st, 'lost': {'ash': 1}}, 'ash'), 1);
  });
}
