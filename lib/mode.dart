/// Modalità di gioco: TAVOLO oppure DAL VIVO (GPS).
///
/// La sceglie il Master per ogni party (`Party/{codice}.mode` = 'tavolo' | 'live', dalla
/// schermata Gestione Party) e la app la segue in tempo reale: c'è un solo deploy.
/// Se il party non ha ancora scelto si usa [kDefaultMode], che si può cambiare in compilazione:
///   flutter run                          -> tavolo
///   flutter run --dart-define=MODE=live  -> dal vivo
const String kDefaultMode = String.fromEnvironment('MODE', defaultValue: 'tavolo');

const String kModeTable = 'tavolo';
const String kModeLive = 'live';

/// Modalità del party corrente, aggiornata da `ModeService`.
class AppMode {
  static String current = kDefaultMode;
}

/// `true` se il party corrente gioca al tavolo.
bool get kTableMode => AppMode.current != kModeLive;

/// Giro corrente della partita da tavolo, aggiornato in tempo reale
/// (serve a calcolare la durata degli effetti "in giri").
class TableClock {
  static int round = 0;
}

// ---- Regole del tavolo (modificale qui) ------------------------------------
const int kActionsOdd = 2; // azioni a turno con numero DISPARI di giocatori
const int kActionsEven = 3; // azioni a turno con numero PARI di giocatori
const int kMoveActionCost = 1; // costo di uno spostamento (in azioni)
const int kMaxTablePlayers = 9; // al tavolo (dal vivo non c'è limite)

// ---- Regole dal vivo (modificale qui) ---------------------------------------
// Dal vivo non ci sono turni: il giro avanza da solo ogni N minuti e le azioni diventano attese.
const int kDefaultRoundMinutes = 10; // durata di un giro (il Master la cambia)
const List<int> kRoundMinuteChoices = [5, 10, 15, 20, 30];
const double kDefaultZoneRadius = 80; // raggio delle zone sulla mappa, in metri
const List<double> kZoneRadiusChoices = [40, 60, 80, 120, 160, 200, 300];
const int kLiveSearchCooldownMinutes = 2; // "Cerca indizi": una volta ogni N minuti
const int kLiveEnterWaitMinutes = 1; // per ogni azione extra (bufera, eruzione) entrando in una zona
const int kLivePenaltyMinutes = 2; // per ogni azione persa (eruzione con te nella zona)
