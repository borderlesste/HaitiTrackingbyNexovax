import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Contexto de perfil activo. Cambiarlo NO da permisos: el servidor los comprueba siempre.
enum AppProfile { collaborator, company, developer }

class ProfileContext {
  static final current = ValueNotifier<AppProfile>(AppProfile.collaborator);
  static const _key = 'active_profile_v1';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    current.value = AppProfile.values.firstWhere((p) => p.name == name, orElse: () => AppProfile.collaborator);
  }

  static Future<void> set(AppProfile p) async {
    current.value = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, p.name);
  }
}

const profileInfo = {
  AppProfile.collaborator: (Icons.directions_walk, 'Colaborador', 'Completa misiones en el mapa y gana recompensas.'),
  AppProfile.company: (Icons.storefront, 'Empresa', 'Gestiona tus establecimientos y solicita campañas de cobertura.'),
  AppProfile.developer: (Icons.code, 'Desarrollador', 'Crea proyectos y claves para usar la API de lugares.'),
};

Future<void> showProfileSwitcher(BuildContext context) async {
  final chosen = await showModalBottomSheet<AppProfile>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Elige tu perfil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          for (final p in AppProfile.values)
            ListTile(
              leading: Icon(profileInfo[p]!.$1),
              title: Text(profileInfo[p]!.$2),
              subtitle: Text(profileInfo[p]!.$3),
              trailing: ProfileContext.current.value == p ? const Icon(Icons.check_circle, color: Colors.green) : null,
              onTap: () => Navigator.pop(ctx, p),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (chosen != null) await ProfileContext.set(chosen);
}

/// Bloque común para la pestaña Perfil de cualquier experiencia.
class ProfileActions extends StatelessWidget {
  const ProfileActions({super.key, this.extra = const []});
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = (user?.userMetadata?['full_name'] as String?) ?? '';
    final p = profileInfo[ProfileContext.current.value]!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(name.isEmpty ? 'Mi cuenta' : name),
          subtitle: Text(user?.email ?? ''),
        ),
        const Divider(),
        ListTile(
          leading: Icon(p.$1),
          title: Text('Perfil activo: ${p.$2}'),
          subtitle: const Text('Toca para cambiar entre Colaborador, Empresa y Desarrollador'),
          trailing: const Icon(Icons.swap_horiz),
          onTap: () => showProfileSwitcher(context),
        ),
        ...extra,
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Cerrar sesión'),
          onTap: () => Supabase.instance.client.auth.signOut(),
        ),
      ],
    );
  }
}
