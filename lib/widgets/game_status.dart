import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../geo.dart';
import '../items.dart';
import '../mode.dart';
import '../table/phases.dart';
import '../table/zones.dart';
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
/// Dal vivo mostra un conto alla rovescia, al tavolo i giri rimasti.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key});

  Widget _chip(IconData icon, Color color, String label, Widget trailing, {Widget? action}) {
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
        trailing,
        if (action != null) ...[const SizedBox(width: 8), action],
      ]),
    );
  }

  /// Timestamp -> conto alla rovescia; numero -> "N giri".
  Widget _time(dynamic v, Color c) {
    final st = TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.bold);
    if (v is Timestamp) return Countdown(v.toDate(), style: st);
    if (!kTableTurns) return Text(untilLabel((v as num).toInt(), TableClock.round), style: st);
    final left = (v as num).toInt() - TableClock.round + 1;
    return Text(left == 1 ? '1 giro' : '$left giri', style: st);
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().userName!;
    return StreamBuilder<Map<String, dynamic>>(
      stream: ItemService.watchUserFields(
          uid, const ['repellentUntil', 'koUntil', 'trappedUntil', 'trappedSkip', 'busyUntil', 'waitUntilAction']),
      builder: (context, snap) {
        final u = snap.data;
        if (u == null) return const SizedBox.shrink();
        final rep = u['repellentUntil'];
        final ko = u['koUntil'];
        final trapUntil = u['trappedUntil'];
        final skip = kTableMode ? ((u['trappedSkip'] as num?) ?? 0).toInt() : 0;
        final busy = kTableMode ? null : u['busyUntil']; // dal vivo: attesa al posto delle azioni

        Future<void> useRope() async {
          try {
            await ItemService.useRopeOnTrap(uid);
            if (context.mounted) snack(context, 'Sei fuggito dalla trappola!');
          } catch (e) {
            if (context.mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
          }
        }

        final rope = TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: const Color(0xFFB5694F)),
          onPressed: useRope,
          child: const Text('Fune di fuga'),
        );

        return Column(children: [
          if (ItemService.isActive(rep))
            _chip(Icons.shield_moon, const Color(0xFF8CD0A8),
                'Repellente attivo: sei nascosto e non puoi combattere', _time(rep, const Color(0xFF3F9F72))),
          if (ItemService.isActive(ko))
            _chip(Icons.healing, const Color(0xFF6CA8F0), 'Pokémon esausto: in recupero', _time(ko, const Color(0xFF2F7FD0))),
          if (skip > 0)
            _chip(Icons.warning_amber_rounded, const Color(0xFFF2A74B),
                'Sei in una Trappola: salterai il prossimo turno', const SizedBox.shrink(),
                action: rope),
          if (kTableMode && !kTableTurns && ItemService.isWaiting(u))
            _chip(Icons.warning_amber_rounded, const Color(0xFFF2A74B),
                'Sei fermo: aspetta che gli altri facciano ancora '
                    '${((u['waitUntilAction'] as num).toInt() - TableClock.actions)} azioni',
                const SizedBox.shrink(),
                action: rope),
          if (!kTableMode && ItemService.isActive(trapUntil))
            _chip(Icons.warning_amber_rounded, const Color(0xFFF2A74B), 'Sei in una Trappola!',
                _time(trapUntil, const Color(0xFFC77D1A)),
                action: rope),
          if (ItemService.isActive(busy))
            _chip(Icons.hourglass_top, Pal.bad, 'In attesa: non puoi cercare, comprare o prendere strumenti',
                _time(busy, Pal.bad)),
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
  StreamSubscription? _userSub, _trapSub, _alarmSub, _eventSub, _noticeSub;
  String? _party;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _traps = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _alarms = [];
  final Set<String> _handling = {};
  final Set<String> _seenEvents = {};
  late final String _uid;
  late final LocationService _loc;
  bool _gps = false; // GPS avviato da questo osservatore (modalità dal vivo)

  @override
  void initState() {
    super.initState();
    _uid = context.read<Session>().userName!;
    _loc = context.read<LocationService>();
    if (!kTableMode) {
      _gps = true;
      _loc.start(_uid);
    }
    _userSub = ItemService.watchUser(_uid).listen((u) {
      final p = u?['actualParty'];
      final party = p is String && p.isNotEmpty ? p : null;
      if (party != _party) _subscribe(party);
    });
  }

  void _subscribe(String? party) {
    _trapSub?.cancel();
    _alarmSub?.cancel();
    _eventSub?.cancel();
    _noticeSub?.cancel();
    _party = party;
    _traps = [];
    _alarms = [];
    if (party == null) return;
    if (!kTableMode) {
      _trapSub = PartyService.party(party)
          .collection('traps')
          .where('active', isEqualTo: true)
          .snapshots()
          .listen((s) {
        _traps = s.docs;
        _checkTraps(context.read<LocationService>());
      });
    }
    if (!kTableMode) {
      _alarmSub = PartyService.party(party)
          .collection('alarms')
          .where('active', isEqualTo: true)
          .snapshots()
          .listen((s) {
        _alarms = s.docs;
        _checkTraps(context.read<LocationService>());
      });
    }
    _eventSub = PartyService.party(party)
        .collection('events')
        .orderBy('at', descending: true)
        .limit(5)
        .snapshots()
        .listen(_onEvents);
    // avvisi segreti delle abilità (Gelata, Vedetta, Mente lucida, Imboscata, Sfida...): solo a chi sono destinati
    _noticeSub = PartyService.party(party).collection('events').where('to', arrayContains: _uid).snapshots().listen((s) {
      for (final d in s.docs) {
        final data = d.data();
        if (data['type'] != 'notice' || !_seenEvents.add('n:${d.id}')) continue;
        final at = data['at'] is Timestamp ? (data['at'] as Timestamp).toDate() : null;
        if (at == null || DateTime.now().difference(at).inSeconds > 60) continue;
        if (mounted) snack(context, '${data['text']}');
      }
    });
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
      if (at == null) continue;
      if (DateTime.now().difference(at).inSeconds > 60) continue;
      if (data['type'] == 'alarm' && data['ownerUid'] == _uid) {
        final pos = context.read<LocationService>().position;
        var where = '';
        if (data['zone'] != null) {
          where = ' in ${zoneSpec('${data['zone']}').name}, settore ${data['sector']}';
        } else if (pos != null && data['lat'] != null) {
          final lat = (data['lat'] as num).toDouble(), lng = (data['lng'] as num).toDouble();
          where = ' a ${formatDistance(distanceMeters(pos.latitude, pos.longitude, lat, lng))} da te';
        }
        if (mounted) snack(context, '🚨 Il tuo Allarme è scattato$where: è passato ${data['uid']}');
        continue;
      }
      if (data['type'] == 'spotted') {
        if ((data['to'] as List? ?? const []).contains(_uid) && mounted) {
          snack(context, '👀 Hai notato ${data['uid']} entrare nel tuo settore '
              '(${zoneSpec('${data['zone']}').name}, settore ${data['sector']}): vediamo se prova a nascondersi…');
        }
        continue;
      }
      if (data['type'] != 'bell' || data['uid'] == _uid) continue;
      final pos = context.read<LocationService>().position;
      var where = '';
      if (data['zone'] != null) {
        // con Ombra (o Depistaggio) si vede solo la zona
        where = data['zone'] == 'fuori'
            ? ' — fuori dalle zone di gioco'
            : ' — in ${zoneSpec('${data['zone']}').name}${data['sector'] == null ? '' : ', settore ${data['sector']}'}';
      } else if (pos != null) {
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
    if (pos == null || _party == null || (_traps.isEmpty && _alarms.isEmpty)) return;
    // a ogni posizione GPS: si usa il profilo già in memoria invece di rileggerlo dal server
    final me = ItemService.lastUser(_uid) ?? (await ItemService.userRef(_uid).get()).data();
    if (ItemService.isActive(me?['stealthUntil'])) return; // Passo felpato
    for (final a in _alarms) {
      final d = a.data();
      final key = 'alarm:${a.id}';
      if (d['ownerUid'] == _uid || _handling.contains(key) || d['lat'] == null) continue;
      final dist = distanceMeters(pos.latitude, pos.longitude, (d['lat'] as num).toDouble(), (d['lng'] as num).toDouble());
      if (dist > kTrapRadiusMeters) continue;
      _handling.add(key);
      try {
        await ItemService.triggerAlarm(_party!, a.id, _uid);
      } catch (_) {
        _handling.remove(key);
      }
    }
    if (ItemService.isActive(me?['trappedUntil'])) return;
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
    _alarmSub?.cancel();
    _eventSub?.cancel();
    _noticeSub?.cancel();
    // passando al tavolo (o uscendo) il GPS non serve più
    if (_gps) _loc.stop();
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
