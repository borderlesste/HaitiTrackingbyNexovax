import 'package:flutter/material.dart';

import '../../core/theme.dart';
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
      child: missions.isEmpty
          ? ListView(children: const [
              SizedBox(height: 120),
              Center(child: Text('No hay misiones activas cerca por ahora.')),
            ])
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: missions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final m = missions[i];
                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: CircleAvatar(
                      backgroundColor: m.isPriority ? HtColors.red : HtColors.blue,
                      child: Icon(m.isPriority ? Icons.star : Icons.storefront, color: Colors.white),
                    ),
                    title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${m.commune ?? ''} · ${(m.distanceM / 1000).toStringAsFixed(1)} km\n'
                        '${m.requiredContributions} aporte(s) · ${m.requirements}'),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('\$${m.rewardUsd}',
                            style: const TextStyle(color: HtColors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                        if (m.hasBonus) Text('+\$${m.bonusUsd} bono', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => MissionDetailScreen(mission: m))),
                  ),
                );
              },
            ),
    );
  }
}
