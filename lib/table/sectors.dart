import 'package:flutter/material.dart';

import 'zones.dart';
import 'phases.dart';

export 'zones.dart' show SectorType, TableLayout, kDefaultSectors;

/// Etichetta, icona e regole di ogni tipo di settore (solo al tavolo).
extension SectorTypeX on SectorType {
  String get label => switch (this) {
        SectorType.cittadino => 'Cittadino',
        SectorType.selvaggio => 'Selvaggio',
        SectorType.impervio => 'Impervio',
        SectorType.rifugio => 'Rifugio',
        SectorType.passaggio => 'Passaggio',
      };

  IconData get icon => switch (this) {
        SectorType.cittadino => Icons.storefront,
        SectorType.selvaggio => Icons.pets,
        SectorType.impervio => Icons.landscape,
        SectorType.rifugio => Icons.cabin,
        SectorType.passaggio => Icons.directions_boat,
      };

  /// Cosa succede in questo settore (testo per i giocatori).
  String get rules => switch (this) {
        SectorType.cittadino => 'Emporio aperto. Nessun incontro selvatico. Tracce più deboli.',
        SectorType.selvaggio =>
          'Entrando, ${(kWildEncounterChance * 100).round()}% di incontrare un Pokémon selvatico.',
        SectorType.impervio => 'Entrare costa +$kImperviousExtraCost azione. Cercando trovi più spesso strumenti '
            '(${(kImperviousSearchItemChance * 100).round()}%). Qui compare il leggendario.',
        SectorType.rifugio =>
          '${kTableTurns ? 'A inizio turno' : 'A ogni nuova fase del giorno'} recuperi $kRefugeHp PS e $kRefugeEnergy energie. '
          'Nessuno può sfidarti a battaglia.',
        SectorType.passaggio => 'Da qui partono e qui arrivano Biglietto, treno e traghetto.',
      };

  /// Modificatore alla forza delle tracce lasciate qui (la forza minima è 1).
  int get traceModifier => switch (this) {
        SectorType.cittadino => -1,
        SectorType.impervio => 1,
        SectorType.passaggio => 1,
        _ => 0,
      };

  /// Modificatore alla CD della furtività (entrare in un settore senza farsi notare da chi c'è):
  /// la folla e la vegetazione coprono, nei rifugi e ai punti di passaggio si nota chi arriva.
  int get stealthCdModifier => switch (this) {
        SectorType.cittadino => -2,
        SectorType.selvaggio => -1,
        SectorType.impervio => -1,
        SectorType.rifugio => 2,
        SectorType.passaggio => 1,
      };

  /// Modificatore alla CD delle informazioni dai locali chieste da qui.
  int get localsCdModifier => switch (this) {
        SectorType.cittadino => -2,
        SectorType.rifugio => -1,
        SectorType.impervio => 2,
        _ => 0,
      };
}

// ---- Regole dei settori (modificale qui) ------------------------------------
const double kWildEncounterChance = 0.25; // selvaggio: probabilità di incontro entrando
const int kWildFleeCost = 1; // fuggire dall'incontro costa 1 azione
const double kWildDropChance = 0.25; // vittoria contro un selvatico: probabilità di uno strumento
const int kWildStatMalus = 2; // il selvatico ha qualche punto statistica in meno del tuo Pokémon
const int kImperviousExtraCost = 1; // entrare in un settore impervio
const double kImperviousSearchItemChance = 0.30; // "Cerca" senza indizi in un settore impervio
const int kRefugeHp = 5; // rifugio: PS recuperati a ogni nuova fase (o inizio turno)
const int kRefugeEnergy = 2; // rifugio: energie recuperate a ogni nuova fase (o inizio turno)

// ---- Furtività: entrare in un settore dove ci sono altri giocatori -------------------
// Tiro d20 + destrezza contro CD = base + settore + percezione del più attento nel settore.
// Per ora destrezza = Velocità × moltiplicatore, percezione = Difesa Speciale × moltiplicatore
// (statistiche del Pokémon attivo); poi potranno diventare statistiche dedicate.
const int kStealthBaseCd = 10;
const double kDexterityMultiplier = 0.5; // destrezza = Velocità × 0.5
const double kPerceptionMultiplier = 0.5; // percezione = Difesa Speciale × 0.5
const int kEludeCost = 1; // se ti notano: 1 azione per eludere (oppure una Fune di fuga)
/// Chi ti nota ha la priorità: la sua prossima azione (sfidarti, un'abilità, uno strumento...) ignora le regole di
/// turno e finché può reagire tu non puoi eludere. La priorità scade dopo che il gruppo fa altre N azioni.
const int kPriorityActions = 2;
const int kPriorityChallengeCost = 1; // ingaggiare chi hai notato costa 1 azione (con la priorità)

int dexterityBonus(int speed) => (speed * kDexterityMultiplier).floor();
int perceptionBonus(int spDef) => (spDef * kPerceptionMultiplier).floor();

/// CD per entrare senza farsi notare in un settore di tipo [t], dove il più attento ha [bestSpDef].
int stealthCd(SectorType? t, int bestSpDef) => kStealthBaseCd + (t?.stealthCdModifier ?? 0) + perceptionBonus(bestSpDef);

// ---- Tracce ---------------------------------------------------------------------
const int kTraceBaseStrength = 1; // forza di una traccia normale
const int kTraceVisibleBonus = 1; // "Lascia una traccia ben visibile"
const int kTraceMaxStrength = 3;
const int kTraceRoundsPerStrength = 2; // la Lente vede una traccia per (forza × 2) giri

/// Forza di una traccia lasciata in un settore di tipo [t].
int traceStrength(SectorType? t, {bool visible = false}) =>
    (kTraceBaseStrength + (visible ? kTraceVisibleBonus : 0) + (t?.traceModifier ?? 0)).clamp(1, kTraceMaxStrength);

String traceStrengthLabel(int s) => switch (s) {
      <= 1 => 'debole',
      2 => 'chiara',
      _ => 'evidente',
    };

// ---- Informazioni dai locali ----------------------------------------------------
const int kTracksActionCost = 1; // "Cerca tracce" (Esplorazione)
const int kLocalsActionCost = 1; // "Parla con i locali" (Esplorazione)
const int kLocalsBaseCd = 12; // CD base del tiro d20 per avere informazioni dai locali
const int kLocalsRounds = 3; // di quanti giri fa parlano i locali

// ---- Azioni di settore (Esplorazione) --------------------------------------------
// Come "Parla con i locali": costano 1 azione, il giocatore tira al tavolo e il Master dice se ha
// superato la CD; se riesce la app applica l'effetto. Se fallisce si perde solo l'azione.
// Riposare non ha prova: l'effetto è immediato.
const int kSectorActionCost = 1;
const int kMinDc = 8; // CD minima (Seguire le tracce)
const int kFollowBaseCd = 16; // Seguire le tracce: 16 − 2 × forza totale delle tracce del settore
const int kBargainCd = 12;
const int kEraseCd = 12;
const int kClimbCd = 13;
const int kBargainDiscount = 1; // Contrattare: −1 moneta a ogni acquisto (minimo 1) per il resto della fase/turno
const int kRestHp = 10; // Riposare: PS in più
const int kRestEnergy = 3; // Riposare: energie in più

class SectorAction {
  static const bargain = 'contrattare';
  static const follow = 'seguire';
  static const erase = 'cancellare';
  static const climb = 'scalare';
  static const rest = 'riposare';
  static const all = [bargain, follow, erase, climb, rest];

  static String label(String id) => switch (id) {
        bargain => 'Contrattare',
        follow => 'Seguire le tracce',
        erase => 'Cancellare le tracce',
        climb => 'Scalare',
        rest => 'Riposare',
        _ => id,
      };

  static IconData icon(String id) => switch (id) {
        bargain => Icons.handshake,
        follow => Icons.hiking,
        erase => Icons.cleaning_services,
        climb => Icons.terrain,
        rest => Icons.hotel,
        _ => Icons.help_outline,
      };

  /// In quale tipo di settore si può fare.
  static bool allowed(String id, SectorType? t) => switch (id) {
        bargain => t == SectorType.cittadino,
        follow => t == SectorType.selvaggio,
        erase => t != null && t != SectorType.cittadino,
        climb => t == SectorType.impervio,
        rest => t == SectorType.rifugio,
        _ => false,
      };

  /// Serve una prova (CD e approvazione del Master)?
  static bool needsCheck(String id) => id != rest;

  /// CD fissa (Seguire le tracce dipende dalle tracce: [followCd]).
  static int? fixedCd(String id) => switch (id) {
        bargain => kBargainCd,
        erase => kEraseCd,
        climb => kClimbCd,
        _ => null,
      };

  static String help(String id) => switch (id) {
        bargain => 'Se riesci, per il resto della fase ogni acquisto all’emporio costa $kBargainDiscount moneta in meno (minimo 1).',
        follow => 'Se riesci leggi la traccia più forte lasciata qui da chi è già ripartito: debole = qualcuno è passato, '
            'chiara = anche dove è andato, evidente = anche chi era e da dove veniva. Più tracce ci sono, più è facile.',
        erase => 'Se riesci, la traccia che hai lasciato entrando qui torna debole.',
        climb => 'Se riesci, il tuo prossimo spostamento costa 1 azione in meno (anche 0).',
        rest => 'Nessuna prova: recuperi $kRestHp PS e $kRestEnergy energie in più e perdi gli status alterati.',
        _ => '',
      };
}

/// CD di "Seguire le tracce": più tracce (e più forti) ci sono nel settore, più è facile.
int followCd(int totalStrength) {
  final cd = kFollowBaseCd - 2 * totalStrength;
  return cd < kMinDc ? kMinDc : cd;
}

