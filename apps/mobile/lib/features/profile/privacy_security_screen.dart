import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import 'help_support_screen.dart';

/// Privacidad y seguridad: contraseña, sesiones, permisos y eliminación de la cuenta.
class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  LocationPermission? _location;

  @override
  void initState() {
    super.initState();
    Geolocator.checkPermission().then((p) {
      if (mounted) setState(() => _location = p);
    }).catchError((_) {});
  }

  Future<void> _signOutOthers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar las otras sesiones'),
        content: const Text('Se cerrará tu cuenta en todos los demás teléfonos y navegadores. Este teléfono sigue conectado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar sesiones')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.others);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Cerramos tu cuenta en los demás dispositivos.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No se pudo. Revisa tu conexión e intenta de nuevo.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final lastSignIn = user?.lastSignInAt == null ? null : DateTime.tryParse(user!.lastSignInAt!);
    final loc = _location;
    final locText = switch (loc) {
      LocationPermission.always || LocationPermission.whileInUse => 'Permitida mientras usas la app',
      LocationPermission.denied => 'No permitida (te la pediremos al registrar un lugar)',
      LocationPermission.deniedForever => 'Bloqueada en los ajustes del teléfono',
      _ => 'Comprobando…',
    };
    return HtScaffold(
      background: Colors.white,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          const ScreenTitle('Privacidad y seguridad', icon: Icons.shield_outlined),
          const SizedBox(height: 16),
          const SectionTitle('Seguridad', icon: Icons.lock_outline),
          const SizedBox(height: 6),
          HtCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.password, color: HtColors.navy),
                title: const Text('Cambiar contraseña', style: TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.devices_other, color: HtColors.navy),
                title: const Text('Cerrar sesión en otros dispositivos', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: lastSignIn == null ? null : Text('Este teléfono: último ingreso ${fechaHora(lastSignIn)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _signOutOthers,
              ),
            ]),
          ),
          const SizedBox(height: 16),
          const SectionTitle('Privacidad', icon: Icons.visibility_outlined),
          const SizedBox(height: 6),
          HtCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KvRow('Ubicación', '', icon: Icons.location_on_outlined),
              Text(locText, style: const TextStyle(color: HtColors.muted)),
              if (loc == LocationPermission.deniedForever) ...[
                const SizedBox(height: 6),
                OutlinedButton(onPressed: Geolocator.openAppSettings, child: const Text('Abrir ajustes del teléfono')),
              ],
              const Divider(height: 22),
              const Text(
                '• Usamos tu ubicación solo al registrar un lugar, para comprobar que estás allí.\n'
                '• Tus fotos de evidencia son privadas: solo las ve el equipo de revisión.\n'
                '• Tu teléfono se usa para pagarte por MonCash; no lo mostramos a empresas.\n'
                '• Nunca te pediremos tu contraseña ni el código SMS por teléfono o WhatsApp.',
                style: TextStyle(height: 1.5),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          const SectionTitle('Eliminar cuenta', icon: Icons.delete_outline),
          const SizedBox(height: 6),
          HtCard(
            color: HtColors.redSoft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Puedes pedir que borremos tu cuenta y tus datos personales. Antes, retira tu saldo disponible: '
                'el saldo no retirado se pierde. Los lugares aprobados siguen en el mapa sin tu nombre.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: HtColors.red, side: const BorderSide(color: HtColors.red)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NewTicketScreen(kind: TicketKind.deletion, subject: 'Eliminar mi cuenta'),
                )),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Solicitar eliminación de la cuenta'),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Cambio de contraseña con la sesión abierta: confirma la actual antes de guardar la nueva.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    final user = auth.currentUser!;
    try {
      // Comprueba la contraseña actual iniciando sesión otra vez con ella.
      if ((user.email ?? '').isNotEmpty) {
        await auth.signInWithPassword(email: user.email!, password: _current.text);
      } else {
        await auth.signInWithPassword(phone: user.phone!, password: _current.text);
      }
    } on AuthException {
      setState(() {
        _busy = false;
        _error = 'La contraseña actual no es correcta.';
      });
      return;
    } catch (_) {
      setState(() {
        _busy = false;
        _error = 'Sin conexión. Intenta de nuevo.';
      });
      return;
    }
    try {
      await auth.updateUser(UserAttributes(password: _next.text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña actualizada.')));
      Navigator.pop(context);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: trn(label),
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _show = !_show),
          ),
        );
    return HtScaffold(
      background: Colors.white,
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            const ScreenTitle('Cambiar contraseña', icon: Icons.password),
            const SizedBox(height: 16),
            TextFormField(
              controller: _current,
              obscureText: !_show,
              decoration: deco('Contraseña actual'),
              validator: (v) => (v == null || v.isEmpty) ? tr('Escribe tu contraseña actual') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _next,
              obscureText: !_show,
              decoration: deco('Nueva contraseña'),
              validator: (v) => (v == null || v.length < 8)
                  ? tr('Mínimo 8 caracteres')
                  : v == _current.text
                      ? tr('Debe ser distinta de la actual')
                      : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _repeat,
              obscureText: !_show,
              decoration: deco('Repite la nueva contraseña'),
              validator: (v) => v != _next.text ? tr('Las contraseñas no coinciden') : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: HtColors.red)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar contraseña'),
            ),
          ],
        ),
      ),
    );
  }
}
