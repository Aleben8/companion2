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
