import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'contribution_draft.dart';
import 'contribution_service.dart';

const _statusLabels = {
  'SUBMITTED': ('Enviado', Colors.blueGrey),
  'AUTO_CHECKED': ('En revisión', Colors.orange),
  'HUMAN_REVIEW': ('En revisión', Colors.orange),
  'APPROVED': ('Aprobado', HtColors.green),
  'REJECTED': ('Rechazado', HtColors.red),
  'NEEDS_CHANGES': ('Requiere cambios', Colors.deepOrange),
  'APPEALED': ('Apelado', Colors.purple),
};

class MyContributionsScreen extends StatefulWidget {
  const MyContributionsScreen({super.key});

  @override
  State<MyContributionsScreen> createState() => _MyContributionsScreenState();
}

class _MyContributionsScreenState extends State<MyContributionsScreen> {
  final _service = ContributionService();
  List<ContributionDraft> _pending = const [];
  List<Map<String, dynamic>> _sent = const [];
  bool _loading = true;
  bool _offline = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final pending = await _service.store.all();
    var offline = false;
    List<Map<String, dynamic>> sent = _sent;
    try {
      sent = await _service.myContributions();
    } catch (_) {
      offline = true;
    }
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _sent = sent;
      _offline = offline;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final n = await _service.syncPending();
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 0 ? 'No se pudo enviar todavía.' : '$n aporte(s) enviados.')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Mis aportes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_offline)
                    const Card(
                      color: Color(0xFFFFF4E5),
                      child: ListTile(leading: Icon(Icons.cloud_off), title: Text('Sin conexión: mostrando solo lo guardado en el teléfono.')),
                    ),
                  if (_pending.isNotEmpty) ...[
                    Row(children: [
                      Expanded(child: Text('Pendientes de envío (${_pending.length})', style: const TextStyle(fontWeight: FontWeight.bold))),
                      TextButton.icon(
                        onPressed: _syncing ? null : _sync,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Enviar ahora'),
                      ),
                    ]),
                    for (final d in _pending)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.cloud_off, color: Colors.orange),
                          title: Text(d.name),
                          subtitle: Text('${d.missionTitle}\n${fmt.format(d.capturedAt.toLocal())}'
                              '${d.lastError != null ? ' · ${d.lastError}' : ''}'),
                          isThreeLine: true,
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                  const Text('Enviados', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_sent.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Todavía no has enviado aportes. Elige una misión en el mapa para empezar.', textAlign: TextAlign.center),
                    ),
                  for (final c in _sent) _sentTile(c, fmt),
                ],
              ),
            ),
    );
  }

  Widget _sentTile(Map<String, dynamic> c, DateFormat fmt) {
    final (label, color) = _statusLabels[c['status']] ?? (c['status'] as String, Colors.grey);
    final mission = (c['missions'] as Map<String, dynamic>?)?['title'] as String? ?? '';
    final reason = c['review_reason'] as String?;
    return Card(
      child: ListTile(
        title: Text(c['name'] as String),
        subtitle: Text([
          if (mission.isNotEmpty) mission,
          fmt.format(DateTime.parse(c['created_at'] as String).toLocal()),
          if (reason != null && reason.isNotEmpty) 'Motivo: $reason',
        ].join('\n')),
        isThreeLine: true,
        trailing: Chip(
          label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          backgroundColor: color,
          side: BorderSide.none,
        ),
      ),
    );
  }
}
