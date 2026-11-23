import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../geo.dart';
import '../mode.dart';
import '../table/zones.dart';
import 'item_service.dart';
import 'party_service.dart';
import 'shared_stream.dart';

/// Una zona del gioco dal vivo: un cerchio sulla mappa posizionato dal Master.
class LiveZone {
  final String id;
  final double lat, lng, radius;
  const LiveZone(this.id, this.lat, this.lng, this.radius);
}

/// Il tavolo portato dal vivo.
///
/// Le zone del tavolo (Hub, Canyon, ...) diventano cerchi sulla mappa e i settori i 4 spicchi
/// del cerchio (1 Nord, 2 Est, 3 Sud, 4 Ovest). La zona e il settore in cui ti trovi vengono
/// ricavati dal GPS e scritti in `Users/{uid}.pos`, lo stesso campo del tavolo: così empori,
/// eventi, leggendario, protezioni e bonus di tipo funzionano allo stesso modo.
///
/// Firestore:
///   Party/{codice}.liveZones       -> { zoneId: {lat, lng, r} }
///   Party/{codice}.roundMinutes    -> durata di un giro (minuti)
///   Party/{codice}/table/state     -> { ..., roundMinutes, roundStartedAt }   (orologio dal vivo)
///   Users/{uid}.busyUntil          -> attesa in corso (al posto delle azioni)
///   Users/{uid}.searchReadyAt      -> quando si può cercare di nuovo
class LiveService {
  static Map<String, LiveZone> zonesOf(Map<String, dynamic>? party) {
    final raw = party?['liveZones'];
    if (raw is! Map) return {};
    final out = <String, LiveZone>{};
    raw.forEach((k, v) {
      if (v is Map && v['lat'] is num && v['lng'] is num) {
        out['$k'] = LiveZone('$k', (v['lat'] as num).toDouble(), (v['lng'] as num).toDouble(),
            (v['r'] as num?)?.toDouble() ?? kDefaultZoneRadius);
      }
    });
    return out;
  }

  static Stream<Map<String, LiveZone>> watchZones(String party) =>
      shared('liveZones:$party', () => PartyService.watchParty(party).map(zonesOf));

  static Future<Map<String, LiveZone>> zones(String party) async =>
      zonesOf((await PartyService.party(party).get()).data());

  /// Master: posiziona (o sposta) una zona sulla mappa.
  static Future<void> setZone(String party, String zoneId, double lat, double lng, double radius) =>
      PartyService.party(party).set({
        'liveZones': {zoneId: {'lat': lat, 'lng': lng, 'r': radius}},
      }, SetOptions(merge: true));

  static Future<void> setRadius(String party, String zoneId, double radius) =>
      PartyService.party(party).update({'liveZones.$zoneId.r': radius});

  static Future<void> removeZone(String party, String zoneId) =>
      PartyService.party(party).update({'liveZones.$zoneId': FieldValue.delete()});

  /// Zone del tavolo che il Master non ha ancora posizionato.
  static List<ZoneSpec> missing(Map<String, LiveZone> zones) => [for (final z in kZones) if (!zones.containsKey(z.id)) z];

  /// Zona e settore che contengono il punto (la zona col centro più vicino, se si sovrappongono).
  static Map<String, dynamic>? locate(Map<String, LiveZone> zones, double lat, double lng) {
    LiveZone? best;
    var bestD = double.infinity;
    for (final z in zones.values) {
      final d = distanceMeters(lat, lng, z.lat, z.lng);
      if (d <= z.radius && d < bestD) {
        best = z;
        bestD = d;
      }
    }
    if (best == null) return null;
    const n = kLiveSectors;
    final deg = bearingDegrees(best.lat, best.lng, lat, lng);
    final sector = ((deg + 180 / n) % 360) ~/ (360 / n) + 1;
    return {'zone': best.id, 'sector': min(sector, n)};
  }

  /// "settore 2 (Est)": con 4 settori sono i punti cardinali.
  static String sectorLabel(String zoneId, dynamic sector) {
    final s = sector is num ? sector.toInt() : int.tryParse('$sector') ?? 0;
    if (s < 1 || s > kLiveSectors) return 'settore $s';
    return 'settore $s (${const ['Nord', 'Est', 'Sud', 'Ovest'][s - 1]})';
  }

  // ------------------------------------------------------------- attese

  static DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : null;

  /// Tempo che manca alla fine di un'attesa (null se non c'è).
  static Duration? left(dynamic until) {
    final t = _ts(until);
    if (t == null) return null;
    final d = t.difference(DateTime.now());
    return d.isNegative ? null : d;
  }

  static String fmt(Duration d) {
    final s = d.inSeconds;
    return s >= 60 ? '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} min' : '$s s';
  }

  /// Dal vivo: blocca le azioni se c'è un'attesa in corso (bufera, eruzione...).
  static void assertNotBusy(Map<String, dynamic>? user) {
    final d = left(user?['busyUntil']);
    if (d != null) throw Exception('Sei in attesa: puoi agire di nuovo tra ${fmt(d)}');
  }

  /// Aggiunge [minutes] di attesa (si somma a quella già in corso).
  static Map<String, dynamic> addBusy(Map<String, dynamic>? user, int minutes) {
    final base = _ts(user?['busyUntil']);
    final from = base != null && base.isAfter(DateTime.now()) ? base : DateTime.now();
    return {'busyUntil': Timestamp.fromDate(from.add(Duration(minutes: minutes)))};
  }

  /// Clessidra dal vivo: azzera le attese.
  static Future<void> clearWaits(String uid) => ItemService.userRef(uid).set({
        'busyUntil': FieldValue.delete(),
        'searchReadyAt': FieldValue.delete(),
      }, SetOptions(merge: true));
}
