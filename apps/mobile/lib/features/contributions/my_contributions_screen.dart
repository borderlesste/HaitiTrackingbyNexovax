import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import 'contribution_detail_screen.dart';
import 'contribution_draft.dart';
import 'contribution_service.dart';
import 'contribution_widgets.dart';

/// Historial de aportes con filtros por estado. [embedded] = dentro de la pestaña "Aportes".
class MyContributionsScreen extends StatefulWidget {
  const MyContributionsScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<MyContributionsScreen> createState() => _MyContributionsScreenState();
}

class _MyContributionsScreenState extends State<MyContributionsScreen> {
  final _service = ContributionService();
  List<ContributionDraft> _pending = const [];
  List<Map<String, dynamic>> _sent = const [];
  Map<String, String> _photos = const {};
  bool _loading = true;
  bool _offline = false;
  bool _syncing = false;
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Supabase.instance.client.auth;
    final userId = auth.currentUser?.id;
    if (userId == null) return;
    final pending = await _service.store.all(userId);
    if (auth.currentUser?.id != userId) return;
    var offline = false;
    var sent = _sent;
    var photos = _photos;
    try {
      sent = await _service.myContributions();
      photos = await _service.photoUrls(sent.map(firstPhoto).whereType<String>());
    } catch (_) {
      offline = true;
    }
    if (!mounted || auth.currentUser?.id != userId) return;
    setState(() {
      _pending = pending;
      _sent = sent;
      _photos = photos;
      _offline = offline;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final n = await _service.syncPending();
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(n == 0 ? 'No se pudo enviar todavía.' : '$n aporte(s) enviados.')));
    _load();
  }

  bool _matches(Map<String, dynamic> c, int f) => switch (f) {
        1 => isInReview(c['status'] as String?),
        2 => c['status'] == 'APPROVED',
        3 => c['status'] == 'REJECTED' || c['status'] == 'NEEDS_CHANGES',
        _ => true,
      };

  Future<void> _showDetail(Map<String, dynamic> c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContributionDetailScreen(id: c['id'] as String)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final counts = [for (var f = 0; f < 4; f++) _sent.where((c) => _matches(c, f)).length];
    final visible = _sent.where((c) => _matches(c, _filter)).toList();
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                const ScreenTitle('Mis aportes', icon: Icons.storefront_outlined),
                const SizedBox(height: 14),
                FilterPills(
                  labels: [
                    'Todos (${counts[0]})',
                    'En revisión (${counts[1]})',
                    'Aprobados (${counts[2]})',
                    'Rechazados (${counts[3]})',
                  ],
                  selected: _filter,
                  onSelected: (i) => setState(() => _filter = i),
                ),
                const SizedBox(height: 12),
                if (_offline) ...[
                  const InfoBanner('Sin conexión: mostrando solo lo guardado en el teléfono.', warning: true),
                  const SizedBox(height: 12),
                ],
                if (_pending.isNotEmpty) ...[
                  HtCard(
                    color: HtColors.amberSoft,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text('Pendientes de envío (${_pending.length})',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        TextButton.icon(
                          onPressed: _syncing ? null : _sync,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Enviar ahora'),
                        ),
                      ]),
                      for (final d in _pending)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('• ${d.name} · ${fechaHora(d.capturedAt)}'
                              '${d.lastError != null ? ' · ${d.lastError}' : ''}'),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text('No hay aportes en esta lista. Elige una misión en el mapa para empezar.',
                        textAlign: TextAlign.center),
                  )
                else
                  HtCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Column(children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _row(visible[i]),
                      ],
                    ]),
                  ),
              ],
            ),
          );
    if (widget.embedded) return content;
    return HtScaffold(body: content);
  }

  Widget _row(Map<String, dynamic> c) {
    return InkWell(
      onTap: () => _showDetail(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          PlaceThumb(url: _photos[firstPhoto(c)], size: 62),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['name'] as String,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.storefront_outlined, size: 15, color: HtColors.muted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(c['category'] as String? ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: HtColors.muted)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(fechaHora(DateTime.parse(c['created_at'] as String)),
                  style: const TextStyle(color: HtColors.muted, fontSize: 13)),
            ]),
          ),
          ContributionStatusChip(c['status'] as String?),
          const Icon(Icons.chevron_right, color: HtColors.muted),
        ]),
      ),
    );
  }
}
