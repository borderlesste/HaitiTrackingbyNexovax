import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/contribution_detail_screen.dart';
import '../contributions/contribution_service.dart';
import '../contributions/contribution_widgets.dart';
import '../contributions/new_contribution_screen.dart';
import 'map_screen.dart';
import 'mission.dart';
import 'mission_completed_screen.dart';

/// Cuántos aportes lleva el usuario en una misión y cuánto puede ganar.
class MissionProgressScreen extends StatefulWidget {
  const MissionProgressScreen({super.key, required this.mission});
  final Mission mission;

  @override
  State<MissionProgressScreen> createState() => _MissionProgressScreenState();
}

class _MissionProgressScreenState extends State<MissionProgressScreen> {
  final _service = ContributionService();
  List<Map<String, dynamic>> _items = const [];
  Map<String, String> _photos = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.missionContributions(widget.mission.id);
      final photos = await _service.photoUrls(items.map(firstPhoto).whereType<String>());
      if (mounted) {
        setState(() {
          _items = items;
          _photos = photos;
        });
      }
    } catch (_) {
      // Sin conexión: se muestra la misión sin aportes.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final total = m.requiredContributions;
    final done = _items.where((c) => c['status'] != 'REJECTED').length.clamp(0, total);
    final pct = total == 0 ? 0 : (done * 100 ~/ total);
    return HtScaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            const ScreenTitle('Progreso de la misión', icon: Icons.track_changes),
            const SizedBox(height: 14),
            HtCard(
              child: Column(children: [
                Row(children: [
                  IconTile(missionIcon(m), size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      if (m.commune != null)
                        Row(children: [
                          const Icon(Icons.location_on_outlined, size: 16, color: HtColors.muted),
                          Text(' ${m.commune}', style: const TextStyle(color: HtColors.muted)),
                        ]),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: HtColors.greenSoft, borderRadius: BorderRadius.circular(10)),
                    child: Text(money(m.totalCents),
                        style: const TextStyle(color: HtColors.green, fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                ]),
                const Divider(height: 26),
                Row(children: [
                  Expanded(child: Text('Progreso: $done de $total', style: const TextStyle(fontSize: 16))),
                  Text('$pct %', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 12,
                    color: HtColors.blue,
                    backgroundColor: HtColors.border,
                  ),
                ),
                if (total > 1 && total <= 8) ...[
                  const SizedBox(height: 14),
                  StepDots(total: total, current: done + 1),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            HtCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionTitle('Mis aportes en esta misión', icon: Icons.assignment_outlined),
                const SizedBox(height: 8),
                if (_loading)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                else if (_items.isEmpty)
                  const Text('Aún no has enviado aportes en esta misión.')
                else
                  for (final c in _items)
                    InkWell(
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ContributionDetailScreen(id: c['id'] as String)));
                        _load();
                      },
                      child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        PlaceThumb(url: _photos[firstPhoto(c)], size: 52),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(c['name'] as String,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        ContributionStatusChip(c['status'] as String?),
                        const Icon(Icons.chevron_right, color: HtColors.muted),
                      ]),
                    ),
                    ),
              ]),
            ),
            const SizedBox(height: 12),
            HtCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionTitle('Recompensa de la misión', icon: Icons.savings_outlined),
                const SizedBox(height: 4),
                KvRow('Por cada establecimiento ($total × \$${m.rewardUsd})', money(m.rewardCents * total)),
                if (m.hasBonus) KvRow('Bono por completar la misión', money(m.bonusCents)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: HtColors.greenSoft, borderRadius: BorderRadius.circular(12)),
                  child: KvRow('Total posible', usd(m.totalCents), bold: true, valueColor: HtColors.green),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            if (done < total)
              FilledButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushReplacement(MaterialPageRoute(builder: (_) => NewContributionScreen(mission: m))),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Continuar registrando'),
              )
            else
              FilledButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => MissionCompletedScreen(mission: m))),
                icon: const Icon(Icons.emoji_events_outlined),
                label: const Text('Ver misión completada'),
              ),
          ],
        ),
      ),
    );
  }
}
