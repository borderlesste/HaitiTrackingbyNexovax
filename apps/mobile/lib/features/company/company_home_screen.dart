import 'package:flutter/material.dart';

import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'company_repo.dart';

/// Pantalla 17: Inicio de empresa (resumen de establecimientos, misiones y accesos rápidos).
class CompanyHomeScreen extends StatefulWidget {
  const CompanyHomeScreen({
    super.key,
    required this.org,
    required this.onRefresh,
    required this.onOpenVerification,
    required this.onOpenEstablishments,
    required this.onOpenMissions,
    required this.onNewEstablishment,
    required this.onRequestMission,
    required this.onOpenBilling,
  });
  final Map<String, dynamic> org;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenVerification;
  final VoidCallback onOpenEstablishments;
  final VoidCallback onOpenMissions;
  final VoidCallback onNewEstablishment;
  final VoidCallback onRequestMission;
  final VoidCallback onOpenBilling;

  @override
  State<CompanyHomeScreen> createState() => _CompanyHomeScreenState();
}

class _Summary {
  int published = 0, pending = 0, rejected = 0, missionsActive = 0, missionsPending = 0, placesFound = 0;
  List<Map<String, dynamic>> recent = const [];
}

class _CompanyHomeScreenState extends State<CompanyHomeScreen> {
  final _repo = CompanyRepo();
  late Future<_Summary> _data = _load();

  bool get _approved => widget.org['status'] == 'APPROVED';

  Future<_Summary> _load() async {
    final s = _Summary();
    if (!_approved) return s;
    final id = widget.org['id'] as String;
    final est = await _repo.establishments(id);
    final claims = await _repo.claims(id);
    final missions = await _repo.missionRequests(id);
    for (final e in [...est, ...claims]) {
      switch (e['status']) {
        case 'APPROVED':
          s.published++;
        case 'REJECTED':
          s.rejected++;
        default:
          s.pending++;
      }
    }
    for (final m in missions) {
      if (m['status'] == 'PENDING') s.missionsPending++;
      if (m['mission_status'] == 'ACTIVE') s.missionsActive++;
      s.placesFound += (m['approved_places'] as num? ?? 0).toInt();
    }
    s.recent = missions.take(3).toList();
    return s;
  }

  Future<void> _refresh() async {
    await widget.onRefresh();
    if (mounted) setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) {
    final org = widget.org;
    final status = org['status'] as String;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_Summary>(
        future: _data,
        builder: (context, snap) {
          final s = snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Row(children: [
                const CircleAvatar(radius: 26, backgroundColor: HtColors.blue, child: Icon(Icons.storefront, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(org['name'] as String, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text('${org['sector']} · ${org['commune'] ?? ''}', style: const TextStyle(color: HtColors.muted)),
                  ]),
                ),
                reviewChip(status),
              ]),
              const SizedBox(height: 16),
              if (!_approved)
                HtCard(
                  color: status == 'REJECTED' ? HtColors.redSoft : HtColors.amberSoft,
                  borderColor: Colors.transparent,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(status == 'REJECTED' ? Icons.error_outline : Icons.hourglass_top, color: status == 'REJECTED' ? HtColors.red : HtColors.amber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(status == 'REJECTED' ? 'Verificación rechazada' : 'Verificación en curso',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(status == 'REJECTED'
                        ? (org['review_reason'] as String? ?? 'Corrige los datos y vuelve a enviarlos.')
                        : 'Sube los documentos de tu empresa para acelerar la revisión. Después podrás registrar establecimientos y solicitar misiones.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: widget.onOpenVerification,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: Text(status == 'REJECTED' ? 'Corregir y reenviar' : 'Ver verificación'),
                    ),
                  ]),
                )
              else ...[
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.35,
                  children: [
                    StatTile(icon: Icons.storefront, value: '${s?.published ?? '–'}', label: 'Establecimientos publicados', color: HtColors.green, onTap: widget.onOpenEstablishments),
                    StatTile(icon: Icons.schedule, value: '${s?.pending ?? '–'}', label: 'En revisión', color: HtColors.amber, onTap: widget.onOpenEstablishments),
                    StatTile(icon: Icons.flag, value: '${s == null ? '–' : s.missionsActive + s.missionsPending}', label: 'Misiones activas o en revisión', onTap: widget.onOpenMissions),
                    StatTile(icon: Icons.place, value: '${s?.placesFound ?? '–'}', label: 'Lugares verificados por misiones', color: HtColors.navy, onTap: widget.onOpenMissions),
                  ],
                ),
                const SizedBox(height: 18),
                const SectionTitle('Accesos rápidos', icon: Icons.bolt),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: QuickAction(icon: Icons.add_business_outlined, label: 'Registrar establecimiento', onTap: widget.onNewEstablishment)),
                  const SizedBox(width: 10),
                  Expanded(child: QuickAction(icon: Icons.add_location_alt_outlined, label: 'Solicitar misión', onTap: widget.onRequestMission)),
                  const SizedBox(width: 10),
                  Expanded(child: QuickAction(icon: Icons.workspace_premium_outlined, label: 'Planes y facturas', onTap: widget.onOpenBilling)),
                ]),
                const SizedBox(height: 18),
                SectionTitle('Misiones recientes', icon: Icons.track_changes, action: 'Ver todas', onAction: widget.onOpenMissions),
                const SizedBox(height: 4),
                if (s == null)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                else if (s.recent.isEmpty)
                  const HtCard(child: Text('Aún no has solicitado misiones.', style: TextStyle(color: HtColors.muted)))
                else
                  HtCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (final (i, m) in s.recent.indexed)
                        SettingRow(
                          icon: Icons.flag_outlined,
                          color: HtColors.blue,
                          title: m['title'] as String,
                          subtitle: '${m['approved_places']} de ${m['target_places']} lugares aprobados',
                          trailing: reviewChip(m['status'] as String?),
                          onTap: widget.onOpenMissions,
                          last: i == s.recent.length - 1,
                        ),
                    ]),
                  ),
              ],
              const SizedBox(height: 16),
              const InfoBanner('Las misiones que solicites se publican solo después de la aprobación y financiación del equipo de Haiti Tracking.'),
            ],
          );
        },
      ),
    );
  }
}
