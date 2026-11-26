import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
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
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordError(details.exception.runtimeType.toString(), details.stack, fatal: true);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error.runtimeType.toString(), stack, fatal: true);
      return true;
    };
  } catch (_) {
    // Sin google-services.json la app funciona igual, solo sin reportes de errores.
  }
  if (supabaseUrl.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  }
  await Lang.load();
  await ProfileContext.load();
  await Guest.load();
  await SavedMissions.load();
  runApp(const HaitiTrackingApp());
}

class HaitiTrackingApp extends StatelessWidget {
  const HaitiTrackingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: Lang.current,
      builder: (context, lang, child) => MaterialApp(
        title: 'Haiti Tracking',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: Lang.materialLocale,
        supportedLocales: const [Locale('es'), Locale('fr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: supabaseUrl.isEmpty ? const _MissingConfig() : const AuthGate(),
      ),
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
  String? _shownUserId;
  String? _recoveryUserId;
  AuthState? _lastRecoveryEvent;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snap) {
        final userId = auth.currentSession?.user.id;
        if (_shownUserId != null && _shownUserId != userId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
          });
        }
        _shownUserId = userId;
        if (_recoveryUserId != userId) _recoveryUserId = null;
        if (snap.data?.event == AuthChangeEvent.passwordRecovery &&
            snap.data?.session?.user.id == userId && !identical(snap.data, _lastRecoveryEvent)) {
          _lastRecoveryEvent = snap.data;
          _recoveryUserId = userId;
        }
        if (userId == null) {
          // Sin cuenta: bienvenida, o la app en modo invitado si eligió explorar.
          return ValueListenableBuilder<bool>(
            valueListenable: Guest.active,
            builder: (context, guest, _) => guest ? const HomeShell() : const WelcomeScreen(),
          );
        }
        if (Guest.active.value) Future.microtask(() => Guest.set(false));
        if (_recoveryUserId == userId) {
          return NewPasswordScreen(key: ValueKey(userId), onDone: () => setState(() => _recoveryUserId = null));
        }
        return ValueListenableBuilder<AppProfile>(
          valueListenable: ProfileContext.current,
          builder: (context, profile, _) => switch (profile) {
            AppProfile.company => CompanyShell(key: ValueKey(userId)),
            AppProfile.developer => DeveloperShell(key: ValueKey(userId)),
            AppProfile.collaborator => HomeShell(key: ValueKey(userId)),
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
