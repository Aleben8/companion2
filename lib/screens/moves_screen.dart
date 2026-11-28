import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../mode.dart';
import '../services/battle_service.dart';
import '../services/item_service.dart';
import '../services/session.dart';
import '../widgets/common.dart';

/// Configurazione delle 2 mosse del Pokémon.
/// Salva in Users/{u}/Pokemon/{p}/MoveSet/{MoveName}:
///   MoveName, MoveType (tipo), MoveTypo (Fisico|Speciale), Dmg (1-7), Description,
///   AltEffect (Rallentamento|Danno|Debuff), targetStat, AltDmg, AltStatusPerc,
///   altStatus / altStatusName (letti dal tipo in "Tipi").
///
/// Con [replaceWithTm] è la modalità "sostituisci una mossa" della MT: scegli quale delle 2 mosse
/// sovrascrivere e la ricrei con le stesse regole; la MT si consuma solo al salvataggio.
class MovesScreen extends StatefulWidget {
  final bool replaceWithTm;
  final String? party; // serve alla MT (costo dell'azione al tavolo)
  const MovesScreen({super.key, this.replaceWithTm = false, this.party});
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
  // MT: mosse attuali e quale si sovrascrive
  List<String>? _current;
  String? _replace;

  @override
  void initState() {
    super.initState();
    if (widget.replaceWithTm) _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final s = context.read<Session>();
    final moves = await BattleService.loadMoves(s.userName!, s.pokemonId!);
    if (!mounted) return;
    setState(() {
      _current = moves.keys.toList()..sort();
      _replace = _current!.isEmpty ? null : _current!.first;
    });
  }

  /// La mossa [i] come si salva in MoveSet (stesse regole della creazione).
  Future<Map<String, dynamic>> _build(int i) async {
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
      final t = await FirebaseFirestore.instance.collection('Tipi').doc(m['MoveType'] as String).get();
      if (t.exists) {
        altStatus = (t.data()?['altStatus'] ?? '').toString();
        altStatusName = (t.data()?['altStatusName'] ?? '').toString();
      }
    }
    m['altStatus'] = altStatus;
    m['altStatusName'] = altStatusName;
    return m;
  }

  /// MT: salva la nuova mossa al posto di quella scelta (e consuma la MT).
  Future<void> _saveTm() async {
    if (!_form.currentState!.validate()) return;
    if (_replace == null) return snack(context, 'Scegli quale mossa sovrascrivere');
    if (_moves[0]['MoveType'] == null) return snack(context, 'Seleziona il TIPO ELEMENTALE della nuova mossa');
    if (_moves[0]['MoveTypo'] == null) return snack(context, 'Seleziona FISICO o SPECIALE per la nuova mossa');
    final name = _names[0].text.trim();
    if (name != _replace && (_current ?? const []).contains(name)) {
      return snack(context, 'Il tuo Pokémon ha già una mossa con questo nome');
    }
    setState(() => _saving = true);
    final s = context.read<Session>();
    try {
      await ItemService.replaceMoveWithTm(
        uid: s.userName!,
        party: widget.party!,
        pk: s.pokemonId!,
        oldMove: _replace!,
        newMove: await _build(0),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
    try {
      for (var i = 0; i < 2; i++) {
        final m = await _build(i);
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
          Text(widget.replaceWithTm ? 'Nuova mossa' : 'Mossa ${i + 1}', style: Theme.of(context).textTheme.titleLarge),
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

  /// MT: quale mossa sovrascrivere, poi il modulo di una sola mossa.
  Widget _tmBody() {
    if (_current == null) return const Center(child: CircularProgressIndicator());
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Scegli quale mossa sovrascrivere e crea quella nuova, di qualsiasi tipo. '
            'La MT si consuma solo quando salvi; se torni indietro resta nella borsa.'),
        const SizedBox(height: 12),
        if (_current!.isEmpty)
          const Text('Il tuo Pokémon non ha ancora mosse: configurale da Impostazioni.')
        else
          SegmentedButton<String>(
            segments: [for (final m in _current!) ButtonSegment(value: m, label: Text(m, overflow: TextOverflow.ellipsis))],
            selected: {if (_replace != null) _replace!},
            onSelectionChanged: (v) => setState(() => _replace = v.first),
          ),
        const SizedBox(height: 16),
        _moveForm(0),
        FilledButton(
          onPressed: _saving || _replace == null ? null : _saveTm,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(kTableMode ? 'Salva la nuova mossa (1 azione)' : 'Salva la nuova mossa'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.replaceWithTm) {
      return Scaffold(appBar: AppBar(title: const Text('MT · sostituisci una mossa')), body: _tmBody());
    }
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
