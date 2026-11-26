import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../auth/login_screen.dart';
import 'moncash_settings_screen.dart';

/// Verificación de la cuenta: teléfono (SMS, se pide al retirar) y correo (enlace).
class VerifyAccountScreen extends StatefulWidget {
  const VerifyAccountScreen({super.key});

  @override
  State<VerifyAccountScreen> createState() => _VerifyAccountScreenState();
}

class _VerifyAccountScreenState extends State<VerifyAccountScreen> {
  final _email = TextEditingController();
  String? _moncash;
  bool _busy = false;
  String? _error;
  String? _sentTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {}
    final m = await loadMoncashPhone();
    if (mounted) setState(() => _moncash = m);
  }

  Future<void> _sendEmail() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Escribe un correo válido.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(email: email), emailRedirectTo: authRedirectUrl);
      setState(() => _sentTo = email);
    } on AuthException catch (e) {
      setState(() => _error = e.message.toLowerCase().contains('already')
          ? 'Ese correo ya está registrado en otra cuenta.'
          : e.message);
    } catch (_) {
      setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final phone = (user?.phone ?? '').isEmpty ? null : '+${user!.phone!.replaceAll('+', '')}';
    final emailOk = (user?.email ?? '').isNotEmpty && user?.emailConfirmedAt != null;
    final pendingEmail = _sentTo ?? user?.newEmail;
    final moncashOk = _moncash != null;
    return HtScaffold(
      background: Colors.white,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            const ScreenTitle('Verificación de cuenta',
                icon: Icons.verified_user_outlined, subtitle: 'Protege tu cuenta y tus pagos.'),
            const SizedBox(height: 16),
            _Item(
              icon: Icons.sms_outlined,
              title: 'Teléfono (SMS)',
              detail: phone == null ? 'Sin teléfono' : formatHaitiPhone(phone),
              ok: moncashOk,
              okText: 'Verificado',
              pendingText: 'Se verifica al retirar',
              note: 'El código SMS solo se pide la primera vez que retiras dinero por MonCash.',
              action: moncashOk ? null : 'Verificar ahora',
              onAction: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoncashSettingsScreen()));
                _load();
              },
            ),
            const SizedBox(height: 12),
            _Item(
              icon: Icons.mail_outline,
              title: 'Correo electrónico',
              detail: emailOk ? user!.email! : (pendingEmail ?? 'Sin correo'),
              ok: emailOk,
              okText: 'Verificado',
              pendingText: pendingEmail != null ? 'Falta confirmar' : 'Opcional',
              note: emailOk
                  ? 'Puedes usarlo para entrar y para recuperar tu contraseña.'
                  : pendingEmail != null
                      ? 'Te enviamos un enlace a $pendingEmail. Ábrelo desde este teléfono para confirmarlo.'
                      : 'Agrega un correo para recibir avisos y recuperar tu contraseña más fácil.',
            ),
            if (!emailOk) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: trn('Tu correo'), prefixIcon: Icon(Icons.alternate_email)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: HtColors.red)),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _sendEmail,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(pendingEmail != null ? 'Enviar el enlace otra vez' : 'Enviar enlace de verificación'),
              ),
            ],
            const SizedBox(height: 16),
            const InfoBanner('Nunca te pediremos tu contraseña ni tus códigos por teléfono, WhatsApp o redes sociales.'),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.detail,
    required this.ok,
    required this.okText,
    required this.pendingText,
    required this.note,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String detail;
  final bool ok;
  final String okText;
  final String pendingText;
  final String note;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return HtCard(
      color: ok ? HtColors.greenSoft : Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconTile(icon, color: ok ? HtColors.green : HtColors.blue, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(detail, style: const TextStyle(color: HtColors.muted)),
            ]),
          ),
          StatusChip(ok ? okText : pendingText, tone: ok ? ChipTone.ok : ChipTone.review),
        ]),
        const SizedBox(height: 8),
        Text(note, style: const TextStyle(height: 1.35)),
        if (action != null) ...[
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: onAction, child: Text(action!))),
        ],
      ]),
    );
  }
}
