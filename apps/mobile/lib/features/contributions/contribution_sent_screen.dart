import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../missions/mission.dart';
import '../missions/mission_completed_screen.dart';
import '../missions/mission_progress_screen.dart';
import 'contribution_draft.dart';
import 'contribution_service.dart';
import 'contribution_widgets.dart';
import 'new_contribution_screen.dart';

/// Confirmación tras enviar (o guardar sin conexión) un aporte.
class ContributionSentScreen extends StatelessWidget {
  const ContributionSentScreen({super.key, required this.mission, required this.draft, this.offline = false});
  final Mission mission;
  final ContributionDraft draft;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return HtScaffold(
      background: Colors.white,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Center(
            child: offline
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Icon(Icons.cloud_off, size: 90, color: HtColors.amber),
                  )
                : const SuccessMark(size: 96),
          ),
          Text(offline ? 'Guardado en tu teléfono' : '¡Aporte enviado!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: HtColors.text)),
          const SizedBox(height: 8),
          Text(
            offline
                ? 'No hay conexión. Lo enviaremos automáticamente cuando vuelvas a tener internet.'
                : 'Tu ubicación ha sido registrada y está en proceso de revisión.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: HtColors.muted, height: 1.35),
          ),
          const SizedBox(height: 18),
          HtCard(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PlaceThumb(file: File(draft.photoPath), size: 92),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(draft.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  _Line(Icons.storefront_outlined, draft.category),
                  if (mission.commune != null) _Line(Icons.location_on_outlined, mission.commune!),
                  _Line(Icons.my_location, '${draft.lat.toStringAsFixed(5)}, ${draft.lng.toStringAsFixed(5)}'),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          HtCard(
            child: Column(children: [
              KvRow('Estado', '', icon: Icons.schedule,
                  trailing: StatusChip(offline ? 'Pendiente de envío' : 'En revisión', tone: ChipTone.review)),
              const Divider(height: 8),
              KvRow('Recompensa estimada', usd(mission.rewardCents),
                  icon: Icons.savings_outlined, valueColor: HtColors.green),
            ]),
          ),
          const SizedBox(height: 12),
          const InfoBanner('Te notificaremos cuando tu aporte sea aprobado o si se requiere información adicional.'),
          const SizedBox(height: 20),
          FutureBuilder<int>(
            future: offline ? Future.value(-1) : _countSent(mission.id),
            builder: (context, snap) {
              final n = snap.data ?? -1;
              final total = mission.requiredContributions;
              final complete = n >= total;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (complete)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pushReplacement(MaterialPageRoute(builder: (_) => MissionCompletedScreen(mission: mission))),
                    icon: const Icon(Icons.emoji_events_outlined),
                    label: const Text('Ver misión completada'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pushReplacement(MaterialPageRoute(builder: (_) => NewContributionScreen(mission: mission))),
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(n > 0 ? 'Registrar siguiente (${n + 1} de $total)' : 'Registrar otro establecimiento'),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context)
                      .pushReplacement(MaterialPageRoute(builder: (_) => MissionProgressScreen(mission: mission))),
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Ver progreso de la misión'),
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

Future<int> _countSent(String missionId) async {
  try {
    final items = await ContributionService().missionContributions(missionId);
    return items.where((c) => c['status'] != 'REJECTED').length;
  } catch (_) {
    return -1;
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: HtColors.navy),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ]),
      );
}
