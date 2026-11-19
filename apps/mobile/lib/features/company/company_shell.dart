import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../missions/mission.dart';

final _db = Supabase.instance.client;

const _statusEs = {'PENDING': 'En revisión', 'APPROVED': 'Aprobado', 'REJECTED': 'Rechazado'};
Color _statusColor(String s) => s == 'APPROVED' ? HtColors.green : (s == 'REJECTED' ? HtColors.red : Colors.orange);

Widget statusChip(String s) => Chip(
      label: Text(_statusEs[s] ?? s, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: _statusColor(s),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );

/// Experiencia Empresa (E-01 a E-07 del MVP).
class CompanyShell extends StatefulWidget {
  const CompanyShell({super.key});

  @override
  State<CompanyShell> createState() => _CompanyShellState();
}

class _CompanyShellState extends State<CompanyShell> {
  Map<String, dynamic>? _org;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _db.from('organizations').select().order('created_at').limit(1);
      setState(() => _org = rows.isEmpty ? null : rows.first);
    } catch (_) {
      setState(() => _org = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final org = _org;
    if (org == null) return _RegisterCompany(onDone: _load);
    final approved = org['status'] == 'APPROVED';
    final titles = ['Mi empresa', 'Establecimientos', 'Campañas', 'Perfil'];
    final body = switch (_tab) {
      0 => _CompanyHome(org: org, onRefresh: _load),
      1 => approved ? _Establishments(org: org) : const _NeedsVerification(),
      2 => approved ? _Campaigns(org: org) : const _NeedsVerification(),
      _ => const ProfileActions(),
    };
    return Scaffold(
      appBar: AppBar(title: Text(titles[_tab])),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.business_outlined), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Lugares'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), label: 'Campañas'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _NeedsVerification extends StatelessWidget {
  const _NeedsVerification();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Disponible cuando el equipo de Haiti Tracking verifique tu empresa.', textAlign: TextAlign.center),
        ),
      );
}

class _RegisterCompany extends StatefulWidget {
  const _RegisterCompany({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_RegisterCompany> createState() => _RegisterCompanyState();
}

class _RegisterCompanyState extends State<_RegisterCompany> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _rep = TextEditingController();
  final _legal = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _commune = TextEditingController();
  String _sector = 'Comercio';
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _db.rpc('register_organization', params: {
        'p_name': _name.text,
        'p_sector': _sector,
        'p_representative': _rep.text,
        'p_legal_id': _legal.text.isEmpty ? null : _legal.text,
        'p_phone': _phone.text.isEmpty ? null : _phone.text,
        'p_email': _email.text.isEmpty ? null : _email.text,
        'p_address': _address.text.isEmpty ? null : _address.text,
        'p_commune': _commune.text.isEmpty ? null : _commune.text,
      });
      widget.onDone();
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration d(String l) => InputDecoration(labelText: l);
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar empresa'), actions: [
        IconButton(onPressed: () => showProfileSwitcher(context), icon: const Icon(Icons.swap_horiz), tooltip: 'Cambiar perfil'),
      ]),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Registra tu empresa. Nuestro equipo la verificará antes de que puedas reclamar establecimientos o pedir campañas.'),
            const SizedBox(height: 16),
            TextFormField(controller: _name, decoration: d('Nombre de la empresa *'), validator: (v) => (v ?? '').trim().length < 2 ? 'Obligatorio' : null),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _sector,
              decoration: d('Sector'),
              items: const ['Comercio', 'Salud', 'Alimentación', 'Transporte', 'Banca y finanzas', 'Educación', 'Logística', 'Otro']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _sector = v ?? 'Otro'),
            ),
            const SizedBox(height: 10),
            TextFormField(controller: _rep, decoration: d('Representante legal *'), validator: (v) => (v ?? '').trim().length < 3 ? 'Obligatorio' : null),
            const SizedBox(height: 10),
            TextFormField(controller: _legal, decoration: d('Número de registro / NIF')),
            const SizedBox(height: 10),
            TextFormField(controller: _phone, decoration: d('Teléfono'), keyboardType: TextInputType.phone),
            const SizedBox(height: 10),
            TextFormField(controller: _email, decoration: d('Correo de contacto'), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 10),
            TextFormField(controller: _address, decoration: d('Dirección')),
            const SizedBox(height: 10),
            TextFormField(controller: _commune, decoration: d('Comuna')),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _submit, child: const Text('Enviar para verificación')),
          ],
        ),
      ),
    );
  }
}

class _CompanyHome extends StatelessWidget {
  const _CompanyHome({required this.org, required this.onRefresh});
  final Map<String, dynamic> org;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final s = org['status'] as String;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: HtColors.navy, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(org['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text('${org['sector']} · ${org['commune'] ?? ''}', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              statusChip(s),
            ]),
          ),
          const SizedBox(height: 12),
          if (s == 'PENDING')
            const Card(child: ListTile(leading: Icon(Icons.hourglass_top), title: Text('Verificación en curso'), subtitle: Text('Te avisaremos cuando el equipo revise tu empresa. Desliza hacia abajo para actualizar.'))),
          if (s == 'REJECTED')
            Card(child: ListTile(leading: const Icon(Icons.error_outline, color: HtColors.red), title: const Text('Verificación rechazada'), subtitle: Text(org['review_reason'] as String? ?? ''))),
          if (s == 'APPROVED')
            const Card(
              child: ListTile(
                leading: Icon(Icons.verified, color: HtColors.green),
                title: Text('Empresa verificada'),
                subtitle: Text('Ya puedes reclamar tus establecimientos y solicitar campañas de cobertura.'),
              ),
            ),
          Card(
            child: Column(children: [
              ListTile(dense: true, title: const Text('Representante'), trailing: Text(org['representative_name'] as String? ?? '')),
              ListTile(dense: true, title: const Text('Teléfono'), trailing: Text(org['contact_phone'] as String? ?? '—')),
              ListTile(dense: true, title: const Text('Correo'), trailing: Text(org['contact_email'] as String? ?? '—')),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Establishments extends StatefulWidget {
  const _Establishments({required this.org});
  final Map<String, dynamic> org;

  @override
  State<_Establishments> createState() => _EstablishmentsState();
}

class _EstablishmentsState extends State<_Establishments> {
  late Future<List<Map<String, dynamic>>> _claims = _loadClaims();

  Future<List<Map<String, dynamic>>> _loadClaims() async =>
      List<Map<String, dynamic>>.from(await _db.from('place_claims_view').select().eq('org_id', widget.org['id']).order('created_at', ascending: false));

  Future<void> _claim() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _ClaimPlace(orgId: widget.org['id'] as String)));
    if (added == true) setState(() => _claims = _loadClaims());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _claim, icon: const Icon(Icons.add_business), label: const Text('Reclamar')),
      body: FutureBuilder(
        future: _claims,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aún no tienes establecimientos. Busca tu negocio por nombre o código HT-NXV y reclámalo.', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final c in list)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront, color: HtColors.blue),
                    title: Text(c['place_name'] as String),
                    subtitle: Text('${c['place_code']} · ${c['place_category']}'
                        '${c['review_reason'] != null ? '\nMotivo: ${c['review_reason']}' : ''}'),
                    trailing: statusChip(c['status'] as String),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ClaimPlace extends StatefulWidget {
  const _ClaimPlace({required this.orgId});
  final String orgId;

  @override
  State<_ClaimPlace> createState() => _ClaimPlaceState();
}

class _ClaimPlaceState extends State<_ClaimPlace> {
  final _q = TextEditingController();
  final _evidence = TextEditingController();
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;

  Future<void> _search() async {
    // Quita caracteres que alteran el filtro de búsqueda.
    final q = _q.text.trim().replaceAll(RegExp(r'[,()%*]'), ' ');
    if (q.length < 2) return;
    setState(() => _searching = true);
    final rows = await _db.from('places').select('id, code, name, category, commune').or('code.ilike.%$q%,name.ilike.%$q%').limit(30);
    setState(() {
      _results = List<Map<String, dynamic>>.from(rows);
      _searching = false;
    });
  }

  Future<void> _claim(Map<String, dynamic> p) async {
    try {
      await _db.from('place_claims').insert({'org_id': widget.orgId, 'place_id': p['id'], 'evidence': _evidence.text.trim().isEmpty ? null : _evidence.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.code == '23505' ? 'Ya reclamaste este lugar.' : e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reclamar establecimiento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _q,
            decoration: InputDecoration(
              labelText: 'Nombre o código (HT-NXV-…)',
              suffixIcon: IconButton(onPressed: _search, icon: const Icon(Icons.search)),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 10),
          TextField(controller: _evidence, decoration: const InputDecoration(labelText: 'Prueba de titularidad (ej.: patente, cargo)')),
          const SizedBox(height: 12),
          if (_searching) const Center(child: CircularProgressIndicator()),
          if (!_searching && _results.isEmpty && _q.text.isNotEmpty)
            const Text('Sin resultados. Si tu negocio no está en el mapa, solicita una campaña para registrarlo.'),
          for (final p in _results)
            Card(
              child: ListTile(
                title: Text(p['name'] as String),
                subtitle: Text('${p['code']} · ${p['category']} · ${p['commune'] ?? ''}'),
                trailing: FilledButton(onPressed: () => _claim(p), child: const Text('Reclamar')),
              ),
            ),
        ],
      ),
    );
  }
}

class _Campaigns extends StatefulWidget {
  const _Campaigns({required this.org});
  final Map<String, dynamic> org;

  @override
  State<_Campaigns> createState() => _CampaignsState();
}

class _CampaignsState extends State<_Campaigns> {
  late Future<List<Map<String, dynamic>>> _list = _load();

  Future<List<Map<String, dynamic>>> _load() async =>
      List<Map<String, dynamic>>.from(await _db.from('campaign_requests_view').select().eq('org_id', widget.org['id']).order('created_at', ascending: false));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _NewCampaign(orgId: widget.org['id'] as String)));
          if (ok == true) setState(() => _list = _load());
        },
        icon: const Icon(Icons.add),
        label: const Text('Solicitar campaña'),
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
                child: Text('Pide al equipo que registre lugares en una zona: tus clientes los encontrarán en el mapa.', textAlign: TextAlign.center),
              ),
            );
          }
          final fmt = DateFormat('dd/MM/yyyy');
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final c in list)
                Card(
                  child: ListTile(
                    title: Text(c['title'] as String),
                    subtitle: Text([
                      '${c['commune'] ?? ''} · ${c['target_places']} lugares · ${fmt.format(DateTime.parse(c['created_at'] as String).toLocal())}',
                      if (c['mission_code'] != null) 'Misión ${c['mission_code']} · ${c['approved_places']} lugares aprobados',
                      if (c['review_reason'] != null) 'Motivo: ${c['review_reason']}',
                    ].join('\n')),
                    isThreeLine: true,
                    trailing: statusChip(c['status'] as String),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NewCampaign extends StatefulWidget {
  const _NewCampaign({required this.orgId});
  final String orgId;

  @override
  State<_NewCampaign> createState() => _NewCampaignState();
}

class _NewCampaignState extends State<_NewCampaign> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _commune = TextEditingController();
  final _target = TextEditingController(text: '20');
  final _budget = TextEditingController(text: '10.00');
  LatLng _center = portAuPrince;
  double _radius = 800;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _db.from('campaign_requests').insert({
        'org_id': widget.orgId,
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'commune': _commune.text.trim().isEmpty ? null : _commune.text.trim(),
        'center': 'SRID=4326;POINT(${_center.longitude} ${_center.latitude})',
        'radius_m': _radius.round(),
        'target_places': int.parse(_target.text),
        'proposed_budget_usd': _budget.text.trim(),
      });
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
      appBar: AppBar(title: const Text('Solicitar campaña')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Objetivo *', hintText: 'Ej.: Registrar farmacias de Delmas'),
                validator: (v) => (v ?? '').trim().length < 4 ? 'Obligatorio' : null),
            const SizedBox(height: 10),
            TextFormField(controller: _desc, decoration: const InputDecoration(labelText: 'Detalles para el equipo'), maxLines: 2),
            const SizedBox(height: 10),
            TextFormField(controller: _commune, decoration: const InputDecoration(labelText: 'Comuna')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _target,
                  decoration: const InputDecoration(labelText: 'Lugares a registrar'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Mínimo 1' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _budget,
                  decoration: const InputDecoration(labelText: 'Presupuesto propuesto USD'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => RegExp(r'^\d+(\.\d{1,2})?$').hasMatch((v ?? '').trim()) ? null : 'Ej.: 10.00',
                ),
              ),
            ]),
            const SizedBox(height: 12),
            const Text('Toca el mapa para marcar el centro de la zona.'),
            const SizedBox(height: 6),
            SizedBox(
              height: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: FlutterMap(
                  options: MapOptions(initialCenter: _center, initialZoom: 13, onTap: (_, p) => setState(() => _center = p)),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.nexovax.haititracking'),
                    CircleLayer(circles: [
                      CircleMarker(point: _center, radius: _radius, useRadiusInMeter: true, color: HtColors.blue.withValues(alpha: .15), borderColor: HtColors.blue, borderStrokeWidth: 1),
                    ]),
                    MarkerLayer(markers: [Marker(point: _center, child: const Icon(Icons.location_on, color: HtColors.red, size: 36))]),
                  ],
                ),
              ),
            ),
            Text('Radio: ${_radius.round()} m'),
            Slider(value: _radius, min: 100, max: 5000, divisions: 49, onChanged: (v) => setState(() => _radius = v)),
            const Text('El equipo revisará la solicitud, el precio y la seguridad de la zona antes de publicar la misión.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _submit, child: const Text('Enviar solicitud')),
          ],
        ),
      ),
    );
  }
}
