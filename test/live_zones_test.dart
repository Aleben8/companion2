import 'package:companion2/services/live_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Canyon centrato a Varese, raggio 100 m; Hub vicino che si sovrappone in parte.
  const canyon = LiveZone('canyon', 45.8190, 8.8250, 100);
  const hub = LiveZone('hub', 45.8190, 8.8270, 100);
  final zones = {'canyon': canyon, 'hub': hub};
  const dLat = 0.0005; // ~55 m
  const dLng = 0.0007; // ~55 m a questa latitudine

  test('i 4 settori sono Nord, Est, Sud, Ovest', () {
    final only = {'canyon': canyon};
    expect(LiveService.locate(only, canyon.lat + dLat, canyon.lng), {'zone': 'canyon', 'sector': 1});
    expect(LiveService.locate(only, canyon.lat, canyon.lng + dLng), {'zone': 'canyon', 'sector': 2});
    expect(LiveService.locate(only, canyon.lat - dLat, canyon.lng), {'zone': 'canyon', 'sector': 3});
    expect(LiveService.locate(only, canyon.lat, canyon.lng - dLng), {'zone': 'canyon', 'sector': 4});
  });

  test('fuori da tutti i cerchi non sei in nessuna zona', () {
    expect(LiveService.locate(zones, 45.83, 8.80), isNull);
  });

  test('dove due zone si sovrappongono vince il centro più vicino', () {
    expect(LiveService.locate(zones, 45.8190, 8.8262)?['zone'], 'hub');
    expect(LiveService.locate(zones, 45.8190, 8.8258)?['zone'], 'canyon');
  });

  test('etichette dei settori', () {
    expect(LiveService.sectorLabel('canyon', 2), 'settore 2 (Est)');
  });
}
