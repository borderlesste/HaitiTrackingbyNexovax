import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../missions/mission.dart';
import 'confirm_gps_screen.dart';
import 'contribution_draft.dart';
import 'contribution_service.dart';
import 'contribution_widgets.dart';
import 'gps.dart';

/// Corrige un aporte con "Requiere cambios" o "Rechazado" y lo reenvía a revisión.
class CorrectContributionScreen extends StatefulWidget {
  const CorrectContributionScreen({super.key, required this.contribution, this.photoUrls = const {}});
  final Map<String, dynamic> contribution;
  final Map<String, String> photoUrls;

  @override
  State<CorrectContributionScreen> createState() => _CorrectContributionScreenState();
}

class _CorrectContributionScreenState extends State<CorrectContributionScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.contribution['name'] as String? ?? '');
  late final _reference = TextEditingController(text: widget.contribution['address_reference'] as String? ?? '');
  late final _notes = TextEditingController(text: widget.contribution['notes'] as String? ?? '');
  late String? _category = placeCategories.contains(widget.contribution['category'])
      ? widget.contribution['category'] as String
      : null;
  File? _newPhoto;
  Position? _newPosition;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get c => widget.contribution;
  Mission? get _mission => missionFromJoin(c['missions'] as Map<String, dynamic>?, parseEwkbPoint);

  @override
  void dispose() {
    _name.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 70);
    if (picked != null) setState(() => _newPhoto = File(picked.path));
  }

  Future<void> _recaptureGps() async {
    final m = _mission;
    Position? pos;
    if (m != null) {
      pos = await Navigator.of(context).push<Position>(MaterialPageRoute(builder: (_) => ConfirmGpsScreen(mission: m)));
    } else {
      try {
        pos = await captureBestPosition();
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      }
    }
    if (pos != null && mounted) setState(() => _newPosition = pos);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final db = Supabase.instance.client;
    try {
      List<String>? photos;
      if (_newPhoto != null) {
        final path = '${db.auth.currentUser!.id}/${c['id']}_${const Uuid().v4().substring(0, 8)}.jpg';
        await db.storage.from('evidence').upload(path, _newPhoto!, fileOptions: const FileOptions(contentType: 'image/jpeg'));
        photos = [path];
      }
      final p = _newPosition;
      await db.rpc('resubmit_contribution', params: {
        'p_id': c['id'],
        'p_name': _name.text.trim(),
        'p_category': _category,
        'p_address_reference': _reference.text.trim(),
        'p_notes': [_notes.text.trim(), if (p?.isMocked ?? false) '[aviso: ubicación simulada detectada]']
            .where((s) => s.isNotEmpty)
            .join(' '),
        'p_lat': p?.latitude,
        'p_lng': p?.longitude,
        'p_accuracy_m': p == null ? null : double.parse(p.accuracy.toStringAsFixed(2)),
        'p_captured_at': p?.timestamp.toUtc().toIso8601String(),
        'p_photo_paths': photos,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aporte corregido y enviado a revisión.')));
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } on StorageException catch (e) {
      setState(() => _error = 'No se pudo subir la foto: ${e.message}');
    } catch (_) {
      setState(() => _error = 'Sin conexión. Para corregir un aporte necesitas internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reason = c['review_reason'] as String?;
    final oldPhoto = firstPhoto(c);
    final oldPoint = parseEwkbPoint(c['location']);
    final remaining = 3 - ((c['resubmit_count'] as num?)?.toInt() ?? 0);
    return HtScaffold(
      background: Colors.white,
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            const ScreenTitle('Corregir aporte',
                icon: Icons.edit_note, subtitle: 'Cambia lo que pidió el revisor y vuelve a enviarlo.'),
            const SizedBox(height: 14),
            if (reason != null && reason.isNotEmpty)
              HtCard(
                color: HtColors.redSoft,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.feedback_outlined, color: HtColors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Observación del revisor', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(reason, style: const TextStyle(height: 1.35)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 16),
            const _Label('Foto del establecimiento'),
            Row(children: [
              PlaceThumb(file: _newPhoto, url: _newPhoto == null ? widget.photoUrls[oldPhoto] : null, size: 90),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: Text(_newPhoto == null ? 'Tomar otra foto' : 'Cambiar foto'),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Elegir de galería'),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            const _Label('Nombre'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().length < 2) ? 'Escribe el nombre' : null,
            ),
            const SizedBox(height: 12),
            const _Label('Categoría'),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.storefront_outlined)),
              hint: const Text('Elige una categoría'),
              items: [for (final x in placeCategories) DropdownMenuItem(value: x, child: Text(x))],
              onChanged: (v) => setState(() => _category = v),
              validator: (v) => v == null ? 'Elige una categoría' : null,
            ),
            const SizedBox(height: 12),
            const _Label('Referencia de ubicación', optional: true),
            TextFormField(controller: _reference),
            const SizedBox(height: 12),
            const _Label('Descripción', optional: true),
            TextFormField(controller: _notes, maxLines: 2),
            const SizedBox(height: 16),
            HtCard(
              color: _newPosition != null ? HtColors.greenSoft : Colors.white,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.location_on, color: HtColors.blue),
                  SizedBox(width: 8),
                  Text('Ubicación (GPS)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
                const SizedBox(height: 6),
                Text(_newPosition != null
                    ? 'Nuevo punto: ${_newPosition!.latitude.toStringAsFixed(5)}, ${_newPosition!.longitude.toStringAsFixed(5)} '
                        '(± ${_newPosition!.accuracy.round()} m)'
                    : oldPoint == null
                        ? 'Se mantiene el punto enviado.'
                        : 'Se mantiene: ${oldPoint.$1.toStringAsFixed(5)}, ${oldPoint.$2.toStringAsFixed(5)}'),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _recaptureGps,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('Capturar de nuevo en el lugar'),
                  ),
                ),
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: HtColors.red)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: const Text('Reenviar a revisión'),
            ),
            const SizedBox(height: 8),
            Text('Te quedan $remaining corrección(es) para este aporte.',
                textAlign: TextAlign.center, style: const TextStyle(color: HtColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.optional = false});
  final String text;
  final bool optional;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(
          text: text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: HtColors.text),
          children: [
            optional
                ? const TextSpan(text: ' (opcional)', style: TextStyle(fontWeight: FontWeight.w400, color: HtColors.muted))
                : const TextSpan(text: ' *', style: TextStyle(color: HtColors.red)),
          ],
        )),
      );
}
