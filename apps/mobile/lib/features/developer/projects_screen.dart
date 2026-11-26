import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'api_test_screen.dart';
import 'credentials_screen.dart';
import 'developer_repo.dart';
import 'stats_screen.dart';

/// Pantalla 27: Mis proyectos (crear y administrar integraciones).
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _repo = DeveloperRepo();
  late Future<(List<Map<String, dynamic>>, Map<String, int>)> _data = _load();

  Future<(List<Map<String, dynamic>>, Map<String, int>)> _load() async {
    final projects = await _repo.projects();
    final usage = await _repo.usage([for (final p in projects) p['id'] as String], days: 1);
    return (projects, {for (final u in usage) if (u['day'] == today()) u['project_id'] as String: (u['requests'] as num).toInt()});
  }

  Future<void> _new() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ProjectFormScreen()));
    if (ok == true && mounted) setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(icon: Icons.cloud_off, title: 'No se pudo cargar', text: 'Revisa tu conexión.',
              action: OutlinedButton(onPressed: () => setState(() => _data = _load()), child: const Text('Reintentar')));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (projects, todayUse) = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => setState(() => _data = _load()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
            children: [
              const ScreenTitle('Mis proyectos', icon: Icons.folder_outlined, subtitle: 'Cada integración tiene sus claves y su cuota.'),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: projects.length >= 5 ? null : _new,
                icon: const Icon(Icons.add),
                label: Text(projects.length >= 5 ? 'Máximo 5 proyectos' : 'Nuevo proyecto'),
              ),
              const SizedBox(height: 14),
              if (projects.isEmpty)
                const EmptyState(icon: Icons.api, title: 'Sin proyectos', text: 'Crea un proyecto para obtener una clave y consultar lugares de Haití desde tu sistema.'),
              for (final p in projects) ...[
                HtCard(
                  padding: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)));
                      if (mounted) setState(() => _data = _load());
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const IconTile(Icons.api, size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(p['environment'] == 'production' ? 'Producción' : 'Pruebas', style: const TextStyle(color: HtColors.muted)),
                            ]),
                          ),
                          reviewChip(p['status'] as String?),
                        ]),
                        const SizedBox(height: 12),
                        ProgressLine(value: todayUse[p['id']] ?? 0, total: (p['daily_quota'] as num).toInt(), label: 'Consultas hoy'),
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

/// Crear o editar un proyecto.
class ProjectFormScreen extends StatefulWidget {
  const ProjectFormScreen({super.key, this.project});
  final Map<String, dynamic>? project;

  @override
  State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.project?['name'] as String?);
  late final _use = TextEditingController(text: widget.project?['intended_use'] as String?);
  String _env = 'test';
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = DeveloperRepo();
      if (widget.project == null) {
        await repo.createProject(_name.text.trim(), _use.text.trim(), _env);
      } else {
        await repo.updateProject(widget.project!['id'] as String, _name.text.trim(), _use.text.trim());
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.project != null;
    return HtScaffold(
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            ScreenTitle(editing ? 'Editar proyecto' : 'Nuevo proyecto', icon: Icons.create_new_folder_outlined),
            const FieldLabel('Nombre de la aplicación', required: true),
            TextFormField(controller: _name, validator: (v) => (v ?? '').trim().length < 2 ? 'Obligatorio' : null),
            const FieldLabel('Uso previsto', required: true),
            TextFormField(
              controller: _use,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Ej.: buscar comercios cercanos en mi app de entregas'),
              validator: (v) => (v ?? '').trim().length < 5 ? 'Describe el uso' : null,
            ),
            if (!editing) ...[
              const FieldLabel('Entorno', required: true),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'test', label: Text('Pruebas'), icon: Icon(Icons.science_outlined)),
                  ButtonSegment(value: 'production', label: Text('Producción'), icon: Icon(Icons.rocket_launch_outlined)),
                ],
                selected: {_env},
                onSelectionChanged: (s) => setState(() => _env = s.first),
              ),
              const SizedBox(height: 12),
              const InfoBanner('Al crear el proyecto aceptas las condiciones de uso de la API. Cuota inicial: 1.000 consultas al día.'),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _submit, child: Text(editing ? 'Guardar' : 'Crear proyecto')),
          ],
        ),
      ),
    );
  }
}

/// Detalle de un proyecto: datos, consumo y accesos a claves, pruebas y estadísticas.
class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.project});
  final Map<String, dynamic> project;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late Map<String, dynamic> _p = widget.project;
  late Future<int> _today = _loadToday();

  Future<int> _loadToday() async {
    final u = await DeveloperRepo().usage([_p['id'] as String], days: 1);
    return u.where((r) => r['day'] == today()).fold<int>(0, (a, r) => a + (r['requests'] as num).toInt());
  }

  Future<void> _edit() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ProjectFormScreen(project: _p)));
    if (ok == true) {
      final list = await DeveloperRepo().projects();
      final fresh = list.where((x) => x['id'] == _p['id']).firstOrNull;
      if (fresh != null && mounted) setState(() => _p = fresh);
    }
  }

  void _open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final id = _p['id'] as String;
    return PanelPage(
      title: _p['name'] as String,
      icon: Icons.api,
      subtitle: _p['intended_use'] as String?,
      onRefresh: () async => setState(() => _today = _loadToday()),
      children: [
        HtCard(
          child: Column(children: [
            KvRow('Estado', '', icon: Icons.info_outline, trailing: reviewChip(_p['status'] as String?)),
            KvRow('Entorno', _p['environment'] == 'production' ? 'Producción' : 'Pruebas', icon: Icons.layers_outlined),
            KvRow('Cuota diaria', '${_p['daily_quota']} consultas', icon: Icons.speed),
            KvRow('Creado', fechaCorta(DateTime.parse(_p['created_at'] as String)), icon: Icons.calendar_today_outlined),
            KvRow('ID del proyecto', '${id.substring(0, 8)}…', icon: Icons.tag),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _edit, icon: const Icon(Icons.edit_outlined), label: const Text('Editar proyecto')),
          ]),
        ),
        const SizedBox(height: 14),
        HtCard(
          child: FutureBuilder<int>(
            future: _today,
            builder: (context, s) => ProgressLine(value: s.data ?? 0, total: (_p['daily_quota'] as num).toInt(), label: 'Consultas hoy'),
          ),
        ),
        const SizedBox(height: 14),
        HtCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SettingRow(icon: Icons.vpn_key_outlined, color: HtColors.blue, title: 'Credenciales', subtitle: 'Generar, rotar y revocar claves',
                onTap: () => _open(CredentialsScreen(projectId: id))),
            SettingRow(icon: Icons.play_circle_outline, color: HtColors.blue, title: 'Probar API', subtitle: 'Consulta de prueba con respuesta JSON',
                onTap: () => _open(ApiTestScreen(projectId: id))),
            SettingRow(icon: Icons.bar_chart, color: HtColors.blue, title: 'Estadísticas', subtitle: 'Uso, errores y consumo',
                onTap: () => _open(StatsScreen(projectId: id)), last: true),
          ]),
        ),
        if (_p['status'] != 'ACTIVE') ...[
          const SizedBox(height: 14),
          const InfoBanner('Este proyecto está suspendido. Escribe a soporte para revisarlo.', warning: true),
        ],
      ],
    );
  }
}
