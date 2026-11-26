import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/contribution_service.dart';
import '../contributions/my_contributions_screen.dart';
import '../missions/map_screen.dart';
import '../missions/mission.dart';
import '../missions/missions_list_screen.dart';
import '../profile/profile_screen.dart';
import '../rewards/rewards_screen.dart';
import '../rewards/withdrawals_screen.dart';

/// Pestañas del colaborador.
enum HomeTab { home, missions, contributions, rewards, profile }

/// Barra inferior del colaborador: Inicio / Misiones / Aportes / Recompensas / Perfil.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Permite que pantallas internas cambien de pestaña (p. ej. "Volver al inicio").
  static final tab = ValueNotifier<HomeTab>(HomeTab.home);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _repo = MissionsRepository();
  final _scaffold = GlobalKey<ScaffoldState>();
  List<Mission> _missions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    HomeShell.tab.value = HomeTab.home;
    HomeShell.tab.addListener(_onTab);
    _load();
    // Envía en segundo plano los aportes guardados sin conexión.
    ContributionService().syncPending().ignore();
  }

  @override
  void dispose() {
    HomeShell.tab.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Consultar misiones no exige GPS: se usa el centro de Port-au-Prince.
      final list = await _repo.nearby(portAuPrince, radiusKm: 40);
      if (mounted) setState(() => _missions = list);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron cargar las misiones.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = HomeShell.tab.value;
    final needsMissions = tab == HomeTab.home || tab == HomeTab.missions;
    final Widget body;
    if (needsMissions && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (needsMissions && _error != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ]),
      );
    } else {
      body = switch (tab) {
        HomeTab.home => MapScreen(missions: _missions, onRefresh: _load),
        HomeTab.missions => MissionsListScreen(missions: _missions, onRefresh: _load),
        HomeTab.contributions => const MyContributionsScreen(embedded: true),
        HomeTab.rewards => const RewardsScreen(),
        HomeTab.profile => const ProfileScreen(),
      };
    }
    return HtScaffold(
      scaffoldKey: _scaffold,
      appBar: HtAppBar(showBack: false, showBell: true, onMenu: () => _scaffold.currentState?.openDrawer()),
      drawer: const _HomeDrawer(),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.index,
        height: 70,
        onDestinationSelected: (i) => HomeShell.tab.value = HomeTab.values[i],
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.location_on_outlined), selectedIcon: Icon(Icons.location_on), label: 'Misiones'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Aportes'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Recompensas'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer();

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = (user?.userMetadata?['full_name'] as String?) ?? '';
    void go(HomeTab t) {
      Navigator.pop(context);
      HomeShell.tab.value = t;
    }

    return Drawer(
      child: ListView(padding: EdgeInsets.zero, children: [
        DrawerHeader(
          decoration: const BoxDecoration(color: HtColors.navy),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
            const HtBrand(size: .9),
            const SizedBox(height: 14),
            Text(name.isEmpty ? 'Colaborador' : name,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          ]),
        ),
        ListTile(leading: const Icon(Icons.home_outlined), title: const Text('Inicio'), onTap: () => go(HomeTab.home)),
        ListTile(leading: const Icon(Icons.location_on_outlined), title: const Text('Misiones'), onTap: () => go(HomeTab.missions)),
        ListTile(leading: const Icon(Icons.assignment_outlined), title: const Text('Mis aportes'), onTap: () => go(HomeTab.contributions)),
        ListTile(leading: const Icon(Icons.savings_outlined), title: const Text('Mis recompensas'), onTap: () => go(HomeTab.rewards)),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Mis retiros'),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WithdrawalsScreen()));
          },
        ),
        ListTile(leading: const Icon(Icons.person_outline), title: const Text('Mi perfil'), onTap: () => go(HomeTab.profile)),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('Cambiar de perfil'),
          subtitle: const Text('Colaborador, Empresa o Desarrollador'),
          onTap: () {
            Navigator.pop(context);
            showProfileSwitcher(context);
          },
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
