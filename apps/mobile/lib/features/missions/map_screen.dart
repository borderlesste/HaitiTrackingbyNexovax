import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/guest.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/new_contribution_screen.dart';
import '../home/home_shell.dart';
import '../rewards/rewards_screen.dart';
import 'mission.dart';
import 'mission_detail_screen.dart';

enum _Filter { all, nearby, priority }

/// Inicio del colaborador: saludo, saldo, buscador, filtros y mapa de misiones con su recompensa.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.missions, required this.onRefresh});

  final List<Mission> missions;
  final Future<void> Function() onRefresh;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  Mission? _selected;
  _Filter _filter = _Filter.all;
  LatLng? _me;
  int? _balanceCents;

  @override
  void initState() {
    super.initState();
    _selected = widget.missions.isEmpty ? null : widget.missions.first;
    if (Guest.isGuest) return;
    loadWithdrawableCents().then((c) {
      if (mounted) setState(() => _balanceCents = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Mission> get _visible {
    final q = _search.text.trim().toLowerCase();
    return widget.missions.where((m) {
      if (q.isNotEmpty && !'${m.title} ${m.commune ?? ''} ${m.description}'.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.priority => m.isPriority || m.hasBonus,
        _Filter.nearby => _me == null || const Distance().as(LengthUnit.Meter, _me!, m.point) <= 5000,
      };
    }).toList();
  }

  Future<void> _locate({bool thenFilter = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw 'Activa la ubicación (GPS) del teléfono.';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Permite el acceso a tu ubicación para ver misiones cercanas.';
      }
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      final me = LatLng(p.latitude, p.longitude);
      setState(() {
        _me = me;
        if (thenFilter) _filter = _Filter.nearby;
      });
      _map.move(me, 14);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e is String ? e : 'No se pudo obtener tu ubicación.')));
    }
  }

  /// Aporte libre: un lugar que falta en el mapa, fuera de cualquier misión y sin recompensa.
  Future<void> _addPlace(BuildContext context) async {
    if (!requireAccount(context, reason: 'Crea una cuenta para agregar lugares que faltan en el mapa.')) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final mission = await MissionsRepository().openContribution();
      if (mission == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Agregar lugares no está disponible por ahora.')));
        return;
      }
      await navigator.push(MaterialPageRoute(builder: (_) => NewContributionScreen(mission: mission)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir el formulario. Revisa tu conexión.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final user = Supabase.instance.client.auth.currentUser;
    final first = ((user?.userMetadata?['first_name'] ?? user?.userMetadata?['full_name'] ?? '') as String).split(' ').first;
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(children: [
            Row(children: [
              const CircleAvatar(radius: 24, backgroundColor: HtColors.blue, child: Icon(Icons.person, color: Colors.white, size: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Guest.isGuest ? 'Hola, bienvenido' : 'Hola, ${first.isEmpty ? 'Colaborador' : first}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: HtColors.text)),
                  const Text('Misiones disponibles en tu zona', style: TextStyle(fontSize: 13, color: HtColors.muted)),
                ]),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => HomeShell.tab.value = HomeTab.rewards,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: HtColors.blueSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: HtColors.blue.withValues(alpha: .2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.savings_outlined, color: HtColors.navy),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Mi saldo', style: TextStyle(fontSize: 12, color: HtColors.muted)),
                      Text(_balanceCents == null ? '—' : usd(_balanceCents!),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: HtColors.text)),
                    ]),
                    const Icon(Icons.chevron_right, color: HtColors.navy),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: trn('Buscar misiones o lugares'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: HtColors.border)),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _FilterChip('Todas', null, _filter == _Filter.all, () => setState(() => _filter = _Filter.all)),
                    _FilterChip('Cercanas', Icons.location_on_outlined, _filter == _Filter.nearby, () {
                      if (_me == null) {
                        _locate(thenFilter: true);
                      } else {
                        setState(() => _filter = _Filter.nearby);
                      }
                    }),
                    _FilterChip('Prioritarias', Icons.star, _filter == _Filter.priority,
                        () => setState(() => _filter = _Filter.priority),
                        iconColor: HtColors.red),
                  ]),
                ),
              ),
              IconButton.outlined(
                onPressed: _locate,
                icon: const Icon(Icons.my_location, color: HtColors.blue),
                tooltip: trn('Mi ubicación'),
              ),
            ]),
          ]),
        ),
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
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
                if (_me != null)
                  CircleLayer(circles: [
                    CircleMarker(point: _me!, radius: 40, color: HtColors.blue.withValues(alpha: .15), borderStrokeWidth: 0),
                    CircleMarker(point: _me!, radius: 7, color: HtColors.blue, borderColor: Colors.white, borderStrokeWidth: 2),
                  ]),
                MarkerLayer(markers: [
                  for (final m in visible)
                    Marker(
                      point: m.point,
                      width: 84,
                      height: 78,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => setState(() => _selected = m),
                        child: RewardPin(mission: m, selected: _selected?.id == m.id),
                      ),
                    ),
                ]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
              ],
            ),
            Positioned(
              top: 12,
              right: 12,
              child: FloatingActionButton.extended(
                heroTag: 'add-place',
                onPressed: () => _addPlace(context),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Agregar un lugar'),
              ),
            ),
            if (visible.isEmpty)
              const Positioned(
                top: 76,
                left: 16,
                right: 16,
                child: InfoBanner('No hay misiones con este filtro. Prueba con "Todas".'),
              ),
            if (_selected != null && visible.contains(_selected))
              Positioned(left: 10, right: 10, bottom: 10, child: MissionPreviewCard(mission: _selected!)),
          ]),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(this.label, this.icon, this.selected, this.onTap, {this.iconColor});
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? HtColors.blue : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? HtColors.blue : HtColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: selected ? Colors.white : (iconColor ?? HtColors.blue)),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : HtColors.text, fontWeight: FontWeight.w600, fontSize: 15)),
          ]),
        ),
      ),
    );
  }
}

/// Pin del mapa con la recompensa: rojo para prioritarias o con bono, azul para el resto.
class RewardPin extends StatelessWidget {
  const RewardPin({super.key, required this.mission, this.selected = false});
  final Mission mission;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = mission.isPriority || mission.hasBonus ? HtColors.red : HtColors.navy;
    return Transform.scale(
      scale: selected ? 1.12 : 1,
      alignment: Alignment.bottomCenter,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26, offset: Offset(0, 2))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('\$${mission.rewardUsd}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            const Icon(Icons.assignment_outlined, color: Colors.white, size: 16),
          ]),
        ),
        Transform.translate(
          offset: const Offset(0, -6),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                border: const Border(
                  right: BorderSide(color: Colors.white, width: 2.5),
                  bottom: BorderSide(color: Colors.white, width: 2.5),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Tarjeta inferior con la misión seleccionada.
class MissionPreviewCard extends StatelessWidget {
  const MissionPreviewCard({super.key, required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
                width: 40, height: 4, decoration: BoxDecoration(color: HtColors.border, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(missionIcon(mission), size: 58),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(mission.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: HtColors.text, height: 1.15)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: HtColors.muted),
                  const SizedBox(width: 2),
                  Flexible(child: Text('${mission.commune ?? ''}, Haití', style: const TextStyle(color: HtColors.muted))),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: HtColors.blueSoft, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                const Text('Recompensa', style: TextStyle(fontSize: 12, color: HtColors.navy)),
                Text('\$${mission.rewardUsd} USD',
                    style: const TextStyle(color: HtColors.red, fontWeight: FontWeight.w800, fontSize: 17)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.checklist, size: 20, color: HtColors.navy),
            const SizedBox(width: 8),
            const Text('Requisitos: ', style: TextStyle(fontWeight: FontWeight.w700)),
            Expanded(child: Text(mission.requirements, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          const Text('La recompensa se acredita solo cuando tu aporte sea revisado y aprobado.',
              style: TextStyle(fontSize: 12, color: HtColors.muted)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => MissionDetailScreen(mission: mission))),
            child: const Row(children: [
              Icon(Icons.play_circle_fill),
              Expanded(child: Text('Ver misión', textAlign: TextAlign.center)),
              Icon(Icons.chevron_right),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Icono según el tipo de misión.
IconData missionIcon(Mission m) => switch (m.type) {
      'PRIORITY_PLACE' => Icons.star,
      'MAJOR_CORRECTION' => Icons.edit_location_alt,
      'INDEPENDENT_CHECK' => Icons.fact_check,
      _ => Icons.storefront,
    };
