import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mode.dart';
import 'item_service.dart';
import 'party_service.dart';

/// Segue la modalità (tavolo / dal vivo) del party corrente del giocatore:
/// `Users/{uid}.actualParty` -> `Party/{codice}.mode`. A ogni cambio aggiorna [AppMode.current]
/// e avvisa i widget, così la home si ricostruisce nella modalità giusta.
class ModeService extends ChangeNotifier {
  StreamSubscription? _userSub, _partySub;
  String? _uid, _party;

  String get mode => AppMode.current;
  String? get party => _party;

  void bind(String uid) {
    if (_uid == uid) return;
    unbind();
    _uid = uid;
    _userSub = ItemService.watchUser(uid).listen((u) {
      final p = u?['actualParty'];
      final party = p is String && p.isNotEmpty ? p : null;
      if (party == _party) return;
      _party = party;
      _partySub?.cancel();
      if (party == null) {
        _set(kDefaultMode);
        return;
      }
      _partySub = PartyService.party(party).snapshots().listen((s) {
        final m = s.data()?['mode'];
        _set(m == kModeLive || m == kModeTable ? m as String : kDefaultMode);
      });
    });
  }

  void unbind() {
    _userSub?.cancel();
    _partySub?.cancel();
    _userSub = _partySub = null;
    _uid = _party = null;
  }

  void _set(String m) {
    if (AppMode.current == m) return;
    AppMode.current = m;
    notifyListeners();
  }

  @override
  void dispose() {
    unbind();
    super.dispose();
  }
}
