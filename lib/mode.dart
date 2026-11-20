/// Modalità dell'app, scelta in fase di compilazione:
///   flutter run                          -> TAVOLO (predefinita)
///   flutter run --dart-define=MODE=live  -> gioco dal vivo (GPS)
/// Entrambe usano lo stesso Firestore: per tenere separati i dati usa codici party diversi.
const String kMode = String.fromEnvironment('MODE', defaultValue: 'tavolo');
const bool kTableMode = kMode == 'tavolo';

/// Giro corrente della partita da tavolo, aggiornato in tempo reale
/// (serve a calcolare la durata degli effetti "in giri").
class TableClock {
  static int round = 0;
}

// ---- Regole del tavolo (modificale qui) ------------------------------------
const int kActionsOdd = 2; // azioni a turno con numero DISPARI di giocatori
const int kActionsEven = 3; // azioni a turno con numero PARI di giocatori
const int kMoveActionCost = 1; // costo di uno spostamento (in azioni)
