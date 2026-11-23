import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import 'item_service.dart';

/// Stato di sessione: giocatore (documento `Users/{UserName}`) e
/// Pokémon attivo (documento `Users/{UserName}/Pokemon/{PokemonDocumentID}`).
class Session extends ChangeNotifier {
  final _db = FirebaseFirestore.instance;

  String? userName;
  String? pokemonId;
  Map<String, dynamic>? pokemon;
  bool loading = false;

  bool get isLoggedIn => userName != null && pokemonId != null;

  DocumentReference<Map<String, dynamic>> get userRef =>
      _db.collection('Users').doc(userName);
  DocumentReference<Map<String, dynamic>> get pokemonRef =>
      userRef.collection('Pokemon').doc(pokemonId);

  Color get color => parseColor(pokemon?['Color']) ?? kDefaultColor;

  static Color? parseColor(dynamic v) {
    if (v is! String) return null;
    var s = v.replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    final n = int.tryParse(s, radix: 16);
    return n == null ? null : Color(n);
  }

  static String colorToHex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Verifica che utente e Pokémon esistano, poi entra.
  Future<bool> login(String user, String pokemonName) async {
    loading = true;
    notifyListeners();
    try {
      final u = _db.collection('Users').doc(user);
      if (!(await u.get()).exists) return false;
      final p = await u.collection('Pokemon').doc(pokemonName).get();
      if (!p.exists) return false;
      userName = user;
      pokemonId = pokemonName;
      await ItemService.ensureInventory(user);
      await _saveActive();
      await reload();
      return true;
    } catch (_) {
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Entra direttamente (dopo la creazione del personaggio).
  Future<void> enter(String user, String pokemonName) async {
    userName = user;
    pokemonId = pokemonName;
    await ItemService.ensureInventory(user);
    await _saveActive();
    await reload();
  }

  /// Il Pokémon con cui si gioca (serve al rifugio e agli incontri selvatici del tavolo).
  Future<void> _saveActive() => userRef.set({'activePokemon': pokemonId}, SetOptions(merge: true));

  Future<void> reload() async {
    if (!isLoggedIn) return;
    final snap = await pokemonRef.get();
    pokemon = snap.data() == null
        ? null
        : {...snap.data()!, 'PokemonDocumentID': pokemonId};
    notifyListeners();
  }

  void logout() {
    userName = null;
    pokemonId = null;
    pokemon = null;
    notifyListeners();
  }
}
