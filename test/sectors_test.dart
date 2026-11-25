import 'package:companion2/services/table_service.dart';
import 'package:companion2/table/sectors.dart';
import 'package:companion2/table/zones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    TableLayout.sectors = kDefaultSectors;
    TableLayout.biomes = null;
  });

  test('distribuzione di partenza: 30 settori come da tabella', () {
    expect(kDefaultSectors.values.fold<int>(0, (a, l) => a + l.length), 30);
    int n(String z, SectorType t) => kDefaultSectors[z]!.where((s) => s == t).length;
    expect(kDefaultSectors['hub']!.length, 5);
    expect(n('hub', SectorType.cittadino), 3);
    expect(n('giungla', SectorType.selvaggio), 1);
    for (final z in ['canyon', 'neve', 'vulcano']) {
      expect(n(z, SectorType.impervio), 1, reason: z);
    }
    for (final z in kZones) {
      expect(n(z.id, SectorType.passaggio), 1, reason: 'ogni zona ha un passaggio');
      expect(n(z.id, SectorType.rifugio), 1, reason: 'ogni zona ha un rifugio');
    }
  });

  test('i settori arrivano dal Master (e si salvano/leggono uguali)', () {
    final custom = {...kDefaultSectors, 'campi': [SectorType.selvaggio, SectorType.passaggio]};
    final back = TableLayout.parse(TableLayout.encode(custom));
    expect(back['campi'], [SectorType.selvaggio, SectorType.passaggio]);
    TableLayout.sectors = back;
    expect(zoneSpec('campi').sectors, 2);
    expect(TableService.arrivalSector('campi'), 2);
  });

  test('forza delle tracce: base 1, ben visibile +1, cittadino −1 (minimo 1), impervio e passaggio +1', () {
    expect(traceStrength(SectorType.selvaggio), 1);
    expect(traceStrength(SectorType.cittadino), 1);
    expect(traceStrength(SectorType.impervio), 2);
    expect(traceStrength(SectorType.passaggio, visible: true), 3);
    expect(traceStrength(SectorType.cittadino, visible: true), 1);
  });

  test('CD dei locali secondo il settore', () {
    expect(TableService.localsCd(SectorType.cittadino), kLocalsBaseCd - 2);
    expect(TableService.localsCd(SectorType.rifugio), kLocalsBaseCd - 1);
    expect(TableService.localsCd(SectorType.impervio), kLocalsBaseCd + 2);
    expect(TableService.localsCd(SectorType.passaggio), kLocalsBaseCd);
  });

  test('biomi: Hub sempre, poi giocatori + 1 (al massimo tutti e 7)', () {
    for (final p in [2, 4, 6, 9]) {
      final b = TableService.drawBiomes(p);
      expect(b.first, 'hub');
      expect(b.length, 1 + (p + 1).clamp(0, 7), reason: '$p giocatori');
      expect(b.toSet().length, b.length);
    }
  });

  test('biomi isolati: l’Hub deve raggiungerli con i collegamenti', () {
    final links = TableService.defaultLinks;
    expect(TableService.unreachableBiomes({'hub', 'giungla', 'vulcano'}, links), isEmpty);
    // il Vulcano si raggiunge solo dalla Giungla: senza Giungla è isolato
    expect(TableService.unreachableBiomes({'hub', 'canyon', 'vulcano'}, links), ['vulcano']);
  });

  test('impervio: +1 azione per entrare nel settore', () {
    const events = <Map<String, dynamic>>[];
    expect(TableService.moveCost(events, 'hub', 'canyon', sector: 1), 1);
    expect(TableService.moveCost(events, 'hub', 'canyon', sector: 4), 1 + kImperviousExtraCost);
  });

  test('furtività: CD = base + settore + percezione (Difesa Speciale × 0.5)', () {
    expect(stealthCd(SectorType.cittadino, 0), kStealthBaseCd - 2);
    expect(stealthCd(SectorType.rifugio, 10), kStealthBaseCd + 2 + 5);
    expect(stealthCd(SectorType.passaggio, 15), kStealthBaseCd + 1 + 7);
    expect(dexterityBonus(15), 7); // Velocità × 0.5
    expect(dexterityBonus(0), 0);
  });

  test('Biglietto: dalla zona isolata si torna gratis alla zona di partenza', () {
    final pos = {'zone': 'vulcano', 'sector': TableService.arrivalSector('vulcano')};
    bool reach(String to, String? free) => TableService.canReach(
        state: null, events: const [], pos: pos, to: to, actionsLeft: 2, tickets: 0, freeReturn: free);
    expect(TableService.freeReturnZone({'from': 'hub', 'at': 'vulcano'}, pos), 'hub');
    expect(TableService.freeReturnZone({'from': 'hub', 'at': 'neve'}, pos), isNull);
    expect(reach('hub', null), isFalse); // non collegata e senza Biglietti
    expect(reach('hub', 'hub'), isTrue); // ritorno gratis
    expect(reach('canyon', 'hub'), isFalse); // il ritorno vale solo verso la zona di partenza
  });
}
