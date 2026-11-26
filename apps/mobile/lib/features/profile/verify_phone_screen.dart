import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/otp_input.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Agrega o cambia el número MonCash de la cuenta y lo verifica con un código SMS.
class VerifyPhoneScreen extends StatefulWidget {
  const VerifyPhoneScreen({super.key});

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  int _seconds = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = normalizeHaitiPhone(_phone.text);
    if (phone == null) return setState(() => _error = 'Escribe un número haitiano de 8 dígitos.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(phone: phone));
      setState(() => _sentTo = phone);
      _timer?.cancel();
      _seconds = 60;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_seconds <= 1) t.cancel();
        if (mounted) setState(() => _seconds--);
      });
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) return setState(() => _error = 'Escribe los 6 dígitos del código.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.verifyOTP(type: OtpType.phoneChange, phone: _sentTo!, token: _code.text);
      await updateMyProfile({'phone': _sentTo});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Número MonCash verificado.')));
      Navigator.pop(context, true);
    } on AuthException {
      setState(() => _error = 'Código incorrecto o vencido.');
    } catch (_) {
      setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
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
              subtitle: 'Verifica el número donde recibirás tus recompensas. Te enviaremos un código por SMS.'),
          const SizedBox(height: 22),
          TextField(
            controller: _phone,
            enabled: _sentTo == null,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
            decoration: const InputDecoration(
              labelText: 'Número MonCash',
              prefixIcon: Icon(Icons.phone_outlined),
              prefixText: '+509 ',
              hintText: '37 12 34 56',
            ),
          ),
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
