import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../services/party_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Gestione Party": cambio/ingresso party e colore del Pokémon.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _newParty = TextEditingController();
  String? _party;
  List<String> _parties = [];
  Color _color = kDefaultColor;
  bool _loading = true;
  bool _busy = false;

  Session get _s => context.read<Session>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = _s.userName!;
      _party = await PartyService.actualParty(uid);
      _parties = await PartyService.myParties(uid);
      if (_party != null && !_parties.contains(_party)) _parties = [..._parties, _party!];
      _color = _s.color;
    } catch (e) {
      debugPrint('Errore load settings: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _switch(String code) async {
    setState(() => _busy = true);
    try {
      await PartyService.switchParty(_s.userName!, code);
      _party = code;
      if (mounted) snack(context, 'Passato al party: $code');
    } catch (e) {
      debugPrint('Errore switch: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _joinNew() async {
    final code = _newParty.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      await PartyService.join(_s.userName!, code);
      _party = code;
      if (!_parties.contains(code)) _parties = [..._parties, code];
      _newParty.clear();
      if (mounted) snack(context, 'Benvenuto in $code!');
    } catch (e) {
      if (mounted) snack(context, 'Errore join: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickColor() async {
    var tmp = _color;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seleziona un colore'),
        content: SingleChildScrollView(child: BlockPicker(pickerColor: _color, onColorChanged: (c) => tmp = c)),
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

  Future<void> _saveAndBack() async {
    setState(() => _busy = true);
    try {
      await _s.pokemonRef.set({'Color': Session.colorToHex(_color)}, SetOptions(merge: true));
      if (mounted) {
        snack(context, 'Impostazioni salvate!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) snack(context, 'Errore: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    const card = Colors.white;
    const white = TextStyle(color: Pal.ink);
    final name = _s.pokemon?['PkmName'] ?? _s.pokemonId ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestione Party'),
        actions: [
          IconButton(
            tooltip: 'Esci',
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              context.read<Session>().logout();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Pal.line, width: 2)),
                  child: Column(children: [
                    DropdownButtonFormField<String>(
                      value: _parties.contains(_party) ? _party : null,
                      dropdownColor: card,
                      style: white.copyWith(fontSize: 18),
                      decoration: const InputDecoration(
                        labelText: 'Party Corrente',
                        labelStyle: TextStyle(color: Pal.sub),
                      ),
                      items: [for (final p in _parties) DropdownMenuItem(value: p, child: Text(p))],
                      onChanged: _busy ? null : (v) => v == null ? null : _switch(v),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _newParty,
                          style: white,
                          decoration: const InputDecoration(
                            hintText: 'Codice nuovo party',
                            hintStyle: TextStyle(color: Pal.sub, fontSize: 20),
                          ),
                          onSubmitted: (_) => _joinNew(),
                        ),
                      ),
                      IconButton(
                        onPressed: _busy ? null : _joinNew,
                        icon: const CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(0xFF4A90F0),
                          child: Icon(Icons.add, color: Colors.black87),
                        ),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(height: 24),
                Text('Personalizzazione Colore per: $name', style: white.copyWith(fontSize: 24, fontWeight: FontWeight.w500)),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickColor,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Colore Identificativo',
                      labelStyle: TextStyle(color: Pal.sub),
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Pal.sub)),
                    ),
                    child: Row(children: [
                      Expanded(child: Text('Tocca per scegliere: ${Session.colorToHex(_color)}', style: white.copyWith(fontSize: 18))),
                      CircleAvatar(radius: 18, backgroundColor: _color),
                    ]),
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  height: 64,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Pal.accent),
                    onPressed: _busy ? null : _saveAndBack,
                    child: const Text('SALVA E TORNA AL GIOCO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
    );
  }
}
