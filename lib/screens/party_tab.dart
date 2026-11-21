import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/party_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/clues_card.dart';
import '../widgets/common.dart';
import '../widgets/drop.dart';

/// Tab "Party": codice del party, giocatori e indizi sulla mappa.
class PartyTab extends StatefulWidget {
  const PartyTab({super.key});
  @override
  State<PartyTab> createState() => _PartyTabState();
}

class _PartyTabState extends State<PartyTab> {
  final _code = TextEditingController();
  String? _party;
  bool _loading = true;

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    if (_party == null) return _joinBox();
    final uid = context.read<Session>().userName!;
    final color = context.read<Session>().color;
    final c = [color, lighten(color, 0.4)];

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: PartyService.players(_party!).doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && snap.data == null) {
          return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
        }
        if (snap.data?.data() == null) return _joinBox();
        return Column(children: [
          DropCard(
            colors: c,
            label: 'Party',
            labelOnTop: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_party!, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: PartyService.players(_party!).snapshots(),
                builder: (context, ps) {
                  final docs = ps.data?.docs ?? [];
                  return Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final d in docs)
                      InfoChip(
                        d.data()['symbol'] != null ? '${d.id} · ${d.data()['symbol']}' : d.id,
                        color: d.id == uid ? color : Pal.sub,
                      ),
                  ]);
                },
              ),
            ]),
          ),
          CluesCard(party: _party!, uid: uid),
        ]);
      },
    );
  }

  Widget _joinBox() {
    return DropCard(
      colors: const [Pal.accent, Color(0xFF9C7BE0)],
      label: 'Party',
      labelOnTop: true,
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
