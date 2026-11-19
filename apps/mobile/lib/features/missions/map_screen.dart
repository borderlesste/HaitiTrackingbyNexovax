import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/theme.dart';
import 'mission.dart';
import 'mission_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.missions, required this.onRefresh});

  final List<Mission> missions;
  final Future<void> Function() onRefresh;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Mission? _selected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: portAuPrince,
            initialZoom: 13,
            onTap: (_, __) => setState(() => _selected = null),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.nexovax.haititracking',
            ),
            MarkerLayer(
              markers: [
                for (final m in widget.missions)
                  Marker(
                    point: m.point,
                    width: 74,
                    height: 52,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = m),
                      child: _RewardPin(mission: m, selected: _selected?.id == m.id),
                    ),
                  ),
              ],
            ),
            const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
          ],
        ),
        if (_selected != null)
          Positioned(left: 12, right: 12, bottom: 12, child: _MissionCard(mission: _selected!)),
      ],
    );
  }
}

class _RewardPin extends StatelessWidget {
  const _RewardPin({required this.mission, required this.selected});
  final Mission mission;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = mission.isPriority || mission.hasBonus ? HtColors.red : HtColors.blue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white, width: selected ? 3 : 2),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Text('\$${mission.rewardUsd}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        Icon(Icons.arrow_drop_down, color: color, size: 22),
      ],
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mission.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('📍 ${mission.commune ?? ''}, Haití'),
                    ],
                  ),
                ),
                Column(
                  children: [
                    const Text('Recompensa', style: TextStyle(fontSize: 12)),
                    Text('\$${mission.rewardUsd} USD',
                        style: const TextStyle(color: HtColors.red, fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Requisitos: ${mission.requirements}'),
            const SizedBox(height: 4),
            const Text('La recompensa se acredita solo cuando tu aporte sea revisado y aprobado.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => MissionDetailScreen(mission: mission))),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Ver misión'),
            ),
          ],
        ),
      ),
    );
  }
}
