import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import 'contribution_service.dart';
import 'contribution_widgets.dart';

/// Comprueba si el establecimiento ya existe (registrado o en revisión) cerca del punto GPS.
/// Devuelve true si la persona confirma que es un lugar distinto.
class DuplicateCheckScreen extends StatefulWidget {
  const DuplicateCheckScreen({
    super.key,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    this.photo,
  });

  final String name;
  final String category;
  final double lat;
  final double lng;
  final File? photo;

  @override
  State<DuplicateCheckScreen> createState() => _DuplicateCheckScreenState();
}

class _DuplicateCheckScreenState extends State<DuplicateCheckScreen> {
  List<DuplicateCandidate>? _found;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _found = null;
      _failed = false;
    });
    try {
      final list = await ContributionService().checkDuplicates(widget.lat, widget.lng, widget.name);
      if (mounted) setState(() => _found = list);
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _found = const [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    final likely = found?.where((d) => d.likelySame).toList() ?? const [];
    return HtScaffold(
      background: Colors.white,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const ScreenTitle('Comprobación de duplicados',
              icon: Icons.content_copy_outlined,
              subtitle: 'Buscamos si este lugar ya está en el mapa o lo registró otra persona.'),
          const SizedBox(height: 14),
          HtCard(
            child: Row(children: [
              PlaceThumb(file: widget.photo, size: 62),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Tu registro', style: TextStyle(color: HtColors.muted, fontSize: 13)),
                  Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  Text(widget.category, style: const TextStyle(color: HtColors.muted)),
                  Text('${widget.lat.toStringAsFixed(5)}, ${widget.lng.toStringAsFixed(5)}',
                      style: const TextStyle(color: HtColors.muted, fontSize: 13)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (found == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Buscando lugares cercanos…'),
              ]),
            )
          else if (_failed)
            const InfoBanner(
              'No pudimos comprobarlo ahora (sin conexión). Puedes continuar: el equipo revisará los duplicados.',
              warning: true,
            )
          else if (found.isEmpty)
            HtCard(
              color: HtColors.greenSoft,
              child: Row(children: const [
                Icon(Icons.verified, color: HtColors.green, size: 34),
                SizedBox(width: 12),
                Expanded(
                  child: Text('No encontramos lugares iguales a menos de 60 m. Puedes continuar.',
                      style: TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
                ),
              ]),
            )
          else ...[
            InfoBanner(
              likely.isNotEmpty
                  ? 'Encontramos ${likely.length == 1 ? 'un lugar muy parecido' : '${likely.length} lugares muy parecidos'} '
                      'cerca. Si es el mismo, no se paga como nuevo y el aporte se rechazará.'
                  : 'Hay lugares registrados cerca. Revisa que no sea el mismo establecimiento.',
              warning: likely.isNotEmpty,
            ),
            const SizedBox(height: 12),
            SectionTitle('Lugares cercanos (${found.length})', icon: Icons.near_me_outlined),
            const SizedBox(height: 6),
            HtCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(children: [
                for (var i = 0; i < found.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _CandidateRow(found[i]),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: found == null ? null : () => Navigator.pop(context, true),
            icon: const Icon(Icons.arrow_forward),
            label: Text(found == null || found.isEmpty ? 'Continuar' : 'Es un lugar diferente, continuar'),
          ),
          if (found != null && found.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.block),
              label: const Text('Es el mismo lugar, no enviar'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow(this.d);
  final DuplicateCandidate d;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        IconTile(d.isPending ? Icons.hourglass_top : Icons.place,
            color: d.likelySame ? HtColors.red : HtColors.blue,
            background: d.likelySame ? HtColors.redSoft : HtColors.blueSoft,
            size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              [d.category, 'a ${d.distanceM.round()} m', d.isPending ? 'en revisión' : (d.code ?? 'en el mapa')].join(' · '),
              style: const TextStyle(color: HtColors.muted, fontSize: 13),
            ),
          ]),
        ),
        if (d.likelySame) const StatusChip('Muy parecido', tone: ChipTone.bad),
      ]),
    );
  }
}
