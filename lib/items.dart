import 'package:flutter/material.dart';

import 'mode.dart';

/// Identificatori degli strumenti (chiavi usate in Firestore: Users/{u}.inventory).
enum ItemId {
  // strumenti base
  repellente, caramella, fune, trappola, pozione, calmanella, revitalizzante, radar,
  // esplorazione
  lente, sensore, allarme, meteo, passoFelpato, clessidra, chiave,
  // battaglia
  elisir, superPozione, antidoto, amuleto, guanto,
  // protezioni di bioma (si comprano nell'emporio della zona)
  corda, bussola, tutaNeve, tutaIgnifuga, zattera, parafulmine,
  // trasporti
  biglietto,
}

enum ItemCategory { esplorazione, battaglia, zona }

extension ItemCategoryX on ItemCategory {
  String get label => switch (this) {
        ItemCategory.esplorazione => 'Esplorazione',
        ItemCategory.battaglia => 'Battaglia',
        ItemCategory.zona => 'Protezioni di zona',
      };
}

class ItemDef {
  final ItemId id;
  final String name;
  final String tableDescription;
  final String tableUsage; // dove/come si usa
  final String? liveDescription; // testo dal vivo, se diverso da quello del tavolo
  final String? liveUsage;
  final List<Color> colors;
  final ItemCategory category;
  final int price; // monete all'emporio
  final IconData icon; // usata se manca lo sprite in assets/images/items/
  final bool tableOnly; // ha senso solo al tavolo (es. Biglietto: dal vivo non ci sono collegamenti)
  final int rarity; // 3 comune, 2 non comune, 1 raro (peso nei premi casuali)
  final String? zone; // protezione di bioma: zona che protegge
  const ItemDef(
    this.id,
    this.name,
    this.tableDescription,
    this.tableUsage,
    this.colors, {
    this.liveDescription,
    this.liveUsage,
    this.category = ItemCategory.esplorazione,
    this.price = 3,
    this.icon = Icons.inventory_2,
    this.tableOnly = false,
    this.rarity = 2,
    this.zone,
  });

  /// Testi della modalità corrente (il Master può cambiarla a partita in corso).
  String get description => kTableMode ? tableDescription : liveDescription ?? tableDescription;
  String get usage => kTableMode ? tableUsage : liveUsage ?? tableUsage;

  String get key => id.name;
  String get asset => 'assets/images/items/$key.png';
}

// ---- Regole numeriche (modificale qui) -------------------------------------
const int kRepellentMinutes = 10; // durata del Repellente
const int kTrapPenaltyMinutes = 5; // tempo perso se cadi in una Trappola
const int kKoMinutes = 5; // tempo di recupero dopo una sconfitta
const int kFleeBlockMinutes = 10; // dopo una fuga le due squadre non possono scontrarsi
const int kPotionHeal = 10; // PS curati dalla Pozione
const int kCandyBonus = 4; // bonus al dado della Caramella Rara
const double kTrapRadiusMeters = 30; // raggio di attivazione della Trappola

// ---- Economia e borsa -------------------------------------------------------
const int kBagLimit = 12; // oggetti massimi in borsa (somma delle quantità)
const int kStartingCoins = 5;
const int kCoinsPvpWin = 3; // vittoria contro un altro giocatore
const int kCoinsGymWin = 5; // prima vittoria contro un capopalestra
const int kCoinsLegendary = 10;
const int kCoinsDeclare = 2; // dichiarare un indizio
const int kCoinsWild = 2; // vittoria contro un Pokémon selvatico (settore selvaggio)
const double kSearchItemChance = 0.15; // "Cerca" senza indizi: probabilità di trovare uno strumento
const double kPvpDropChance = 0.4; // vittoria PvP: probabilità di uno strumento

// ---- Nuovi effetti ---------------------------------------------------------------
const int kEnergyElixir = 5; // Elisir
const int kSuperPotionHeal = 20; // Super Pozione
const int kGloveDamage = 2; // Guanto
const double kSensorRadiusMeters = 50; // Sensore dal vivo
const double kLensRadiusMeters = 50; // Lente dal vivo
const int kLensMinutes = 20; // quanto vecchie possono essere le tracce (dal vivo)
const int kStealthMinutes = 5; // Passo felpato dal vivo
const int kStealthRounds = 1; // Passo felpato al tavolo (fino a fine giro)
const int kShieldRounds = 2; // protezione di zona: giro corrente + il successivo
const int kWeatherLookahead = 2; // Radar meteo: giri guardati in avanti

// Al tavolo le durate sono in GIRI (un giro = tutti i giocatori hanno giocato)
const int kRepellentRounds = 2;
const int kKoRounds = 1;
const int kFleeBlockRounds = 2;

/// Dotazione iniziale: ogni giocatore parte con tutti gli strumenti.
const Map<ItemId, int> kStartingInventory = {
  ItemId.repellente: 1,
  ItemId.caramella: 1,
  ItemId.fune: 1,
  ItemId.trappola: 1,
  ItemId.pozione: 1,
  ItemId.calmanella: 1,
  ItemId.revitalizzante: 1,
  ItemId.radar: 1,
};

/// Ricette di crafting (dalla Borsa/Emporio): ingredienti -> risultato.
class Recipe {
  final Map<ItemId, int> inputs;
  final ItemId output;
  const Recipe(this.inputs, this.output);
}

const List<Recipe> kRecipes = [
  Recipe({ItemId.pozione: 2}, ItemId.superPozione),
  Recipe({ItemId.caramella: 2}, ItemId.guanto),
  Recipe({ItemId.pozione: 1, ItemId.elisir: 1}, ItemId.revitalizzante),
];

/// Assortimento base di ogni emporio locale (più la protezione del suo bioma).
const List<ItemId> kBasicStock = [ItemId.pozione, ItemId.fune, ItemId.antidoto, ItemId.elisir, ItemId.sensore];

/// Protezione venduta nell'emporio di ogni zona (hub e campi non hanno eventi dannosi).
const Map<String, ItemId> kZoneShield = {
  'canyon': ItemId.corda,
  'giungla': ItemId.bussola,
  'neve': ItemId.tutaNeve,
  'vulcano': ItemId.tutaIgnifuga,
  'isola': ItemId.zattera,
  'colline': ItemId.parafulmine,
};

const List<ItemDef> kItems = [
  ItemDef(
    ItemId.repellente,
    'Repellente',
    'La posizione del tuo party sarà nascosta al resto dei giocatori per $kRepellentRounds giri. '
        'Durante questo tempo non potete essere ingaggiati in scontri.',
    'Si usa dallo zaino.',
    [Color(0xFF5A9E88), Color(0xFF8CD0A8)],
    liveDescription: 'La localizzazione del tuo party sarà nascosta al resto dei giocatori per $kRepellentMinutes minuti. '
        'Durante questo tempo non potete essere ingaggiati in scontri.',
    price: 4, icon: Icons.shield_outlined, rarity: 2,
  ),
  ItemDef(
    ItemId.caramella,
    'Caramella Rara',
    'I tiri di un solo giocatore e per un solo scontro saranno aumentati di $kCandyBonus. '
        "L'utilizzo deve essere dichiarato prima dello scontro.",
    'Si usa in battaglia, prima del primo turno.',
    [Color(0xFFF28AA8), Color(0xFFF7B3C6)],
    category: ItemCategory.battaglia, price: 4, icon: Icons.cake, rarity: 2,
  ),
  ItemDef(
    ItemId.fune,
    'Fune di fuga',
    'Potrai uscire da uno scontro: la battaglia termina all’istante e il party deve allontanarsi in una '
        'direzione casuale. Si applica la regola del doppio scontro: le due squadre non potranno '
        'scontrarsi subito dopo.',
    'Si usa in battaglia, oppure quando cadi in una Trappola.',
    [Color(0xFFB5694F), Color(0xFFD9A07A)],
    category: ItemCategory.battaglia, price: 3, icon: Icons.logout, rarity: 3,
  ),
  ItemDef(
    ItemId.trappola,
    'Trappola',
    'Posizionala nel tuo settore. Il primo party avversario che entrerà nel settore dovrà usare '
        'una Fune di fuga o salterà il prossimo turno.',
    'Si usa dalla borsa: la trappola viene piazzata nel settore in cui ti trovi.',
    [Color(0xFF6B5B95), Color(0xFFA79BD0)],
    liveDescription: 'Posizionala dove preferisci. Il primo party avversario che si avvicinerà alla zona dovrà usare '
        'una Fune di fuga o perderà $kTrapPenaltyMinutes minuti.',
    liveUsage: 'Si usa dallo zaino: la trappola viene piazzata nella tua posizione.',
    price: 3, icon: Icons.warning_amber, rarity: 3,
  ),
  ItemDef(
    ItemId.pozione,
    'Pozione',
    'Il Pokémon bersaglio recupera $kPotionHeal punti vita. Se usata durante uno scontro, '
        "l'utilizzo richiede un turno.",
    'Si usa dalla borsa o in battaglia (richiede un turno).',
    [Color(0xFF3C7BD1), Color(0xFF6CA8F0)],
    category: ItemCategory.battaglia, price: 3, icon: Icons.local_pharmacy, rarity: 3,
  ),
  ItemDef(
    ItemId.calmanella,
    'Calmanella',
    'Utilizzando la Calmanella, rivelerai la tua zona e il tuo settore agli altri giocatori.',
    'Si usa dallo zaino.',
    [Color(0xFFE5644E), Color(0xFFF0A060)],
    liveDescription: 'Utilizzando la Calmanella, rivelerai la tua posizione attuale agli altri giocatori.',
    price: 2, icon: Icons.notifications, rarity: 3,
  ),
  ItemDef(
    ItemId.revitalizzante,
    'Revitalizzante',
    'Il tuo Pokémon sconfitto recupera subito tutti i punti vita: non perdi il turno di recupero.',
    'Si usa dallo zaino, quando il tuo Pokémon è esausto.',
    [Color(0xFF5FA8E0), Color(0xFFB4DDF5)],
    liveDescription: 'Il tuo Pokémon sconfitto recupera subito tutti i punti vita: non perdi i $kKoMinutes minuti di recupero.',
    category: ItemCategory.battaglia, price: 5, icon: Icons.favorite, rarity: 2,
  ),
  ItemDef(
    ItemId.radar,
    'Radar',
    'Ti viene fornita la zona e il settore in cui si trovano tutti gli altri party.',
    'Si usa dallo zaino.',
    [Color(0xFF3E8CA8), Color(0xFF7FBCD0)],
    liveDescription: 'Ti viene fornita la posizione attuale di tutti gli altri party.',
    price: 5, icon: Icons.radar, rarity: 2,
  ),

  // ---- Esplorazione --------------------------------------------------------
  ItemDef(
    ItemId.lente,
    'Lente',
    'Analizza le tracce lasciate nei settori: mostra quali zone sono già state battute di recente e '
        'dove si stanno dirigendo i giocatori passati dal tuo settore.',
    'Si usa dalla borsa.',
    [Color(0xFF8E6BD8), Color(0xFFC4A8F0)],
    liveDescription: 'Analizza le tracce lasciate qui intorno: mostra chi ha cercato indizi nelle vicinanze di recente.',
    price: 4,
    icon: Icons.search,
    rarity: 2,
  ),
  ItemDef(
    ItemId.sensore,
    'Sensore',
    'Ti dice quanti indizi nascosti ci sono nel tuo settore (esclusi i tuoi).',
    'Si usa dalla borsa.',
    [Color(0xFF3FA796), Color(0xFF8FD9CB)],
    liveDescription: 'Ti dice quanti indizi nascosti ci sono entro ${kSensorRadiusMeters ~/ 1} metri da te (esclusi i tuoi).',
    price: 3,
    icon: Icons.sensors,
    rarity: 3,
  ),
  ItemDef(
    ItemId.allarme,
    'Allarme',
    'Si piazza come una Trappola, ma non blocca nessuno: ti avvisa in segreto quando un altro party entra nel settore.',
    'Si usa dalla borsa: viene piazzato dove ti trovi.',
    [Color(0xFFE5A23A), Color(0xFFF5D08A)],
    liveDescription: 'Si piazza come una Trappola, ma non blocca nessuno: ti avvisa in segreto quando un altro party si avvicina.',
    price: 3,
    icon: Icons.notifications_active,
    rarity: 3,
  ),
  ItemDef(
    ItemId.meteo,
    'Radar meteo',
    'Mostra gli eventi di zona previsti nei prossimi $kWeatherLookahead giri.',
    'Si usa dalla borsa.',
    [Color(0xFF4F7FCB), Color(0xFF9CC0F0)],
    price: 4,
    icon: Icons.thunderstorm,
    rarity: 2,
  ),
  ItemDef(
    ItemId.passoFelpato,
    'Passo felpato',
    'Fino a fine giro ignori Trappole e Allarmi, non lasci tracce e sei invisibile al Radar.',
    'Si usa dalla borsa.',
    [Color(0xFF6B7A8F), Color(0xFFADB9C9)],
    liveDescription: 'Per $kStealthMinutes minuti ignori Trappole e Allarmi, non lasci tracce e sei invisibile al Radar.',
    price: 5,
    icon: Icons.do_not_step,
    rarity: 1,
  ),
  ItemDef(
    ItemId.clessidra,
    'Clessidra',
    'Ottieni subito altre azioni, come un secondo turno solo per te (pari alle azioni di un turno).',
    'Si usa nel tuo turno, dalla borsa.',
    [Color(0xFFD9A23A), Color(0xFFF2D58A)],
    liveDescription: 'Azzera subito le attese: puoi cercare indizi, comprare e agire senza aspettare '
        '(anche dopo bufera ed eruzione).',
    liveUsage: 'Si usa dalla borsa, quando sei in attesa.',
    price: 6,
    icon: Icons.hourglass_bottom,
    rarity: 1,
  ),
  ItemDef(
    ItemId.chiave,
    'Chiave',
    'Sblocca per sempre un settore chiuso da una frana o dalla marea nella zona in cui ti trovi.',
    'Si usa dalla borsa, nella zona con il settore bloccato.',
    [Color(0xFFB08A3E), Color(0xFFE0C47A)],
    price: 5,
    icon: Icons.vpn_key,
    rarity: 1,
  ),

  // ---- Battaglia -------------------------------------------------------------
  ItemDef(
    ItemId.elisir,
    'Elisir',
    'Il Pokémon recupera $kEnergyElixir energie. In battaglia richiede un turno.',
    'Si usa in battaglia (richiede un turno).',
    [Color(0xFF3CA6D1), Color(0xFF8ADCF0)],
    category: ItemCategory.battaglia,
    price: 4,
    icon: Icons.bolt,
    rarity: 3,
  ),
  ItemDef(
    ItemId.superPozione,
    'Super Pozione',
    'Il Pokémon recupera $kSuperPotionHeal punti vita. In battaglia richiede un turno.',
    'Si usa dalla borsa o in battaglia (richiede un turno). Si ottiene anche unendo 2 Pozioni.',
    [Color(0xFF2B5FB8), Color(0xFF6C94E0)],
    category: ItemCategory.battaglia,
    price: 7,
    icon: Icons.science,
    rarity: 2,
  ),
  ItemDef(
    ItemId.antidoto,
    'Antidoto',
    'Rimuove subito i danni nel tempo e gli altri status alterati (rallentamenti, malus) del tuo Pokémon. '
        'In battaglia richiede un turno.',
    'Si usa in battaglia (richiede un turno).',
    [Color(0xFF59B36B), Color(0xFFA6E0B0)],
    category: ItemCategory.battaglia,
    price: 3,
    icon: Icons.healing,
    rarity: 3,
  ),
  ItemDef(
    ItemId.amuleto,
    'Amuleto',
    'Blocca il primo status alterato che subirai nello scontro. Va dichiarato prima del primo turno.',
    'Si usa in battaglia, prima del primo turno.',
    [Color(0xFF9A6BC9), Color(0xFFD2B0F0)],
    category: ItemCategory.battaglia,
    price: 5,
    icon: Icons.verified_user,
    rarity: 2,
  ),
  ItemDef(
    ItemId.guanto,
    'Guanto',
    '+$kGloveDamage al danno di ogni tuo attacco andato a segno, per un solo scontro. '
        'Va dichiarato prima del primo turno. Si ottiene anche unendo 2 Caramelle Rare.',
    'Si usa in battaglia, prima del primo turno.',
    [Color(0xFFC95B4F), Color(0xFFF0A59C)],
    category: ItemCategory.battaglia,
    price: 5,
    icon: Icons.sports_mma,
    rarity: 2,
  ),

  // ---- Protezioni di bioma (emporio locale) -----------------------------------
  ItemDef(
    ItemId.biglietto,
    'Biglietto',
    'Ti permette di raggiungere una zona NON collegata alla tua (es. dalla Regione innevata all\'Isola dei relitti). '
        'Il costo in azioni è quello normale dello spostamento.',
    'Si usa spostandoti: se la zona non è collegata, la app te lo propone.',
    [Color(0xFF8A6BC9), Color(0xFFC9B3F0)],
    price: 5,
    icon: Icons.train,
    tableOnly: true,
    rarity: 2,
  ),
  ItemDef(
    ItemId.corda,
    'Corda da scalata',
    'Per $kShieldRounds giri ignori gli effetti dell’evento in corso nel Canyon (costo di ingresso, settori bloccati).',
    'Si usa dalla borsa. Si compra nell’emporio del Canyon.',
    [Color(0xFFA9795A), Color(0xFFDDB596)],
    category: ItemCategory.zona,
    price: 4,
    icon: Icons.terrain,
    zone: 'canyon',
  ),
  ItemDef(
    ItemId.bussola,
    'Bussola',
    'Per $kShieldRounds giri ignori la nebbia della Giungla: il tuo Radar vede anche chi è nascosto là.',
    'Si usa dalla borsa. Si compra nell’emporio della Giungla.',
    [Color(0xFF4F9A5B), Color(0xFF9ADBA0)],
    category: ItemCategory.zona,
    price: 4,
    icon: Icons.explore,
    zone: 'giungla',
  ),
  ItemDef(
    ItemId.tutaNeve,
    'Tuta da neve',
    'Per $kShieldRounds giri ignori la bufera nella Regione innevata (nessun costo extra per entrare).',
    'Si usa dalla borsa. Si compra nell’emporio della Regione innevata.',
    [Color(0xFF6FB6D9), Color(0xFFBFE4F5)],
    category: ItemCategory.zona,
    price: 4,
    icon: Icons.ac_unit,
    zone: 'neve',
  ),
  ItemDef(
    ItemId.tutaIgnifuga,
    'Tuta ignifuga',
    'Per $kShieldRounds giri ignori l’eruzione del Vulcano: niente costo extra, azioni perse o bonus Fuoco.',
    'Si usa dalla borsa. Si compra nell’emporio del Vulcano.',
    [Color(0xFFE0603A), Color(0xFFF5A783)],
    category: ItemCategory.zona,
    price: 4,
    icon: Icons.local_fire_department,
    zone: 'vulcano',
  ),
  ItemDef(
    ItemId.zattera,
    'Zattera',
    'Per $kShieldRounds giri ignori l’alta marea all’Isola dei relitti: puoi entrare anche nei settori sommersi.',
    'Si usa dalla borsa. Si compra nell’emporio dell’Isola.',
    [Color(0xFF3C8FC9), Color(0xFF8FC8EC)],
    category: ItemCategory.zona,
    price: 4,
    icon: Icons.sailing,
    zone: 'isola',
  ),
  ItemDef(
    ItemId.parafulmine,
    'Parafulmine',
    'Per $kShieldRounds giri ignori la tempesta sulle Colline ventose: niente bonus di tipo negli scontri in zona.',
    'Si usa dalla borsa. Si compra nell’emporio delle Colline.',
    [Color(0xFFE0C23A), Color(0xFFF5E48A)],
    category: ItemCategory.zona,
    price: 4,
    icon: Icons.flash_on,
    zone: 'colline',
  ),
];

ItemDef itemDef(ItemId id) => kItems.firstWhere((i) => i.id == id);
