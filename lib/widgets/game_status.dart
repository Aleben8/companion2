import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../geo.dart';
import '../items.dart';
import '../services/item_service.dart';
import '../services/location_service.dart';
import '../services/party_service.dart';
import '../services/session.dart';
import '../theme.dart';
import 'common.dart';

/// Conto alla rovescia mm:ss che si aggiorna ogni secondo.
class Countdown extends StatefulWidget {
  final DateTime until;
  final TextStyle? style;
  const Countdown(this.until, {super.key, this.style});
  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(DateTime.now());
    final s = left.isNegative ? 0 : left.inSeconds;
    final txt = '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    return Text(txt, style: widget.style);
  }
}

/// Effetti attivi: Repellente, Pokémon esausto, bloccato in una Trappola.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key});

  Widget _chip(BuildContext context, IconData icon, Color color, String label, DateTime until,
      {Widget? action}) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(color: Pal.ink, fontSize: 15, fontWeight: FontWeight.w600))),
        Countdown(until, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        if (action != null) ...[const SizedBox(width: 8), action],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().userName!;
    return StreamBuilder<Map<String, dynamic>?>(
      stream: ItemService.watchUser(uid),
      builder: (context, snap) {
        final u = snap.data;
        if (u == null) return const SizedBox.shrink();
        DateTime? t(String k) => u[k] is Timestamp ? (u[k] as Timestamp).toDate() : null;
        final rep = t('repellentUntil');
        final ko = t('koUntil');
        final trap = t('trappedUntil');
        final now = DateTime.now();
        return Column(children: [
          if (rep != null && rep.isAfter(now))
            _chip(context, Icons.shield_moon, const Color(0xFF8CD0A8),
                'Repellente attivo: sei nascosto e non puoi combattere', rep),
          if (ko != null && ko.isAfter(now))
            _chip(context, Icons.healing, const Color(0xFF6CA8F0),
                'Pokémon esausto: in recupero', ko),
          if (trap != null && trap.isAfter(now))
            _chip(context, Icons.warning_amber_rounded, const Color(0xFFF2A74B),
                'Sei in una Trappola!', trap,
                action: TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: const Color(0xFFB5694F)),
                  onPressed: () async {
                    try {
                      await ItemService.useRopeOnTrap(uid);
                      if (context.mounted) snack(context, 'Sei fuggito dalla trappola!');
                    } catch (e) {
                      if (context.mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
                    }
                  },
                  child: const Text('Fune di fuga'),
                )),
        ]);
      },
    );
  }
}

/// Osservatore invisibile: avvia il GPS, controlla le trappole vicine e
/// avvisa quando un altro giocatore suona la Calmanella.
class GameWatcher extends StatefulWidget {
  const GameWatcher({super.key});
  @override
  State<GameWatcher> createState() => _GameWatcherState();
}

class _GameWatcherState extends State<GameWatcher> {
  StreamSubscription? _userSub, _trapSub, _eventSub;
  String? _party;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _traps = [];
  final Set<String> _handling = {};
  final Set<String> _seenEvents = {};
  late final String _uid;

  @override
  void initState() {
    super.initState();
    _uid = context.read<Session>().userName!;
    context.read<LocationService>().start(_uid);
    _userSub = ItemService.watchUser(_uid).listen((u) {
      final p = u?['actualParty'];
      final party = p is String && p.isNotEmpty ? p : null;
      if (party != _party) _subscribe(party);
    });
  }

  void _subscribe(String? party) {
    _trapSub?.cancel();
    _eventSub?.cancel();
    _party = party;
    _traps = [];
    if (party == null) return;
    _trapSub = PartyService.party(party)
        .collection('traps')
        .where('active', isEqualTo: true)
        .snapshots()
        .listen((s) {
      _traps = s.docs;
      _checkTraps(context.read<LocationService>());
    });
    _eventSub = PartyService.party(party)
        .collection('events')
        .orderBy('at', descending: true)
        .limit(5)
        .snapshots()
        .listen(_onEvents);
  }

  void _onEvents(QuerySnapshot<Map<String, dynamic>> snap) {
    final fresh = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in snap.docs) {
      if (_seenEvents.add(d.id)) fresh.add(d);
    }
    // Si mostrano solo gli eventi recenti (< 60 s), non quelli già vecchi.
    for (final d in fresh) {
      final data = d.data();
      final at = data['at'] is Timestamp ? (data['at'] as Timestamp).toDate() : null;
      if (data['type'] != 'bell' || data['uid'] == _uid || at == null) continue;
      if (DateTime.now().difference(at).inSeconds > 60) continue;
      final pos = context.read<LocationService>().position;
      var where = '';
      if (pos != null) {
        final lat = (data['lat'] as num).toDouble();
        final lng = (data['lng'] as num).toDouble();
        where =
            ' — a ${formatDistance(distanceMeters(pos.latitude, pos.longitude, lat, lng))} verso ${compass(pos.latitude, pos.longitude, lat, lng)}';
      }
      if (mounted) snack(context, '🔔 ${data['uid']} ha suonato la Calmanella$where');
    }
  }

  Future<void> _checkTraps(LocationService loc) async {
    final pos = loc.position;
    if (pos == null || _party == null || _traps.isEmpty) return;
    if (ItemService.isActive((await ItemService.userRef(_uid).get()).data()?['trappedUntil'])) return;
    for (final t in _traps) {
      final d = t.data();
      if (d['ownerUid'] == _uid || _handling.contains(t.id)) continue;
      final dist = distanceMeters(pos.latitude, pos.longitude, (d['lat'] as num).toDouble(), (d['lng'] as num).toDouble());
      if (dist > kTrapRadiusMeters) continue;
      _handling.add(t.id);
      try {
        final hit = await ItemService.triggerTrap(_party!, t.id, _uid);
        if (hit && mounted) {
          snack(context, '⚠️ Sei caduto in una Trappola! Usa una Fune di fuga o perdi $kTrapPenaltyMinutes minuti', error: true);
        }
      } catch (_) {
        _handling.remove(t.id);
      }
    }
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _trapSub?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Si ricostruisce a ogni nuova posizione GPS.
    final loc = context.watch<LocationService>();
    _checkTraps(loc);
    if (loc.error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('📍 ${loc.error}', style: const TextStyle(color: Pal.sub, fontSize: 12)),
      );
    }
    return const SizedBox.shrink();
  }
}
