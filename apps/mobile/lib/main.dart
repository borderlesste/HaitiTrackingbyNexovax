import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';

// Se pasan al compilar: flutter run --dart-define-from-file=env.json
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  }
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

/// Muestra login o la app según haya sesión.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        return auth.currentSession == null ? const LoginScreen() : const HomeShell();
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
