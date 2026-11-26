import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import 'profile_context.dart';
import 'theme.dart';
import 'ui.dart';

/// Modo invitado: explorar la app sin cuenta. Solo es una vista; todo lo que escribe datos exige cuenta.
class Guest {
  static final active = ValueNotifier<bool>(false);
  static const _key = 'guest_mode_v1';

  static bool get isGuest => Supabase.instance.client.auth.currentSession == null;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    active.value = prefs.getBool(_key) ?? false;
  }

  static Future<void> set(bool on) async {
    active.value = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, on);
  }
}

void openRegister(BuildContext context, {AppProfile profile = AppProfile.collaborator}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterScreen(profile: profile)));
}

void openLogin(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
}

/// Devuelve true si hay sesión. Si no, invita a crear una cuenta y devuelve false.
bool requireAccount(BuildContext context, {required String reason, AppProfile profile = AppProfile.collaborator}) {
  if (!Guest.isGuest) return true;
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.person_add_alt, size: 48, color: HtColors.blue),
          const SizedBox(height: 12),
          const Text('Crea tu cuenta gratis',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(reason, textAlign: TextAlign.center, style: const TextStyle(color: HtColors.muted, height: 1.35)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openRegister(context, profile: profile);
            },
            child: const Text('Crear una cuenta'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openLogin(context);
            },
            child: const Text('Ya tengo cuenta: iniciar sesión'),
          ),
        ]),
      ),
    ),
  );
  return false;
}

/// Pantalla que ve el invitado en las secciones que necesitan cuenta: explica qué hay y cómo empezar.
class GuestGate extends StatelessWidget {
  const GuestGate({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
    required this.points,
    this.profile = AppProfile.collaborator,
    this.cta = 'Crear mi cuenta',
  });

  final String title;
  final IconData icon;
  final String description;
  final List<String> points;
  final AppProfile profile;
  final String cta;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        ScreenTitle(title, icon: icon),
        const SizedBox(height: 14),
        HtCard(
          color: HtColors.blueSoft,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(description, style: const TextStyle(fontSize: 16, height: 1.4)),
            const SizedBox(height: 12),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle, color: HtColors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p, style: const TextStyle(height: 1.35))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => openRegister(context, profile: profile),
          icon: const Icon(Icons.person_add_alt),
          label: Text(cta),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => openLogin(context),
          icon: const Icon(Icons.login),
          label: const Text('Ya tengo cuenta'),
        ),
        const SizedBox(height: 12),
        const Text('Puedes seguir explorando el mapa y las misiones sin cuenta.',
            textAlign: TextAlign.center, style: TextStyle(color: HtColors.muted)),
      ],
    );
  }
}
