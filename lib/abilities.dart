/// Abilità dei Pokémon (progetto completo in abilita.md).
///
/// Ogni tipo ha 3 abilità: 2 attive e 1 passiva. Il Pokémon parte senza abilità e ne sblocca una a ogni
/// palestra vinta nella partita in corso (capopalestra di zona al tavolo, palestra GPS dal vivo), fino al
/// kit completo: [kMaxActives] attive e [kMaxPassives] passiva.
///
/// Le regole valgono identiche al tavolo e dal vivo: l'unità è il **giro** (al tavolo una fase del giorno,
/// dal vivo `roundMinutes` minuti), lo stesso contatore (`state.round`, `TableClock.round`) degli eventi di zona.
///
/// Stato sul documento del Pokémon (`Users/{uid}/Pokemon/{pk}`), azzerato a ogni nuova partita:
///   abilities          -> [chiave, ...]           abilità sbloccate
///   abilityOffer       -> [chiave, chiave]        le 2 estratte in attesa di scelta
///   abilityNotice      -> [chiave, ...]           sbloccate direttamente, da mostrare ("Hai sbloccato…")
///   abilityOfferNext   -> n                       badge vinti mentre c'era già una scelta in sospeso
///   abilityUsedRound   -> { chiave: giro }        ultimo uso di ogni attiva
///   abilityActiveUntil -> giro                    ultimo giro dell'effetto in corso (regola "una alla volta")
///   abilityActiveKey   -> chiave                  quale attiva è in corso
library;

import 'dart:math';

// ---- Regole (modificale qui) --------------------------------------------------
const int kMaxActives = 2; // attive nel kit completo
const int kMaxPassives = 1; // passive nel kit completo
const int kAbilityChoices = 2; // abilità estratte a ogni badge
const int kMonoTypeFullKitBadges = 2; // tipo singolo: badge per il kit completo
const int kAbilityActionCost = 1; // al tavolo un'attiva costa 1 azione
const int kLiveAbilityWaitMinutes = 1; // dal vivo: attesa breve dopo un'attiva
const int kNextBattleRounds = 2; // "nella prossima lotta entro 2 giri"

class AbilityDef {
  final String key;
  final String type; // chiave del tipo come in constants.dart (kTypes), Tipi e PkmTypePrim/Sec
  final bool active;
  final String name;
  final String text;
  final int cooldown; // ricarica in giri (2, 4 o 8); 0 per le passive
  final int duration; // giri dell'effetto (0 = immediata)
  final bool reaction; // di reazione: non costa azioni
  final bool nextBattle; // effetto "nella prossima lotta entro [kNextBattleRounds] giri"
  const AbilityDef(
    this.key,
    this.type,
    this.name,
    this.text, {
    this.active = true,
    this.cooldown = 0,
    this.duration = 0,
    this.reaction = false,
    this.nextBattle = false,
  });

  const AbilityDef.passive(this.key, this.type, this.name, this.text)
      : active = false,
        cooldown = 0,
        duration = 0,
        reaction = false,
        nextBattle = false;

  /// Giri in cui dura l'effetto: per quelle "per la prossima lotta" la finestra di [kNextBattleRounds] giri.
  int get effectRounds => nextBattle ? kNextBattleRounds : duration;
}

/// Chiavi delle abilità (usate in Firestore).
class Ab {
  // Normale
  static const racimolare = 'racimolare', distrazione = 'distrazione', clienteAbituale = 'clienteAbituale';
  // Fuoco
  static const fiammata = 'fiammata', ardore = 'ardore', sangueCaldo = 'sangueCaldo';
  // Acqua
  static const pioggia = 'pioggia', idratazione = 'idratazione', nuotatore = 'nuotatore';
  // Erba
  static const sintesi = 'sintesi', rovi = 'rovi', fotosintesi = 'fotosintesi';
  // Elettro
  static const impulso = 'impulso', riflessi = 'riflessi', statico = 'statico';
  // Ghiaccio
  static const gelata = 'gelata', ibernazione = 'ibernazione', pelleSpessa = 'pelleSpessa';
  // Lotta
  static const pugnoDiFerro = 'pugnoDiFerro', sfida = 'sfida', tenacia = 'tenacia';
  // Veleno
  static const escaTossica = 'escaTossica', secrezione = 'secrezione', immunita = 'immunita';
  // Terra
  static const scavo = 'scavo', sismo = 'sismo', passoSicuro = 'passoSicuro';
  // Volante
  static const ricognizione = 'ricognizione', vedetta = 'vedetta', correnti = 'correnti';
  // Psico
  static const preveggenza = 'preveggenza', depistaggio = 'depistaggio', menteLucida = 'menteLucida';
  // Coleottero
  static const fiuto = 'fiuto', sciame = 'sciame', nido = 'nido';
  // Roccia
  static const barricata = 'barricata', rinforzo = 'rinforzo', corazza = 'corazza';
  // Spettro
  static const svanire = 'svanire', spavento = 'spavento', attraversamuri = 'attraversamuri';
  // Drago
  static const auraDrago = 'auraDrago', danzaDrago = 'danzaDrago', sangueAntico = 'sangueAntico';
  // Buio
  static const borseggio = 'borseggio', imboscata = 'imboscata', ombra = 'ombra';
  // Acciaio
  static const forgia = 'forgia', sonda = 'sonda', lega = 'lega';
  // Folletto
  static const benedizione = 'benedizione', incanto = 'incanto', fortuna = 'fortuna';
}

/// Le 54 abilità (tabella di abilita.md, prima stesura da bilanciare).
const List<AbilityDef> kAbilities = [
  // ---- Normale
  AbilityDef(Ab.racimolare, 'Normale', 'Racimolare', 'Ricevi subito 3 monete.', cooldown: 2),
  AbilityDef(Ab.distrazione, 'Normale', 'Distrazione',
      'Per 1 giro gli altri giocatori nel tuo settore non possono Cercare (indizi o strumenti).',
      cooldown: 4, duration: 1),
  AbilityDef.passive(Ab.clienteAbituale, 'Normale', 'Cliente abituale',
      'All’emporio ogni acquisto costa 1 moneta in meno (minimo 1).'),
  // ---- Fuoco
  AbilityDef(Ab.fiammata, 'Fuoco', 'Fiammata',
      'Per 1 giro la tua zona è "rovente": chi ci entra paga +1 azione (non chi ha la Tuta ignifuga).',
      cooldown: 8, duration: 1),
  AbilityDef(Ab.ardore, 'Fuoco', 'Ardore', 'Per 2 giri le tue mosse di tipo Fuoco fanno +1 danno (come l’evento Vulcano).',
      cooldown: 4, duration: 2),
  AbilityDef.passive(Ab.sangueCaldo, 'Fuoco', 'Sangue caldo',
      'Gli effetti dell’evento Vulcano non ti toccano; in lotta il tuo Danno nel tempo dura 1 turno in più.'),
  // ---- Acqua
  AbilityDef(Ab.pioggia, 'Acqua', 'Pioggia',
      'Tutte le tracce della tua zona tornano a forza 1 e per 1 giro il bonus Fuoco degli eventi lì è annullato.',
      cooldown: 4, duration: 1),
  AbilityDef(Ab.idratazione, 'Acqua', 'Idratazione', 'Subito +5 PS e via il tuo status alterato.', cooldown: 4),
  AbilityDef.passive(Ab.nuotatore, 'Acqua', 'Nuotatore',
      'Entri nei settori sommersi dalla marea; gli effetti dell’evento Isola non ti toccano.'),
  // ---- Erba
  AbilityDef(Ab.sintesi, 'Erba', 'Sintesi', 'Subito +10 PS e +3 energie (fuori dalla lotta).', cooldown: 8),
  AbilityDef(Ab.rovi, 'Erba', 'Rovi',
      'Per 2 giri nel tuo settore: chi entra perde 2 PS e lascia una traccia evidente (forza 3).',
      cooldown: 8, duration: 2),
  AbilityDef.passive(Ab.fotosintesi, 'Erba', 'Fotosintesi',
      'A ogni nuovo giro +2 PS ovunque (si somma al rifugio); la nebbia della Giungla non acceca il tuo Radar.'),
  // ---- Elettro
  AbilityDef(Ab.impulso, 'Elettro', 'Impulso', 'Come un Radar, ma solo sulla tua zona e senza consumare strumenti.',
      cooldown: 4),
  AbilityDef(Ab.riflessi, 'Elettro', 'Riflessi',
      'Nella prossima lotta entro 2 giri la tua prima Schiva riesce anche contro un attacco imbloccabile.',
      cooldown: 4, nextBattle: true),
  AbilityDef.passive(Ab.statico, 'Elettro', 'Statico',
      'Gli effetti dell’evento Colline non ti toccano; chi lotta contro di te parte con −2 energie.'),
  // ---- Ghiaccio
  AbilityDef(Ab.gelata, 'Ghiaccio', 'Gelata',
      'Per 2 giri il tuo settore è ghiacciato: chi ci entra paga +1 azione e tu ricevi un avviso segreto (come l’Allarme).',
      cooldown: 8, duration: 2),
  AbilityDef(Ab.ibernazione, 'Ghiaccio', 'Ibernazione',
      'Per 1 giro nessuno può sfidarti (né tu puoi sfidare) e recuperi 5 PS, come in un rifugio.',
      cooldown: 4, duration: 1),
  AbilityDef.passive(Ab.pelleSpessa, 'Ghiaccio', 'Pelle spessa',
      'La bufera della Regione innevata non ti tocca; in lotta il Rallentamento non ti colpisce.'),
  // ---- Lotta
  AbilityDef(Ab.pugnoDiFerro, 'Lotta', 'Pugno di ferro',
      'Nella prossima lotta entro 2 giri il primo attacco andato a segno conta almeno come Forte.',
      cooldown: 2, nextBattle: true),
  AbilityDef(Ab.sfida, 'Lotta', 'Sfida',
      'Un giocatore nel tuo settore deve lottare subito con te (non può rifiutare; non vale nei rifugi né contro chi ha il Repellente).',
      cooldown: 2),
  AbilityDef.passive(Ab.tenacia, 'Lotta', 'Tenacia', 'Dopo una sconfitta non aspetti il recupero ma riparti con metà PS.'),
  // ---- Veleno
  AbilityDef(Ab.escaTossica, 'Veleno', 'Esca tossica',
      'Per 2 giri nel tuo settore: il primo altro giocatore che entra ha il Pokémon avvelenato (Danno nel tempo).',
      cooldown: 4, duration: 2),
  AbilityDef(Ab.secrezione, 'Veleno', 'Secrezione',
      'Nella prossima lotta entro 2 giri il tuo primo attacco a segno avvelena sempre (Danno nel tempo), qualunque sia la mossa.',
      cooldown: 8, nextBattle: true),
  AbilityDef.passive(Ab.immunita, 'Veleno', 'Immunità', 'Il Danno nel tempo non ti colpisce.'),
  // ---- Terra
  AbilityDef(Ab.scavo, 'Terra', 'Scavo',
      'Cerchi uno strumento nel tuo settore con il 50% di trovarlo (non cerca indizi, non vale come "Cerca").',
      cooldown: 2),
  AbilityDef(Ab.sismo, 'Terra', 'Sismo',
      'Per 1 giro un altro settore della tua zona, a scelta, è bloccato come per la frana (non quello del leggendario).',
      cooldown: 8, duration: 1),
  AbilityDef.passive(Ab.passoSicuro, 'Terra', 'Passo sicuro', 'Il costo extra dei settori impervi non ti riguarda.'),
  // ---- Volante
  AbilityDef(Ab.ricognizione, 'Volante', 'Ricognizione',
      'Vedi in quali zone ci sono eventi in corso o annunciati e quanti giocatori ci sono in ogni zona (senza nomi).',
      cooldown: 2),
  AbilityDef(Ab.vedetta, 'Volante', 'Vedetta',
      'Per 2 giri ricevi un avviso segreto (con il nome) quando qualcuno entra nella tua zona.',
      cooldown: 2, duration: 2),
  AbilityDef.passive(Ab.correnti, 'Volante', 'Correnti ascensionali',
      'Gli effetti dell’evento Colline non ti toccano; il primo ingresso in una zona a ogni giro non lascia traccia.'),
  // ---- Psico
  AbilityDef(Ab.preveggenza, 'Psico', 'Preveggenza', 'Come un Radar meteo (eventi dei prossimi 2 giri), senza consumarlo.',
      cooldown: 2),
  AbilityDef(Ab.depistaggio, 'Psico', 'Depistaggio',
      'Per 2 giri chi ti trova con Radar o Calmanella vede una zona a caso (dal vivo: distanza e direzione false).',
      cooldown: 4, duration: 2),
  AbilityDef.passive(Ab.menteLucida, 'Psico', 'Mente lucida', 'Ricevi un avviso segreto quando qualcuno usa un Radar e ti vede.'),
  // ---- Coleottero
  AbilityDef(Ab.fiuto, 'Coleottero', 'Fiuto', 'Leggi tutte le tracce del tuo settore come con la Lente, senza averla.',
      cooldown: 2),
  AbilityDef(Ab.sciame, 'Coleottero', 'Sciame',
      'Per 1 giro nessuno nella tua zona (tranne te) può usare Radar, Lente o Sensore.',
      cooldown: 8, duration: 1),
  AbilityDef.passive(Ab.nido, 'Coleottero', 'Nido',
      'Dagli incontri selvatici fuggi senza costo; vincendo, la probabilità di uno strumento sale al 50%.'),
  // ---- Roccia
  AbilityDef(Ab.barricata, 'Roccia', 'Barricata', 'Per 1 giro il tuo settore è bloccato per gli altri (come la frana).',
      cooldown: 4, duration: 1),
  AbilityDef(Ab.rinforzo, 'Roccia', 'Rinforzo',
      'Nella prossima lotta entro 2 giri il primo colpo che subisci è dimezzato, senza dover usare Difesa.',
      cooldown: 8, nextBattle: true),
  AbilityDef.passive(Ab.corazza, 'Roccia', 'Corazza',
      'La frana del Canyon non ti blocca; in lotta Difesa ti dà +2 energie in più.'),
  // ---- Spettro
  AbilityDef(Ab.svanire, 'Spettro', 'Svanire', 'Per 2 giri sei invisibile al Radar e non lasci tracce.',
      cooldown: 2, duration: 2),
  AbilityDef(Ab.spavento, 'Spettro', 'Spavento',
      'Un giocatore nel tuo settore perde 1 azione (dal vivo: 2 minuti di attesa).',
      cooldown: 8),
  AbilityDef.passive(Ab.attraversamuri, 'Spettro', 'Attraversamuri', 'Trappole e Allarmi non scattano su di te.'),
  // ---- Drago
  AbilityDef(Ab.auraDrago, 'Drago', 'Aura del drago',
      'Nella prossima lotta contro un altro giocatore entro 2 giri l’avversario parte con −2 energie '
          '(non vale contro capipalestra, selvatici e leggendario).',
      cooldown: 8, nextBattle: true),
  AbilityDef(Ab.danzaDrago, 'Drago', 'Danza del drago', 'Nella prossima lotta entro 2 giri +1 al dado per tutto lo scontro.',
      cooldown: 8, nextBattle: true),
  AbilityDef.passive(Ab.sangueAntico, 'Drago', 'Sangue antico',
      '+2 al dado contro il leggendario; le vittorie sui capipalestra danno +2 monete.'),
  // ---- Buio
  AbilityDef(Ab.borseggio, 'Buio', 'Borseggio',
      'Un giocatore a caso nel tuo settore ti passa uno strumento a caso (se non c’è nessuno, l’uso è perso).',
      cooldown: 4),
  AbilityDef(Ab.imboscata, 'Buio', 'Imboscata',
      'Per 2 giri, se qualcuno entra nel tuo settore puoi sfidarlo subito (avviso a te, non può rifiutare) con +2 al dado '
          'nel primo turno. Non vale nei rifugi né contro chi ha il Repellente.',
      cooldown: 4, duration: 2),
  AbilityDef.passive(Ab.ombra, 'Buio', 'Ombra',
      'Il Radar e la Calmanella degli altri mostrano solo la tua zona, non il settore né la distanza precisa.'),
  // ---- Acciaio
  AbilityDef(Ab.forgia, 'Acciaio', 'Forgia', 'Fai una ricetta di crafting con un solo ingrediente invece di due.',
      cooldown: 2),
  AbilityDef(Ab.sonda, 'Acciaio', 'Sonda',
      'Disattivi nel tuo settore tutte le Trappole e gli Allarmi e gli effetti di Gelata ed Esca tossica, e scopri di chi erano.',
      cooldown: 8),
  AbilityDef.passive(Ab.lega, 'Acciaio', 'Lega', 'La borsa contiene 2 oggetti in più (14); il Debuff non ti colpisce.'),
  // ---- Folletto
  AbilityDef(Ab.benedizione, 'Folletto', 'Benedizione',
      'Tu e tutti i giocatori nel tuo settore recuperate 10 PS e perdete gli status alterati.',
      cooldown: 4),
  AbilityDef(Ab.incanto, 'Folletto', 'Incanto',
      'Nella prossima lotta entro 2 giri il primo status alterato che ricevi torna all’avversario.',
      cooldown: 4, nextBattle: true),
  AbilityDef.passive(Ab.fortuna, 'Folletto', 'Fortuna',
      'Quando trovi o vinci uno strumento, 25% di prenderne due (non vale per la MT).'),
];

AbilityDef? abilityDef(String key) {
  for (final a in kAbilities) {
    if (a.key == key) return a;
  }
  return null;
}

/// Abilità di un tipo (2 attive e 1 passiva).
List<AbilityDef> abilitiesOfType(String type) => [for (final a in kAbilities) if (a.type == type) a];

/// I tipi del Pokémon (documento del Pokémon: PkmTypePrim, PkmTypeSec).
List<String> pokemonTypes(Map<String, dynamic>? pokemon) {
  final out = <String>[];
  for (final k in ['PkmTypePrim', 'PkmTypeSec']) {
    final t = '${pokemon?[k] ?? ''}'.trim();
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }
  return out;
}

bool isMonoType(Map<String, dynamic>? pokemon) => pokemonTypes(pokemon).length < 2;

/// Riserva del Pokémon: tipo singolo = 2 attive + passiva del tipo; tipo doppio = attive e passive di entrambi i tipi.
List<AbilityDef> abilityPool(Map<String, dynamic>? pokemon) =>
    [for (final t in pokemonTypes(pokemon)) ...abilitiesOfType(t)];

/// Chiavi sbloccate (documento del Pokémon).
List<String> unlockedAbilities(Map<String, dynamic>? pokemon) =>
    [for (final k in (pokemon?['abilities'] as List? ?? const [])) if (abilityDef('$k') != null) '$k'];

bool hasAbility(Map<String, dynamic>? pokemon, String key) => unlockedAbilities(pokemon).contains(key);

/// Passive sbloccate del Pokémon.
Set<String> passivesOf(Map<String, dynamic>? pokemon) =>
    {for (final k in unlockedAbilities(pokemon)) if (abilityDef(k)?.active == false) k};

/// Abilità che si possono ancora sbloccare rispettando il kit massimo.
List<AbilityDef> unlockableAbilities(Map<String, dynamic>? pokemon) {
  final have = unlockedAbilities(pokemon);
  final actives = have.where((k) => abilityDef(k)!.active).length;
  final passives = have.length - actives;
  return [
    for (final a in abilityPool(pokemon))
      if (!have.contains(a.key) && (a.active ? actives < kMaxActives : passives < kMaxPassives)) a,
  ];
}

bool kitComplete(Map<String, dynamic>? pokemon) => unlockableAbilities(pokemon).isEmpty;

/// Cosa succede a un nuovo badge: [offer] = due abilità da cui scegliere; [unlock] = sbloccate subito
/// (una sola rimasta, oppure il tipo singolo dopo il primo badge riceve insieme le rimaste).
({List<String> offer, List<String> unlock}) badgeReward(Map<String, dynamic>? pokemon, {Random? rnd}) {
  final can = [for (final a in unlockableAbilities(pokemon)) a.key];
  if (can.isEmpty) return (offer: const [], unlock: const []);
  if (can.length == 1) return (offer: const [], unlock: can);
  // tipo singolo: al 1º badge sceglie tra 2, al 2º riceve insieme le rimaste (kit completo in 2 badge)
  if (isMonoType(pokemon) && unlockedAbilities(pokemon).isNotEmpty) return (offer: const [], unlock: can);
  final pick = [...can]..shuffle(rnd ?? Random());
  return (offer: pick.take(kAbilityChoices).toList(), unlock: const []);
}

// ---- uso delle attive -----------------------------------------------------------

int _n(dynamic v, [int d = 0]) => v is num ? v.toInt() : d;

/// Giro dell'ultimo uso dell'attiva (null = mai usata).
int? usedRound(Map<String, dynamic>? pokemon, String key) {
  final m = pokemon?['abilityUsedRound'];
  return m is Map && m[key] is num ? (m[key] as num).toInt() : null;
}

/// L'attiva in corso (effetto non ancora finito) al giro [round], o null.
String? activeAbility(Map<String, dynamic>? pokemon, int round) {
  final until = _n(pokemon?['abilityActiveUntil'], -1);
  if (until < round) return null;
  final k = pokemon?['abilityActiveKey'];
  return k is String ? k : null;
}

/// Giri che mancano perché l'attiva sia di nuovo pronta (0 = pronta).
int cooldownLeft(Map<String, dynamic>? pokemon, String key, int round) {
  final used = usedRound(pokemon, key);
  final def = abilityDef(key);
  if (used == null || def == null) return 0;
  final left = def.cooldown - (round - used);
  return left > 0 ? left : 0;
}

/// Perché l'attiva [key] non si può usare adesso (null = si può). Le regole: deve essere sbloccata, non in
/// ricarica, nessun'altra attiva in corso e al massimo un'attiva per giro.
String? abilityBlock(Map<String, dynamic>? pokemon, String key, int round) {
  final def = abilityDef(key);
  if (def == null || !def.active) return 'Non è un’abilità attiva';
  if (!hasAbility(pokemon, key)) return 'Si sblocca con il prossimo badge';
  if (round < 1) return 'La partita non è ancora iniziata';
  final left = cooldownLeft(pokemon, key, round);
  if (left > 0) return left == 1 ? 'Pronta tra 1 giro' : 'Pronta tra $left giri';
  final running = activeAbility(pokemon, round);
  if (running != null) {
    return running == key ? 'È già in corso' : 'Un’altra abilità è in corso';
  }
  final m = pokemon?['abilityUsedRound'];
  if (m is Map && m.values.any((v) => _n(v, -99) == round)) return 'Hai già usato un’abilità in questo giro';
  return null;
}
