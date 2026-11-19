import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/profile_context.dart';
import '../../core/theme.dart';

final _db = Supabase.instance.client;
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Experiencia Desarrollador (D-01 a D-06 del MVP).
class DeveloperShell extends StatefulWidget {
  const DeveloperShell({super.key});

  @override
  State<DeveloperShell> createState() => _DeveloperShellState();
}

class _DeveloperShellState extends State<DeveloperShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final titles = ['Mis proyectos API', 'Documentación', 'Perfil'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_tab])),
      body: switch (_tab) {
        0 => const _Projects(),
        1 => const _Docs(),
        _ => const ProfileActions(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.apps_outlined), label: 'Proyectos'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Docs'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _Projects extends StatefulWidget {
  const _Projects();

  @override
  State<_Projects> createState() => _ProjectsState();
}

class _ProjectsState extends State<_Projects> {
  late Future<List<Map<String, dynamic>>> _list = _load();

  Future<List<Map<String, dynamic>>> _load() async =>
      List<Map<String, dynamic>>.from(await _db.from('api_projects').select().eq('owner_id', _db.auth.currentUser!.id).order('created_at'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _NewProject()));
          if (ok == true) setState(() => _list = _load());
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo proyecto'),
      ),
      body: FutureBuilder(
        future: _list,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Crea un proyecto para obtener una clave y consultar lugares de Haití desde tu sistema.', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final p in list)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.api, color: HtColors.blue),
                    title: Text(p['name'] as String),
                    subtitle: Text('${p['environment'] == 'test' ? 'Pruebas' : 'Producción'} · cuota ${p['daily_quota']}/día · ${p['status']}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ProjectDetail(project: p))),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NewProject extends StatefulWidget {
  const _NewProject();

  @override
  State<_NewProject> createState() => _NewProjectState();
}

class _NewProjectState extends State<_NewProject> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _use = TextEditingController();
  bool _terms = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_terms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debes aceptar los términos de la API.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await _db.rpc('create_api_project', params: {'p_name': _name.text, 'p_intended_use': _use.text, 'p_accept_terms': true});
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo proyecto API')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre de la aplicación *'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Obligatorio' : null),
            const SizedBox(height: 10),
            TextFormField(controller: _use, decoration: const InputDecoration(labelText: 'Uso previsto *', hintText: 'Ej.: buscar comercios cercanos en mi app de entregas'),
                maxLines: 2, validator: (v) => (v ?? '').trim().length < 5 ? 'Describe el uso' : null),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _terms,
              onChanged: (v) => setState(() => _terms = v ?? false),
              title: const Text('Acepto los términos de la API'),
              subtitle: const Text('Solo se entregan datos públicos. Guardaré mi clave en mi servidor, nunca dentro de una app distribuida.'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: const Text('Crear proyecto')),
          ],
        ),
      ),
    );
  }
}

class _ProjectDetail extends StatefulWidget {
  const _ProjectDetail({required this.project});
  final Map<String, dynamic> project;

  @override
  State<_ProjectDetail> createState() => _ProjectDetailState();
}

class _ProjectDetailState extends State<_ProjectDetail> {
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _data = _load();
  final _testKey = TextEditingController();
  String? _testResult;

  String get _id => widget.project['id'] as String;

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async {
    final keys = await _db.from('developer_api_keys').select('id, prefix, created_at, revoked_at, last_used_at').eq('project_id', _id).order('created_at');
    final usage = await _db.from('api_usage').select().eq('project_id', _id).order('day', ascending: false).limit(7);
    return (List<Map<String, dynamic>>.from(keys), List<Map<String, dynamic>>.from(usage));
  }

  Future<void> _newKey() async {
    try {
      final secret = await _db.rpc('create_api_key', params: {'p_project': _id}) as String;
      if (!mounted) return;
      _testKey.text = secret;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Tu nueva clave'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Cópiala ahora: no volverá a mostrarse. Guárdala solo en tu servidor.', style: TextStyle(color: HtColors.red)),
            const SizedBox(height: 10),
            SelectableText(secret, style: const TextStyle(fontFamily: 'monospace')),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: secret));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clave copiada')));
              },
              child: const Text('Copiar'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ya la guardé')),
          ],
        ),
      );
      setState(() => _data = _load());
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _revoke(Map<String, dynamic> k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revocar clave'),
        content: Text('La clave ${k['prefix']}… dejará de funcionar de inmediato. No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revocar')),
        ],
      ),
    );
    if (ok != true) return;
    await _db.rpc('revoke_api_key', params: {'p_key': k['id']});
    setState(() => _data = _load());
  }

  Future<void> _test() async {
    setState(() => _testResult = 'Consultando…');
    try {
      final rows = await _db.rpc('api_places_nearby', params: {'p_api_key': _testKey.text.trim(), 'p_lat': 18.5392, 'p_lng': -72.335, 'p_radius_m': 5000, 'p_limit': 5});
      setState(() => _testResult = const JsonEncoder.withIndent('  ').convert(rows));
      setState(() => _data = _load());
    } on PostgrestException catch (e) {
      setState(() => _testResult = 'Error: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: Text(widget.project['name'] as String)),
      body: FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (keys, usage) = snap.data!;
          final today = usage.isEmpty ? 0 : (usage.first['day'] == DateFormat('yyyy-MM-dd').format(DateTime.now()) ? usage.first['requests'] as int : 0);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  title: const Text('Consumo de hoy'),
                  subtitle: LinearProgressIndicator(value: (today / (widget.project['daily_quota'] as int)).clamp(0.0, 1.0)),
                  trailing: Text('$today / ${widget.project['daily_quota']}'),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: Text('Claves', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                TextButton.icon(onPressed: _newKey, icon: const Icon(Icons.vpn_key_outlined), label: const Text('Nueva clave')),
              ]),
              if (keys.isEmpty) const Text('Sin claves todavía.'),
              for (final k in keys)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.key, color: k['revoked_at'] == null ? HtColors.green : Colors.grey),
                    title: Text('${k['prefix']}_••••••', style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text(k['revoked_at'] != null
                        ? 'Revocada'
                        : 'Creada ${fmt.format(DateTime.parse(k['created_at'] as String).toLocal())}'
                            '${k['last_used_at'] != null ? '\nÚltimo uso ${fmt.format(DateTime.parse(k['last_used_at'] as String).toLocal())}' : ''}'),
                    trailing: k['revoked_at'] == null ? TextButton(onPressed: () => _revoke(k), child: const Text('Revocar')) : null,
                  ),
                ),
              const SizedBox(height: 12),
              const Text('Últimos días', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (usage.isEmpty) const Text('Sin consumo todavía.'),
              for (final u in usage) ListTile(dense: true, title: Text(u['day'] as String), trailing: Text('${u['requests']} solicitudes')),
              const Divider(),
              const Text('Probar la API', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(controller: _testKey, decoration: const InputDecoration(labelText: 'Pega tu clave secreta'), obscureText: true),
              const SizedBox(height: 8),
              FilledButton.tonal(onPressed: _test, child: const Text('Buscar lugares cerca de Port-au-Prince')),
              if (_testResult != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF101828), borderRadius: BorderRadius.circular(10)),
                  child: SelectableText(_testResult!, style: const TextStyle(color: Color(0xFFB6F5C9), fontFamily: 'monospace', fontSize: 12)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Docs extends StatelessWidget {
  const _Docs();

  @override
  Widget build(BuildContext context) {
    const code = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFB6F5C9));
    Widget block(String s) => Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF101828), borderRadius: BorderRadius.circular(10)),
          child: SelectableText(s, style: code),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Lugares cercanos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text('Devuelve lugares públicos aprobados alrededor de un punto (máx. 10 km y 200 resultados).'),
        block('POST $_supabaseUrl/rest/v1/rpc/api_places_nearby\n'
            'apikey: <clave publicable de Haiti Tracking>\n'
            'Content-Type: application/json\n\n'
            '{\n  "p_api_key": "htk_…",\n  "p_lat": 18.5392,\n  "p_lng": -72.3350,\n  "p_radius_m": 1000,\n  "p_limit": 50\n}'),
        const Text('Respuesta', style: TextStyle(fontWeight: FontWeight.bold)),
        block('[\n  {\n    "code": "HT-NXV-000001",\n    "name": "Pharmacie …",\n    "category": "Farmacia",\n    "commune": "Delmas",\n    "lat": 18.5466,\n    "lng": -72.3035,\n    "distance_m": 132.4\n  }\n]'),
        const Text('Reglas', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('• Guarda la clave secreta en tu servidor; nunca la incluyas en una app móvil o web pública.\n'
            '• Cuota diaria por proyecto: al superarla, la API responde con error hasta el día siguiente.\n'
            '• Solo se devuelven lugares públicos: nunca viviendas ni datos personales.\n'
            '• Si una clave se expone, revócala y crea otra desde esta app.'),
      ],
    );
  }
}
