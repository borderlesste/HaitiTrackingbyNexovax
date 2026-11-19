import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'mission.dart';

class MissionDetailScreen extends StatelessWidget {
  const MissionDetailScreen({super.key, required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final until = m.endAt == null ? 'Sin fecha límite' : DateFormat('dd/MM/yyyy').format(m.endAt!.toLocal());
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de misión')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(m.code, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 4),
          Text(m.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('📍 ${m.commune ?? ''}, Haití · ${(m.distanceM / 1000).toStringAsFixed(1)} km'),
          const SizedBox(height: 16),
          _Box(children: [
            _Row('Recompensa por aporte aprobado', '\$${m.rewardUsd} USD', highlight: true),
            if (m.hasBonus) _Row('Bono al completar la misión', '\$${m.bonusUsd} USD', highlight: true),
            _Row('Aportes necesarios', '${m.requiredContributions}'),
            _Row('Disponible hasta', until),
          ]),
          const SizedBox(height: 12),
          _Box(children: [
            const Text('Qué hay que hacer', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(m.description),
            const SizedBox(height: 8),
            Text('Requisitos: ${m.requirements}'),
          ]),
          const SizedBox(height: 12),
          const _Box(children: [
            Text('Seguridad', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('• Solo lugares abiertos al público, nunca viviendas privadas.\n'
                '• No fotografíes personas sin permiso ni entres en propiedades privadas.\n'
                '• No hagas misiones de noche ni en zonas que consideres inseguras.'),
          ]),
          const SizedBox(height: 12),
          const Text(
            'La recompensa se acredita solo cuando tu aporte sea revisado y aprobado. '
            'Los retiros por MonCash todavía no están disponibles.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            // El flujo de aporte (GPS + foto + datos) llega en la fase 3.
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('El registro de aportes estará disponible muy pronto.')),
            ),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Comenzar misión'),
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: highlight ? HtColors.red : null, fontSize: highlight ? 16 : 14)),
          ],
        ),
      );
}
