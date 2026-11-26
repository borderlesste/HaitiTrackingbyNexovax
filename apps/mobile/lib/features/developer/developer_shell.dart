import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/panel.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../billing/billing_screen.dart';
import 'api_docs_screen.dart';
import 'api_test_screen.dart';
import 'credentials_screen.dart';
import 'developer_dashboard_screen.dart';
import 'developer_register_screen.dart';
import 'developer_repo.dart';
import 'developer_settings_screen.dart';
import 'projects_screen.dart';
import 'stats_screen.dart';

enum _Tab { dashboard, projects, keys, docs, settings }

/// Experiencia Desarrollador: Inicio / Proyectos / Claves / Docs / Cuenta.
class DeveloperShell extends StatefulWidget {
  const DeveloperShell({super.key});

  @override
  State<DeveloperShell> createState() => _DeveloperShellState();
}

class _DeveloperShellState extends State<DeveloperShell> {
  final _repo = DeveloperRepo();
  final _scaffold = GlobalKey<ScaffoldState>();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;
  _Tab _tab = _Tab.dashboard;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _repo.profile();
      if (mounted) {
        setState(() {
          _profile = p;
          _error = null;
          _refreshKey++;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar tu cuenta. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  void _billing() => _push(const BillingScreen(audience: 'developer'));
  void _test() => _push(const ApiTestScreen());
  void _stats() => _push(const StatsScreen());

  @override
  Widget build(BuildContext context) {
    if (_loading) return const HtScaffold(appBar: HtAppBar(showBack: false), body: Center(child: CircularProgressIndicator()));
    if (_error != null && _profile == null) {
      return HtScaffold(
        appBar: const HtAppBar(showBack: false),
        body: EmptyState(icon: Icons.cloud_off, title: 'Sin conexión', text: _error!, action: FilledButton(onPressed: _load, child: const Text('Reintentar'))),
      );
    }
    final profile = _profile;
    if (profile == null) {
      return HtScaffold(appBar: const HtAppBar(showBack: false), body: DeveloperRegisterScreen(onDone: _load));
    }
    final body = switch (_tab) {
      _Tab.dashboard => DeveloperDashboardScreen(
          key: ValueKey('d$_refreshKey'),
          profile: profile,
          onProjects: () => setState(() => _tab = _Tab.projects),
          onCredentials: () => setState(() => _tab = _Tab.keys),
          onDocs: () => setState(() => _tab = _Tab.docs),
          onTest: _test,
          onStats: _stats,
          onBilling: _billing,
        ),
      _Tab.projects => const ProjectsScreen(),
      _Tab.keys => const CredentialsScreen(embedded: true),
      _Tab.docs => const ApiDocsScreen(),
      _Tab.settings => DeveloperSettingsScreen(key: ValueKey('s$_refreshKey'), profile: profile, onChanged: _load, onBilling: _billing),
    };
    return HtScaffold(
      scaffoldKey: _scaffold,
      appBar: HtAppBar(showBack: false, showBell: true, onMenu: () => _scaffold.currentState?.openDrawer()),
      drawer: _DeveloperDrawer(
        name: profile['display_name'] as String? ?? '',
        go: (t) => setState(() => _tab = t),
        onTest: _test,
        onStats: _stats,
        onBilling: _billing,
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        height: 70,
        onDestinationSelected: (i) => setState(() => _tab = _Tab.values[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Proyectos'),
          NavigationDestination(icon: Icon(Icons.vpn_key_outlined), selectedIcon: Icon(Icons.vpn_key), label: 'Claves'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Docs'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Cuenta'),
        ],
      ),
    );
  }
}

class _DeveloperDrawer extends StatelessWidget {
  const _DeveloperDrawer({required this.name, required this.go, required this.onTest, required this.onStats, required this.onBilling});
  final String name;
  final void Function(_Tab) go;
  final VoidCallback onTest;
  final VoidCallback onStats;
  final VoidCallback onBilling;

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
            Text(name.isEmpty ? 'Desarrollador' : name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const Text('Perfil Desarrollador', style: TextStyle(color: Colors.white70)),
          ]),
        ),
        ListTile(leading: const Icon(Icons.dashboard_outlined), title: const Text('Dashboard API'), onTap: () => tap(() => go(_Tab.dashboard))),
        ListTile(leading: const Icon(Icons.folder_outlined), title: const Text('Mis proyectos'), onTap: () => tap(() => go(_Tab.projects))),
        ListTile(leading: const Icon(Icons.vpn_key_outlined), title: const Text('Credenciales API'), onTap: () => tap(() => go(_Tab.keys))),
        ListTile(leading: const Icon(Icons.menu_book_outlined), title: const Text('Documentación API'), onTap: () => tap(() => go(_Tab.docs))),
        ListTile(leading: const Icon(Icons.play_circle_outline), title: const Text('Probar API'), onTap: () => tap(onTest)),
        ListTile(leading: const Icon(Icons.bar_chart), title: const Text('Estadísticas'), onTap: () => tap(onStats)),
        ListTile(leading: const Icon(Icons.workspace_premium_outlined), title: const Text('Planes y facturación'), onTap: () => tap(onBilling)),
        ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Configuración'), onTap: () => tap(() => go(_Tab.settings))),
        ListTile(
          leading: const Icon(Icons.support_agent),
          title: const Text('Ayuda y soporte'),
          onTap: () => tap(() => showSupportSheet(context, audience: 'Desarrollador')),
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
