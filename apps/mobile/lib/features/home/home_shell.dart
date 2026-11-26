import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/guest.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/contribution_service.dart';
import '../contributions/my_contributions_screen.dart';
import '../missions/map_screen.dart';
import '../missions/mission.dart';
import '../missions/missions_list_screen.dart';
import '../notifications/notifications_screen.dart';
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
    if (!Guest.isGuest) Notices.refreshBadge().ignore();
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
    } else if (Guest.isGuest && tab == HomeTab.contributions) {
      body = const GuestGate(
        title: 'Mis aportes',
        icon: Icons.assignment_outlined,
        description: 'Aquí verás cada lugar que registres y el estado de su revisión.',
        points: [
          'Toma una foto del lugar y marca su ubicación con el GPS.',
          'Funciona sin conexión: tus aportes se envían cuando vuelve la señal.',
          'Sigue la revisión: en revisión, aprobado o con cambios pedidos.',
        ],
      );
    } else if (Guest.isGuest && tab == HomeTab.rewards) {
      body = const GuestGate(
        title: 'Mis recompensas',
        icon: Icons.savings,
        description: 'Cada aporte aprobado suma recompensas en dólares a tu saldo.',
        points: [
          'Bonos extra al completar misiones enteras.',
          'Retira tu saldo a tu cuenta MonCash.',
          'Solo pediremos verificar tu número por SMS cuando quieras retirar.',
        ],
      );
    } else if (Guest.isGuest && tab == HomeTab.profile) {
      body = const _GuestProfile();
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
      appBar: HtAppBar(showBack: false, showBell: !Guest.isGuest, onMenu: () => _scaffold.currentState?.openDrawer()),
      drawer: const _HomeDrawer(),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.index,
        height: 70,
        onDestinationSelected: (i) => HomeShell.tab.value = HomeTab.values[i],
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: tr('Inicio')),
          NavigationDestination(icon: Icon(Icons.location_on_outlined), selectedIcon: Icon(Icons.location_on), label: tr('Misiones')),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: tr('Aportes')),
          NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: tr('Recompensas')),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: tr('Perfil')),
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

    if (Guest.isGuest) return _GuestDrawer(go: go);
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

/// Menú lateral del invitado: explorar y crear una cuenta.
class _GuestDrawer extends StatelessWidget {
  const _GuestDrawer({required this.go});
  final void Function(HomeTab) go;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(padding: EdgeInsets.zero, children: [
        const DrawerHeader(
          decoration: BoxDecoration(color: HtColors.navy),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
            HtBrand(size: .9),
            SizedBox(height: 14),
            Text('Modo invitado', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          ]),
        ),
        ListTile(leading: const Icon(Icons.home_outlined), title: const Text('Inicio'), onTap: () => go(HomeTab.home)),
        ListTile(leading: const Icon(Icons.location_on_outlined), title: const Text('Misiones'), onTap: () => go(HomeTab.missions)),
        ListTile(leading: const Icon(Icons.savings_outlined), title: const Text('Cómo se gana'), onTap: () => go(HomeTab.rewards)),
        const Divider(),
        for (final p in AppProfile.values)
          ListTile(
            leading: Icon(profileInfo[p]!.$1, color: HtColors.blue),
            title: Text('Ser ${profileInfo[p]!.$2.toLowerCase()}'),
            subtitle: Text(profileInfo[p]!.$3),
            onTap: () {
              Navigator.pop(context);
              openRegister(context, profile: p);
            },
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.login),
          title: const Text('Iniciar sesión'),
          onTap: () {
            Navigator.pop(context);
            openLogin(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.exit_to_app, color: HtColors.muted),
          title: const Text('Salir del modo invitado'),
          onTap: () {
            Navigator.pop(context);
            Guest.set(false);
          },
        ),
      ]),
    );
  }
}

/// Pestaña Perfil del invitado: elegir cómo quiere participar.
class _GuestProfile extends StatelessWidget {
  const _GuestProfile();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        const ScreenTitle('Únete a Haiti Tracking',
            icon: Icons.person_outline, subtitle: 'Estás explorando sin cuenta. Elige cómo quieres participar.'),
        const SizedBox(height: 16),
        for (final p in AppProfile.values) ...[
          HtCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: IconTile(profileInfo[p]!.$1),
              title: Text(profileInfo[p]!.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              subtitle: Text(profileInfo[p]!.$3),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openRegister(context, profile: p),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => openLogin(context),
          icon: const Icon(Icons.login),
          label: const Text('Ya tengo cuenta: iniciar sesión'),
        ),
        const SizedBox(height: 12),
        const Text('Registrarte es gratis y no pide ningún código. '
            'El número solo se verifica por SMS si eres colaborador y quieres retirar fondos.',
            textAlign: TextAlign.center, style: TextStyle(color: HtColors.muted, height: 1.35)),
      ],
    );
  }
}
