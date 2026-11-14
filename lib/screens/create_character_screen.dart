import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../services/item_service.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import 'moves_screen.dart';

/// "Crea Giocatore e Pokémon": nome utente, nome Pokémon, tipi,
/// 5 statistiche (0-15, totale max 30) e colore identificativo.
class CreateCharacterScreen extends StatefulWidget {
  const CreateCharacterScreen({super.key});
  @override
  State<CreateCharacterScreen> createState() => _CreateCharacterScreenState();
}

class _CreateCharacterScreenState extends State<CreateCharacterScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _name = TextEditingController();
  final Map<String, TextEditingController> _stats = {
    for (final k in kStatLabels.keys) k: TextEditingController(text: '0'),
  };
  String? _primary;
  String? _secondary;
  Color _color = kDefaultColor;
  bool _saving = false;

  int get _total => _stats.values.fold(0, (s, c) => s + (int.tryParse(c.text) ?? 0));

  String? _statValidator(String? v) {
    if (v == null || v.isEmpty) return 'Richiesto';
    final n = int.tryParse(v);
    if (n == null) return 'Usa numeri';
    if (n < 0) return 'Min 0';
    if (n > kStatMax) return 'Max $kStatMax';
    return null;
  }

  Future<void> _pickColor() async {
    var tmp = _color;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seleziona un colore'),
        content: SingleChildScrollView(
          child: BlockPicker(pickerColor: _color, onColorChanged: (c) => tmp = c),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _color = tmp);
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_primary == null) {
      snack(context, 'Seleziona il tipo primario', error: true);
      return;
    }
    if (_total > kStatPointsTotal) {
      snack(context, 'Errore: Totale statistiche $_total/$kStatPointsTotal. Riduci i punti!', error: true);
      return;
    }
    setState(() => _saving = true);
    final db = FirebaseFirestore.instance;
    final user = _user.text.trim();
    final pk = _name.text.trim();
    try {
      final userRef = db.collection('Users').doc(user);
      if ((await userRef.get()).exists) {
        if (mounted) snack(context, 'Utente già esistente!', error: true);
        return;
      }
      // Resistenze e debolezze vengono dal tipo primario (collezione "Tipi").
      var resist = <String>[];
      var weak = <String>[];
      final t = await db.collection('Tipi').doc(_primary).get();
      if (t.exists) {
        resist = List<String>.from(t.data()?['Resistenze'] ?? []);
        weak = List<String>.from(t.data()?['Debolezze'] ?? []);
      }
      await userRef.set({'UserName': user, 'inventory': ItemService.startingInventory()});
      await userRef.collection('Pokemon').doc(pk).set({
        'PkmName': pk,
        'PkmTypePrim': _primary,
        'PkmTypeSec': _secondary ?? '',
        for (final e in _stats.entries) e.key: int.parse(e.value.text),
        'PokemonDocumentID': pk,
        'PkmExp': 0,
        'PkmInitialLife': kInitialLife,
        'PkmLife': kInitialLife,
        'PkmLv': 1,
        'Resistenze': resist,
        'Debolezze': weak,
        'Color': Session.colorToHex(_color),
      });
      if (!mounted) return;
      await context.read<Session>().enter(user, pk);
      if (!mounted) return;
      snack(context, 'Base salvata! Configura le mosse.');
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MovesScreen()));
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) snack(context, 'Errore di salvataggio: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _typeDropdown(String label, String? value, ValueChanged<String?> onChanged,
      {bool optional = false}) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        if (optional)
          const DropdownMenuItem(value: '', child: Text('Nessuno')),
        for (final t in kTypes)
          DropdownMenuItem(
            value: t,
            child: Row(children: [TypeIcon(t, size: 22), const SizedBox(width: 8), Text(t)]),
          ),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final over = _total > kStatPointsTotal;
    return Scaffold(
      appBar: AppBar(title: const Text('Crea Giocatore e Pokémon')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _user,
              decoration: const InputDecoration(labelText: 'Nome Utente', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Inserisci username' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome Pokémon', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Inserisci nome Pokémon' : null,
            ),
            const SizedBox(height: 14),
            _typeDropdown('Tipo primario', _primary, (v) => setState(() => _primary = v)),
            const SizedBox(height: 14),
            _typeDropdown('Tipo secondario', _secondary ?? '',
                (v) => setState(() => _secondary = (v == null || v.isEmpty) ? null : v),
                optional: true),
            const SizedBox(height: 20),
            for (final e in kStatLabels.entries) ...[
              TextFormField(
                controller: _stats[e.key],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: e.value, border: const OutlineInputBorder()),
                validator: _statValidator,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Punti Statistica Totali: $_total / $kStatPointsTotal',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, color: over ? Colors.red : null),
            ),
            if (over)
              Text('Hai superato il limite di $kStatPointsTotal punti!',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickColor,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Colore Identificativo', border: OutlineInputBorder()),
                child: Row(children: [
                  Expanded(child: Text('Tocca per scegliere: ${Session.colorToHex(_color)}')),
                  CircleAvatar(radius: 14, backgroundColor: _color),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salva e configura le mosse'),
            ),
          ],
        ),
      ),
    );
  }
}
