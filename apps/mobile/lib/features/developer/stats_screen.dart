import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:intl/intl.dart';

import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'developer_repo.dart';

/// Pantalla 31: Estadísticas (uso, errores y consumo por día).
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.projectId, this.embedded = false});
  final String? projectId;
  final bool embedded;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _repo = DeveloperRepo();
  late String? _project = widget.projectId;
  int _range = 0; // 0 = 7 días, 1 = 30 días
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _data = _load();

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async {
    final projects = await _repo.projects();
    final usage = await _repo.usage([for (final p in projects) p['id'] as String], days: 30);
    return (projects, usage);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _data,
      builder: (context, snap) {
        final children = <Widget>[];
        if (snap.hasError) {
          children.add(EmptyState(icon: Icons.cloud_off, title: 'No se pudo cargar', text: 'Revisa tu conexión.',
              action: OutlinedButton(onPressed: () => setState(() => _data = _load()), child: const Text('Reintentar'))));
        } else if (!snap.hasData) {
          children.add(const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
        } else {
          final (projects, usage) = snap.data!;
          final days = lastDays(_range == 0 ? 7 : 30);
          final byDay = usageByDay(usage, projectId: _project);
          final fmt = DateFormat('yyyy-MM-dd');
          final req = [for (final d in days) byDay[fmt.format(d)]?.$1 ?? 0];
          final err = [for (final d in days) byDay[fmt.format(d)]?.$2 ?? 0];
          final total = req.fold<int>(0, (a, b) => a + b);
          final errors = err.fold<int>(0, (a, b) => a + b);
          final quota = projects
              .where((p) => _project == null || p['id'] == _project)
              .fold<int>(0, (a, p) => a + (p['daily_quota'] as num).toInt());
          final todayReq = req.last;
          final peak = req.fold<int>(0, (a, b) => b > a ? b : a);
          children.addAll([
            DropdownButtonFormField<String?>(
              initialValue: _project,
              isExpanded: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.folder_outlined)),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos los proyectos')),
                for (final p in projects) DropdownMenuItem(value: p['id'] as String, child: Text(p['name'] as String)),
              ],
              onChanged: (v) => setState(() => _project = v),
            ),
            const SizedBox(height: 10),
            FilterPills(labels: const ['Últimos 7 días', 'Últimos 30 días'], selected: _range, onSelected: (i) => setState(() => _range = i)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: [
                StatTile(icon: Icons.query_stats, value: '$total', label: 'Consultas en el periodo'),
                StatTile(icon: Icons.today, value: '$todayReq', label: 'Consultas hoy', color: HtColors.navy),
                StatTile(icon: Icons.error_outline, value: '$errors', label: 'Errores', color: HtColors.red),
                StatTile(icon: Icons.trending_up, value: '$peak', label: 'Pico diario', color: HtColors.green),
              ],
            ),
            const SizedBox(height: 14),
            HtCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Consultas por día', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 12),
                MiniBars(
                  values: req,
                  labels: [for (final d in days) _range == 0 ? const ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'][d.weekday - 1] : (d.day % 5 == 0 ? '${d.day}' : '')],
                ),
              ]),
            ),
            const SizedBox(height: 14),
            HtCard(child: ProgressLine(value: todayReq, total: quota == 0 ? 1 : quota, label: 'Consumo de la cuota hoy')),
            const SizedBox(height: 14),
            const InfoBanner('Las cifras se actualizan con cada consulta. La cuota diaria se reinicia a medianoche (hora del servidor).'),
          ]);
        }
        if (widget.embedded) {
          return RefreshIndicator(
            onRefresh: () async => setState(() => _data = _load()),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 28), children: [
              const ScreenTitle('Estadísticas', icon: Icons.bar_chart, subtitle: 'Uso, errores y consumo.'),
              const SizedBox(height: 16),
              ...children,
            ]),
          );
        }
        return PanelPage(
          title: 'Estadísticas',
          icon: Icons.bar_chart,
          subtitle: 'Uso, errores y consumo.',
          onRefresh: () async => setState(() => _data = _load()),
          children: children,
        );
      },
    );
  }
}
