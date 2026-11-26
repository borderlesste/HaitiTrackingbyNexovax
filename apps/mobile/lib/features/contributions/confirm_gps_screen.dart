import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../missions/mission.dart';
import 'gps.dart';

/// Revisa en el mapa el punto GPS capturado antes de enviarlo. Devuelve la posición confirmada.
class ConfirmGpsScreen extends StatefulWidget {
  const ConfirmGpsScreen({super.key, required this.mission, this.initial});
  final Mission mission;
  final Position? initial;

  @override
  State<ConfirmGpsScreen> createState() => _ConfirmGpsScreenState();
}

class _ConfirmGpsScreenState extends State<ConfirmGpsScreen> {
  final _map = MapController();
  Position? _pos;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pos = widget.initial;
    if (_pos == null) _capture();
  }

  Future<void> _capture() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await captureBestPosition();
      if (!mounted) return;
      setState(() => _pos = p);
      _map.move(GpsCheck(widget.mission, p).point, 17);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final check = _pos == null ? null : GpsCheck(m, _pos!);
    return HtScaffold(
      background: Colors.white,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const ScreenTitle('Confirmar punto GPS',
              icon: Icons.my_location, subtitle: 'Revisa que el punto esté justo en la entrada del establecimiento.'),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 300,
              child: Stack(children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(initialCenter: check?.point ?? m.point, initialZoom: check == null ? 15 : 17),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.nexovax.haititracking',
                    ),
                    CircleLayer(circles: [
                      if (m.requiresOnSite && m.radiusM != null)
                        CircleMarker(
                          point: m.point,
                          radius: m.radiusM!.toDouble(),
                          useRadiusInMeter: true,
                          color: HtColors.blue.withValues(alpha: .08),
                          borderColor: HtColors.blue.withValues(alpha: .6),
                          borderStrokeWidth: 2,
                        ),
                      if (check != null)
                        CircleMarker(
                          point: check.point,
                          radius: _pos!.accuracy,
                          useRadiusInMeter: true,
                          color: (check.ok ? HtColors.green : HtColors.red).withValues(alpha: .18),
                          borderColor: check.ok ? HtColors.green : HtColors.red,
                          borderStrokeWidth: 1.5,
                        ),
                    ]),
                    if (check != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: check.point,
                          width: 46,
                          height: 46,
                          alignment: Alignment.topCenter,
                          child: const Icon(Icons.location_on, color: HtColors.red, size: 46),
                        ),
                      ]),
                    const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
                  ],
                ),
                if (_busy)
                  Container(
                    color: Colors.white.withValues(alpha: .6),
                    alignment: Alignment.center,
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text('Buscando tu ubicación…', style: TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          const Wrap(spacing: 14, runSpacing: 4, children: [
            _Legend(color: HtColors.red, text: 'Tu punto y su margen de error'),
            _Legend(color: HtColors.blue, text: 'Área de la misión'),
          ]),
          const SizedBox(height: 14),
          if (_error != null) ...[
            InfoBanner(_error!, warning: true),
            const SizedBox(height: 12),
          ],
          if (check != null)
            HtCard(
              child: Column(children: [
                KvRow('Latitud', _pos!.latitude.toStringAsFixed(6), icon: Icons.explore_outlined),
                KvRow('Longitud', _pos!.longitude.toStringAsFixed(6), icon: Icons.explore_outlined),
                KvRow('Precisión', '± ${_pos!.accuracy.round()} m',
                    icon: Icons.gps_fixed, valueColor: check.accuracyOk ? HtColors.green : HtColors.red, bold: true),
                if (m.requiresOnSite)
                  KvRow('Distancia al centro', '${check.distanceToCenter.round()} m', icon: Icons.straighten),
                const Divider(height: 22),
                _Check(check.accuracyOk, 'Precisión de ${maxAccuracyM.round()} m o mejor'),
                _Check(check.insideArea, m.requiresOnSite ? 'Dentro del área de la misión' : 'Misión sin presencia física'),
                _Check(check.notMocked, 'Ubicación real del teléfono (sin apps de ubicación falsa)'),
              ]),
            ),
          const SizedBox(height: 12),
          if (check != null && !check.ok)
            const InfoBanner(
              'Sal al aire libre, acércate a la entrada del lugar y vuelve a capturar. '
              'Con edificios altos o techos la precisión empeora.',
              warning: true,
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: check != null && check.ok && !_busy ? () => Navigator.pop(context, _pos) : null,
            icon: const Icon(Icons.check),
            label: const Text('Confirmar ubicación'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _capture,
            icon: const Icon(Icons.refresh),
            label: const Text('Capturar de nuevo'),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color.withValues(alpha: .35), shape: BoxShape.circle, border: Border.all(color: color))),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: HtColors.muted)),
      ]);
}

class _Check extends StatelessWidget {
  const _Check(this.ok, this.text);
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? HtColors.green : HtColors.red, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
