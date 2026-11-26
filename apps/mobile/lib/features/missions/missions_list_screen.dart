import 'package:flutter/material.dart';

import '../../core/guest.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'active_missions_screen.dart';
import 'map_screen.dart';
import 'mission.dart';
import 'mission_detail_screen.dart';
import 'saved_missions.dart';

/// Explorar misiones: búsqueda, filtros rápidos y orden.
class MissionsListScreen extends StatefulWidget {
  const MissionsListScreen({super.key, required this.missions, required this.onRefresh});

  final List<Mission> missions;
  final Future<void> Function() onRefresh;

  @override
  State<MissionsListScreen> createState() => _MissionsListScreenState();
}

enum _Sort { distance, reward, ending }

class _MissionsListScreenState extends State<MissionsListScreen> {
  final _query = TextEditingController();
  int _filter = 0;
  _Sort _sort = _Sort.distance;

  static const _filters = ['Todas', 'Cercanas', 'Prioritarias', 'Con bono', 'Guardadas'];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _matches(Mission m, Set<String> saved) {
    final q = _query.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = '${m.title} ${m.commune ?? ''} ${m.description} ${m.code}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return switch (_filter) {
      1 => m.distanceM <= 3000,
      2 => m.isPriority,
      3 => m.hasBonus,
      4 => saved.contains(m.id),
      _ => true,
    };
  }

  List<Mission> _visible(Set<String> saved) {
    final list = widget.missions.where((m) => _matches(m, saved)).toList();
    switch (_sort) {
      case _Sort.distance:
        list.sort((a, b) => a.distanceM.compareTo(b.distanceM));
      case _Sort.reward:
        list.sort((a, b) => b.totalCents.compareTo(a.totalCents));
      case _Sort.ending:
        final far = DateTime(9999);
        list.sort((a, b) => (a.endAt ?? far).compareTo(b.endAt ?? far));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: SavedMissions.ids,
      builder: (context, saved, _) {
        final list = _visible(saved);
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              const ScreenTitle('Explorar misiones',
                  icon: Icons.location_on_outlined, subtitle: 'Elige una misión cerca de ti y empieza a ganar.'),
              const SizedBox(height: 14),
              TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre, comuna o código',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_query.clear),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              FilterPills(labels: _filters, selected: _filter, onSelected: (i) => setState(() => _filter = i)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Text('${list.length} misión(es)', style: const TextStyle(color: HtColors.muted)),
                ),
                PopupMenuButton<_Sort>(
                  initialValue: _sort,
                  onSelected: (v) => setState(() => _sort = v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: _Sort.distance, child: Text('Más cercanas')),
                    PopupMenuItem(value: _Sort.reward, child: Text('Mayor recompensa')),
                    PopupMenuItem(value: _Sort.ending, child: Text('Terminan pronto')),
                  ],
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.sort, size: 20, color: HtColors.blue),
                    const SizedBox(width: 4),
                    Text(
                      switch (_sort) {
                        _Sort.distance => 'Más cercanas',
                        _Sort.reward => 'Mayor recompensa',
                        _Sort.ending => 'Terminan pronto',
                      },
                      style: const TextStyle(color: HtColors.blue, fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),
              ]),
              if (!Guest.isGuest) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ActiveMissionsScreen(missions: widget.missions))),
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Mis misiones activas'),
                ),
              ],
              const SizedBox(height: 12),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 50),
                  child: Text(
                    widget.missions.isEmpty
                        ? 'No hay misiones activas cerca por ahora.'
                        : _filter == 4
                            ? 'Aún no guardaste misiones. Ábrelas y toca "Guardar para después".'
                            : 'Ninguna misión coincide con tu búsqueda.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final m in list) ...[
                _MissionTile(mission: m, saved: saved.contains(m.id)),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({required this.mission, this.saved = false});
  final Mission mission;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    void open() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MissionDetailScreen(mission: m)));
    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(16),
      child: HtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(missionIcon(m), color: m.isPriority ? HtColors.red : HtColors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: HtColors.text)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: HtColors.muted),
                  Flexible(
                    child: Text(' ${m.commune ?? ''} · ${(m.distanceM / 1000).toStringAsFixed(1)} km',
                        style: const TextStyle(color: HtColors.muted)),
                  ),
                ]),
              ]),
            ),
            if (saved)
              const Padding(
                padding: EdgeInsets.only(right: 6, top: 4),
                child: Icon(Icons.bookmark, color: HtColors.amber, size: 22),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: HtColors.greenSoft, borderRadius: BorderRadius.circular(10)),
              child: Text('\$${missionTotal(m)}',
                  style: const TextStyle(color: HtColors.green, fontWeight: FontWeight.w800, fontSize: 17)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            '${m.requiredContributions} ubicaciones${m.hasBonus ? ' · Bono incluido' : ''} · \$${m.rewardUsd} c/u',
            style: const TextStyle(color: HtColors.text),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: open,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Ver misión'),
              SizedBox(width: 6),
              Icon(Icons.chevron_right),
            ]),
          ),
        ]),
      ),
    );
  }
}
