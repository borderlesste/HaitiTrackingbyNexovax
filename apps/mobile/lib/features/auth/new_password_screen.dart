import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Mínimo 8 caracteres');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: _password.text));
      widget.onDone();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva contraseña')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Escribe tu nueva contraseña.'),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Nueva contraseña', errorText: _error),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar')),
        ],
      ),
    );
  }
}
