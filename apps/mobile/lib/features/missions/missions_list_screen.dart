import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import 'map_screen.dart';
import 'mission.dart';
import 'mission_detail_screen.dart';

class MissionsListScreen extends StatelessWidget {
  const MissionsListScreen({super.key, required this.missions, required this.onRefresh});

  final List<Mission> missions;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const ScreenTitle('Misiones', icon: Icons.location_on_outlined, subtitle: 'Misiones activas cerca de Puerto Príncipe.'),
          const SizedBox(height: 16),
          if (missions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Text('No hay misiones activas cerca por ahora.', textAlign: TextAlign.center),
            ),
          for (final m in missions) ...[
            _MissionTile(mission: m),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    void open() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MissionDetailScreen(mission: m)));
    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(16),
      child: HtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(missionIcon(m), color: m.isPriority ? HtColors.red : HtColors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: HtColors.text)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: HtColors.muted),
                  Flexible(
                    child: Text(' ${m.commune ?? ''} · ${(m.distanceM / 1000).toStringAsFixed(1)} km',
                        style: const TextStyle(color: HtColors.muted)),
                  ),
                ]),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: HtColors.greenSoft, borderRadius: BorderRadius.circular(10)),
              child: Text('\$${missionTotal(m)}',
                  style: const TextStyle(color: HtColors.green, fontWeight: FontWeight.w800, fontSize: 17)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            '${m.requiredContributions} ubicaciones${m.hasBonus ? ' · Bono incluido' : ''} · \$${m.rewardUsd} c/u',
            style: const TextStyle(color: HtColors.text),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: open,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Ver misión'),
              SizedBox(width: 6),
              Icon(Icons.chevron_right),
            ]),
          ),
        ]),
      ),
    );
  }
}
