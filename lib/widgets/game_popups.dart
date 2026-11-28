import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../abilities.dart';
import '../mode.dart';
import '../screens/table_sheets.dart';
import '../services/ability_service.dart';
import '../services/item_service.dart';
import '../services/session.dart';
import '../services/table_service.dart';
import '../table/events.dart';
import '../table/phases.dart';
import '../table/sectors.dart';
import '../table/zones.dart';
import '../theme.dart';
import 'abilities_card.dart';
import 'common.dart';
import 'drop.dart';

int _i(dynamic v) => v is num ? v.toInt() : 0;
String _err(Object e) => '$e'.replaceFirst('Exception: ', '');

/// Contenuto di un popup: lo stesso widget serve alla finestra e alla scheda fissata.
/// [close] chiude la finestra (o toglie la scheda fissata) dopo un'azione andata a buon fine.
typedef PopupContent = Widget Function(BuildContext context, VoidCallback close);

/// Scheda fissata da un popup.
class PinnedPopup {
  final String title;
  final List<Color> colors;
  final PopupContent content;
  const PinnedPopup(this.title, this.colors, this.content);
}

/// Popup degli eventi di gioco: ognuno si apre una volta sola e si può **fissare** (diventa una scheda in cima
/// alla Home finché non la togli) oppure chiudere. Gli stati restano in memoria solo per questa sessione.
class PopupCenter extends ChangeNotifier {
  static final instance = PopupCenter();
  final Map<String, PinnedPopup> _pinned = {};
  final Set<String> _shown = {};

  Iterable<MapEntry<String, PinnedPopup>> get pinned => _pinned.entries;
  bool isPinned(String key) => _pinned.containsKey(key);

  /// true la prima volta che si chiede per [key] (il popup si apre una volta sola).
  bool firstTime(String key) => _shown.add(key);

  void pin(String key, String title, List<Color> colors, PopupContent content) {
    _pinned[key] = PinnedPopup(title, colors, content);
    notifyListeners();
  }

  void unpin(String key) {
    if (_pinned.remove(key) != null) notifyListeners();
  }

  /// Toglie le schede fissate il cui nome comincia con [prefix] (es. la fase precedente).
  void unpinWhere(bool Function(String key) test) {
    final before = _pinned.length;
    _pinned.removeWhere((k, _) => test(k));
    if (_pinned.length != before) notifyListeners();
  }
}

/// Apre il popup [key] (una volta sola, salvo [force]): titolo, contenuto con le azioni e, in fondo,
/// "📌 Fissa sullo schermo" e "Chiudi".
Future<void> showGamePopup(
  BuildContext context, {
  required String key,
  required String title,
  required List<Color> colors,
  required PopupContent content,
  bool force = false,
}) async {
  final center = PopupCenter.instance;
  if (!force && !center.firstTime(key)) return;
  if (center.isPinned(key)) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      content: SingleChildScrollView(child: content(ctx, () => Navigator.of(ctx).pop())),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.push_pin_outlined, size: 18),
          label: const Text('Fissa sullo schermo'),
          onPressed: () {
            center.pin(key, title, colors, content);
            Navigator.of(ctx).pop();
          },
        ),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Chiudi')),
      ],
    ),
  );
}

/// Le schede fissate dai popup, in cima alla Home.
class PinnedPopups extends StatelessWidget {
  const PinnedPopups({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: PopupCenter.instance,
        builder: (context, _) => Column(children: [
          for (final e in PopupCenter.instance.pinned.toList())
            DropCard(
              colors: e.value.colors,
              label: e.value.title,
              labelOnTop: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                e.value.content(context, () => PopupCenter.instance.unpin(e.key)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.push_pin, size: 16),
                    label: const Text('Togli'),
                    onPressed: () => PopupCenter.instance.unpin(e.key),
                  ),
                ),
              ]),
            ),
        ]),
      );
}

/// Bottone dentro un popup: esegue [action], mostra l'errore se va male, chiude se va bene.
class _PopupButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final List<Color> colors;
  final Future<void> Function() action;
  final VoidCallback? close;
  const _PopupButton({required this.label, this.icon, required this.colors, required this.action, this.close});
  @override
  State<_PopupButton> createState() => _PopupButtonState();
}

class _PopupButtonState extends State<_PopupButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DropButton(
          label: widget.label,
          icon: widget.icon,
          colors: widget.colors,
          height: 42,
          busy: _busy,
          onTap: () async {
            setState(() => _busy = true);
            try {
              await widget.action();
              widget.close?.call();
            } on _Cancelled {
              // annullato: niente da fare
            } catch (e) {
              if (context.mounted) snack(context, _err(e), error: true);
            }
            if (mounted) setState(() => _busy = false);
          },
        ),
      );
}

const spottedColors = [Color(0xFF5B6B8C), Color(0xFF9AA8C7)];

/// Ti hanno notato entrando in un settore: decidi tu per primo, prima che chi ti ha notato possa reagire.
///  - Eludi: resti nel settore ma ti nascondi (1 azione); chi ti ha notato perde l'occasione.
///  - Fune di fuga: scappi in un altro settore della zona (scegli quale).
///  - Resta: rimani allo scoperto e chi ti ha notato ottiene la priorità.
class SpottedActions extends StatelessWidget {
  final String party, uid;
  final VoidCallback close;
  const SpottedActions({super.key, required this.party, required this.uid, required this.close});

  Future<void> _rope(BuildContext context) async {
    final options = await TableService.escapeSectors(party, uid);
    if (options.isEmpty) throw Exception('Non ci sono altri settori liberi in cui fuggire');
    final pos = (await ItemService.userRef(uid).get()).data()?['pos'] as Map?;
    if (!context.mounted || pos == null) return;
    final zone = '${pos['zone']}';
    final to = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Dove fuggi?'), children: [
        for (final s in options)
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, s), child: Text(TableLayout.title(zone, s))),
        SimpleDialogOption(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla', style: TextStyle(color: Pal.sub))),
      ]),
    );
    if (to == null) throw const _Cancelled();
    await TableService.elude(party, uid, rope: true, toSector: to);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, dynamic>?>(
        stream: ItemService.watchUser(uid),
        builder: (context, snap) {
          final u = snap.data;
          final sp = u?['spotted'] as Map?;
          if (u != null && sp == null) {
            return const Text('Fatto: nessuno ti sta più osservando.', style: TextStyle(color: Pal.sub));
          }
          final ropes = ItemService.readInventory(u)['fune'] ?? 0;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (sp != null) ...[
              Text('Entrando in ${zoneSpec('${sp['zone']}').name}, ${TableLayout.title('${sp['zone']}', _i(sp['sector']))}, '
                  'qualcuno ti ha visto.',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Tiro ${sp['roll']} + destrezza = ${sp['total']}, serviva ${sp['cd']}.',
                  style: const TextStyle(color: Pal.sub, fontSize: 12)),
            ],
            const SizedBox(height: 4),
            const Text('Decidi tu per primo: chi ti ha notato può reagire solo se resti allo scoperto.',
                style: TextStyle(fontSize: 12)),
            _PopupButton(
              label: 'Eludi ($kEludeCost azione) · resti qui, nascosto',
              icon: Icons.visibility_off,
              colors: spottedColors,
              close: close,
              action: () => TableService.elude(party, uid),
            ),
            _PopupButton(
              label: 'Fune di fuga ×$ropes · fuggi in un altro settore',
              icon: Icons.logout,
              colors: const [Color(0xFFB5694F), Color(0xFFD9A07A)],
              close: close,
              action: ropes <= 0 ? () async => throw Exception('Non hai Funi di fuga') : () => _rope(context),
            ),
            _PopupButton(
              label: 'Resta allo scoperto',
              colors: Pal.neutral,
              close: close,
              action: () => TableService.face(party, uid),
            ),
          ]);
        },
      );
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Osservatore invisibile della Home: apre i popup degli eventi che riguardano il giocatore.
///  - hai notato qualcuno entrare nel tuo settore (priorità: sfida, abilità, strumento, lascia stare);
///  - ti hanno sfidato (Sfida dell'avversario) o la tua Imboscata è scattata;
///  - nuova fase del giorno (al tavolo).
/// Vittoria e sconfitta le apre la tab Battaglia ([showBattleResultPopup]).
class GamePopupsWatcher extends StatefulWidget {
  final ValueChanged<String> onBattle;
  const GamePopupsWatcher({super.key, required this.onBattle});
  @override
  State<GamePopupsWatcher> createState() => _GamePopupsWatcherState();
}

class _GamePopupsWatcherState extends State<GamePopupsWatcher> {
  StreamSubscription? _userSub, _stateSub;
  String? _party;
  int? _lastRound;
  late final String _uid;

  @override
  void initState() {
    super.initState();
    _uid = context.read<Session>().userName!;
    _userSub = ItemService.watchUser(_uid).listen(_onUser);
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  void _later(VoidCallback f) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) f();
      });

  void _onUser(Map<String, dynamic>? u) {
    final p = u?['actualParty'];
    final party = p is String && p.isNotEmpty ? p : null;
    if (party != _party) {
      _party = party;
      _lastRound = null;
      _stateSub?.cancel();
      if (party != null) _stateSub = TableService.watchState(party).listen(_onState);
    }
    if (party == null) return;
    final sp = u?['spotted'];
    if (kTableMode && sp is Map) {
      // ti hanno notato entrando: decidi tu per primo (eludere, fuggire con la Fune, restare)
      _later(() => showGamePopup(context,
          key: 'spotted:${sp['zone']}:${sp['sector']}:${sp['roll']}:${sp['total']}',
          title: 'Ti hanno notato!',
          colors: spottedColors,
          content: (context, close) => SpottedActions(party: party, uid: _uid, close: close)));
    }
    final pr = u?['priority'];
    if (kTableMode && pr is Map && TableService.priorityValid(u)) {
      final key = 'priority:${pr['target']}:${pr['untilAction']}';
      _later(() => showGamePopup(context,
          key: key, title: 'Hai notato ${pr['target']}!', colors: _spotColors, content: _priority(party, '${pr['target']}')));
    }
    final fb = u?['forcedBattle'];
    if (fb is Map) {
      _later(() => showGamePopup(context,
          key: 'forced:${fb['id']}', title: 'Sei stato sfidato!', colors: typeColors('Lotta'), content: _forced(fb)));
    }
    final am = u?['ambush'];
    if (am is Map) {
      _later(() => showGamePopup(context,
          key: 'ambush:${am['target']}:${am['round']}', title: 'Imboscata!', colors: typeColors('Buio'), content: _ambush(party, am)));
    }
  }

  void _onState(Map<String, dynamic>? st) {
    if (!kTableMode || kTableTurns || st?['started'] != true) return;
    final r = _i(st!['round']);
    final prev = _lastRound;
    _lastRound = r;
    if (prev == null || r <= prev) return;
    // la fase nuova sostituisce quella vecchia, anche se era fissata
    PopupCenter.instance.unpinWhere((k) => k.startsWith('phase:'));
    _later(() => showGamePopup(context,
        key: 'phase:$r', title: '${phaseIcon(r)} ${phaseLabel(r)}', colors: Pal.gold, content: _phase(_party!, r)));
  }

  static const _spotColors = [Color(0xFFC0563A), Color(0xFFE89A6A)];

  // ------------------------------------------------------------------ contenuti

  /// Hai notato qualcuno: con la priorità puoi sfidarlo, usare un'abilità o uno strumento, oppure lasciar stare.
  PopupContent _priority(String party, String target) => (context, close) => StreamBuilder<Map<String, dynamic>?>(
        stream: ItemService.watchUser(_uid),
        builder: (context, snap) {
          final u = snap.data;
          if (u != null && !TableService.priorityValid(u)) {
            return const Text('Non hai più la priorità: l’occasione è passata.', style: TextStyle(color: Pal.sub));
          }
          final left = _i((u?['priority'] as Map?)?['untilAction']) - TableClock.actions;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('$target è entrato nel tuo settore, ti ha visto e non si è nascosto. Hai la priorità: puoi reagire '
                'subito, anche se hai appena agito.'),
            const SizedBox(height: 4),
            Text('La priorità scade dopo ${left <= 1 ? 'la prossima azione' : 'altre $left azioni'} del gruppo.',
                style: const TextStyle(color: Pal.sub, fontSize: 12)),
            _PopupButton(
              label: 'Sfida $target ($kPriorityChallengeCost azione)',
              icon: Icons.sports_mma,
              colors: _spotColors,
              close: close,
              action: () async => widget.onBattle(await TableService.priorityChallenge(party, _uid)),
            ),
            AbilitiesCard(compact: true, onBattle: (id) {
              close();
              widget.onBattle(id);
            }),
            _PopupButton(
              label: 'Usa uno strumento',
              icon: Icons.backpack_outlined,
              colors: Pal.gold,
              action: () => showTableSheet(context, TableSheet.tools, party: party, me: _uid),
            ),
            _PopupButton(
              label: 'Lascia stare',
              colors: Pal.neutral,
              close: close,
              action: () => TableService.dropPriority(_uid),
            ),
          ]);
        },
      );

  /// Qualcuno ti ha sfidato (Sfida, Imboscata, priorità): la lotta è già cominciata.
  PopupContent _forced(Map fb) => (context, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${fb['by']} ti ha sfidato: la lotta è già iniziata e non puoi rifiutare.'),
        _PopupButton(
          label: 'Vai alla lotta',
          icon: Icons.sports_mma,
          colors: typeColors('Lotta'),
          close: close,
          action: () async {
            await AbilityService.dismissForcedBattle(_uid);
            widget.onBattle('${fb['id']}');
          },
        ),
      ]);

  /// La tua Imboscata è scattata: sfida chi è entrato (non costa azioni) o lascia stare.
  PopupContent _ambush(String party, Map am) => (context, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${am['target']} è arrivato nel tuo settore (${zoneSpec('${am['zone']}').name}). Puoi sfidarlo subito con '
            '+$kAmbushDice al dado nel primo turno: non può rifiutare e non costa azioni.'),
        _PopupButton(
          label: 'Sfida ${am['target']}',
          icon: Icons.sports_mma,
          colors: typeColors('Buio'),
          close: close,
          action: () async => widget.onBattle(await AbilityService.ambushChallenge(party, _uid)),
        ),
        _PopupButton(
          label: 'Lascia stare',
          colors: Pal.neutral,
          close: close,
          action: () => AbilityService.dismissAmbush(_uid),
        ),
      ]);

  /// Nuova fase del giorno: gli eventi di zona in corso e in arrivo.
  PopupContent _phase(String party, int round) => (context, close) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: TableService.watchEvents(party),
        builder: (context, snap) {
          final events = [
            for (final d in snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              if (d.data()['status'] == 'active' || d.data()['status'] == 'announced') d.data(),
          ];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('Inizia una nuova fase del giorno. Chi è in un rifugio ha recuperato PS ed energie.'),
            const SizedBox(height: 8),
            if (events.isEmpty)
              const Text('Nessun evento di zona in corso o in arrivo.', style: TextStyle(color: Pal.sub))
            else
              for (final e in events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${e['status'] == 'active' ? '⚠️' : '🔜'} ${eventDef('${e['defId']}').name} · '
                    '${zoneSpec('${e['zone']}').name} · '
                    '${e['status'] == 'active' ? untilLabel(_i(e['endRound']), round) : (_i(e['startRound']) >= TableService.kManualStart ? 'in arrivo' : whenLabel(_i(e['startRound']), round))}',
                  ),
                ),
          ]);
        },
      );

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
