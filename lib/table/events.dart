/// Eventi di zona. Ogni evento è una scheda di dati: la app li applica da sola.
///
/// Fasi: scheduled (pianificato) -> announced (annunciato 1 giro prima)
///       -> active (in corso per [duration] giri) -> ended.
class ZoneEventDef {
  final String id;
  final String zone; // '' = scelta a caso all'avvio (leggendario)
  final String name;
  final String announce; // testo dell'annuncio
  final String active; // testo quando l'evento è in corso
  final String table; // cosa fare sul tabellone
  final int duration; // giri di durata
  final int moveExtra; // azioni in più per ENTRARE nella zona
  final int blockSectors; // quanti settori vengono bloccati
  final int actionPenalty; // azioni perse al prossimo turno da chi è nella zona all'inizio
  final Map<String, int> typeBonus; // bonus di danno per tipo di mossa, nelle battaglie in zona
  final bool hideRadar; // chi è nella zona è invisibile al Radar
  final bool claimItem; // chi è nella zona può prendere uno strumento
  final List<String>? claimPool; // strumenti possibili (null = tutti)
  final bool legendary;
  final bool passage; // mentre è attivo, dalla zona dell'evento si va in qualsiasi zona
  const ZoneEventDef({
    required this.id,
    this.zone = '',
    required this.name,
    required this.announce,
    required this.active,
    required this.table,
    this.duration = 2,
    this.moveExtra = 0,
    this.blockSectors = 0,
    this.actionPenalty = 0,
    this.typeBonus = const {},
    this.hideRadar = false,
    this.claimItem = false,
    this.claimPool,
    this.legendary = false,
    this.passage = false,
  });
}

// ---- Quanti eventi e quando (modificali qui) -------------------------------
const int kEventsPerGame = 5; // eventi di zona estratti a caso (più 1 leggendario)
const int kFirstEventRound = 3; // il primo evento parte al giro 3...
const int kEventGap = 2; // ...e poi uno ogni 2 giri (in ordine casuale)
const int kLegendaryStatPoints = 38; // forza del leggendario (i giocatori ne hanno 30)

const List<ZoneEventDef> kZoneEventDefs = [
  ZoneEventDef(
    id: 'hub_mercato',
    zone: 'hub',
    name: 'Mercato in città',
    announce: 'Si sente un gran trambusto in città: sta per aprire un mercato.',
    active: 'Il mercato è aperto! Chi è nell’Hub può prendere uno strumento (una volta sola).',
    table: 'Metti il segnalino mercato sull’Hub.',
    claimItem: true,
  ),
  ZoneEventDef(
    id: 'canyon_frana',
    zone: 'canyon',
    name: 'Frana nel Canyon',
    announce: 'Il terreno del Canyon trema: attenti ai massi…',
    active: 'È crollata una frana: alcuni settori del Canyon sono bloccati.',
    table: 'Copri i settori bloccati con i segnalini roccia.',
    blockSectors: 2,
  ),
  ZoneEventDef(
    id: 'giungla_nebbia',
    zone: 'giungla',
    name: 'Nebbia fitta',
    announce: 'Una nebbia densa sale dalla Giungla…',
    active: 'La nebbia nasconde chi è nella Giungla: il Radar non li vede.',
    table: 'Metti il segnalino nebbia sulla Giungla.',
    hideRadar: true,
  ),
  ZoneEventDef(
    id: 'neve_bufera',
    zone: 'neve',
    name: 'Bufera di neve',
    announce: 'Il cielo si fa grigio sulla Regione innevata…',
    active: 'Infuria la bufera: entrare nella Regione innevata costa 1 azione in più.',
    table: 'Metti il segnalino bufera sulla Regione innevata.',
    moveExtra: 1,
  ),
  ZoneEventDef(
    id: 'vulcano_eruzione',
    zone: 'vulcano',
    name: 'Il vulcano erutta',
    announce: 'Il vulcano brontola…',
    active: 'Eruzione! Entrare costa 1 azione in più, le mosse Fuoco fanno +1 danno e chi è nella zona perde 1 azione al prossimo turno.',
    table: 'Metti il segnalino eruzione sul Vulcano.',
    moveExtra: 1,
    actionPenalty: 1,
    typeBonus: {'Fuoco': 1},
  ),
  ZoneEventDef(
    id: 'campi_raccolto',
    zone: 'campi',
    name: 'Raccolto abbondante',
    announce: 'I contadini preparano il raccolto…',
    active: 'Raccolto! Chi è nei Campi può prendere uno strumento (una volta sola).',
    table: 'Metti il segnalino raccolto sui Campi.',
    claimItem: true,
    claimPool: ['pozione', 'caramella', 'revitalizzante'],
  ),
  ZoneEventDef(
    id: 'isola_marea',
    zone: 'isola',
    name: 'Alta marea',
    announce: 'Il mare si ritira e si prepara a tornare con forza…',
    active: 'Alta marea: alcuni settori dell’Isola sono sommersi.',
    table: 'Copri i settori sommersi con i segnalini onda.',
    blockSectors: 2,
  ),
  ZoneEventDef(
    id: 'hub_treno',
    zone: 'hub',
    name: 'Treno straordinario',
    announce: 'In stazione si parla di un treno speciale in partenza…',
    active: 'Il treno è in stazione! Chi è nell’Hub può raggiungere qualsiasi zona senza Biglietto.',
    table: 'Metti il segnalino treno sull’Hub.',
    passage: true,
  ),
  ZoneEventDef(
    id: 'isola_traghetto',
    zone: 'isola',
    name: 'Traghetto dei relitti',
    announce: 'Una sirena si sente dal porto: sta per salpare un traghetto…',
    active: 'Il traghetto è al molo! Chi è all’Isola dei relitti può raggiungere qualsiasi zona senza Biglietto.',
    table: 'Metti il segnalino traghetto sull’Isola dei relitti.',
    passage: true,
  ),
  ZoneEventDef(
    id: 'colline_tempesta',
    zone: 'colline',
    name: 'Tempesta elettrica',
    announce: 'Nubi cariche di elettricità si addensano sulle Colline…',
    active: 'Tempesta! Nelle Colline le mosse Elettro fanno +2 danno e le Volante +1.',
    table: 'Metti il segnalino tempesta sulle Colline.',
    typeBonus: {'Elettro': 2, 'Volante': 1},
  ),
];

const ZoneEventDef kLegendaryDef = ZoneEventDef(
  id: 'leggendario',
  name: 'Risveglio leggendario',
  announce: 'Un’energia antica si risveglia in {zone}…',
  active: 'Un Pokémon leggendario è apparso in {zone}! Chi è lì può sfidarlo: il primo a batterlo vince una ricompensa.',
  table: 'Metti il segnalino leggendario nella zona indicata.',
  legendary: true,
);

ZoneEventDef eventDef(String id) =>
    id == kLegendaryDef.id ? kLegendaryDef : kZoneEventDefs.firstWhere((d) => d.id == id);
