import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/panel.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../billing/billing_screen.dart';
import 'company_home_screen.dart';
import 'company_missions_screen.dart';
import 'company_register_screen.dart';
import 'company_repo.dart';
import 'company_settings_screen.dart';
import 'company_verification_screen.dart';
import 'establishment_form_screen.dart';
import 'establishments_screen.dart';

enum _Tab { home, establishments, missions, profile }

/// Experiencia Empresa: Inicio / Establecimientos / Misiones / Perfil.
class CompanyShell extends StatefulWidget {
  const CompanyShell({super.key});

  @override
  State<CompanyShell> createState() => _CompanyShellState();
}

class _CompanyShellState extends State<CompanyShell> {
  final _repo = CompanyRepo();
  final _scaffold = GlobalKey<ScaffoldState>();
  Map<String, dynamic>? _org;
  bool _loading = true;
  String? _error;
  _Tab _tab = _Tab.home;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final org = await _repo.myOrganization();
      if (mounted) {
        setState(() {
          _org = org;
          _error = null;
          _refreshKey++;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar tu empresa. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _approved => _org?['status'] == 'APPROVED';

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  void _openVerification() => _push(CompanyVerificationScreen(org: _org!, onChanged: _load));
  void _openBilling() => _push(BillingScreen(audience: 'company', orgId: _org!['id'] as String));
  void _newEstablishment() => _approved ? _push(EstablishmentFormScreen(orgId: _org!['id'] as String)) : _openVerification();
  void _requestMission() => _approved ? _push(MissionRequestScreen(orgId: _org!['id'] as String)) : _openVerification();

  @override
  Widget build(BuildContext context) {
    if (_loading) return const HtScaffold(appBar: HtAppBar(showBack: false), body: Center(child: CircularProgressIndicator()));
    if (_error != null && _org == null) {
      return HtScaffold(
        appBar: const HtAppBar(showBack: false),
        body: EmptyState(
          icon: Icons.cloud_off,
          title: 'Sin conexión',
          text: _error!,
          action: FilledButton(onPressed: _load, child: const Text('Reintentar')),
        ),
      );
    }
    final org = _org;
    if (org == null) {
      // Pantalla 15: aún no hay empresa registrada.
      return HtScaffold(
        appBar: const HtAppBar(showBack: false),
        body: CompanyRegisterScreen(onDone: _load),
      );
    }

    Widget locked(String what) => EmptyState(
          icon: Icons.lock_clock_outlined,
          title: 'Disponible tras la verificación',
          text: 'Podrás gestionar $what cuando el equipo verifique tu empresa.',
          action: FilledButton(onPressed: _openVerification, child: const Text('Ver verificación')),
        );

    final id = org['id'] as String;
    final body = switch (_tab) {
      _Tab.home => CompanyHomeScreen(
          key: ValueKey('home$_refreshKey'),
          org: org,
          onRefresh: _load,
          onOpenVerification: _openVerification,
          onOpenEstablishments: () => setState(() => _tab = _Tab.establishments),
          onOpenMissions: () => setState(() => _tab = _Tab.missions),
          onNewEstablishment: _newEstablishment,
          onRequestMission: _requestMission,
          onOpenBilling: _openBilling,
        ),
      _Tab.establishments => _approved ? EstablishmentsScreen(key: ValueKey('est$_refreshKey'), orgId: id) : locked('tus establecimientos'),
      _Tab.missions => _approved ? CompanyMissionsScreen(key: ValueKey('mis$_refreshKey'), orgId: id) : locked('tus misiones'),
      _Tab.profile => CompanySettingsScreen(
          key: ValueKey('cfg$_refreshKey'),
          org: org,
          onChanged: _load,
          onOpenVerification: _openVerification,
          onOpenBilling: _openBilling,
        ),
    };

    return HtScaffold(
      scaffoldKey: _scaffold,
      appBar: HtAppBar(showBack: false, showBell: true, onMenu: () => _scaffold.currentState?.openDrawer()),
      drawer: _CompanyDrawer(
        org: org,
        go: (t) => setState(() => _tab = t),
        onVerification: _openVerification,
        onBilling: _openBilling,
        onNewEstablishment: _newEstablishment,
        onRequestMission: _requestMission,
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        height: 70,
        onDestinationSelected: (i) => setState(() => _tab = _Tab.values[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Establecimientos'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: 'Misiones'),
          NavigationDestination(icon: Icon(Icons.business_outlined), selectedIcon: Icon(Icons.business), label: 'Empresa'),
        ],
      ),
    );
  }
}

class _CompanyDrawer extends StatelessWidget {
  const _CompanyDrawer({
    required this.org,
    required this.go,
    required this.onVerification,
    required this.onBilling,
    required this.onNewEstablishment,
    required this.onRequestMission,
  });
  final Map<String, dynamic> org;
  final void Function(_Tab) go;
  final VoidCallback onVerification;
  final VoidCallback onBilling;
  final VoidCallback onNewEstablishment;
  final VoidCallback onRequestMission;

  @override
  Widget build(BuildContext context) {
    void tap(VoidCallback f) {
      Navigator.pop(context);
      f();
    }

    return Drawer(
      child: ListView(padding: EdgeInsets.zero, children: [
        DrawerHeader(
          decoration: const BoxDecoration(color: HtColors.navy),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
            const HtBrand(size: .9),
            const SizedBox(height: 14),
            Text(org['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const Text('Perfil Empresa', style: TextStyle(color: Colors.white70)),
          ]),
        ),
        ListTile(leading: const Icon(Icons.home_outlined), title: const Text('Inicio'), onTap: () => tap(() => go(_Tab.home))),
        ListTile(leading: const Icon(Icons.storefront_outlined), title: const Text('Mis establecimientos'), onTap: () => tap(() => go(_Tab.establishments))),
        ListTile(leading: const Icon(Icons.add_business_outlined), title: const Text('Registrar establecimiento'), onTap: () => tap(onNewEstablishment)),
        ListTile(leading: const Icon(Icons.add_location_alt_outlined), title: const Text('Solicitar misión'), onTap: () => tap(onRequestMission)),
        ListTile(leading: const Icon(Icons.track_changes), title: const Text('Seguimiento de misiones'), onTap: () => tap(() => go(_Tab.missions))),
        ListTile(leading: const Icon(Icons.verified_user_outlined), title: const Text('Verificación empresarial'), onTap: () => tap(onVerification)),
        ListTile(leading: const Icon(Icons.workspace_premium_outlined), title: const Text('Planes y facturación'), onTap: () => tap(onBilling)),
        ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Perfil y configuración'), onTap: () => tap(() => go(_Tab.profile))),
        ListTile(
          leading: const Icon(Icons.support_agent),
          title: const Text('Ayuda y soporte'),
          onTap: () => tap(() => showSupportSheet(context, audience: 'Empresa ${org['name']}')),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('Cambiar de perfil'),
          subtitle: const Text('Colaborador, Empresa o Desarrollador'),
          onTap: () => tap(() => showProfileSwitcher(context)),
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: HtColors.red),
          title: const Text('Cerrar sesión', style: TextStyle(color: HtColors.red)),
          onTap: () => Supabase.instance.client.auth.signOut(),
        ),
      ]),
    );
  }
}
