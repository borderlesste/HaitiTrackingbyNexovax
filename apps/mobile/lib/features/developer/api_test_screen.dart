import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'developer_repo.dart';

/// Pantalla 30: Probar API. La consulta se hace con tu sesión y el proyecto elegido:
/// no hace falta escribir la clave secreta en el teléfono. Cuenta en la cuota del proyecto.
class ApiTestScreen extends StatefulWidget {
  const ApiTestScreen({super.key, this.projectId, this.embedded = false});
  final String? projectId;
  final bool embedded;

  @override
  State<ApiTestScreen> createState() => _ApiTestScreenState();
}

class _ApiTestScreenState extends State<ApiTestScreen> {
  final _repo = DeveloperRepo();
  final _lat = TextEditingController(text: '18.5392');
  final _lng = TextEditingController(text: '-72.3350');
  double _radius = 2000;
  int _limit = 10;
  List<Map<String, dynamic>> _projects = const [];
  String? _project;
  bool _loading = true;
  bool _running = false;
  String? _result;
  int? _status;
  int? _ms;

  @override
  void initState() {
    super.initState();
    _repo.projects().then((p) {
      if (!mounted) return;
      setState(() {
        _projects = p;
        _project = widget.projectId ?? p.where((x) => x['status'] == 'ACTIVE').firstOrNull?['id'] as String?;
        _loading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _run() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (_project == null) return snack(context, 'Elige un proyecto.');
    if (lat == null || lng == null) return snack(context, 'Latitud y longitud no válidas.');
    setState(() {
      _running = true;
      _result = null;
    });
    final sw = Stopwatch()..start();
    try {
      final rows = await _repo.testNearby(_project!, lat, lng, _radius, _limit);
      setState(() {
        _status = 200;
        _result = const JsonEncoder.withIndent('  ').convert(rows);
      });
    } on PostgrestException catch (e) {
      setState(() {
        _status = 400;
        _result = const JsonEncoder.withIndent('  ').convert({'code': e.code, 'message': e.message});
      });
    } catch (_) {
      setState(() {
        _status = 0;
        _result = '{\n  "message": "Sin conexión"\n}';
      });
    } finally {
      sw.stop();
      if (mounted) {
        setState(() {
          _running = false;
          _ms = sw.elapsedMilliseconds;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (_projects.isEmpty)
        const EmptyState(icon: Icons.api, title: 'Sin proyectos', text: 'Crea un proyecto para probar la API.')
      else ...[
        HtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Text('POST', style: TextStyle(color: HtColors.green, fontWeight: FontWeight.w800)),
              SizedBox(width: 8),
              Expanded(child: Text('api_places_nearby', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700))),
            ]),
            const FieldLabel('Proyecto', required: true),
            DropdownButtonFormField<String>(
              initialValue: _project,
              isExpanded: true,
              items: [
                for (final p in _projects)
                  DropdownMenuItem(value: p['id'] as String, enabled: p['status'] == 'ACTIVE', child: Text(p['name'] as String)),
              ],
              onChanged: (v) => setState(() => _project = v),
            ),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const FieldLabel('p_lat'),
                  TextField(controller: _lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const FieldLabel('p_lng'),
                  TextField(controller: _lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                ]),
              ),
            ]),
            const FieldLabel('p_radius_m'),
            Row(children: [
              Expanded(child: Slider(value: _radius, min: 100, max: 10000, divisions: 99, onChanged: (v) => setState(() => _radius = v))),
              Text('${_radius.round()} m', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const FieldLabel('p_limit'),
            FilterPills(
              labels: const ['5', '10', '25', '50'],
              selected: [5, 10, 25, 50].indexOf(_limit),
              onSelected: (i) => setState(() => _limit = [5, 10, 25, 50][i]),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow),
              label: const Text('Enviar consulta'),
            ),
          ]),
        ),
        if (_result != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            const Text('Respuesta', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            StatusChip(_status == 200 ? '200 OK' : 'Error', tone: _status == 200 ? ChipTone.ok : ChipTone.bad),
            const Spacer(),
            if (_ms != null) Text('$_ms ms', style: const TextStyle(color: HtColors.muted)),
            IconButton(
              tooltip: 'Copiar',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () => Clipboard.setData(ClipboardData(text: _result!)),
            ),
          ]),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF101828), borderRadius: BorderRadius.circular(12)),
            child: SelectableText(_result!, style: const TextStyle(color: Color(0xFFB6F5C9), fontFamily: 'monospace', fontSize: 12, height: 1.35)),
          ),
        ],
        const SizedBox(height: 14),
        const InfoBanner('Las pruebas usan tu sesión: no escribas tu clave secreta en el teléfono. '
            'Cada prueba cuenta en la cuota diaria del proyecto (máx. 50 resultados).'),
      ],
    ];
    if (widget.embedded) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 28), children: [
        const ScreenTitle('Probar API', icon: Icons.play_circle_outline, subtitle: 'Consultas de prueba con respuesta JSON.'),
        const SizedBox(height: 16),
        ...children,
      ]);
    }
    return PanelPage(title: 'Probar API', icon: Icons.play_circle_outline, subtitle: 'Consultas de prueba con respuesta JSON.', children: children);
  }
}
