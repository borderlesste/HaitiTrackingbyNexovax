import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/money.dart';
import '../../core/guest.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/new_contribution_screen.dart';
import 'map_screen.dart';
import 'mission.dart';

class MissionDetailScreen extends StatelessWidget {
  const MissionDetailScreen({super.key, required this.mission});
  final Mission mission;

  /// Requisitos en forma de lista: los de la misión ("GPS + foto + datos") más las reglas fijas.
  List<String> get _requirements {
    final m = mission;
    final parts = m.requirements
        .split(RegExp(r'\s*[+,;]\s*'))
        .where((s) => s.trim().isNotEmpty)
        .map((s) => switch (s.trim().toLowerCase()) {
              'gps' => 'Capturar la ubicación (GPS)',
              'foto' => 'Tomar una foto clara del establecimiento',
              'datos del lugar' => 'Completar la información solicitada',
              _ => s.trim()[0].toUpperCase() + s.trim().substring(1),
            })
        .toList();
    return [
      if (m.requiresOnSite) 'Estar dentro del área de la misión',
      ...parts,
      if (m.requiredContributions > 1) 'Registrar ${m.requiredContributions} establecimientos distintos',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final until = m.endAt == null ? null : fechaCorta(m.endAt!);
    return HtScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const Text('Detalle de la misión', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: HtColors.text)),
          const SizedBox(height: 14),
          HtCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconTile(missionIcon(m), size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: HtColors.text)),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: HtColors.muted),
                    Flexible(child: Text(' ${m.commune ?? ''}', style: const TextStyle(color: HtColors.muted))),
                  ]),
                  if (until != null) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.event_outlined, size: 16, color: HtColors.muted),
                      Text(' Disponible hasta: $until', style: const TextStyle(color: HtColors.muted)),
                    ]),
                  ],
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          _RewardBox(mission: m),
          const SizedBox(height: 12),
          HtCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('Objetivo', icon: Icons.track_changes),
              const SizedBox(height: 8),
              Text(m.description.isEmpty ? m.title : m.description, style: const TextStyle(fontSize: 15, height: 1.4)),
              const SizedBox(height: 16),
              const SectionTitle('Requisitos', icon: Icons.assignment_outlined),
              const SizedBox(height: 6),
              for (final r in _requirements)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.check_circle, color: HtColors.green, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 15))),
                  ]),
                ),
            ]),
          ),
          if (m.requiresOnSite) ...[
            const SizedBox(height: 12),
            HtCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionTitle('Área de la misión', icon: Icons.location_on_outlined),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 170,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: m.point,
                        initialZoom: _zoomFor(m.radiusM),
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.nexovax.haititracking',
                        ),
                        CircleLayer(circles: [
                          CircleMarker(
                            point: m.point,
                            radius: (m.radiusM ?? 300).toDouble(),
                            useRadiusInMeter: true,
                            color: HtColors.blue.withValues(alpha: .18),
                            borderColor: HtColors.blue,
                            borderStrokeWidth: 2,
                          ),
                        ]),
                        MarkerLayer(markers: [
                          Marker(
                            point: m.point,
                            width: 40,
                            height: 40,
                            alignment: Alignment.topCenter,
                            child: const Icon(Icons.location_on, color: HtColors.red, size: 40),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          const InfoBanner(
            'Solo lugares abiertos al público. No fotografíes personas sin permiso ni entres en propiedades privadas, '
            'y no hagas misiones de noche ni en zonas que consideres inseguras.',
            warning: true,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () {
              if (!requireAccount(context,
                  reason: 'Para hacer misiones y ganar recompensas necesitas una cuenta de colaborador. '
                      'Solo toma un minuto y no hace falta ningún código.')) {
                return;
              }
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewContributionScreen(mission: m)));
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar misión'),
          ),
        ],
      ),
    );
  }

  static double _zoomFor(int? radiusM) {
    final r = radiusM ?? 300;
    if (r > 3000) return 11;
    if (r > 1200) return 12.5;
    if (r > 500) return 14;
    return 15;
  }
}

class _RewardBox extends StatelessWidget {
  const _RewardBox({required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final subtotal = m.rewardCents * m.requiredContributions;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: HtColors.greenSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.savings, color: HtColors.amber, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Recompensa total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(usd(m.totalCents),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: HtColors.green)),
            ]),
          ),
        ]),
        const Divider(height: 22),
        const Text('Desglose:', style: TextStyle(fontWeight: FontWeight.w700)),
        KvRow('${m.requiredContributions} ubicaciones × \$${m.rewardUsd}', money(subtotal), icon: Icons.check_circle_outline),
        if (m.hasBonus) KvRow('Bono por completar la misión', '+${money(m.bonusCents)}', icon: Icons.emoji_events_outlined),
        const SizedBox(height: 4),
        const Text('Se paga solo lo aprobado por el equipo de revisión.',
            style: TextStyle(fontSize: 12, color: HtColors.muted)),
      ]),
    );
  }
}
