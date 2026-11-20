/// Palestre, profili dei capipalestra e regole di generazione.
///
/// I capipalestra NON sono personaggi fissi: quando il gioco viene avviato,
/// per ogni palestra viene pescato a caso un Pokémon, un allenatore, 2 mosse e
/// una distribuzione di statistiche, sempre coerenti con il tipo della palestra
/// (vedi [kTypeProfiles]).
library;

import 'table/type_chart.dart';

/// Raggio entro cui si può sfidare una palestra.
const double kGymRadiusMeters = 50;

/// Modalità prova: permette di sfidare le palestre da qualsiasi posizione.
/// Lasciala a `false` per il gioco reale.
const bool kGymTestMode = false;

/// Punti statistica dei capipalestra (i giocatori ne hanno 30).
const int kGymStatPoints = 30;

class GymSpec {
  final String id;
  final String name;
  final String type;
  final String address; // aiuta il Master a trovare il punto per calibrare
  final double lat;
  final double lng;
  const GymSpec(this.id, this.name, this.type, this.address, this.lat, this.lng);
}

/// ATTENZIONE: coordinate PROVVISORIE (stimate dal centro di Varese).
/// Il Master le calibra sul posto dalla schermata Palestre ("Imposta qui"),
/// oppure si sostituiscono qui con quelle prese da Google Maps (tasto destro > coordinate).
const List<GymSpec> kGyms = [
  GymSpec('biblioteca', 'Palestra della Biblioteca', 'Normale',
      'Biblioteca civica, Via Sacco 9 (Palazzo Estense)', 45.8172, 8.8250),
  GymSpec('giardini', 'Palestra dei Giardini Estensi', 'Erba',
      'Giardini Estensi (lato giardino)', 45.8165, 8.8240),
  GymSpec('montegrappa', 'Palestra di Piazza Montegrappa', 'Acqua',
      'Piazza Montegrappa', 45.8197, 8.8251),
  GymSpec('motta', 'Palestra di Piazza della Motta', 'Fuoco',
      'Piazza della Motta (il falò)', 45.8203, 8.8242),
  GymSpec('battistero', 'Palestra del Battistero', 'Volante',
      'Battistero di San Giovanni, Piazza Canonica', 45.8208, 8.8248),
  GymSpec('tribunale', 'Palestra del Tribunale', 'Roccia',
      'Tribunale, Piazza Cacciatori delle Alpi', 45.8202, 8.8286),
];

GymSpec gymSpec(String id) => kGyms.firstWhere((g) => g.id == id);

// --------------------------------------------------------------- profili tipo

class MoveTemplate {
  final String name;
  final bool special; // true = Speciale, false = Fisico
  final String description;
  const MoveTemplate(this.name, this.special, this.description);
}

/// Effetto alterato possibile per un tipo. `effect == null` = nessun effetto.
class EffectPref {
  final String? effect; // Danno | Rallentamento | Debuff
  final String? stat; // per Debuff: Atk, AtkSpec, Def, DefSpec
  const EffectPref(this.effect, [this.stat]);
}

class TypeProfile {
  final List<String> pokemon;
  final List<String> trainers;
  final List<MoveTemplate> moves;
  final List<EffectPref> effects;
  final Map<String, int> statWeights; // peso di ogni statistica nella distribuzione
  final double defenseChance; // probabilità di scegliere Difesa in un turno
  final double dodgeChance; // probabilità di scegliere Schiva in un turno
  const TypeProfile({
    required this.pokemon,
    required this.trainers,
    required this.moves,
    required this.effects,
    required this.statWeights,
    required this.defenseChance,
    required this.dodgeChance,
  });
}

const Map<String, TypeProfile> kTypeProfiles = {
  'Normale': TypeProfile(
    pokemon: ['Snorlax', 'Eevee', 'Kangaskhan', 'Tauros', 'Lopunny', 'Furret'],
    trainers: ['Livia', 'Bruno', 'Gina', 'Ettore', 'Ada'],
    moves: [
      MoveTemplate('Corposcontro', false, 'Si lancia con tutto il peso contro il bersaglio.'),
      MoveTemplate('Colpo Rapido', false, 'Un attacco veloce e preciso.'),
      MoveTemplate('Sgranocchio', false, 'Un morso deciso.'),
      MoveTemplate('Iper Raggio', true, 'Un raggio di energia pura.'),
    ],
    effects: [EffectPref(null), EffectPref(null), EffectPref('Debuff', 'Atk'), EffectPref('Rallentamento')],
    statWeights: {'Atk': 3, 'AtkSpec': 2, 'Def': 3, 'DefSpec': 3, 'Vel': 3},
    defenseChance: 0.15,
    dodgeChance: 0.15,
  ),
  'Erba': TypeProfile(
    pokemon: ['Venusaur', 'Roserade', 'Tangela', 'Leafeon', 'Sceptile', 'Bulbasaur'],
    trainers: ['Flora', 'Silvio', 'Edera', 'Ortensia', 'Basilio'],
    moves: [
      MoveTemplate('Foglielama', false, 'Foglie affilate come rasoi.'),
      MoveTemplate('Gigassorbimento', true, 'Assorbe energia dal bersaglio.'),
      MoveTemplate('Frustata', false, 'Liane che colpiscono più volte.'),
      MoveTemplate('Raggiosolare', true, 'Concentra la luce del sole in un raggio.'),
    ],
    effects: [EffectPref('Danno'), EffectPref('Debuff', 'Atk'), EffectPref('Rallentamento'), EffectPref(null)],
    statWeights: {'Atk': 2, 'AtkSpec': 4, 'Def': 2, 'DefSpec': 4, 'Vel': 2},
    defenseChance: 0.20,
    dodgeChance: 0.10,
  ),
  'Acqua': TypeProfile(
    pokemon: ['Blastoise', 'Vaporeon', 'Gyarados', 'Lapras', 'Starmie', 'Squirtle'],
    trainers: ['Marina', 'Nereo', 'Delfina', 'Corrado', 'Sorgente'],
    moves: [
      MoveTemplate('Pistolacqua', true, 'Un getto d’acqua a pressione.'),
      MoveTemplate('Idropulsar', true, 'Bolle d’acqua che rallentano chi le subisce.'),
      MoveTemplate('Cascata', false, 'Si abbatte sul bersaglio come un’onda.'),
      MoveTemplate('Surf', true, 'Un’onda enorme travolge tutto.'),
    ],
    effects: [EffectPref('Rallentamento'), EffectPref('Debuff', 'Atk'), EffectPref(null)],
    statWeights: {'Atk': 2, 'AtkSpec': 4, 'Def': 3, 'DefSpec': 4, 'Vel': 2},
    defenseChance: 0.20,
    dodgeChance: 0.10,
  ),
  'Fuoco': TypeProfile(
    pokemon: ['Arcanine', 'Ninetales', 'Flareon', 'Typhlosion', 'Rapidash', 'Charmander'],
    trainers: ['Vulcano', 'Ardea', 'Fiammetta', 'Scintilla', 'Falò'],
    moves: [
      MoveTemplate('Lanciafiamme', true, 'Un getto di fuoco intenso.'),
      MoveTemplate('Braciere', true, 'Piccole fiamme che bruciano il bersaglio.'),
      MoveTemplate('Fuocobomba', true, 'Una palla di fuoco devastante.'),
      MoveTemplate('Zannate Ardenti', false, 'Un morso infuocato.'),
    ],
    effects: [EffectPref('Danno'), EffectPref('Danno'), EffectPref('Debuff', 'Def'), EffectPref(null)],
    statWeights: {'Atk': 3, 'AtkSpec': 5, 'Def': 1, 'DefSpec': 2, 'Vel': 3},
    defenseChance: 0.08,
    dodgeChance: 0.12,
  ),
  'Volante': TypeProfile(
    pokemon: ['Pidgeot', 'Staraptor', 'Altaria', 'Swellow', 'Noivern', 'Talonflame'],
    trainers: ['Aquilino', 'Zefiro', 'Vera', 'Falco', 'Brezza'],
    moves: [
      MoveTemplate('Aeroassalto', false, 'Piomba in picchiata sul bersaglio.'),
      MoveTemplate('Raffica', true, 'Un vento fortissimo che sbilancia.'),
      MoveTemplate('Alacciaio', false, 'Ali dure come l’acciaio.'),
      MoveTemplate('Becco Trivella', false, 'Un colpo di becco rotante.'),
    ],
    effects: [EffectPref('Rallentamento'), EffectPref('Debuff', 'Def'), EffectPref(null)],
    statWeights: {'Atk': 4, 'AtkSpec': 2, 'Def': 1, 'DefSpec': 2, 'Vel': 5},
    defenseChance: 0.08,
    dodgeChance: 0.25,
  ),
  'Ghiaccio': TypeProfile(
    pokemon: ['Glaceon', 'Abomasnow', 'Weavile', 'Walrein', 'Glalie', 'Mamoswine'],
    trainers: ['Brina', 'Gelsomino', 'Nevio', 'Cristalla', 'Borea'],
    moves: [
      MoveTemplate('Geloraggio', true, 'Un raggio di freddo intenso.'),
      MoveTemplate('Gelopugno', false, 'Un pugno ricoperto di ghiaccio.'),
      MoveTemplate('Bora', true, 'Un vento gelido che rallenta tutto.'),
      MoveTemplate('Cristalloscudo', false, 'Schegge di ghiaccio affilate.'),
    ],
    effects: [EffectPref('Rallentamento'), EffectPref('Rallentamento'), EffectPref('Debuff', 'Atk'), EffectPref(null)],
    statWeights: {'Atk': 2, 'AtkSpec': 4, 'Def': 3, 'DefSpec': 4, 'Vel': 2},
    defenseChance: 0.20,
    dodgeChance: 0.10,
  ),
  'Roccia': TypeProfile(
    pokemon: ['Onix', 'Golem', 'Rhyperior', 'Tyranitar', 'Aerodactyl', 'Omastar'],
    trainers: ['Petra', 'Sasso', 'Rocco', 'Pietro', 'Selce'],
    moves: [
      MoveTemplate('Pietrataglio', false, 'Schegge di roccia affilatissime.'),
      MoveTemplate('Frana', false, 'Fa crollare massi sul bersaglio.'),
      MoveTemplate('Forzantica', true, 'Una potenza antica risveglia le rocce.'),
      MoveTemplate('Tombaroccia', false, 'Rocce che rallentano i movimenti.'),
    ],
    effects: [EffectPref('Rallentamento'), EffectPref('Debuff', 'Atk'), EffectPref('Debuff', 'Def'), EffectPref(null)],
    statWeights: {'Atk': 4, 'AtkSpec': 1, 'Def': 5, 'DefSpec': 3, 'Vel': 1},
    defenseChance: 0.25,
    dodgeChance: 0.05,
  ),
};

/// Debolezze/resistenze di riserva se in Firestore (collezione "Tipi") manca il documento.
const Map<String, List<String>> kFallbackWeak = kTypeWeak;
const Map<String, List<String>> kFallbackResist = kTypeResist;
