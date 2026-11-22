/// Le 8 macro-zone della mappa da tavolo: un Hub centrale e 7 biomi.
/// `type` = tipo dominante del bioma (colori, capi di zona, leggendari).
/// `sectors` = numero di settori in cui è divisa la zona (MODIFICALO in base alla tua mappa).
class ZoneSpec {
  final String id;
  final String name;
  final String type;
  final int sectors;
  final List<String> legendaries;
  const ZoneSpec(this.id, this.name, this.type, this.sectors, this.legendaries);
}

const List<ZoneSpec> kZones = [
  ZoneSpec('hub', 'Hub centrale', 'Normale', 4, ['Mewtwo']),
  ZoneSpec('canyon', 'Canyon', 'Roccia', 4, ['Regirock', 'Landorus']),
  ZoneSpec('giungla', 'Giungla', 'Erba', 4, ['Celebi', 'Virizion']),
  ZoneSpec('neve', 'Regione innevata', 'Ghiaccio', 4, ['Articuno', 'Regice']),
  ZoneSpec('vulcano', 'Vulcano', 'Fuoco', 4, ['Moltres', 'Entei', 'Reshiram']),
  ZoneSpec('campi', 'Campi e fattoria', 'Normale', 4, ['Mew', 'Shaymin']),
  ZoneSpec('isola', 'Isola dei relitti', 'Acqua', 4, ['Kyogre', 'Suicune']),
  ZoneSpec('colline', 'Colline ventose', 'Volante', 4, ['Zapdos', 'Lugia', 'Rayquaza']),
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
