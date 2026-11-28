/// Fasi del giorno (tavolo senza turni).
///
/// Non ci sono turni: chiunque agisce quando vuole. Ogni N azioni fatte da tutto il gruppo
/// (`state.phaseActions`, lo sceglie il Master) si passa alla fase successiva:
/// Mattina → Pomeriggio → Sera → Notte → mattina del giorno dopo.
/// Il "giro" del resto della app (`state.round`, `TableClock.round`) è la fase: tutto ciò che
/// dura "N giri" dura N fasi.
///
/// Regole per agire (vedi [actBlock]):
///  1. mai due volte di fila: dopo una tua azione deve agire qualcun altro;
///  2. mai due azioni uguali di fila (es. "cerca" dopo "cerca"); gli spostamenti tra settori della
///     stessa zona sono liberi (si pagano solo le azioni);
///  3. cambi di zona: al massimo [kZoneMovesPerDay] al giorno e distanziati di [kZoneMoveGap] fasi
///     (se cambi zona la sera, la mattina dopo no: dal pomeriggio sì);
///  4. chi è fermo (Trappola, eventi) aspetta che il gruppo faccia altre azioni.
/// Le reazioni obbligate (eludere, fuggire dal selvatico) contano per il gruppo ma non per 1 e 2.
library;

/// `true` = si torna ai turni (ordine, azioni a turno, "Fine turno"). Il codice dei turni è rimasto.
const bool kTableTurns = false;

const List<String> kPhaseNames = ['Mattina', 'Pomeriggio', 'Sera', 'Notte'];
const List<String> kPhaseIcons = ['🌅', '☀️', '🌇', '🌙'];
const int kZoneMovesPerDay = 2;
/// Fasi tra un cambio di zona e il successivo: 3 = se cambi zona la sera, la notte e la mattina dopo
/// no, dal pomeriggio sì.
const int kZoneMoveGap = 3;
const int kTrapWaitActions = 2; // Trappola: fermo finché il gruppo non fa altre 2 azioni
const int kMinPhaseActions = 2;
const int kMaxPhaseActions = 20;

/// Azioni per fase suggerite al Master: una a testa più una.
int suggestedPhaseActions(int players) => (players + 1).clamp(kMinPhaseActions, kMaxPhaseActions);

/// Tipi di azione (per la regola "mai due uguali di fila").
class ActKind {
  static const move = 'move'; // spostarsi in un altro settore della stessa zona
  static const zone = 'zone'; // cambiare zona
  static const search = 'search'; // cercare indizi
  static const tracks = 'tracks'; // cercare tracce
  static const locals = 'locals'; // parlare con i locali
  static const forced = 'forced'; // eludere, fuggire: reazioni obbligate

  static String label(String? k) => switch (k) {
        move => 'spostarti tra i settori',
        zone => 'cambiare zona',
        search => 'cercare indizi',
        tracks => 'cercare tracce',
        locals => 'parlare con i locali',
        // azioni di settore (lib/table/sectors.dart, SectorAction)
        'contrattare' => 'contrattare',
        'seguire' => 'seguire le tracce',
        'cancellare' => 'cancellare le tracce',
        'scalare' => 'scalare',
        'riposare' => 'riposare',
        _ => 'agire',
      };
}

int dayOf(int round) => round < 1 ? 1 : (round - 1) ~/ kPhaseNames.length + 1;
int phaseIndex(int round) => round < 1 ? 0 : (round - 1) % kPhaseNames.length;
String phaseName(int round) => kPhaseNames[phaseIndex(round)];
String phaseIcon(int round) => kPhaseIcons[phaseIndex(round)];
String phaseLabel(int round) => 'Giorno ${dayOf(round)} · ${phaseName(round)}';

/// Fase (giro) dopo [actions] azioni del gruppo, con [perPhase] azioni a fase.
int roundAfter(int actions, int perPhase) => 1 + actions ~/ (perPhase < 1 ? 1 : perPhase);

/// "nel pomeriggio", "stasera", "domani mattina", "giorno 4 di notte" visto dalla fase [now].
String whenLabel(int round, int now) {
  final i = phaseIndex(round);
  final dd = dayOf(round) - dayOf(now);
  if (dd == 0) return const ['stamattina', 'nel pomeriggio', 'stasera', 'stanotte'][i];
  final part = const ['mattina', 'pomeriggio', 'sera', 'notte'][i];
  if (dd == 1) return 'domani $part';
  return 'giorno ${dayOf(round)}, $part';
}

/// Fino a quando dura qualcosa che finisce con la fase [round]: "fino a stasera", "fino a domani mattina".
String untilLabel(int round, int now) {
  if (round <= now) return 'fino alla fine di questa fase';
  return 'fino a ${whenLabel(round, now)}';
}

/// Perché [uid] non può fare un'azione di tipo [kind] adesso (null = può).
///  - [state]: `actions` (azioni del gruppo), `lastUid` (chi ha agito per ultimo), `round`;
///  - [user]: `lastKind`, `waitUntilAction`, `zoneMoves` (fasi in cui ha cambiato zona), `freeAction` (Clessidra).
String? actBlock({
  required Map<String, dynamic>? state,
  required Map<String, dynamic>? user,
  required String uid,
  required String kind,
}) {
  if (state == null || state['started'] != true) return 'La partita non è ancora iniziata';
  final actions = _n(state['actions']);
  final round = _n(state['round'], 1);
  final wait = _n(user?['waitUntilAction']) - actions;
  if (wait > 0) return 'Sei fermo: aspetta ancora $wait ${wait == 1 ? 'azione' : 'azioni'} degli altri';
  if (kind == ActKind.forced) return null;
  final free = user?['freeAction'] == true;
  if (!free && state['lastUid'] == uid) return 'Hai appena agito: aspetta che agisca qualcun altro';
  // dentro la zona ci si sposta quante volte si vuole (pagando le azioni): la regola vale per il resto
  if (!free && kind != ActKind.move && user?['lastKind'] == kind) {
    return 'Non puoi ${ActKind.label(kind)} due volte di fila';
  }
  if (kind == ActKind.zone) {
    final moves = [for (final m in (user?['zoneMoves'] as List? ?? const [])) _n(m)];
    final today = moves.where((m) => dayOf(m) == dayOf(round)).length;
    if (today >= kZoneMovesPerDay) return 'Hai già cambiato zona $kZoneMovesPerDay volte oggi';
    if (moves.isNotEmpty) {
      final last = moves.reduce((a, b) => a > b ? a : b);
      if (round - last < kZoneMoveGap) {
        return last == round
            ? 'Hai già cambiato zona in questa fase'
            : 'Hai cambiato zona da poco: potrai di nuovo ${whenLabel(last + kZoneMoveGap, round)}';
      }
    }
  }
  return null;
}

/// Si può agire in generale (senza guardare il tipo di azione)? Per i messaggi della schermata.
String? anyActBlock({required Map<String, dynamic>? state, required Map<String, dynamic>? user, required String uid}) {
  final r = actBlock(state: state, user: user, uid: uid, kind: '_');
  return r;
}

/// Come citare un giro nei testi: "giro 3" con i turni, "Giorno 1 · Sera" con le fasi.
String roundRef(dynamic r) {
  final n = _n(r);
  return kTableTurns ? 'giro $n' : phaseLabel(n);
}

int _n(dynamic v, [int d = 0]) => v is num ? v.toInt() : d;
