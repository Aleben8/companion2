import 'package:flutter/material.dart';

import 'zones.dart';

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
        SectorType.rifugio => 'A inizio turno recuperi $kRefugeHp PS. Nessuno può sfidarti a battaglia.',
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
const int kRefugeHp = 5; // rifugio: PS recuperati a inizio turno

// ---- Furtività: entrare in un settore dove ci sono altri giocatori -------------------
// Tiro d20 + destrezza contro CD = base + settore + percezione del più attento nel settore.
// Per ora destrezza = Velocità × moltiplicatore, percezione = Difesa Speciale × moltiplicatore
// (statistiche del Pokémon attivo); poi potranno diventare statistiche dedicate.
const int kStealthBaseCd = 10;
const double kDexterityMultiplier = 0.5; // destrezza = Velocità × 0.5
const double kPerceptionMultiplier = 0.5; // percezione = Difesa Speciale × 0.5
const int kEludeCost = 1; // se ti notano: 1 azione per eludere (oppure una Fune di fuga)

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
const int kLocalsBaseCd = 12; // CD base del tiro d20 per avere informazioni dai locali
const int kLocalsRounds = 3; // di quanti giri fa parlano i locali
