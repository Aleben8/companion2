import 'package:flutter/material.dart';

/// Identificatori degli strumenti (chiavi usate in Firestore: Users/{u}.inventory).
enum ItemId { repellente, caramella, fune, trappola, pozione, calmanella, revitalizzante, radar }

class ItemDef {
  final ItemId id;
  final String name;
  final String description;
  final String usage; // dove/come si usa
  final List<Color> colors;
  const ItemDef(this.id, this.name, this.description, this.usage, this.colors);

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

const List<ItemDef> kItems = [
  ItemDef(
    ItemId.repellente,
    'Repellente',
    'La localizzazione del tuo party sarà nascosta al resto dei giocatori per $kRepellentMinutes minuti. '
        'Durante questo tempo non potete essere ingaggiati in scontri.',
    'Si usa dallo zaino.',
    [Color(0xFF5A9E88), Color(0xFF8CD0A8)],
  ),
  ItemDef(
    ItemId.caramella,
    'Caramella Rara',
    'I tiri di un solo giocatore e per un solo scontro saranno aumentati di $kCandyBonus. '
        "L'utilizzo deve essere dichiarato prima dello scontro.",
    'Si usa in battaglia, prima del primo turno.',
    [Color(0xFFF28AA8), Color(0xFFF7B3C6)],
  ),
  ItemDef(
    ItemId.fune,
    'Fune di fuga',
    'Potrai uscire da uno scontro: la battaglia termina all’istante e il party deve allontanarsi in una '
        'direzione casuale. Si applica la regola del doppio scontro: le due squadre non potranno '
        'scontrarsi subito dopo.',
    'Si usa in battaglia, oppure quando cadi in una Trappola.',
    [Color(0xFFB5694F), Color(0xFFD9A07A)],
  ),
  ItemDef(
    ItemId.trappola,
    'Trappola',
    'Posizionala dove preferisci. Il primo party avversario che si avvicinerà alla zona dovrà usare '
        'una Fune di fuga o perderà $kTrapPenaltyMinutes minuti.',
    'Si usa dallo zaino: la trappola viene piazzata nella tua posizione.',
    [Color(0xFF6B5B95), Color(0xFFA79BD0)],
  ),
  ItemDef(
    ItemId.pozione,
    'Pozione',
    'Il Pokémon bersaglio recupera $kPotionHeal punti vita. Se usata durante uno scontro, '
        "l'utilizzo richiede un turno.",
    'Si usa in battaglia (richiede un turno).',
    [Color(0xFF3C7BD1), Color(0xFF6CA8F0)],
  ),
  ItemDef(
    ItemId.calmanella,
    'Calmanella',
    'Utilizzando la Calmanella, rivelerai la tua posizione attuale agli altri giocatori.',
    'Si usa dallo zaino.',
    [Color(0xFFE5644E), Color(0xFFF0A060)],
  ),
  ItemDef(
    ItemId.revitalizzante,
    'Revitalizzante',
    'Il tuo Pokémon sconfitto recupera subito tutti i punti vita: non perdi i $kKoMinutes minuti di recupero.',
    'Si usa dallo zaino, quando il tuo Pokémon è esausto.',
    [Color(0xFF5FA8E0), Color(0xFFB4DDF5)],
  ),
  ItemDef(
    ItemId.radar,
    'Radar',
    'Ti viene fornita la posizione attuale di tutti gli altri party.',
    'Si usa dallo zaino.',
    [Color(0xFF3E8CA8), Color(0xFF7FBCD0)],
  ),
];

ItemDef itemDef(ItemId id) => kItems.firstWhere((i) => i.id == id);
