import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/otp_input.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Verifica por SMS el número MonCash antes de retirar. Es el único momento en que se pide un código.
/// Si es el mismo número de la cuenta se envía un código de inicio de sesión; si es otro, se cambia el
/// número de la cuenta con su propio código. La función del servidor verifica el código y registra la prueba.
class VerifyPhoneScreen extends StatefulWidget {
  const VerifyPhoneScreen({super.key});

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  late final String? _ownerId;
  String? _sentTo;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _ownerId = user?.id;
    final p = user?.phone ?? '';
    final d = p.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11 && d.startsWith('509')) _phone.text = d.substring(3);
  }

  String? get _accountPhone {
    final p = Supabase.instance.client.auth.currentUser?.phone ?? '';
    return p.isEmpty ? null : (p.startsWith('+') ? p : '+$p');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    if (session == null || session.user.id != _ownerId) return;
    final phone = normalizeHaitiPhone(_phone.text);
    if (phone == null) return setState(() => _error = 'Escribe un número haitiano de 8 dígitos.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final refreshedUser = (await auth.getUser(session.accessToken)).user;
      if (!mounted || refreshedUser?.id != _ownerId || auth.currentUser?.id != _ownerId) return;
      if (normalizeHaitiPhone(refreshedUser?.phone ?? '') == phone) {
        await auth.signInWithOtp(phone: phone, shouldCreateUser: false);
      } else {
        final changed = await auth.updateUser(UserAttributes(phone: phone));
        if (!mounted || changed.user?.id != _ownerId || auth.currentUser?.id != _ownerId) return;
        // Con autoconfirmación, el cambio actualiza el número sin enviar un código.
        if (normalizeHaitiPhone(changed.user?.phone ?? '') == phone) {
          await auth.signInWithOtp(phone: phone, shouldCreateUser: false);
        }
      }
      if (!mounted || auth.currentUser?.id != _ownerId) return;
      setState(() => _sentTo = phone);
      _timer?.cancel();
      _seconds = 60;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_seconds <= 1) t.cancel();
        if (mounted) setState(() => _seconds--);
      });
    } on AuthException {
      if (mounted) setState(() => _error = 'No se pudo enviar el código. Inténtalo de nuevo.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final db = Supabase.instance.client;
    final session = db.auth.currentSession;
    final phone = _sentTo;
    if (_busy || phone == null || session == null || session.user.id != _ownerId) return;
    if (_code.text.length != 6) return setState(() => _error = 'Escribe los 6 dígitos del código.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await db.functions.invoke(
        'verify-moncash',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {'phone': phone, 'code': _code.text},
      );
      final data = response.data;
      if (data is! Map || data['verified'] != true) throw const FormatException();
      if (!mounted || db.auth.currentUser?.id != _ownerId) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Número MonCash verificado.')));
      Navigator.pop(context, true);
    } on FunctionException catch (error) {
      if (mounted) {
        setState(() => _error = switch (error.status) {
              400 || 422 => 'Código incorrecto o vencido.',
              429 => 'Demasiados intentos. Espera antes de volver a intentarlo.',
              _ => 'No se pudo verificar el número. Inténtalo de nuevo.',
            });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo verificar el número. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtScaffold(
      background: Colors.white,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          const ScreenTitle('Mi MonCash',
              icon: Icons.verified_user_outlined,
              subtitle: 'Para retirar recompensas verifica el número donde las recibirás. Te enviaremos un código por SMS.'),
          const SizedBox(height: 22),
          TextField(
            controller: _phone,
            enabled: _sentTo == null,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
            decoration: InputDecoration(
              labelText: trn('Número MonCash'),
              prefixIcon: Icon(Icons.phone_outlined),
              prefixText: trn('+509 '),
              hintText: trn('37123456'),
            ),
          ),
          if (_sentTo == null && _accountPhone != null) ...[
            const SizedBox(height: 10),
            const Text('Si escribes otro número, también pasará a ser el número para iniciar sesión.',
                style: TextStyle(color: HtColors.muted, fontSize: 13)),
          ],
          if (_sentTo != null) ...[
            const SizedBox(height: 22),
            Text('Código enviado a ${formatHaitiPhone(_sentTo)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            OtpInput(controller: _code, onCompleted: (_) => _verify()),
            const SizedBox(height: 10),
            Center(
              child: _seconds > 0
                  ? Text('Reenviar código en 00:${_seconds.toString().padLeft(2, '0')}')
                  : TextButton(onPressed: _busy ? null : _send, child: const Text('Reenviar código')),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: HtColors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : (_sentTo == null ? _send : _verify),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_sentTo == null ? Icons.sms_outlined : Icons.check),
            label: Text(_sentTo == null ? 'Enviar código' : 'Verificar'),
          ),
        ],
      ),
    );
  }
}
