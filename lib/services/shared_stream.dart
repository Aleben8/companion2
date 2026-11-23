import 'dart:async';

/// Stream condivisi: un solo ascolto Firestore per chiave, qualunque sia il numero di widget che lo usano.
///
/// Perché: `StreamBuilder(stream: ItemService.watchUser(uid))` dentro un `build()` crea uno stream NUOVO a ogni
/// ricostruzione, e lo StreamBuilder chiude l'ascolto vecchio e ne apre uno nuovo (con relativi rebuild a cascata).
/// [shared] restituisce sempre lo stesso oggetto per la stessa chiave, quindi lo StreamBuilder non si riaggancia, e chi
/// arriva dopo riceve subito l'ultimo valore. Quando nessuno ascolta più, l'ascolto su Firestore viene chiuso
/// (dopo una breve attesa, così cambiare tab non lo riapre ogni volta).
Stream<T> shared<T>(String key, Stream<T> Function() create) =>
    (_cache.putIfAbsent(key, () => _Shared<T>(create)) as _Shared<T>).stream;

final Map<String, _Shared<dynamic>> _cache = {};

/// Quanto resta aperto l'ascolto dopo che l'ultimo widget lo ha lasciato.
Duration sharedIdleDelay = const Duration(seconds: 30);

class _Shared<T> {
  final Stream<T> Function() _create;
  final _out = StreamController<T>.broadcast();
  StreamSubscription<T>? _src;
  Timer? _idle;
  T? _last;
  bool _hasLast = false;
  int _listeners = 0;
  late final Stream<T> stream = Stream<T>.multi((c) {
    _idle?.cancel();
    if (_hasLast) c.add(_last as T);
    final sub = _out.stream.listen(c.add, onError: c.addError);
    _listeners++;
    _src ??= _create().listen((v) {
      _last = v;
      _hasLast = true;
      _out.add(v);
    }, onError: _out.addError);
    c.onCancel = () {
      sub.cancel();
      if (--_listeners == 0) {
        _idle = Timer(sharedIdleDelay, () {
          _src?.cancel();
          _src = null;
        });
      }
    };
  });

  _Shared(this._create);

  T? get last => _last;
}

/// Ultimo valore noto di uno stream condiviso (per `initialData`, così non c'è il frame vuoto al primo build).
T? sharedLast<T>(String key) => _cache[key]?.last as T?;

/// Confronto profondo tra valori Firestore (mappe, liste, numeri, Timestamp...): serve a `distinct`
/// per non ricostruire i widget quando un documento cambia in campi che non li riguardano.
bool jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !jsonEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
