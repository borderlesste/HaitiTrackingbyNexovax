import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/contribution_service.dart';
import '../notifications/notifications_screen.dart';
import 'edit_profile_screen.dart';
import 'help_support_screen.dart';
import 'moncash_settings_screen.dart';
import 'privacy_security_screen.dart';
import 'verify_account_screen.dart';

class _Stats {
  const _Stats({this.total = 0, this.approved = 0, this.trustPct, this.missionsDone = 0});
  final int total;
  final int approved;
  final int? trustPct;
  final int missionsDone;
}

Future<_Stats> _loadStats() async {
  final list = await ContributionService().myContributions();
  final approved = list.where((c) => c['status'] == 'APPROVED').toList();
  final rejected = list.where((c) => c['status'] == 'REJECTED').length;
  final reviewed = approved.length + rejected;
  // Misiones completadas: aportes aprobados ≥ los requeridos por la misión.
  final byMission = <String, int>{};
  final required = <String, int>{};
  for (final c in approved) {
    final id = c['mission_id'] as String;
    byMission[id] = (byMission[id] ?? 0) + 1;
    required[id] = ((c['missions'] as Map<String, dynamic>?)?['required_approved_contributions'] as num?)?.toInt() ?? 1;
  }
  return _Stats(
    total: list.length,
    approved: approved.length,
    trustPct: reviewed == 0 ? null : (approved.length * 100 ~/ reviewed),
    missionsDone: byMission.entries.where((e) => e.value >= (required[e.key] ?? 1)).length,
  );
}

/// Pestaña Perfil del colaborador.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  MyProfile? _profile;
  _Stats _stats = const _Stats();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await loadMyProfile();
      if (mounted) setState(() => _profile = p);
    } catch (_) {}
    try {
      final s = await _loadStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  Future<void> _chooseLanguage() async {
    final current = _profile?.language ?? 'ht';
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Idioma de la aplicación', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final e in languageNames.entries)
            ListTile(
              title: Text(e.value),
              trailing: e.key == current ? const Icon(Icons.check_circle, color: HtColors.green) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text('Por ahora la app se muestra en español; usaremos tu preferencia en los mensajes y en próximas versiones.',
                style: TextStyle(fontSize: 12, color: HtColors.muted)),
          ),
        ]),
      ),
    );
    if (chosen == null || chosen == current) return;
    await updateMyProfile({'preferred_language': chosen});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final p = _profile;
    final name = p?.fullName.isNotEmpty == true ? p!.fullName : ((user?.userMetadata?['full_name'] as String?) ?? 'Mi cuenta');
    final contact = (user?.email?.isNotEmpty ?? false) ? user!.email! : formatHaitiPhone(p?.phone);
    final phoneOk = p?.phoneVerified == true;
    final s = _stats;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const ScreenTitle('Mi perfil', icon: Icons.person_outline),
          const SizedBox(height: 16),
          Row(children: [
            const CircleAvatar(
              radius: 46,
              backgroundColor: Color(0xFFD6E4FB),
              child: Icon(Icons.person, size: 64, color: HtColors.blue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: HtColors.text)),
                const SizedBox(height: 6),
                StatusChip(p?.verified == true ? 'Colaborador verificado' : 'Colaborador',
                    tone: p?.verified == true ? ChipTone.ok : ChipTone.info),
                const SizedBox(height: 6),
                if (contact.isNotEmpty)
                  Row(children: [
                    Icon(user?.email?.isNotEmpty == true ? Icons.mail_outline : Icons.phone_outlined, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(contact, overflow: TextOverflow.ellipsis)),
                  ]),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: p == null ? null : () => _open(EditProfileScreen(profile: p)),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar perfil'),
          ),
          const SizedBox(height: 14),
          HtCard(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(child: _Stat(Icons.storefront, HtColors.blue, '${s.total}', 'Aportes')),
                Expanded(child: _Stat(Icons.check_circle_outline, HtColors.green, '${s.approved}', 'Aprobados')),
              ]),
              const Divider(height: 20),
              Row(children: [
                Expanded(
                  child: _Stat(Icons.bar_chart, HtColors.blue, s.trustPct == null ? '—' : '${s.trustPct}%', 'Nivel de confianza',
                      valueColor: HtColors.green),
                ),
                Expanded(child: _Stat(Icons.flag_outlined, HtColors.blue, '${s.missionsDone}', 'Misiones completadas')),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          const SectionTitle('Ajustes de cuenta', icon: Icons.settings_outlined),
          const SizedBox(height: 8),
          HtCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _SettingTile(
                leading: const Icon(Icons.person_outline, color: HtColors.navy),
                title: 'Mi cuenta y datos personales',
                onTap: p == null ? null : () => _open(EditProfileScreen(profile: p)),
              ),
              _SettingTile(
                leading: const Icon(Icons.verified_user_outlined, color: HtColors.navy),
                title: 'Verificación de cuenta',
                subtitle: 'Teléfono y correo',
                onTap: () => _open(const VerifyAccountScreen()),
              ),
              _SettingTile(
                leading: const MonCashBadge(size: 36),
                title: 'Mi MonCash',
                subtitle: phoneOk ? maskPhone(p?.row['moncash_phone'] as String?) : 'Se verifica al retirar',
                badge: phoneOk
                    ? const StatusChip('Verificado', tone: ChipTone.ok)
                    : const StatusChip('Verificar', tone: ChipTone.review),
                onTap: () => _open(const MoncashSettingsScreen()),
              ),
              _SettingTile(
                leading: const Icon(Icons.language, color: HtColors.blue),
                title: 'Idioma de la aplicación',
                subtitle: languageNames[p?.language ?? 'ht'],
                onTap: _chooseLanguage,
              ),
              _SettingTile(
                leading: const Icon(Icons.notifications_none, color: HtColors.navy),
                title: 'Notificaciones',
                onTap: () => _open(const NotificationsScreen()),
              ),
              _SettingTile(
                leading: const Icon(Icons.shield_outlined, color: HtColors.navy),
                title: 'Privacidad y seguridad',
                subtitle: 'Contraseña, sesiones y eliminar cuenta',
                onTap: () => _open(const PrivacySecurityScreen()),
              ),
              _SettingTile(
                leading: const Icon(Icons.help_outline, color: HtColors.navy),
                title: 'Ayuda y soporte',
                onTap: () => _open(const HelpSupportScreen()),
              ),
              _SettingTile(
                leading: const Icon(Icons.swap_horiz, color: HtColors.navy),
                title: 'Cambiar de perfil',
                subtitle: profileInfo[ProfileContext.current.value]!.$2,
                onTap: () => showProfileSwitcher(context),
                last: true,
              ),
            ]),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFEEF1F6),
              foregroundColor: HtColors.red,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.color, this.value, this.label, {this.valueColor = HtColors.text});
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      IconTile(icon, color: color, background: color.withValues(alpha: .1), size: 52),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: valueColor)),
          Text(label, style: const TextStyle(fontSize: 13)),
        ]),
      ),
    ]);
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.leading, required this.title, this.subtitle, this.badge, this.onTap, this.last = false});
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? badge;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ListTile(
        leading: SizedBox(width: 48, child: Center(child: leading)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (badge != null) badge!,
          const Icon(Icons.chevron_right),
        ]),
        onTap: onTap,
      ),
      if (!last) const Divider(height: 1, indent: 16, endIndent: 16),
    ]);
  }
}
