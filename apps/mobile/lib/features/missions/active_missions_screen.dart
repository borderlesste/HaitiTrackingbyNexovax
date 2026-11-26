import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/contribution_service.dart';
import 'map_screen.dart';
import 'mission.dart';
import 'mission_completed_screen.dart';
import 'mission_detail_screen.dart';
import 'mission_progress_screen.dart';
import 'saved_missions.dart';

/// Misiones en las que el colaborador ya participa: en curso, completadas y guardadas.
class ActiveMissionsScreen extends StatefulWidget {
  const ActiveMissionsScreen({super.key, required this.missions});
  final List<Mission> missions;

  @override
  State<ActiveMissionsScreen> createState() => _ActiveMissionsScreenState();
}

class _Group {
  _Group(this.missionId, this.title, this.commune, this.required);
  final String missionId;
  final String title;
  final String? commune;
  final int required;
  int sent = 0;
  int approved = 0;
  int needsFix = 0;
  DateTime last = DateTime(2000);
}

class _ActiveMissionsScreenState extends State<ActiveMissionsScreen> {
  final _service = ContributionService();
  List<_Group> _groups = const [];
  bool _loading = true;
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _service.myContributions();
      final byId = <String, _Group>{};
      for (final c in rows) {
        final id = c['mission_id'] as String?;
        if (id == null) continue;
        final m = c['missions'] as Map<String, dynamic>?;
        final g = byId.putIfAbsent(
          id,
          () => _Group(id, (m?['title'] as String?) ?? 'Misión', m?['commune'] as String?,
              (m?['required_approved_contributions'] as num?)?.toInt() ?? 1),
        );
        final status = c['status'] as String?;
        if (status != 'REJECTED') g.sent++;
        if (status == 'APPROVED') g.approved++;
        if (status == 'NEEDS_CHANGES' || status == 'REJECTED') g.needsFix++;
        final at = DateTime.tryParse(c['created_at'] as String? ?? '');
        if (at != null && at.isAfter(g.last)) g.last = at;
      }
      final list = byId.values.toList()..sort((a, b) => b.last.compareTo(a.last));
      if (mounted) {
        setState(() {
          _groups = list;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar tus misiones. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Mission? _mission(String id) {
    for (final m in widget.missions) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = _groups.where((g) => g.sent < g.required).toList();
    final done = _groups.where((g) => g.sent >= g.required).toList();
    return HtScaffold(
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: SavedMissions.ids,
        builder: (context, saved, _) {
          final savedList = widget.missions.where((m) => saved.contains(m.id)).toList();
          final labels = [
            'En curso (${inProgress.length})',
            'Completadas (${done.length})',
            'Guardadas (${savedList.length})',
          ];
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                const ScreenTitle('Mis misiones activas',
                    icon: Icons.playlist_add_check, subtitle: 'Sigue tu avance y retoma donde lo dejaste.'),
                const SizedBox(height: 14),
                FilterPills(labels: labels, selected: _tab, onSelected: (i) => setState(() => _tab = i)),
                const SizedBox(height: 14),
                if (_loading)
                  const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                else if (_error != null && _tab < 2)
                  InfoBanner(_error!, warning: true)
                else if (_tab == 2)
                  ...(savedList.isEmpty
                      ? [const _Empty('Aún no guardaste misiones para después.')]
                      : [for (final m in savedList) _SavedTile(mission: m)])
                else ...[
                  if ((_tab == 0 ? inProgress : done).isEmpty)
                    _Empty(_tab == 0
                        ? 'No tienes misiones en curso. Explora las misiones y empieza una.'
                        : 'Todavía no completaste ninguna misión.'),
                  for (final g in (_tab == 0 ? inProgress : done)) _GroupTile(group: g, mission: _mission(g.missionId), onBack: _load),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: HtColors.muted)),
      );
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.mission, required this.onBack});
  final _Group group;
  final Mission? mission;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final m = mission;
    final complete = g.sent >= g.required;
    final allApproved = g.approved >= g.required;
    final (label, tone) = allApproved
        ? ('Aprobada', ChipTone.ok)
        : g.needsFix > 0
            ? ('Requiere cambios', ChipTone.bad)
            : complete
                ? ('En revisión', ChipTone.review)
                : ('En curso', ChipTone.info);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: m == null
            ? null
            : () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => complete ? MissionCompletedScreen(mission: m) : MissionProgressScreen(mission: m)));
                onBack();
              },
        child: HtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconTile(m == null ? Icons.flag_outlined : missionIcon(m)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  if (g.commune != null) Text(g.commune!, style: const TextStyle(color: HtColors.muted)),
                ]),
              ),
              StatusChip(label, tone: tone),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('${g.sent.clamp(0, g.required)} de ${g.required} ubicaciones')),
              if (m != null) Text(money(m.totalCents), style: const TextStyle(color: HtColors.green, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: g.required == 0 ? 0 : (g.sent / g.required).clamp(0, 1).toDouble(),
                minHeight: 8,
                color: complete ? HtColors.green : HtColors.blue,
                backgroundColor: HtColors.border,
              ),
            ),
            if (m == null) ...[
              const SizedBox(height: 8),
              const Text('Esta misión ya no está activa cerca de ti.', style: TextStyle(color: HtColors.muted, fontSize: 12)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MissionDetailScreen(mission: m))),
        child: HtCard(
          child: Row(children: [
            IconTile(missionIcon(m)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('${m.commune ?? ''} · ${(m.distanceM / 1000).toStringAsFixed(1)} km',
                    style: const TextStyle(color: HtColors.muted)),
              ]),
            ),
            Text(money(m.totalCents), style: const TextStyle(color: HtColors.green, fontWeight: FontWeight.w800)),
            IconButton(
              tooltip: trn('Quitar de guardadas'),
              icon: const Icon(Icons.bookmark_remove_outlined),
              onPressed: () => SavedMissions.toggle(m.id),
            ),
          ]),
        ),
      ),
    );
  }
}
