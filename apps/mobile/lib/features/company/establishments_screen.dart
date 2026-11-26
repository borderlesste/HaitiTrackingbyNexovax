import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'company_repo.dart';
import 'establishment_form_screen.dart';

/// Pantalla 18: Mis establecimientos (registrados por la empresa y reclamados del mapa).
class EstablishmentsScreen extends StatefulWidget {
  const EstablishmentsScreen({super.key, required this.orgId});
  final String orgId;

  @override
  State<EstablishmentsScreen> createState() => _EstablishmentsScreenState();
}

class _EstablishmentsScreenState extends State<EstablishmentsScreen> {
  final _repo = CompanyRepo();
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>, Map<String, String>)> _data = _load();
  int _filter = 0;

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>, Map<String, String>)> _load() async {
    final own = await _repo.establishments(widget.orgId);
    final claims = await _repo.claims(widget.orgId);
    final firstPhotos = [for (final e in own) if ((e['photo_paths'] as List).isNotEmpty) (e['photo_paths'] as List).first as String];
    return (own, claims, await _repo.photoUrls(firstPhotos));
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off,
            title: 'No se pudo cargar',
            text: 'Revisa tu conexión.',
            action: OutlinedButton(onPressed: () => setState(() => _data = _load()), child: const Text('Reintentar')),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (own, claims, urls) = snap.data!;
        bool match(String? s) => switch (_filter) { 1 => s == 'APPROVED', 2 => s == 'PENDING', 3 => s == 'REJECTED', _ => true };
        final ownF = own.where((e) => match(e['status'] as String?)).toList();
        final claimsF = claims.where((c) => match(c['status'] as String?)).toList();
        int count(String s) => own.where((e) => e['status'] == s).length + claims.where((c) => c['status'] == s).length;
        return RefreshIndicator(
          onRefresh: () async => setState(() => _data = _load()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            children: [
              const ScreenTitle('Mis establecimientos', icon: Icons.storefront_outlined),
              const SizedBox(height: 12),
              FilterPills(
                labels: [
                  'Todos (${own.length + claims.length})',
                  'Publicados (${count('APPROVED')})',
                  'En revisión (${count('PENDING')})',
                  'Rechazados (${count('REJECTED')})',
                ],
                selected: _filter,
                onSelected: (i) => setState(() => _filter = i),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _open(EstablishmentFormScreen(orgId: widget.orgId)),
                    icon: const Icon(Icons.add_business),
                    label: const Text('Registrar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _open(ClaimPlaceScreen(orgId: widget.orgId)),
                    icon: const Icon(Icons.search),
                    label: const Text('Reclamar del mapa'),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              if (ownF.isEmpty && claimsF.isEmpty)
                const EmptyState(
                  icon: Icons.storefront,
                  title: 'Sin establecimientos',
                  text: 'Registra tu negocio con su ubicación y fotos, o reclama uno que ya esté en el mapa.',
                ),
              for (final e in ownF) ...[
                HtCard(
                  padding: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _open(EstablishmentFormScreen(orgId: widget.orgId, existing: e)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 72,
                            height: 64,
                            child: () {
                              final paths = e['photo_paths'] as List;
                              final url = paths.isEmpty ? null : urls[paths.first];
                              return url == null
                                  ? const ColoredBox(color: HtColors.blueSoft, child: Icon(Icons.storefront, color: HtColors.blue))
                                  : Image.network(url, fit: BoxFit.cover);
                            }(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(e['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            Text('${e['category']} · ${e['commune'] ?? ''}', style: const TextStyle(color: HtColors.muted, fontSize: 13)),
                            if (e['place_code'] != null)
                              Text(e['place_code'] as String, style: const TextStyle(color: HtColors.blue, fontSize: 13, fontWeight: FontWeight.w600)),
                            if (e['status'] == 'REJECTED' && e['review_reason'] != null)
                              Text('Motivo: ${e['review_reason']}', style: const TextStyle(color: HtColors.red, fontSize: 13)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          reviewChip(e['status'] as String?),
                          const SizedBox(height: 6),
                          const Icon(Icons.chevron_right),
                        ]),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (claimsF.isNotEmpty) ...[
                const SizedBox(height: 6),
                const SectionTitle('Reclamados del mapa', icon: Icons.flag_outlined),
                const SizedBox(height: 8),
                for (final c in claimsF) ...[
                  HtCard(
                    child: Row(children: [
                      const IconTile(Icons.storefront, size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c['place_name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('${c['place_code']} · ${c['place_category']}', style: const TextStyle(color: HtColors.muted, fontSize: 13)),
                          if (c['review_reason'] != null) Text('Motivo: ${c['review_reason']}', style: const TextStyle(color: HtColors.red, fontSize: 13)),
                        ]),
                      ),
                      reviewChip(c['status'] as String?),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Reclamar un lugar que ya está en el mapa (busca por nombre o código HT-NXV).
class ClaimPlaceScreen extends StatefulWidget {
  const ClaimPlaceScreen({super.key, required this.orgId});
  final String orgId;

  @override
  State<ClaimPlaceScreen> createState() => _ClaimPlaceScreenState();
}

class _ClaimPlaceScreenState extends State<ClaimPlaceScreen> {
  final _repo = CompanyRepo();
  final _q = TextEditingController();
  final _evidence = TextEditingController();
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  bool _searched = false;

  Future<void> _search() async {
    setState(() => _searching = true);
    try {
      final r = await _repo.searchPlaces(_q.text);
      setState(() {
        _results = r;
        _searched = true;
      });
    } catch (_) {
      if (mounted) snack(context, 'No se pudo buscar. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _claim(Map<String, dynamic> p) async {
    try {
      await _repo.claimPlace(widget.orgId, p['id'] as String, _evidence.text.trim().isEmpty ? null : _evidence.text.trim());
      if (!mounted) return;
      snack(context, 'Reclamo enviado. El equipo lo revisará.');
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) snack(context, e.code == '23505' ? 'Ya reclamaste este lugar.' : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PanelPage(
      title: 'Reclamar establecimiento',
      icon: Icons.flag_outlined,
      subtitle: 'Si tu negocio ya está en el mapa, reclámalo para administrarlo.',
      children: [
        TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Nombre o código (HT-NXV-…)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(onPressed: _search, icon: const Icon(Icons.arrow_forward)),
          ),
          onSubmitted: (_) => _search(),
        ),
        const FieldLabel('Prueba de titularidad'),
        TextField(controller: _evidence, decoration: const InputDecoration(hintText: 'Ej.: número de patente, cargo en la empresa')),
        const SizedBox(height: 14),
        if (_searching) const Center(child: CircularProgressIndicator()),
        if (!_searching && _searched && _results.isEmpty)
          const InfoBanner('Sin resultados. Puedes registrarlo como establecimiento nuevo.'),
        for (final p in _results) ...[
          HtCard(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${p['code']} · ${p['category']} · ${p['commune'] ?? ''}', style: const TextStyle(color: HtColors.muted, fontSize: 13)),
                ]),
              ),
              TextButton(onPressed: () => _claim(p), child: const Text('Reclamar')),
            ]),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
