/// Fasi del giorno (tavolo senza turni).
///
/// Non ci sono turni: chiunque agisce quando vuole. Ogni giocatore ha N azioni per fase
/// (`state.actionsPerPlayer`, le sceglie il Master) e la fase passa alla successiva quando **tutti**
/// le hanno usate: Mattina → Pomeriggio → Sera → Notte → mattina del giorno dopo.
/// Le azioni perse (Trappola, eventi, Spavento) contano come usate (`state.lost`); chi non vuole fare
/// nulla può "stare fermo" (è un'azione: recupera un po' di PS ed energie).
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
const int kTrapWaitActions = 2; // Trappola: perdi 2 azioni (quelle che restano in questa fase, poi della prossima)
const int kMinPhaseActions = 2;
const int kMaxPhaseActions = 20;
const int kDefaultActionsPerPlayer = 2; // azioni a testa per fase (le sceglie il Master)
const int kMinActionsPerPlayer = 1;
const int kMaxActionsPerPlayer = 6;
const int kWaitHp = 3; // "Stai fermo": PS recuperati
const int kWaitEnergy = 2; // "Stai fermo": energie recuperate

// ---- azioni a testa per fase -------------------------------------------------------

/// Azioni di ogni giocatore in una fase.
int actionsPerPlayer(Map<String, dynamic>? st) =>
    _n(st?['actionsPerPlayer'], kDefaultActionsPerPlayer).clamp(kMinActionsPerPlayer, kMaxActionsPerPlayer);

/// Giocatori della partita (l'ordine sorteggiato all'avvio).
List<String> phasePlayers(Map<String, dynamic>? st) => [for (final p in (st?['order'] as List? ?? const [])) '$p'];

int _usedRaw(Map<String, dynamic>? st, String uid) => _n((st?['used'] as Map?)?[uid]);
int lostActions(Map<String, dynamic>? st, String uid) => _n((st?['lost'] as Map?)?[uid]);

/// Azioni già usate in questa fase, contando quelle perse (Trappola, eventi).
int usedActions(Map<String, dynamic>? st, String uid) {
  final per = actionsPerPlayer(st), used = _usedRaw(st, uid);
  final room = per - used;
  return used + (room > 0 ? (lostActions(st, uid) < room ? lostActions(st, uid) : room) : 0);
}

/// Azioni che restano a [uid] in questa fase.
int actionsLeft(Map<String, dynamic>? st, String uid) {
  final left = actionsPerPlayer(st) - usedActions(st, uid);
  return left > 0 ? left : 0;
}

/// Chi deve ancora agire in questa fase.
List<String> waitingFor(Map<String, dynamic>? st) => [for (final p in phasePlayers(st)) if (actionsLeft(st, p) > 0) p];

/// Dopo questa azione: se tutti hanno usato le loro azioni si passa alla fase successiva (anche più d'una, se
/// le azioni perse coprono intere fasi). Restituisce il nuovo giro e le mappe `used` / `lost` aggiornate.
({int round, Map<String, int> used, Map<String, int> lost}) settlePhase(
    Map<String, dynamic> st, int round, Map<String, int> used, Map<String, int> lost) {
  final per = actionsPerPlayer(st);
  final players = phasePlayers(st);
  var r = round;
  for (var guard = 0; guard < 8 && players.isNotEmpty; guard++) {
    final cur = {...st, 'used': used, 'lost': lost};
    if (waitingFor(cur).isNotEmpty) break;
    // le azioni perse usate in questa fase si scalano, le altre restano per la prossima
    lost = {
      for (final p in players)
        if ((lost[p] ?? 0) - (per - (used[p] ?? 0)).clamp(0, per) > 0) p: (lost[p] ?? 0) - (per - (used[p] ?? 0)).clamp(0, per),
    };
    used = {};
    r++;
  }
  return (round: r, used: used, lost: lost);
}

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
  static const wait = 'wait'; // stare fermo: è un'azione (recuperi un po' di PS ed energie)
  static const ability = 'ability'; // usare un'abilità attiva del Pokémon (lib/abilities.dart)
  static const item = 'item'; // usare uno strumento che costa un'azione (MT)
  static const challenge = 'challenge'; // ingaggiare chi hai notato entrare nel tuo settore (con la priorità)

  static String label(String? k) => switch (k) {
        move => 'spostarti tra i settori',
        zone => 'cambiare zona',
        search => 'cercare indizi',
        tracks => 'cercare tracce',
        locals => 'parlare con i locali',
        wait => 'stare fermo',
        ability => 'usare un’abilità',
        item => 'usare uno strumento',
        challenge => 'sfidare',
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
  final wait = _n(user?['waitUntilAction']) - actions; // vecchie partite (prima delle azioni a testa)
  if (wait > 0) return 'Sei fermo: aspetta ancora $wait ${wait == 1 ? 'azione' : 'azioni'} degli altri';
  if (kind == ActKind.forced) return null;
  if (state['order'] is List && actionsLeft(state, uid) <= 0) {
    return lostActions(state, uid) > 0
        ? 'Hai perso le azioni di questa fase (Trappola o evento): aspetta la prossima'
        : 'Hai usato le tue azioni di questa fase: aspetta gli altri';
  }
  // Clessidra, oppure la priorità di chi ha notato qualcuno entrare nel suo settore (finché non scade)
  final pr = user?['priority'];
  final free = user?['freeAction'] == true || (pr is Map && pr['pending'] != true && actions < _n(pr['untilAction']));
  // mai due volte di fila, ma solo se qualcun altro ha ancora azioni in questa fase (altrimenti si resterebbe bloccati)
  final othersCanAct = state['order'] is! List || waitingFor(state).any((p) => p != uid);
  if (!free && othersCanAct && state['lastUid'] == uid) return 'Hai appena agito: aspetta che agisca qualcun altro';
  // dentro la zona ci si sposta (e si sta fermi) quante volte si vuole: la regola vale per il resto
  if (!free && kind != ActKind.move && kind != ActKind.wait && user?['lastKind'] == kind) {
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
