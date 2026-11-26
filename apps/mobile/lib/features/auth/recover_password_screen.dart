import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'login_screen.dart';

Future<void> requestPasswordRecovery(GoTrueClient auth, String recipient, {required bool byPhone}) async {
  try {
    if (byPhone) {
      await auth.signInWithOtp(phone: recipient, shouldCreateUser: false);
    } else {
      await auth.resetPasswordForEmail(recipient, redirectTo: authRedirectUrl);
    }
  } on AuthRetryableFetchException catch (e) {
    if (e.statusCode == null) rethrow;
  } on AuthException {
    // La respuesta visible debe ser la misma aunque Auth no encuentre una cuenta.
  }
}

/// Recuperar la contraseña: código SMS al teléfono de la cuenta o enlace al correo.
class RecoverPasswordScreen extends StatefulWidget {
  const RecoverPasswordScreen({super.key, this.initial = ''});
  final String initial;

  @override
  State<RecoverPasswordScreen> createState() => _RecoverPasswordScreenState();
}

class _RecoverPasswordScreenState extends State<RecoverPasswordScreen> {
  late bool _byPhone = !widget.initial.contains('@');
  late final _id = TextEditingController(text: widget.initial);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _sentTo;
  bool _busy = false;
  bool _show = false;
  String? _error;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    // Si abre el enlace del correo, la raíz muestra la pantalla de nueva contraseña.
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery && mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _id.dispose();
    _code.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final byPhone = _byPhone;
    final recipient = byPhone ? normalizeHaitiPhone(_id.text)! : _id.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      await requestPasswordRecovery(auth, recipient, byPhone: byPhone);
      if (mounted) setState(() => _sentTo = recipient);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo solicitar la recuperación. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyAndSave() async {
    if (!_form.currentState!.validate()) return;
    final phone = _sentTo!;
    final code = _code.text.trim();
    final password = _password.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ProfileContext.set(AppProfile.collaborator);
      final verified = await auth.verifyOTP(type: OtpType.sms, phone: phone, token: code);
      if (verified.session == null || auth.currentUser?.id != verified.session!.user.id) {
        throw const AuthException('La sesión de recuperación no está disponible.');
      }
      await auth.updateUser(UserAttributes(password: password));
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Listo. Tu contraseña fue cambiada.')));
      nav.popUntil((r) => r.isFirst);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = switch (e.code) {
          'otp_expired' => 'El código no es correcto o ya venció.',
          'weak_password' => 'Elige una contraseña más segura.',
          'same_password' => 'Elige una contraseña distinta a la anterior.',
          _ => 'No se pudo cambiar la contraseña. Inténtalo de nuevo.',
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentTo != null;
    InputDecoration pass(String label) => InputDecoration(
          labelText: trn(label),
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _show = !_show),
          ),
        );
    return HtScaffold(
      background: Colors.white,
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            const ScreenTitle('Recuperar contraseña',
                icon: Icons.lock_reset, subtitle: 'Te ayudamos a entrar de nuevo a tu cuenta.'),
            const SizedBox(height: 18),
            if (!sent) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, icon: Icon(Icons.sms_outlined), label: Text('Por SMS')),
                  ButtonSegment(value: false, icon: Icon(Icons.mail_outline), label: Text('Por correo')),
                ],
                selected: {_byPhone},
                onSelectionChanged: _busy ? null : (v) => setState(() {
                  _byPhone = v.first;
                  _id.clear();
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: ValueKey(_byPhone),
                controller: _id,
                keyboardType: _byPhone ? TextInputType.phone : TextInputType.emailAddress,
                inputFormatters: _byPhone
                    ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)]
                    : null,
                decoration: InputDecoration(
                  labelText: trn(_byPhone ? 'Teléfono de tu cuenta' : 'Correo de tu cuenta'),
                  hintText: trn(_byPhone ? '37123456' : 'nombre@correo.com'),
                  prefixText: trn(_byPhone ? '+509 ' : null),
                  prefixIcon: Icon(_byPhone ? Icons.phone_outlined : Icons.mail_outline),
                ),
                validator: (v) => _byPhone
                    ? (normalizeHaitiPhone(v ?? '') == null ? tr('Escribe los 8 dígitos de tu teléfono') : null)
                    : ((v ?? '').contains('@') ? null : tr('Escribe un correo válido')),
              ),
              const SizedBox(height: 12),
              InfoBanner(_byPhone
                  ? 'Te enviaremos un código de 6 dígitos por SMS para crear una contraseña nueva.'
                  : 'Te enviaremos un enlace. Ábrelo desde este teléfono para crear la contraseña nueva.'),
            ] else if (_byPhone) ...[
              HtCard(
                color: HtColors.blueSoft,
                child: Text('Si hay una cuenta asociada a ${formatHaitiPhone(_sentTo)}, recibirás un código por SMS.',
                    style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                decoration: InputDecoration(labelText: trn('Código SMS'), hintText: trn('••••••')),
                validator: (v) => (v ?? '').length != 6 ? tr('El código tiene 6 dígitos') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: !_show,
                decoration: pass('Nueva contraseña'),
                validator: (v) => (v == null || v.length < 8) ? tr('Mínimo 8 caracteres') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _repeat,
                obscureText: !_show,
                decoration: pass('Repite la contraseña'),
                validator: (v) => v != _password.text ? tr('Las contraseñas no coinciden') : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : () => setState(() => _sentTo = null),
                  child: const Text('Cambiar número o reenviar código'),
                ),
              ),
            ] else ...[
              const Center(child: Icon(Icons.mark_email_read_outlined, size: 72, color: HtColors.green)),
              const SizedBox(height: 10),
              Text('Si hay una cuenta asociada a $_sentTo, recibirás un enlace para crear tu contraseña nueva.',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.35)),
              const SizedBox(height: 10),
              TextButton(onPressed: () => setState(() => _sentTo = null), child: const Text('No me llegó, enviar otra vez')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: HtColors.red)),
            ],
            const SizedBox(height: 18),
            if (!sent)
              FilledButton.icon(
                onPressed: _busy ? null : _send,
                icon: _busy ? const _Spin() : Icon(_byPhone ? Icons.sms_outlined : Icons.send),
                label: Text(_byPhone ? 'Enviar código' : 'Enviar enlace'),
              )
            else if (_byPhone)
              FilledButton.icon(
                onPressed: _busy ? null : _verifyAndSave,
                icon: _busy ? const _Spin() : const Icon(Icons.check),
                label: const Text('Guardar contraseña y entrar'),
              ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: const Text('Volver a iniciar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spin extends StatelessWidget {
  const _Spin();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
}
