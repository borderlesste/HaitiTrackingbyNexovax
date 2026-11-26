import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../profile/help_support_screen.dart';
import 'contribution_service.dart';
import 'contribution_widgets.dart';
import 'correct_contribution_screen.dart';

/// Detalle de un aporte: evidencias, estado, observaciones del revisor y recompensa.
class ContributionDetailScreen extends StatefulWidget {
  const ContributionDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<ContributionDetailScreen> createState() => _ContributionDetailScreenState();
}

class _ContributionDetailScreenState extends State<ContributionDetailScreen> {
  final _service = ContributionService();
  Map<String, dynamic>? _c;
  Map<String, String> _photos = const {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _service.contribution(widget.id);
      final paths = ((c['photo_paths'] as List?) ?? const []).cast<String>();
      final photos = await _service.photoUrls(paths);
      if (mounted) {
        setState(() {
          _c = c;
          _photos = photos;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el aporte.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    Widget body;
    if (c == null) {
      body = Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Reintentar')),
              ]),
      );
    } else {
      body = RefreshIndicator(onRefresh: _load, child: _content(c));
    }
    return HtScaffold(background: Colors.white, body: body);
  }

  Widget _content(Map<String, dynamic> c) {
    final status = c['status'] as String?;
    final mission = c['missions'] as Map<String, dynamic>?;
    final paths = ((c['photo_paths'] as List?) ?? const []).cast<String>();
    final point = parseEwkbPoint(c['location']);
    final reason = c['review_reason'] as String?;
    final previous = c['previous_review_reason'] as String?;
    final resubmits = (c['resubmit_count'] as num?)?.toInt() ?? 0;
    final canFix = (status == 'NEEDS_CHANGES' || status == 'REJECTED') && resubmits < 3;
    final created = DateTime.parse(c['created_at'] as String);
    final reviewedAt = c['reviewed_at'] == null ? null : DateTime.parse(c['reviewed_at'] as String);
    final reward = cents(mission?['individual_reward_usd']);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        const ScreenTitle('Detalle del aporte', icon: Icons.storefront_outlined),
        const SizedBox(height: 14),
        // Evidencias
        SizedBox(
          height: 200,
          child: paths.isEmpty
              ? const PlaceThumb(size: 200)
              : PageView(children: [
                  for (final p in paths)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _photos[p] == null
                          ? Container(color: HtColors.blueSoft, child: const Icon(Icons.image_outlined, size: 48, color: HtColors.blue))
                          : Image.network(_photos[p]!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: HtColors.blueSoft)),
                    ),
                ]),
        ),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['name'] as String, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(c['category'] as String? ?? '', style: const TextStyle(color: HtColors.muted)),
            ]),
          ),
          ContributionStatusChip(status),
        ]),
        if (mission != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.flag_outlined, size: 18, color: HtColors.muted),
            const SizedBox(width: 6),
            Expanded(child: Text('Misión: ${mission['title']}', style: const TextStyle(color: HtColors.muted))),
          ]),
        ],
        if (reason != null && reason.isNotEmpty && (status == 'NEEDS_CHANGES' || status == 'REJECTED')) ...[
          const SizedBox(height: 14),
          HtCard(
            color: HtColors.redSoft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.feedback_outlined, color: HtColors.red),
                const SizedBox(width: 8),
                Text(status == 'NEEDS_CHANGES' ? 'Cambios pedidos' : 'Motivo del rechazo',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
              const SizedBox(height: 6),
              Text(reason, style: const TextStyle(height: 1.35)),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        const SectionTitle('Estado', icon: Icons.timeline),
        const SizedBox(height: 6),
        HtCard(
          child: Column(children: [
            _Step(done: true, title: resubmits > 0 ? 'Reenviado con correcciones' : 'Enviado', detail: fechaHora(created)),
            _Step(
              done: status != 'SUBMITTED',
              active: isInReview(status),
              title: 'En revisión',
              detail: isInReview(status) ? 'El equipo revisa la foto, el GPS y los datos (24–72 h).' : null,
            ),
            _Step(
              done: status == 'APPROVED' || status == 'REJECTED' || status == 'NEEDS_CHANGES',
              bad: status == 'REJECTED' || status == 'NEEDS_CHANGES',
              last: true,
              title: switch (status) {
                'APPROVED' => 'Aprobado',
                'REJECTED' => 'Rechazado',
                'NEEDS_CHANGES' => 'Requiere cambios',
                _ => 'Resultado',
              },
              detail: reviewedAt == null ? null : fechaHora(reviewedAt),
            ),
          ]),
        ),
        if (previous != null && previous.isNotEmpty) ...[
          const SizedBox(height: 10),
          InfoBanner('Observación anterior: $previous'),
        ],
        const SizedBox(height: 14),
        const SectionTitle('Datos del lugar', icon: Icons.info_outline),
        const SizedBox(height: 6),
        HtCard(
          child: Column(children: [
            if ((c['address_reference'] as String?)?.isNotEmpty ?? false)
              KvRow('Referencia', c['address_reference'] as String, icon: Icons.signpost_outlined),
            if ((c['notes'] as String?)?.isNotEmpty ?? false)
              KvRow('Descripción', c['notes'] as String, icon: Icons.notes),
            if (point != null)
              KvRow('Coordenadas', '${point.$1.toStringAsFixed(5)}, ${point.$2.toStringAsFixed(5)}', icon: Icons.my_location),
            if (c['accuracy_m'] != null) KvRow('Precisión GPS', '± ${(num.tryParse('${c['accuracy_m']}') ?? 0).round()} m', icon: Icons.gps_fixed),
            if (c['captured_at'] != null)
              KvRow('Capturado', fechaHora(DateTime.parse(c['captured_at'] as String)), icon: Icons.schedule),
          ]),
        ),
        if (point != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 170,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(point.$1, point.$2),
                  initialZoom: 17,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.nexovax.haititracking',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(point.$1, point.$2),
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
        ],
        if (reward > 0 || mission?['open_contribution'] != true) ...[
          const SizedBox(height: 14),
          HtCard(
            color: status == 'APPROVED' ? HtColors.greenSoft : HtColors.surface,
            child: KvRow(status == 'APPROVED' ? 'Recompensa ganada' : 'Recompensa si se aprueba', usd(reward),
                icon: Icons.savings_outlined, bold: true, valueColor: HtColors.green),
          ),
        ],
        const SizedBox(height: 20),
        if (canFix)
          FilledButton.icon(
            onPressed: () async {
              final done = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => CorrectContributionScreen(contribution: c, photoUrls: _photos)));
              if (done == true) _load();
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Corregir y reenviar'),
          )
        else if (status == 'NEEDS_CHANGES' || status == 'REJECTED')
          const InfoBanner('Ya corregiste este aporte 3 veces. Registra uno nuevo o escribe a soporte.', warning: true),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => NewTicketScreen(
              kind: TicketKind.claim,
              contributionId: c['id'] as String,
              subject: 'Aporte: ${c['name']}',
            ),
          )),
          icon: const Icon(Icons.support_agent),
          label: const Text('Reclamar o consultar sobre este aporte'),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.done, required this.title, this.detail, this.active = false, this.bad = false, this.last = false});
  final bool done;
  final bool active;
  final bool bad;
  final bool last;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final color = bad ? HtColors.red : (done ? HtColors.green : (active ? HtColors.amber : HtColors.border));
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Icon(bad ? Icons.cancel : (done ? Icons.check_circle : (active ? Icons.schedule : Icons.circle_outlined)),
              color: color, size: 24),
          if (!last) Expanded(child: Container(width: 2, color: HtColors.border)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14, top: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: done || active ? HtColors.text : HtColors.muted)),
              if (detail != null) Text(detail!, style: const TextStyle(color: HtColors.muted, fontSize: 13)),
            ]),
          ),
        ),
      ]),
    );
  }
}
