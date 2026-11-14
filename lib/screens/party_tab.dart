import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/party_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/drop.dart';

/// Tab "Party": numero del giocatore, assegnazione di numero + indizio a un
/// altro giocatore e lista degli "Indizi del Party".
class PartyTab extends StatefulWidget {
  const PartyTab({super.key});
  @override
  State<PartyTab> createState() => _PartyTabState();
}

class _PartyTabState extends State<PartyTab> {
  final _code = TextEditingController();
  final _riddle = TextEditingController();
  String? _party;
  String? _target;
  dynamic _myNumber;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadParty();
  }

  Future<void> _loadParty() async {
    final uid = context.read<Session>().userName!;
    try {
      _party = await PartyService.actualParty(uid);
    } catch (e) {
      debugPrint('Errore nel recupero del party utente: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _join() async {
    if (_code.text.trim().isEmpty) return;
    final uid = context.read<Session>().userName!;
    setState(() => _loading = true);
    try {
      await PartyService.join(uid, _code.text);
      _party = _code.text.trim();
    } catch (e) {
      if (mounted) snack(context, 'Errore durante il join: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _assign() async {
    if (_target == null || _party == null || _riddle.text.trim().isEmpty) {
      snack(context, 'Seleziona un giocatore e scrivi un indizio!');
      return;
    }
    final n = int.tryParse('$_myNumber');
    if (n == null) {
      snack(context, 'Il tuo numero non è ancora disponibile', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await PartyService.assignNumberAndRiddle(code: _party!, targetUid: _target!, number: n, riddle: _riddle.text);
      if (mounted) {
        snack(context, 'Numero e indizio assegnati!');
        _riddle.clear();
      }
    } catch (e) {
      if (mounted) snack(context, 'Errore assegnazione: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    if (_party == null) return _joinBox();
    final uid = context.read<Session>().userName!;
    final color = context.read<Session>().color;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: PartyService.players(_party!).doc(uid).snapshots(),
      builder: (context, snap) {
        final me = snap.data?.data();
        if (snap.connectionState == ConnectionState.waiting && me == null) {
          return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
        }
        if (me == null) return _joinBox();
        _myNumber = me['number'] ?? '?';
        final visible = me['numberVisibility'] == true;
        final assigned = me['assignedNumber'];
        final c = [color, lighten(color, 0.4)];
        return Column(children: [
          DropCard(
            colors: c,
            label: 'Party',
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_party!, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
                  const SizedBox(height: 2),
                  const Text('Il tuo numero di giocatore', style: TextStyle(color: Pal.sub, fontSize: 12)),
                ]),
              ),
              Container(
                width: 70,
                height: 70,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: c)),
                child: Text('$_myNumber', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          DropCard(
            colors: const [Color(0xFF3E8CA8), Color(0xFF7FBCD0)],
            label: 'Il tuo numero',
            child: Row(children: [
              Expanded(
                child: Text(
                  visible ? 'Hai sbloccato il numero che ti è stato assegnato!' : 'Vinci una battaglia per sbloccarlo.',
                  style: const TextStyle(color: Pal.sub, fontStyle: FontStyle.italic, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Container(
                  key: ValueKey(visible),
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: visible ? Pal.ok : Pal.line,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(22),
                      bottomRight: Radius.circular(22),
                      topRight: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: visible && assigned != null
                      ? Text('$assigned', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800))
                      : const Icon(Icons.lock_outline, color: Pal.sub),
                ),
              ),
            ]),
          ),
          DropCard(
            colors: const [Color(0xFFF2884B), Color(0xFFE0337A)],
            label: 'Indizio',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Assegna il tuo numero a un giocatore', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 10),
              _playerDropdown(uid),
              const SizedBox(height: 10),
              TextField(
                controller: _riddle,
                decoration: const InputDecoration(
                  hintText: "Scrivi qui l'indizio…",
                  filled: true,
                  fillColor: Pal.bg,
                  border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
              ),
              const SizedBox(height: 12),
              DropButton(
                label: 'Assegna Numero & Indizio',
                icon: Icons.send,
                colors: const [Color(0xFFF2884B), Color(0xFFE0337A)],
                busy: _busy,
                onTap: _assign,
              ),
            ]),
          ),
          _clues(uid),
        ]);
      },
    );
  }

  Widget _playerDropdown(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PartyService.players(_party!).snapshots(),
      builder: (context, snap) {
        final docs = (snap.data?.docs ?? []).where((d) => d.id != uid).toList();
        if (docs.isEmpty) {
          return const Text("Sei l'unico nel party!", style: TextStyle(color: Pal.sub));
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: Pal.bg, borderRadius: BorderRadius.circular(14)),
          child: DropdownButton<String>(
            isExpanded: true,
            underline: const SizedBox(),
            value: docs.any((d) => d.id == _target) ? _target : null,
            hint: const Text('Seleziona giocatore', style: TextStyle(color: Pal.sub)),
            items: [
              for (final d in docs)
                DropdownMenuItem(
                  value: d.id,
                  child: Text((d.data()['nickname'] ?? d.data()['userId'] ?? 'Giocatore ${d.data()['number']}').toString()),
                ),
            ],
            onChanged: (v) => setState(() => _target = v),
          ),
        );
      },
    );
  }

  Widget _clues(String uid) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: PartyService.party(_party!).snapshots(),
      builder: (context, partySnap) {
        final unlocked = partySnap.data?.data()?['riddleView'] == true;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: PartyService.players(_party!).snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            return DropCard(
              colors: unlocked ? const [Pal.ok, Color(0xFF9BDFA0)] : Pal.neutral,
              label: 'Indizi del Party',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(unlocked ? Icons.lock_open : Icons.lock_outline, size: 18, color: unlocked ? Pal.ok : Pal.sub),
                  const SizedBox(width: 8),
                  InfoChip(unlocked ? 'SBLOCCATI' : 'BLOCCATI', color: unlocked ? Pal.ok : Pal.sub),
                ]),
                const SizedBox(height: 10),
                if (docs.isEmpty) const Text('Nessun giocatore nel party', style: TextStyle(color: Pal.sub)),
                for (final d in docs) _clueTile(d, uid, unlocked),
              ]),
            );
          },
        );
      },
    );
  }

  Widget _clueTile(QueryDocumentSnapshot<Map<String, dynamic>> d, String uid, bool unlocked) {
    final riddle = (d.data()['riddle'] ?? '').toString();
    final mine = d.id == uid;
    final text = unlocked ? (riddle.isEmpty ? 'Nessun indizio assegnato' : riddle) : 'Indizio bloccato';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: mine ? const Color(0xFFEAF2FF) : Pal.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mine ? const Color(0xFF448AFF) : Pal.line, width: mine ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InfoChip(d.id, color: mine ? const Color(0xFF448AFF) : Pal.sub),
        const SizedBox(height: 6),
        Text(text,
            style: TextStyle(
              color: unlocked ? Pal.ink : Pal.sub,
              fontStyle: unlocked ? FontStyle.italic : FontStyle.normal,
              fontSize: 15,
            )),
      ]),
    );
  }

  Widget _joinBox() {
    return DropCard(
      colors: const [Pal.accent, Color(0xFF9C7BE0)],
      label: 'Party',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Inserisci il codice del party', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          onSubmitted: (_) => _join(),
          decoration: const InputDecoration(
            hintText: 'Codice party',
            filled: true,
            fillColor: Pal.bg,
            border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(14))),
          ),
        ),
        const SizedBox(height: 12),
        DropButton(label: 'Entra nel Party', icon: Icons.login, onTap: _join),
      ]),
    );
  }
}
