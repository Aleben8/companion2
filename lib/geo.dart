import 'dart:math';

/// Distanza in metri tra due coordinate (formula di Haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = pow(sin(dLat / 2), 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLng / 2), 2);
  return 2 * r * asin(min(1.0, sqrt(a)));
}

/// Direzione (N, NE, E, SE, S, SO, O, NO) per andare dal punto 1 al punto 2.
String compass(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * pi / 180;
  final y = sin(rad(lng2 - lng1)) * cos(rad(lat2));
  final x = cos(rad(lat1)) * sin(rad(lat2)) -
      sin(rad(lat1)) * cos(rad(lat2)) * cos(rad(lng2 - lng1));
  final deg = (atan2(y, x) * 180 / pi + 360) % 360;
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
  return names[((deg + 22.5) ~/ 45) % 8];
}

String formatDistance(double m) =>
    m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

String formatAge(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} s fa';
  if (d.inMinutes < 60) return '${d.inMinutes} min fa';
  return '${d.inHours} h fa';
}
