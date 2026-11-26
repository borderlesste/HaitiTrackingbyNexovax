import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/contribution_draft.dart' show placeCategories;
import '../missions/mission.dart' show portAuPrince;
import 'company_repo.dart';

const _typeEs = {'COLLECT': 'Recopilar lugares nuevos', 'VERIFY': 'Verificar ubicaciones existentes'};

String _missionStatusEs(Map<String, dynamic> c) {
  if (c['status'] == 'REJECTED') return 'Rechazada';
  if (c['status'] == 'PENDING') return 'En revisión';
  return switch (c['mission_status']) {
    'ACTIVE' => 'En curso',
    'PAUSED' => 'Pausada',
    'COMPLETED' || 'EXPIRED' => 'Completada',
    'CANCELLED' || 'ARCHIVED' => 'Cancelada',
    _ => 'Aprobada · preparando',
  };
}

Widget _missionChip(Map<String, dynamic> c) {
  final s = _missionStatusEs(c);
  final tone = switch (s) {
    'Rechazada' || 'Cancelada' => ChipTone.bad,
    'En revisión' => ChipTone.review,
    'Completada' || 'En curso' => ChipTone.ok,
    _ => ChipTone.info,
  };
  return StatusChip(s, tone: tone);
}

/// Pantalla 22: Seguimiento de misiones solicitadas por la empresa.
class CompanyMissionsScreen extends StatefulWidget {
  const CompanyMissionsScreen({super.key, required this.orgId});
  final String orgId;

  @override
  State<CompanyMissionsScreen> createState() => _CompanyMissionsScreenState();
}

class _CompanyMissionsScreenState extends State<CompanyMissionsScreen> {
  final _repo = CompanyRepo();
  late Future<List<Map<String, dynamic>>> _list = _repo.missionRequests(widget.orgId);
  int _filter = 0;

  Future<void> _new() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MissionRequestScreen(orgId: widget.orgId)));
    if (mounted) setState(() => _list = _repo.missionRequests(widget.orgId));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _list,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off,
            title: 'No se pudo cargar',
            text: 'Revisa tu conexión.',
            action: OutlinedButton(onPressed: () => setState(() => _list = _repo.missionRequests(widget.orgId)), child: const Text('Reintentar')),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        final groups = ['', 'En revisión', 'En curso', 'Completada'];
        final list = _filter == 0 ? all : all.where((c) => _missionStatusEs(c) == groups[_filter]).toList();
        return RefreshIndicator(
          onRefresh: () async => setState(() => _list = _repo.missionRequests(widget.orgId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            children: [
              const ScreenTitle('Seguimiento de misiones', icon: Icons.track_changes, subtitle: 'Progreso y resultados de tus solicitudes.'),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Solicitar misión')),
              const SizedBox(height: 12),
              FilterPills(
                labels: [
                  'Todas (${all.length})',
                  for (final g in groups.skip(1)) '$g (${all.where((c) => _missionStatusEs(c) == g).length})',
                ],
                selected: _filter,
                onSelected: (i) => setState(() => _filter = i),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.map_outlined,
                  title: 'Sin misiones',
                  text: 'Pide al equipo que registre o verifique lugares en una zona. Los colaboradores los recopilarán con GPS y fotos.',
                ),
              for (final c in list) ...[
                HtCard(
                  padding: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MissionRequestDetailScreen(request: c))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const IconTile(Icons.flag_outlined, size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              Text('${c['commune'] ?? 'Zona marcada'} · ${fechaCorta(DateTime.parse(c['created_at'] as String))}',
                                  style: const TextStyle(color: HtColors.muted, fontSize: 13)),
                            ]),
                          ),
                          _missionChip(c),
                        ]),
                        if (c['mission_id'] != null) ...[
                          const SizedBox(height: 12),
                          ProgressLine(value: (c['approved_places'] as num).toInt(), total: (c['target_places'] as num).toInt(), label: 'Lugares aprobados'),
                        ],
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Detalle y resultados de una misión solicitada.
class MissionRequestDetailScreen extends StatelessWidget {
  const MissionRequestDetailScreen({super.key, required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final c = request;
    final center = LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble());
    final approved = (c['approved_places'] as num? ?? 0).toInt();
    final pending = (c['pending_places'] as num? ?? 0).toInt();
    final target = (c['target_places'] as num).toInt();
    final status = c['status'] as String;
    return PanelPage(
      title: c['title'] as String,
      icon: Icons.flag_outlined,
      subtitle: _typeEs[c['request_type']] ?? 'Recopilar lugares nuevos',
      children: [
        HtCard(
          child: Column(children: [
            KvRow('Estado', '', icon: Icons.info_outline, trailing: _missionChip(c)),
            if (c['mission_code'] != null) KvRow('Código de misión', c['mission_code'] as String, icon: Icons.tag),
            KvRow('Solicitada', fechaHora(DateTime.parse(c['created_at'] as String)), icon: Icons.calendar_today_outlined),
            if (c['desired_end'] != null) KvRow('Fecha deseada', fechaCorta(DateTime.parse(c['desired_end'] as String)), icon: Icons.event_outlined),
            KvRow('Presupuesto propuesto', '\$${(c['proposed_budget_usd'] as num).toStringAsFixed(2)} USD', icon: Icons.payments_outlined),
          ]),
        ),
        if (status == 'REJECTED' && c['review_reason'] != null) ...[
          const SizedBox(height: 12),
          InfoBanner('Motivo: ${c['review_reason']}', warning: true),
        ],
        const SizedBox(height: 14),
        HtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProgressLine(value: approved, total: target, label: 'Lugares aprobados'),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _Mini(Icons.check_circle, HtColors.green, '$approved', 'Aprobados')),
              Expanded(child: _Mini(Icons.schedule, HtColors.amber, '$pending', 'En revisión')),
              Expanded(child: _Mini(Icons.flag, HtColors.blue, '$target', 'Objetivo')),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        const SectionTitle('Zona de la misión', icon: Icons.map_outlined),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: FlutterMap(
              options: MapOptions(initialCenter: center, initialZoom: 13, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.nexovax.haititracking'),
                CircleLayer(circles: [
                  CircleMarker(
                    point: center,
                    radius: (c['radius_m'] as num).toDouble(),
                    useRadiusInMeter: true,
                    color: HtColors.blue.withValues(alpha: .15),
                    borderColor: HtColors.blue,
                    borderStrokeWidth: 1.5,
                  ),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('${c['commune'] ?? ''} · radio ${c['radius_m']} m${c['category'] != null ? ' · ${c['category']}' : ''}',
            style: const TextStyle(color: HtColors.muted)),
        if ((c['description'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          const SectionTitle('Detalles', icon: Icons.notes),
          const SizedBox(height: 4),
          Text(c['description'] as String, style: const TextStyle(height: 1.4)),
        ],
        const SizedBox(height: 14),
        const InfoBanner('Los lugares se publican solo después de la revisión de nuestros moderadores. '
            'Los resultados aprobados aparecen en el mapa y en la API de lugares.'),
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.icon, this.color, this.value, this.label);
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, color: color),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: HtColors.muted, fontSize: 12)),
      ]);
}

/// Pantalla 21: Solicitar misión (recopilación o verificación de ubicaciones en una zona).
/// La solicitud pasa por la aprobación del equipo, que define recompensa y presupuesto antes de publicarla.
class MissionRequestScreen extends StatefulWidget {
  const MissionRequestScreen({super.key, required this.orgId});
  final String orgId;

  @override
  State<MissionRequestScreen> createState() => _MissionRequestScreenState();
}

class _MissionRequestScreenState extends State<MissionRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _target = TextEditingController(text: '20');
  final _budget = TextEditingController(text: '10.00');
  String _type = 'COLLECT';
  String? _category;
  String? _commune;
  DateTime? _until;
  LatLng _center = portAuPrince;
  double _radius = 800;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await CompanyRepo().requestMission({
        'org_id': widget.orgId,
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'commune': _commune,
        'request_type': _type,
        'category': _category,
        'desired_end': _until == null ? null : DateFormat('yyyy-MM-dd').format(_until!),
        'center': 'SRID=4326;POINT(${_center.longitude} ${_center.latitude})',
        'radius_m': _radius.round(),
        'target_places': int.parse(_target.text),
        'proposed_budget_usd': _budget.text.trim(),
      });
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const _RequestSent()));
    } on PostgrestException catch (e) {
      if (mounted) snack(context, e.message);
    } catch (_) {
      if (mounted) snack(context, 'No se pudo enviar. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtScaffold(
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            const ScreenTitle('Solicitar misión', icon: Icons.add_location_alt_outlined, subtitle: 'Encarga la recopilación o verificación de ubicaciones.'),
            const FieldLabel('Tipo de misión', required: true),
            for (final e in _typeEs.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HtCard(
                  padding: EdgeInsets.zero,
                  borderColor: _type == e.key ? HtColors.blue : null,
                  child: ListTile(
                    onTap: () => setState(() => _type = e.key),
                    leading: Icon(_type == e.key ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: _type == e.key ? HtColors.blue : HtColors.muted),
                    title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(e.key == 'COLLECT'
                        ? 'Registrar negocios o puntos que aún no están en el mapa.'
                        : 'Confirmar que lugares ya registrados siguen ahí.'),
                  ),
                ),
              ),
            const FieldLabel('Objetivo', required: true),
            TextFormField(
              controller: _title,
              decoration: InputDecoration(hintText: trn('Ej.: Registrar farmacias de Delmas')),
              validator: (v) => (v ?? '').trim().length < 4 ? tr('Obligatorio') : null,
            ),
            const FieldLabel('Categoría de lugares'),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              hint: const Text('Cualquier categoría'),
              items: [for (final c in placeCategories) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _category = v),
            ),
            const FieldLabel('Comuna'),
            DropdownButtonFormField<String>(
              initialValue: _commune,
              isExpanded: true,
              hint: const Text('Elige la comuna'),
              items: [for (final c in haitiCommunes) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _commune = v),
            ),
            const FieldLabel('Zona GPS', required: true),
            const Text('Toca el mapa para marcar el centro y ajusta el radio.', style: TextStyle(color: HtColors.muted)),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: FlutterMap(
                  options: MapOptions(initialCenter: _center, initialZoom: 13, onTap: (_, p) => setState(() => _center = p)),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.nexovax.haititracking'),
                    CircleLayer(circles: [
                      CircleMarker(point: _center, radius: _radius, useRadiusInMeter: true, color: HtColors.blue.withValues(alpha: .15), borderColor: HtColors.blue, borderStrokeWidth: 1.5),
                    ]),
                    MarkerLayer(markers: [Marker(point: _center, width: 40, height: 40, alignment: Alignment.topCenter, child: const Icon(Icons.location_on, color: HtColors.red, size: 40))]),
                  ],
                ),
              ),
            ),
            Row(children: [
              const Icon(Icons.radar, color: HtColors.blue),
              Expanded(child: Slider(value: _radius, min: 100, max: 5000, divisions: 49, onChanged: (v) => setState(() => _radius = v))),
              Text('${_radius.round()} m', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const FieldLabel('Lugares', required: true),
                  TextFormField(
                    controller: _target,
                    keyboardType: TextInputType.number,
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? tr('Mínimo 1') : null,
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const FieldLabel('Presupuesto USD', required: true),
                  TextFormField(
                    controller: _budget,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(prefixText: trn('\$ ')),
                    validator: (v) => RegExp(r'^\d+(\.\d{1,2})?$').hasMatch((v ?? '').trim()) ? null : tr('Ej.: 10.00'),
                  ),
                ]),
              ),
            ]),
            const FieldLabel('Fecha deseada de entrega'),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: _until ?? now.add(const Duration(days: 14)));
                if (d != null) setState(() => _until = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.event_outlined)),
                child: Text(_until == null ? 'Opcional' : fechaCorta(_until!), style: TextStyle(color: _until == null ? HtColors.muted : HtColors.text)),
              ),
            ),
            const FieldLabel('Requisitos y detalles'),
            TextFormField(controller: _desc, maxLines: 3, decoration: InputDecoration(hintText: trn('Ej.: foto del letrero, horario de atención…'))),
            const SizedBox(height: 14),
            const InfoBanner('El equipo revisará la zona, el precio y la seguridad antes de publicarla. '
                'Te confirmaremos la recompensa por lugar y el presupuesto final.'),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: const Text('Enviar solicitud'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestSent extends StatelessWidget {
  const _RequestSent();

  @override
  Widget build(BuildContext context) {
    return HtScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        children: [
          const Center(child: SuccessMark()),
          const SizedBox(height: 12),
          const Text('¡Solicitud enviada!', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Nuestro equipo revisará tu misión. Cuando se apruebe, aparecerá en el mapa de los colaboradores '
              'y podrás seguir su progreso aquí.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: HtColors.muted, height: 1.4)),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.track_changes), label: const Text('Ver seguimiento')),
        ],
      ),
    );
  }
}
