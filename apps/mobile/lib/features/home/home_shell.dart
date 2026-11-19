import 'package:flutter/material.dart';
import '../../core/profile_context.dart';

import '../contributions/contribution_service.dart';
import '../contributions/my_contributions_screen.dart';
import '../missions/map_screen.dart';
import '../missions/mission.dart';
import '../missions/missions_list_screen.dart';
import '../rewards/rewards_screen.dart';

/// Barra inferior del colaborador: Mapa / Misiones / Recompensas / Perfil.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _repo = MissionsRepository();
  int _tab = 0;
  List<Mission> _missions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // Envía en segundo plano los aportes guardados sin conexión.
    ContributionService().syncPending().ignore();
  }

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
    final titles = ['Misiones en el mapa', 'Misiones', 'Recompensas', 'Perfil'];
    final Widget body;
    if (_tab <= 1 && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_tab <= 1 && _error != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ]),
      );
    } else {
      body = switch (_tab) {
        0 => MapScreen(missions: _missions, onRefresh: _load),
        1 => MissionsListScreen(missions: _missions, onRefresh: _load),
        2 => const RewardsScreen(),
        _ => const _ProfileScreen(),
      };
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [if (_tab <= 1) IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.location_on_outlined), selectedIcon: Icon(Icons.location_on), label: 'Mapa'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Misiones'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Recompensas'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context) => ProfileActions(extra: [
        ListTile(
          leading: const Icon(Icons.assignment_turned_in_outlined),
          title: const Text('Mis aportes'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyContributionsScreen())),
        ),
      ]);
}
