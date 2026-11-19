import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/brand_header.dart';

/// Enlace que abre la app desde los correos de confirmación y de recuperación.
const authRedirectUrl = 'com.nexovax.haititracking://login-callback';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (_registering) {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'full_name': _name.text.trim()},
          emailRedirectTo: authRedirectUrl,
        );
        if (res.session == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cuenta creada. Revisa tu correo para confirmarla.'),
          ));
        }
      } else {
        await auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Escribe tu correo para recuperar la contraseña.');
      return;
    }
    await Supabase.instance.client.auth.resetPasswordForEmail(email, redirectTo: authRedirectUrl);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Te enviamos un enlace para restablecer la contraseña.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const BrandHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _registering ? 'Crear cuenta' : 'Iniciar sesión',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text('Completa misiones en el mapa y gana recompensas.'),
                    const SizedBox(height: 20),
                    if (_registering) ...[
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Nombre completo', prefixIcon: Icon(Icons.person_outline)),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().length < 3) ? 'Escribe tu nombre' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline)),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      validator: (v) => (v == null || !v.contains('@')) ? 'Correo no válido' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline)),
                      obscureText: true,
                      validator: (v) => (v == null || v.length < 8) ? 'Mínimo 8 caracteres' : null,
                    ),
                    if (!_registering)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('¿Olvidaste tu contraseña?')),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_registering ? 'Registrarme' : 'Entrar'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _registering = !_registering),
                      child: Text(_registering ? '¿Ya tienes cuenta? Inicia sesión' : '¿No tienes cuenta? Regístrate'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
