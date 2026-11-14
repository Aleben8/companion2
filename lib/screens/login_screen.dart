import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session.dart';
import 'create_character_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pokemon = TextEditingController();
  String? _error;

  Future<void> _login() async {
    final u = _user.text.trim();
    final p = _pokemon.text.trim();
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Inserisci entrambi i campi');
      return;
    }
    final ok = await context.read<Session>().login(u, p);
    if (!ok && mounted) setState(() => _error = 'Utente o Pokémon non trovati!');
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<Session>().loading;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _user,
                  decoration: const InputDecoration(labelText: 'Nome Utente', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pokemon,
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(labelText: 'Pokemon', border: OutlineInputBorder()),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: loading ? null : _login,
                  child: loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Accedi'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CreateCharacterScreen()),
                  ),
                  child: const Text('Crea Giocatore e Pokémon'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
