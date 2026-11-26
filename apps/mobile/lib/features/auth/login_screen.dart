import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'register_screen.dart';

/// Enlace que abre la app desde los correos de confirmación y de recuperación.
const authRedirectUrl = 'com.nexovax.haititracking://login-callback';

/// Inicio de sesión con teléfono (cuentas nuevas) o correo (cuentas anteriores) y contraseña.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // Al iniciar sesión se vuelve a la raíz, donde AuthGate ya muestra la app.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session != null && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _id.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _isEmail => _id.text.contains('@');

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      // Al entrar se abre siempre la app del colaborador (Empresa/Desarrollador se eligen luego en el menú).
      await ProfileContext.set(AppProfile.collaborator);
      if (_isEmail) {
        await auth.signInWithPassword(email: _id.text.trim(), password: _password.text);
      } else {
        await auth.signInWithPassword(phone: normalizeHaitiPhone(_id.text)!, password: _password.text);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message.toLowerCase().contains('invalid') ? 'Datos de acceso incorrectos.' : e.message);
    } catch (_) {
      setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _id.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Para recuperar la contraseña escribe el correo de tu cuenta. '
          'Si te registraste con teléfono, contacta a soporte desde la app.');
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
    return HtScaffold(
      background: Colors.white,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            const ScreenTitle('Iniciar sesión',
                icon: Icons.login, subtitle: 'Completa misiones en el mapa y gana recompensas.'),
            const SizedBox(height: 22),
            TextFormField(
              controller: _id,
              decoration: const InputDecoration(
                labelText: 'Teléfono o correo',
                hintText: '37 12 34 56',
                prefixIcon: Icon(Icons.person_outline),
              ),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.email],
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.contains('@')) return null;
                return normalizeHaitiPhone(s) == null ? 'Escribe tu teléfono (8 dígitos) o tu correo' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.length < 8) ? 'Mínimo 8 caracteres' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('¿Olvidaste tu contraseña?')),
            ),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: HtColors.red)),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.login),
              label: const Text('Entrar'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RegisterScreen())),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Crear una cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}
