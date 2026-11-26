import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/guest.dart';
import 'core/profile_context.dart';
import 'core/theme.dart';
import 'features/missions/saved_missions.dart';
import 'features/company/company_shell.dart';
import 'features/developer/developer_shell.dart';
import 'features/auth/welcome_screen.dart';
import 'features/auth/new_password_screen.dart';
import 'features/home/home_shell.dart';

// Se pasan al compilar: flutter run --dart-define-from-file=env.json
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Crashlytics: reporta cierres inesperados (configuración en android/app/google-services.json).
  try {
    await Firebase.initializeApp();
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {
    // Sin google-services.json la app funciona igual, solo sin reportes de errores.
  }
  if (supabaseUrl.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  }
  await ProfileContext.load();
  await Guest.load();
  await SavedMissions.load();
  runApp(const HaitiTrackingApp());
}

class HaitiTrackingApp extends StatelessWidget {
  const HaitiTrackingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Haiti Tracking',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: supabaseUrl.isEmpty ? const _MissingConfig() : const AuthGate(),
    );
  }
}

/// Muestra la bienvenida, la app en modo invitado o la app con cuenta. Si se abre el enlace de recuperación, pide la nueva contraseña.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _recovering = false;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snap) {
        if (snap.data?.event == AuthChangeEvent.passwordRecovery) _recovering = true;
        if (auth.currentSession == null) {
          // Sin cuenta: bienvenida, o la app en modo invitado si eligió explorar.
          return ValueListenableBuilder<bool>(
            valueListenable: Guest.active,
            builder: (context, guest, _) => guest ? const HomeShell() : const WelcomeScreen(),
          );
        }
        if (Guest.active.value) Future.microtask(() => Guest.set(false));
        if (_recovering) return NewPasswordScreen(onDone: () => setState(() => _recovering = false));
        return ValueListenableBuilder<AppProfile>(
          valueListenable: ProfileContext.current,
          builder: (context, profile, _) => switch (profile) {
            AppProfile.company => const CompanyShell(),
            AppProfile.developer => const DeveloperShell(),
            AppProfile.collaborator => const HomeShell(),
          },
        );
      },
    );
  }
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Falta la configuración de Supabase.\n'
            'Ejecuta: flutter run --dart-define-from-file=env.json',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
