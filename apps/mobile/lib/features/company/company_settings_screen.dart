import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/panel.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'company_repo.dart';

/// Pantalla 24: Perfil y configuración de la empresa (datos comerciales, usuarios autorizados y soporte).
class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key, required this.org, required this.onChanged, required this.onOpenVerification, required this.onOpenBilling});
  final Map<String, dynamic> org;
  final Future<void> Function() onChanged;
  final VoidCallback onOpenVerification;
  final VoidCallback onOpenBilling;

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final _repo = CompanyRepo();
  late Future<List<Map<String, dynamic>>> _members = _repo.members(widget.org['id'] as String);

  String get _orgId => widget.org['id'] as String;

  bool _isOwner(List<Map<String, dynamic>> members) =>
      members.any((m) => m['user_id'] == _repo.uid && m['member_role'] == 'owner');

  Future<void> _editContact() async {
    final o = widget.org;
    final phone = TextEditingController(text: (o['contact_phone'] as String?)?.replaceFirst('+509', ''));
    final email = TextEditingController(text: o['contact_email'] as String?);
    final address = TextEditingController(text: o['address'] as String?);
    final web = TextEditingController(text: o['website'] as String?);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Datos de contacto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono', prefixText: '+509 ')),
            const SizedBox(height: 10),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
            const SizedBox(height: 10),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Dirección')),
            const SizedBox(height: 10),
            TextField(controller: web, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Sitio web')),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await _repo.updateContact(_orgId, phone: normalizeHaitiPhone(phone.text), email: t(email), address: t(address), website: t(web));
      await widget.onChanged();
      if (mounted) snack(context, 'Datos actualizados.');
    } on PostgrestException catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  Future<void> _addMember() async {
    final c = TextEditingController();
    final contact = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar usuario'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('La persona debe tener ya una cuenta en Haiti Tracking.'),
          const SizedBox(height: 12),
          TextField(controller: c, decoration: const InputDecoration(labelText: 'Teléfono o correo')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Agregar')),
        ],
      ),
    );
    if (contact == null || contact.isEmpty) return;
    try {
      await _repo.addMember(_orgId, contact);
      if (mounted) {
        snack(context, 'Usuario agregado.');
        setState(() => _members = _repo.members(_orgId));
      }
    } on PostgrestException catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  Future<void> _removeMember(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar usuario'),
        content: Text('${m['full_name']} dejará de tener acceso a la empresa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.removeMember(_orgId, m['user_id'] as String);
      if (mounted) setState(() => _members = _repo.members(_orgId));
    } on PostgrestException catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.org;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        const ScreenTitle('Perfil y configuración', icon: Icons.settings_outlined),
        const SizedBox(height: 16),
        HtCard(
          child: Column(children: [
            Row(children: [
              const IconTile(Icons.storefront, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o['name'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(o['sector'] as String, style: const TextStyle(color: HtColors.muted)),
                ]),
              ),
              reviewChip(o['status'] as String?),
            ]),
            const Divider(height: 24),
            KvRow('Representante', o['representative_name'] as String? ?? '—', icon: Icons.person_outline),
            KvRow('NIF / registro', o['legal_id'] as String? ?? '—', icon: Icons.badge_outlined),
            KvRow('Teléfono', formatHaitiPhone(o['contact_phone'] as String?).isEmpty ? '—' : formatHaitiPhone(o['contact_phone'] as String?), icon: Icons.phone_outlined),
            KvRow('Correo', o['contact_email'] as String? ?? '—', icon: Icons.mail_outline),
            KvRow('Dirección', [o['address'], o['commune']].whereType<String>().join(', '), icon: Icons.location_on_outlined),
            if (o['website'] != null) KvRow('Sitio web', o['website'] as String, icon: Icons.language),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _editContact, icon: const Icon(Icons.edit_outlined), label: const Text('Editar datos de contacto')),
          ]),
        ),
        const SizedBox(height: 18),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _members,
          builder: (context, snap) {
            final members = snap.data ?? const [];
            final owner = _isOwner(members);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SectionTitle('Usuarios autorizados', icon: Icons.group_outlined, action: owner ? 'Agregar' : null, onAction: owner ? _addMember : null),
              const SizedBox(height: 6),
              HtCard(
                padding: EdgeInsets.zero,
                child: !snap.hasData
                    ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                    : Column(children: [
                        for (final (i, m) in members.indexed)
                          SettingRow(
                            icon: m['member_role'] == 'owner' ? Icons.admin_panel_settings_outlined : Icons.person_outline,
                            title: m['full_name'] as String,
                            subtitle: [m['member_role'] == 'owner' ? 'Dueño' : 'Usuario', if (m['phone'] != null) maskPhone(m['phone'] as String)].join(' · '),
                            trailing: owner && m['member_role'] != 'owner'
                                ? IconButton(onPressed: () => _removeMember(m), icon: const Icon(Icons.person_remove_outlined, color: HtColors.red))
                                : null,
                            last: i == members.length - 1,
                          ),
                      ]),
              ),
            ]);
          },
        ),
        const SizedBox(height: 18),
        HtCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SettingRow(icon: Icons.verified_user_outlined, title: 'Verificación empresarial', subtitle: 'Documentos y estado', onTap: widget.onOpenVerification),
            SettingRow(icon: Icons.workspace_premium_outlined, title: 'Planes y facturación', onTap: widget.onOpenBilling),
            SettingRow(icon: Icons.support_agent, title: 'Ayuda y soporte', onTap: () => showSupportSheet(context, audience: 'Empresa ${o['name']}', category: 'COMPANY')),
            SettingRow(icon: Icons.swap_horiz, title: 'Cambiar de perfil', subtitle: 'Colaborador, Empresa o Desarrollador', onTap: () => showProfileSwitcher(context)),
            SettingRow(icon: Icons.logout, title: 'Cerrar sesión', color: HtColors.red, onTap: () => Supabase.instance.client.auth.signOut(), last: true),
          ]),
        ),
      ],
    );
  }
}
