import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Posizione GPS del giocatore (solo con l'app aperta in primo piano).
/// Salva su `Users/{uid}.location` al massimo ogni ~20 secondi.
class LocationService extends ChangeNotifier {
  Position? position;
  String? error;
  StreamSubscription<Position>? _sub;
  String? _uid;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  bool get active => _sub != null;

  Future<void> start(String uid) async {
    if (_uid == uid && _sub != null) return;
    await stop();
    _uid = uid;
    error = null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        error = 'Servizi di localizzazione disattivati';
        notifyListeners();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        error = 'Permesso di posizione negato';
        notifyListeners();
        return;
      }
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 8),
      ).listen(_onPosition, onError: (e) {
        error = 'Errore posizione: $e';
        notifyListeners();
      });
    } catch (e) {
      error = 'Errore posizione: $e';
      notifyListeners();
    }
  }

  void _onPosition(Position p) {
    position = p;
    error = null;
    notifyListeners();
    _writeIfDue(p);
  }

  Future<void> _writeIfDue(Position p, {bool force = false}) async {
    final uid = _uid;
    if (uid == null) return;
    if (!force && DateTime.now().difference(_lastWrite).inSeconds < 20) return;
    _lastWrite = DateTime.now();
    try {
      await FirebaseFirestore.instance.collection('Users').doc(uid).set({
        'location': {
          'lat': p.latitude,
          'lng': p.longitude,
          'acc': p.accuracy,
          'at': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Errore salvataggio posizione: $e');
    }
  }

  /// Posizione aggiornata al momento (usata da Radar, Calmanella e Trappola).
  Future<Position?> current() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      position = p;
      notifyListeners();
      _writeIfDue(p, force: true);
      return p;
    } catch (e) {
      return position;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _uid = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
