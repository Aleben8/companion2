import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../services/session.dart';
import '../widgets/common.dart';

/// Configurazione delle 2 mosse del Pokémon.
/// Salva in Users/{u}/Pokemon/{p}/MoveSet/{MoveName}:
///   MoveName, MoveType (tipo), MoveTypo (Fisico|Speciale), Dmg (1-7), Description,
///   AltEffect (Rallentamento|Danno|Debuff), targetStat, AltDmg, AltStatusPerc,
///   altStatus / altStatusName (letti dal tipo in "Tipi").
class MovesScreen extends StatefulWidget {
  const MovesScreen({super.key});
  @override
  State<MovesScreen> createState() => _MovesScreenState();
}

class _MovesScreenState extends State<MovesScreen> {
  final _form = GlobalKey<FormState>();
  final List<Map<String, dynamic>> _moves = [
    {'Dmg': 1},
    {'Dmg': 1},
  ];
  final _names = [TextEditingController(), TextEditingController()];
  final _desc = [TextEditingController(), TextEditingController()];
  bool _saving = false;

  static const _effects = {
    'Rallentamento': 'Riduce la velocità del bersaglio.',
    'Danno': 'Infligge un piccolo danno bonus nel turno successivo.',
    'Debuff': 'Riduce una statistica del bersaglio.',
  };
  static const _debuffStats = {
    'Atk': 'Attacco',
    'AtkSpec': 'Attacco Speciale',
    'Def': 'Difesa',
    'DefSpec': 'Difesa Speciale',
  };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    for (var i = 0; i < 2; i++) {
      if (_moves[i]['MoveType'] == null) {
        snack(context, 'Seleziona il TIPO ELEMENTALE per la Mossa ${i + 1}');
        return;
      }
      if (_moves[i]['MoveTypo'] == null) {
        snack(context, 'Seleziona FISICO o SPECIALE per la Mossa ${i + 1}');
        return;
      }
    }
    setState(() => _saving = true);
    final s = context.read<Session>();
    final db = FirebaseFirestore.instance;
    try {
      for (var i = 0; i < 2; i++) {
        final m = Map<String, dynamic>.from(_moves[i]);
        m['MoveName'] = _names[i].text.trim();
        m['Description'] = _desc[i].text.trim();
        final dmg = (m['Dmg'] as int?) ?? 0;
        final perc = altStatusChanceForDmg(dmg);
        m['AltDmg'] = dmg;
        m['AltStatusPerc'] = perc;
        // Per "Danno" il bersaglio è sempre la vita; per "Rallentamento" la velocità.
        if (m['AltEffect'] == 'Danno') m['targetStat'] = 'PkmLife';
        if (m['AltEffect'] == 'Rallentamento') m['targetStat'] = 'Vel';
        var altStatus = '';
        var altStatusName = '';
        if (perc > 0) {
          final t = await db.collection('Tipi').doc(m['MoveType'] as String).get();
          if (t.exists) {
            altStatus = (t.data()?['altStatus'] ?? '').toString();
            altStatusName = (t.data()?['altStatusName'] ?? '').toString();
          }
        }
        m['altStatus'] = altStatus;
        m['altStatusName'] = altStatusName;
        await s.pokemonRef.collection('MoveSet').doc(m['MoveName'] as String).set(m);
      }
      if (!mounted) return;
      snack(context, 'Mosse, Danni ed Effetti salvati!');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) snack(context, 'Errore: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _moveForm(int i) {
    final m = _moves[i];
    final dmg = (m['Dmg'] as int?) ?? 1;
    final effect = m['AltEffect'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Mossa ${i + 1}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextFormField(
            controller: _names[i],
            decoration: const InputDecoration(labelText: 'Nome mossa', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Inserisci nome' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: m['MoveType'] as String?,
            decoration: const InputDecoration(labelText: 'Tipo Elementale', border: OutlineInputBorder()),
            items: [
              for (final t in kTypes)
                DropdownMenuItem(
                  value: t,
                  child: Row(children: [TypeIcon(t, size: 22), const SizedBox(width: 8), Text(t)]),
                ),
            ],
            onChanged: (v) => setState(() => m['MoveType'] = v),
          ),
          const SizedBox(height: 12),
          const Text('Categoria'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Fisico', label: Text('Fisico')),
              ButtonSegment(value: 'Speciale', label: Text('Speciale')),
            ],
            emptySelectionAllowed: true,
            selected: {if (m['MoveTypo'] != null) m['MoveTypo'] as String},
            onSelectionChanged: (s) => setState(() => m['MoveTypo'] = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Text('Danno: $dmg   •   Energia: ${energyCostForDmg(dmg)}   •   '
                  'Prob. effetto: ${altStatusChanceForDmg(dmg)}'),
            ),
          ]),
          Slider(
            value: dmg.toDouble(),
            min: 1,
            max: 7,
            divisions: 6,
            label: '$dmg',
            onChanged: (v) => setState(() => m['Dmg'] = v.round()),
          ),
          DropdownButtonFormField<String>(
            value: effect,
            decoration: const InputDecoration(labelText: 'Effetto alterato', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('Nessuno')),
              for (final e in _effects.entries)
                DropdownMenuItem(value: e.key, child: Text('${e.key} — ${e.value}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              m['AltEffect'] = v;
              m['targetStat'] = null;
            }),
          ),
          if (effect == 'Debuff') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: m['targetStat'] as String?,
              decoration: const InputDecoration(labelText: 'Stat colpita', border: OutlineInputBorder()),
              items: [
                for (final e in _debuffStats.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => m['targetStat'] = v),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _desc[i],
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Descrizione', border: OutlineInputBorder()),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mosse')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _moveForm(0),
            _moveForm(1),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salva mosse'),
            ),
          ],
        ),
      ),
    );
  }
}
