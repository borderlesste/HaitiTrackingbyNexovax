import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/contribution_detail_screen.dart';
import '../contributions/contribution_service.dart';
import '../contributions/contribution_widgets.dart';
import '../home/home_shell.dart';
import 'mission.dart';

/// Confirmación de que se registraron todos los objetivos de la misión.
class MissionCompletedScreen extends StatefulWidget {
  const MissionCompletedScreen({super.key, required this.mission});
  final Mission mission;

  @override
  State<MissionCompletedScreen> createState() => _MissionCompletedScreenState();
}

class _MissionCompletedScreenState extends State<MissionCompletedScreen> {
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
      final items = (await _service.missionContributions(widget.mission.id))
          .where((c) => c['status'] != 'REJECTED')
          .toList();
      final photos = await _service.photoUrls(items.map(firstPhoto).whereType<String>());
      if (mounted) {
        setState(() {
          _items = items;
          _photos = photos;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goTab(HomeTab t) {
    HomeShell.tab.value = t;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final approved = _items.where((c) => c['status'] == 'APPROVED').length;
    final needsFix = _items.where((c) => c['status'] == 'NEEDS_CHANGES').length;
    final allApproved = _items.isNotEmpty && approved >= m.requiredContributions;
    final (label, tone) = allApproved
        ? ('Aprobada', ChipTone.ok)
        : needsFix > 0
            ? ('Requiere cambios', ChipTone.bad)
            : ('En revisión', ChipTone.review);
    return HtScaffold(
      background: Colors.white,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Center(child: SuccessMark(size: 100)),
          Text(allApproved ? '¡Misión completada!' : '¡Misión enviada!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: HtColors.text)),
          const SizedBox(height: 6),
          Text(
            allApproved
                ? 'Todos tus aportes fueron aprobados. La recompensa ya está en tu saldo.'
                : 'Registraste todos los objetivos. Ahora el equipo revisa cada aporte.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: HtColors.muted, height: 1.35),
          ),
          const SizedBox(height: 16),
          HtCard(
            color: HtColors.greenSoft,
            child: Row(children: [
              const Icon(Icons.check_circle, color: HtColors.green, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${_items.length.clamp(0, m.requiredContributions)} de ${m.requiredContributions} ubicaciones registradas',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          HtCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: _loading
                ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                : Column(children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      InkWell(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ContributionDetailScreen(id: _items[i]['id'] as String))),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(children: [
                            PlaceThumb(url: _photos[firstPhoto(_items[i])], size: 48),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_items[i]['name'] as String,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            ),
                            ContributionStatusChip(_items[i]['status'] as String?),
                          ]),
                        ),
                      ),
                    ],
                  ]),
          ),
          const SizedBox(height: 12),
          HtCard(
            child: Column(children: [
              KvRow('Estado de la misión', '', icon: Icons.flag_outlined, trailing: StatusChip(label, tone: tone)),
              const Divider(height: 10),
              KvRow('${m.requiredContributions} ubicaciones × \$${m.rewardUsd}', money(m.rewardCents * m.requiredContributions)),
              if (m.hasBonus) KvRow('Bono por completar la misión', money(m.bonusCents)),
              const Divider(height: 10),
              KvRow(allApproved ? 'Ganado' : 'Recompensa (si se aprueba)', usd(m.totalCents),
                  bold: true, valueColor: HtColors.green, icon: Icons.savings_outlined),
            ]),
          ),
          const SizedBox(height: 12),
          InfoBanner(needsFix > 0
              ? 'Hay aportes con cambios pedidos: tócalos para corregirlos y no perder el bono.'
              : 'Te notificaremos cuando la misión sea aprobada o si requiere ajustes.'),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => _goTab(HomeTab.missions), child: const Text('Ver misiones')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => _goTab(HomeTab.home), child: const Text('Ir al mapa')),
        ],
      ),
    );
  }
}
