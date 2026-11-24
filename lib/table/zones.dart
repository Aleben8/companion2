import '../mode.dart';

/// Le 8 macro-zone della mappa da tavolo: un Hub centrale e 7 biomi.
/// `type` = tipo dominante del bioma (colori, capi di zona, leggendari).
/// Il numero di settori e il loro tipo stanno in [kDefaultSectors] e li può cambiare il Master
/// (riquadro Master > "Settori delle zone"): [sectors] legge sempre la disposizione in uso.
class ZoneSpec {
  final String id;
  final String name;
  final String type;
  final List<String> legendaries;
  const ZoneSpec(this.id, this.name, this.type, this.legendaries);

  /// Numero di settori della zona nella partita corrente (dal vivo sono sempre i 4 spicchi N/E/S/O).
  int get sectors => TableLayout.count(id);
}

const List<ZoneSpec> kZones = [
  ZoneSpec('hub', 'Hub centrale', 'Normale', ['Mewtwo']),
  ZoneSpec('canyon', 'Canyon', 'Roccia', ['Regirock', 'Landorus']),
  ZoneSpec('giungla', 'Giungla', 'Erba', ['Celebi', 'Virizion']),
  ZoneSpec('neve', 'Regione innevata', 'Ghiaccio', ['Articuno', 'Regice']),
  ZoneSpec('vulcano', 'Vulcano', 'Fuoco', ['Moltres', 'Entei', 'Reshiram']),
  ZoneSpec('campi', 'Campi e fattoria', 'Normale', ['Mew', 'Shaymin']),
  ZoneSpec('isola', 'Isola dei relitti', 'Acqua', ['Kyogre', 'Suicune']),
  ZoneSpec('colline', 'Colline ventose', 'Volante', ['Zapdos', 'Lugia', 'Rayquaza']),
];

/// Collegamenti PROPOSTI tra le zone (letti dalla mappa). Il Master li può cambiare dal riquadro
/// "Collegamenti tra zone" della tab Tavolo: qui c'è solo il punto di partenza.
const List<List<String>> kDefaultLinks = [
  ['hub', 'canyon'],
  ['hub', 'giungla'],
  ['hub', 'neve'],
  ['hub', 'campi'],
  ['hub', 'isola'],
  ['giungla', 'vulcano'],
  ['giungla', 'neve'],
  ['giungla', 'colline'],
  ['neve', 'campi'],
  ['canyon', 'colline'],
];

ZoneSpec zoneSpec(String id) => kZones.firstWhere((z) => z.id == id, orElse: () => kZones.first);

// =============================================================================
//  Settori
// =============================================================================

/// Tipo di un settore (effetti in `lib/table/sectors.dart`).
enum SectorType { cittadino, selvaggio, impervio, rifugio, passaggio }

/// Disposizione PROPOSTA: 30 settori in tutto. Il Master la cambia dal riquadro Master.
const Map<String, List<SectorType>> kDefaultSectors = {
  'hub': [SectorType.cittadino, SectorType.cittadino, SectorType.cittadino, SectorType.rifugio, SectorType.passaggio],
  'giungla': [SectorType.cittadino, SectorType.rifugio, SectorType.passaggio, SectorType.selvaggio],
  'canyon': [SectorType.cittadino, SectorType.rifugio, SectorType.passaggio, SectorType.impervio],
  'neve': [SectorType.cittadino, SectorType.rifugio, SectorType.passaggio, SectorType.impervio],
  'vulcano': [SectorType.cittadino, SectorType.rifugio, SectorType.passaggio, SectorType.impervio],
  'campi': [SectorType.cittadino, SectorType.rifugio, SectorType.passaggio],
  'colline': [SectorType.cittadino, SectorType.rifugio, SectorType.passaggio],
  'isola': [SectorType.cittadino, SectorType.rifugio, SectorType.passaggio],
};

const int kMinSectors = 1;
const int kMaxSectors = 8;
const int kLiveSectors = 4; // dal vivo: i 4 spicchi del cerchio

/// Disposizione dei settori e biomi della partita corrente (tavolo).
/// La aggiorna in tempo reale l'osservatore della tab Tavolo dallo stato della partita
/// (o, prima dell'avvio, dal documento del party); i servizi la ricaricano con `TableService.loadLayout`.
class TableLayout {
  static Map<String, List<SectorType>> sectors = kDefaultSectors;

  /// Zone in gioco (l'Hub c'è sempre). null = tutte (es. partita avviata prima dei biomi, o dal vivo).
  static Set<String>? biomes;

  static int count(String zone) => kTableMode ? (sectors[zone] ?? kDefaultSectors[zone] ?? const []).length : kLiveSectors;

  /// Tipo del settore [n] (1..N) della zona; null dal vivo o se il settore non esiste.
  static SectorType? typeOf(String zone, int n) {
    if (!kTableMode) return null;
    final list = sectors[zone] ?? kDefaultSectors[zone] ?? const [];
    return n >= 1 && n <= list.length ? list[n - 1] : null;
  }

  /// Primo settore di quel tipo nella zona (es. il passaggio dove arrivano Biglietto, treno e traghetto).
  static int? firstOf(String zone, SectorType t) {
    final list = sectors[zone] ?? kDefaultSectors[zone] ?? const [];
    final i = list.indexOf(t);
    return i < 0 ? null : i + 1;
  }

  static bool inPlay(String zone) => !kTableMode || biomes == null || biomes!.contains(zone);

  static List<ZoneSpec> get zonesInPlay => [for (final z in kZones) if (inPlay(z.id)) z];

  // ---- conversione da/per Firestore: { zoneId: ['cittadino', ...] }
  static Map<String, List<SectorType>> parse(dynamic raw) {
    if (raw is! Map) return kDefaultSectors;
    final out = <String, List<SectorType>>{...kDefaultSectors};
    raw.forEach((k, v) {
      if (v is List && v.isNotEmpty) {
        out['$k'] = [for (final s in v) SectorType.values.firstWhere((t) => t.name == '$s', orElse: () => SectorType.cittadino)];
      }
    });
    return out;
  }

  static Map<String, List<String>> encode(Map<String, List<SectorType>> l) =>
      {for (final e in l.entries) e.key: [for (final t in e.value) t.name]};
}

