import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/panel.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'developer_register_screen.dart' show showApiTerms;
import 'developer_repo.dart';

/// Pantalla 33: Configuración del desarrollador (perfil, seguridad y notificaciones).
class DeveloperSettingsScreen extends StatefulWidget {
  const DeveloperSettingsScreen({super.key, required this.profile, required this.onChanged, required this.onBilling});
  final Map<String, dynamic> profile;
  final Future<void> Function() onChanged;
  final VoidCallback onBilling;

  @override
  State<DeveloperSettingsScreen> createState() => _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState extends State<DeveloperSettingsScreen> {
  final _repo = DeveloperRepo();
  late final Map<String, dynamic> _p = Map.of(widget.profile);

  Future<void> _toggle(String field, bool value) async {
    setState(() => _p[field] = value);
    try {
      await _repo.updateProfile({field: value});
    } catch (_) {
      if (mounted) {
        setState(() => _p[field] = !value);
        snack(context, 'No se pudo guardar.');
      }
    }
  }

  Future<void> _editProfile() async {
    final name = TextEditingController(text: _p['display_name'] as String?);
    final company = TextEditingController(text: _p['company_name'] as String?);
    final country = TextEditingController(text: _p['country'] as String?);
    final web = TextEditingController(text: _p['website'] as String?);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Perfil de desarrollador', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 10),
            TextField(controller: company, decoration: const InputDecoration(labelText: 'Empresa (opcional)')),
            const SizedBox(height: 10),
            TextField(controller: country, decoration: const InputDecoration(labelText: 'País')),
            const SizedBox(height: 10),
            TextField(controller: web, decoration: const InputDecoration(labelText: 'Sitio web')),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ]),
        ),
      ),
    );
    if (ok != true || name.text.trim().length < 2) return;
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final values = {'display_name': name.text.trim(), 'company_name': t(company), 'country': t(country) ?? 'Haití', 'website': t(web)};
    try {
      await _repo.updateProfile(values);
      setState(() => _p.addAll(values));
      await widget.onChanged();
    } catch (_) {
      if (mounted) snack(context, 'No se pudo guardar.');
    }
  }

  Future<void> _resetPassword() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      return snack(context, 'Tu cuenta usa teléfono: cambia la contraseña desde "Olvidé mi contraseña" al iniciar sesión.');
    }
    await Supabase.instance.client.auth.resetPasswordForEmail(email, redirectTo: 'com.nexovax.haititracking://login-callback');
    if (mounted) snack(context, 'Te enviamos un enlace para cambiar la contraseña.');
  }

  Future<void> _signOutOthers() async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.others);
      if (mounted) snack(context, 'Se cerraron las sesiones en otros dispositivos.');
    } catch (_) {
      if (mounted) snack(context, 'No se pudo cerrar las otras sesiones.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        const ScreenTitle('Configuración', icon: Icons.settings_outlined),
        const SizedBox(height: 16),
        HtCard(
          child: Column(children: [
            Row(children: [
              const CircleAvatar(radius: 26, backgroundColor: HtColors.blue, child: Icon(Icons.code, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_p['display_name'] as String? ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text([_p['company_name'], _p['country']].whereType<String>().join(' · '), style: const TextStyle(color: HtColors.muted)),
                ]),
              ),
              IconButton(onPressed: _editProfile, icon: const Icon(Icons.edit_outlined, color: HtColors.blue)),
            ]),
            const Divider(height: 22),
            KvRow('Cuenta', user?.email?.isNotEmpty == true ? user!.email! : formatHaitiPhone('+${user?.phone ?? ''}'), icon: Icons.account_circle_outlined),
            KvRow('Condiciones API', 'Aceptadas ${fechaCorta(DateTime.parse(_p['terms_accepted_at'] as String))}', icon: Icons.gavel_outlined),
          ]),
        ),
        const SizedBox(height: 18),
        const SectionTitle('Seguridad', icon: Icons.shield_outlined),
        const SizedBox(height: 6),
        HtCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SettingRow(icon: Icons.lock_reset, title: 'Cambiar contraseña', onTap: _resetPassword),
            SettingRow(icon: Icons.devices_other, title: 'Cerrar sesión en otros dispositivos', subtitle: 'Mantiene abierta solo esta sesión', onTap: _signOutOthers),
            SettingRow(icon: Icons.gavel_outlined, title: 'Condiciones de uso de la API', onTap: () => showApiTerms(context), last: true),
          ]),
        ),
        const SizedBox(height: 18),
        const SectionTitle('Notificaciones', icon: Icons.notifications_none),
        const SizedBox(height: 6),
        HtCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(
              value: _p['notify_quota'] as bool? ?? true,
              onChanged: (v) => _toggle('notify_quota', v),
              title: const Text('Cuota casi agotada', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Aviso al llegar al 80 % de la cuota diaria'),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              value: _p['notify_security'] as bool? ?? true,
              onChanged: (v) => _toggle('notify_security', v),
              title: const Text('Seguridad de claves', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Claves nuevas, rotadas o revocadas'),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              value: _p['notify_billing'] as bool? ?? true,
              onChanged: (v) => _toggle('notify_billing', v),
              title: const Text('Facturación', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Facturas y cambios de plan'),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        HtCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SettingRow(icon: Icons.workspace_premium_outlined, title: 'Planes y facturación', onTap: widget.onBilling),
            SettingRow(icon: Icons.support_agent, title: 'Ayuda y soporte', onTap: () => showSupportSheet(context, audience: 'Desarrollador')),
            SettingRow(icon: Icons.swap_horiz, title: 'Cambiar de perfil', subtitle: 'Colaborador, Empresa o Desarrollador', onTap: () => showProfileSwitcher(context)),
            SettingRow(icon: Icons.logout, title: 'Cerrar sesión', color: HtColors.red, onTap: () => Supabase.instance.client.auth.signOut(), last: true),
          ]),
        ),
      ],
    );
  }
}
