import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:intl/intl.dart';

import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'developer_repo.dart';

/// Pantalla 26: Dashboard API (resumen de proyectos y consultas).
class DeveloperDashboardScreen extends StatefulWidget {
  const DeveloperDashboardScreen({
    super.key,
    required this.profile,
    required this.onProjects,
    required this.onCredentials,
    required this.onDocs,
    required this.onTest,
    required this.onStats,
    required this.onBilling,
  });
  final Map<String, dynamic> profile;
  final VoidCallback onProjects;
  final VoidCallback onCredentials;
  final VoidCallback onDocs;
  final VoidCallback onTest;
  final VoidCallback onStats;
  final VoidCallback onBilling;

  @override
  State<DeveloperDashboardScreen> createState() => _DeveloperDashboardScreenState();
}

class _Dash {
  _Dash(this.projects, this.keys, this.usage);
  final List<Map<String, dynamic>> projects;
  final List<Map<String, dynamic>> keys;
  final List<Map<String, dynamic>> usage;
}

class _DeveloperDashboardScreenState extends State<DeveloperDashboardScreen> {
  final _repo = DeveloperRepo();
  late Future<_Dash> _data = _load();

  Future<_Dash> _load() async {
    final projects = await _repo.projects();
    final ids = [for (final p in projects) p['id'] as String];
    return _Dash(projects, await _repo.allKeys(ids), await _repo.usage(ids, days: 7));
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.profile['display_name'] as String? ?? '').split(' ').first;
    return RefreshIndicator(
      onRefresh: () async => setState(() => _data = _load()),
      child: FutureBuilder<_Dash>(
        future: _data,
        builder: (context, snap) {
          final d = snap.data;
          final days = lastDays(7);
          final byDay = d == null ? const <String, (int, int)>{} : usageByDay(d.usage);
          final fmt = DateFormat('yyyy-MM-dd');
          final req = [for (final x in days) byDay[fmt.format(x)]?.$1 ?? 0];
          final week = req.fold<int>(0, (a, b) => a + b);
          final quota = d?.projects.fold<int>(0, (a, p) => a + (p['daily_quota'] as num).toInt()) ?? 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Row(children: [
                const CircleAvatar(radius: 26, backgroundColor: HtColors.blue, child: Icon(Icons.code, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hola, ${name.isEmpty ? 'desarrollador' : name}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const Text('Dashboard de la API de lugares', style: TextStyle(color: HtColors.muted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              if (snap.hasError)
                EmptyState(icon: Icons.cloud_off, title: 'No se pudo cargar', text: 'Revisa tu conexión.',
                    action: OutlinedButton(onPressed: () => setState(() => _data = _load()), child: const Text('Reintentar')))
              else if (d == null)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: HtColors.blue, borderRadius: BorderRadius.circular(18)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Consultas hoy', style: TextStyle(color: Colors.white70, fontSize: 15)),
                    Text('${req.last} / $quota', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: quota == 0 ? 0 : (req.last / quota).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.white24,
                        color: Colors.white,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: .95,
                  children: [
                    StatTile(icon: Icons.folder_outlined, value: '${d.projects.length}', label: 'Proyectos', onTap: widget.onProjects),
                    StatTile(icon: Icons.vpn_key_outlined, value: '${d.keys.where((k) => k['revoked_at'] == null).length}', label: 'Claves activas', color: HtColors.green, onTap: widget.onCredentials),
                    StatTile(icon: Icons.query_stats, value: '$week', label: 'Consultas 7 días', color: HtColors.navy, onTap: widget.onStats),
                  ],
                ),
                const SizedBox(height: 14),
                HtCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Expanded(child: Text('Últimos 7 días', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                      TextButton(onPressed: widget.onStats, child: const Text('Ver estadísticas')),
                    ]),
                    MiniBars(values: req, labels: [for (final x in days) const ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'][x.weekday - 1]], height: 90),
                  ]),
                ),
                const SizedBox(height: 16),
                const SectionTitle('Herramientas', icon: Icons.handyman_outlined),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: QuickAction(icon: Icons.menu_book_outlined, label: 'Documentación', onTap: widget.onDocs)),
                  const SizedBox(width: 10),
                  Expanded(child: QuickAction(icon: Icons.play_circle_outline, label: 'Probar API', onTap: widget.onTest)),
                  const SizedBox(width: 10),
                  Expanded(child: QuickAction(icon: Icons.workspace_premium_outlined, label: 'Planes', onTap: widget.onBilling)),
                ]),
                if (d.projects.isEmpty) ...[
                  const SizedBox(height: 16),
                  HtCard(
                    color: HtColors.blueSoft,
                    borderColor: Colors.transparent,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Empieza en 3 pasos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 6),
                      const Text('1. Crea un proyecto.\n2. Genera una clave y guárdala en tu servidor.\n3. Consulta lugares cercanos con la API.',
                          style: TextStyle(height: 1.5)),
                      const SizedBox(height: 10),
                      FilledButton.icon(onPressed: widget.onProjects, icon: const Icon(Icons.add), label: const Text('Crear mi primer proyecto')),
                    ]),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}
