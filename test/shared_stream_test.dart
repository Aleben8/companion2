import 'dart:async';

import 'package:companion2/services/shared_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stessa chiave = stesso oggetto stream (lo StreamBuilder non si riaggancia)', () {
    final a = shared('k1', () => const Stream<int>.empty());
    final b = shared('k1', () => const Stream<int>.empty());
    expect(identical(a, b), isTrue);
  });

  test('un solo ascolto alla sorgente e chi arriva dopo riceve subito l’ultimo valore', () async {
    var opened = 0;
    final src = StreamController<int>.broadcast(onListen: () => opened++);
    final s = shared('k2', () => src.stream);
    final first = <int>[], second = <int>[];
    final s1 = s.listen(first.add);
    src.add(1);
    await Future<void>.delayed(Duration.zero);
    final s2 = s.listen(second.add);
    await Future<void>.delayed(Duration.zero);
    src.add(2);
    await Future<void>.delayed(Duration.zero);
    expect(opened, 1);
    expect(first, [1, 2]);
    expect(second, [1, 2]);
    await s1.cancel();
    await s2.cancel();
  });

  test('senza ascoltatori la sorgente si chiude dopo l’attesa', () async {
    sharedIdleDelay = const Duration(milliseconds: 50);
    var open = false;
    final src = StreamController<int>(onListen: () => open = true, onCancel: () => open = false);
    final sub = shared('k3', () => src.stream).listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(open, isTrue);
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(open, isTrue, reason: 'resta aperta per un po’ (es. cambio tab)');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(open, isFalse);
  });

  test('jsonEquals confronta mappe e liste annidate', () {
    expect(jsonEquals({'pos': {'zone': 'hub', 'sector': 1}}, {'pos': {'zone': 'hub', 'sector': 1}}), isTrue);
    expect(jsonEquals({'pos': {'zone': 'hub', 'sector': 1}}, {'pos': {'zone': 'hub', 'sector': 2}}), isFalse);
    expect(jsonEquals({'b': [1, 2]}, {'b': [1, 2]}), isTrue);
  });
}
