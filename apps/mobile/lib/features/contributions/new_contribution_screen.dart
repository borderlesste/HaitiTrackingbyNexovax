import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/evidence_upload.dart';
import '../../core/theme.dart';
import '../missions/mission.dart';
import 'contribution_draft.dart';
import 'contribution_service.dart';
import 'confirm_gps_screen.dart';
import 'contribution_sent_screen.dart';
import 'duplicate_check_screen.dart';
import 'gps.dart';
import '../../core/ui.dart';

class NewContributionScreen extends StatefulWidget {
  const NewContributionScreen({super.key, required this.mission});
  final Mission mission;

  @override
  State<NewContributionScreen> createState() => _NewContributionScreenState();
}

class _NewContributionScreenState extends State<NewContributionScreen> {
  final _service = ContributionService();
  final _userId = Supabase.instance.client.auth.currentUser?.id;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final _draftId = const Uuid().v4();

  String? _category;
  Position? _position;
  String? _gpsError;
  bool _locating = false;
  File? _photo;
  bool _sending = false;

  /// La persona revisó el punto en el mapa (pantalla "Confirmar punto GPS").
  bool _gpsConfirmed = false;

  /// Número de este aporte dentro de la misión (1 de 5, 2 de 5...).
  int _number = 1;

  @override
  void initState() {
    super.initState();
    _locate();
    _service.missionContributions(widget.mission.id).then((list) {
      final done = list.where((c) => c['status'] != 'REJECTED').length;
      if (mounted) setState(() => _number = done + 1);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? get _distanceToMission => _position == null
      ? null
      : const Distance().as(LengthUnit.Meter, widget.mission.point, LatLng(_position!.latitude, _position!.longitude));

  bool get _insideArea {
    if (!widget.mission.requiresOnSite) return true;
    final d = _distanceToMission;
    final r = widget.mission.radiusM;
    if (d == null) return false;
    if (r == null) return true;
    return d <= r + (_position?.accuracy ?? 0);
  }

  bool get _accuracyOk =>
      _position != null && (!widget.mission.requiresOnSite || _position!.accuracy <= maxAccuracyM);

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _gpsError = null;
    });
    try {
      final pos = await captureBestPosition();
      setState(() {
        _position = pos;
        _gpsConfirmed = false;
      });
    } catch (e) {
      setState(() => _gpsError = e.toString());
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 70);
    if (picked == null || !mounted) return;
    final photo = File(picked.path);
    try {
      final type = await inspectEvidence(photo);
      // Copia en la carpeta de la app para que el borrador sobreviva sin conexión.
      final dir = await getApplicationDocumentsDirectory();
      final saved = await photo.copy('${dir.path}/aporte_$_draftId.${type.extension}');
      if (mounted) setState(() => _photo = saved);
    } on InvalidEvidence catch (e) {
      if (mounted) _snack(e.message);
    } on FileSystemException {
      if (mounted) _snack('No se pudo guardar la imagen.');
    }
  }

  Future<void> _review() async {
    final userId = _userId;
    if (userId == null || Supabase.instance.client.auth.currentUser?.id != userId) {
      return _snack('Inicia sesión en tu cuenta para enviar el aporte.');
    }
    if (!_formKey.currentState!.validate()) return;
    if (_photo == null) return _snack('Agrega una foto del establecimiento.');
    if (_position == null) return _snack('Primero confirma tu ubicación GPS.');

    // 1) Confirmar el punto GPS en el mapa.
    if (!_gpsConfirmed || !_accuracyOk || !_insideArea) {
      final confirmed = await _openGpsReview();
      if (confirmed != true) return;
    }
    if (!mounted) return;

    // 2) Comprobar duplicados (sin conexión deja continuar: lo revisa el equipo).
    final distinct = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => DuplicateCheckScreen(
        name: _name.text.trim(),
        category: _category!,
        lat: _position!.latitude,
        lng: _position!.longitude,
        photo: _photo,
      ),
    ));
    if (distinct != true || !mounted) return;

    setState(() => _sending = true);
    try {
      // 3) Enviar o guardar sin conexión.
      final draft = ContributionDraft(
        id: _draftId,
        userId: userId,
        missionId: widget.mission.id,
        missionTitle: widget.mission.title,
        name: _name.text.trim(),
        category: _category!,
        lat: _position!.latitude,
        lng: _position!.longitude,
        accuracyM: _position!.accuracy,
        capturedAt: _position!.timestamp,
        photoPath: _photo!.path,
        addressReference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        isMocked: _position!.isMocked,
      );
      final result = await _service.submit(draft);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ContributionSentScreen(
          mission: widget.mission,
          draft: draft,
          offline: result == SubmitResult.savedOffline,
        ),
      ));
    } on PostgrestException {
      if (mounted) _snack('El servidor rechazó el aporte.');
    } on InvalidEvidence catch (e) {
      if (mounted) _snack(e.message);
    } on StateError {
      if (mounted) _snack('No se pudo guardar el aporte en el teléfono.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool> _openGpsReview() async {
    final pos = await Navigator.of(context).push<Position>(MaterialPageRoute(
      builder: (_) => ConfirmGpsScreen(mission: widget.mission, initial: _position),
    ));
    if (pos == null || !mounted) return false;
    setState(() {
      _position = pos;
      _gpsError = null;
      _gpsConfirmed = true;
    });
    return true;
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));


  @override
  Widget build(BuildContext context) {
    final total = widget.mission.requiredContributions;
    return HtScaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Row(children: [
              const Expanded(
                child: Text('Registrar establecimiento',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: HtColors.text)),
              ),
              if (total > 1)
                Text('Aporte ${_number.clamp(1, total)} de $total', style: const TextStyle(color: HtColors.muted)),
            ]),
            const SizedBox(height: 4),
            Text(widget.mission.title, style: const TextStyle(color: HtColors.muted)),
            if (total > 1) ...[
              const SizedBox(height: 14),
              StepDots(total: total.clamp(1, 8), current: _number.clamp(1, 8)),
            ],
            const SizedBox(height: 18),
            const _FieldLabel('Foto del establecimiento'),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 200,
                color: HtColors.blueSoft,
                child: _photo == null
                    ? const Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add_a_photo_outlined, size: 44, color: HtColors.blue),
                          SizedBox(height: 6),
                          Text('Toma una foto clara del frente del lugar'),
                        ]),
                      )
                    : Stack(fit: StackFit.expand, children: [
                        Image.file(_photo!, fit: BoxFit.cover),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            backgroundColor: Colors.white,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: HtColors.text),
                              tooltip: 'Quitar foto',
                              onPressed: () => setState(() => _photo = null),
                            ),
                          ),
                        ),
                      ]),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Tomar foto'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Elegir de galería'),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            const Text('No fotografíes personas ni el interior de viviendas.',
                style: TextStyle(fontSize: 12, color: HtColors.muted)),
            const SizedBox(height: 16),
            HtCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionTitle('Información del establecimiento', icon: Icons.storefront),
                const SizedBox(height: 12),
                const _FieldLabel('Nombre'),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(hintText: 'Mini Market Belle Vue'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Escribe el nombre' : null,
                ),
                const SizedBox(height: 12),
                const _FieldLabel('Categoría'),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.storefront_outlined)),
                  hint: const Text('Elige una categoría'),
                  items: [for (final c in placeCategories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _category = v),
                  validator: (v) => v == null ? 'Elige una categoría' : null,
                ),
                const SizedBox(height: 12),
                const _FieldLabel('Descripción', optional: true),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(hintText: 'Tienda de alimentos y artículos básicos.'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                const _FieldLabel('Referencia de ubicación', optional: true),
                TextFormField(
                  controller: _reference,
                  decoration: const InputDecoration(hintText: 'Ej.: frente a la estación de Delmas 33'),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            _gpsCard(),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _sending ? null : _review,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: const Text('Guardar y continuar'),
            ),
            const SizedBox(height: 8),
            Text(
                widget.mission.paid
                    ? 'Recompensa posible: \$${widget.mission.rewardUsd} USD, solo si el aporte es aprobado.'
                    : 'Aporte libre: no tiene recompensa. El lugar se publica en el mapa cuando el equipo lo aprueba.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: HtColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _gpsCard() {
    final p = _position;
    final ok = p != null && _accuracyOk && _insideArea;
    final Color bg = p == null ? Colors.white : (ok ? HtColors.greenSoft : HtColors.redSoft);
    String status;
    if (_locating) {
      status = 'Buscando tu ubicación…';
    } else if (_gpsError != null) {
      status = _gpsError!;
    } else if (p == null) {
      status = 'Ubicación no capturada';
    } else if (!widget.mission.requiresOnSite) {
      status = 'Misión sin presencia física: se registra tu ubicación actual';
    } else if (!_insideArea) {
      status = 'Fuera del área de la misión (a ${_distanceToMission!.round()} m del centro)';
    } else if (!_accuracyOk) {
      status = 'Precisión baja: espera unos segundos y actualiza';
    } else {
      status = widget.mission.radiusM == null ? 'Ubicación lista' : 'Dentro del área de la misión';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: HtColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.location_on, color: ok ? HtColors.green : HtColors.red),
          const SizedBox(width: 10),
          const Expanded(child: Text('Ubicación (GPS)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          if (ok) const Icon(Icons.check_circle, color: HtColors.green),
        ]),
        const SizedBox(height: 4),
        Text(status, style: TextStyle(color: ok ? HtColors.green : HtColors.text, fontWeight: FontWeight.w600)),
        if (p != null) ...[
          const Divider(height: 18),
          Row(children: [
            const Icon(Icons.my_location, size: 18, color: HtColors.navy),
            const SizedBox(width: 8),
            Expanded(child: Text('${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: HtColors.blueSoft, borderRadius: BorderRadius.circular(8)),
              child: Text('± ${p.accuracy.round()} m', style: const TextStyle(color: HtColors.blue, fontWeight: FontWeight.w600)),
            ),
          ]),
        ],
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (p != null)
            TextButton.icon(
              onPressed: _locating ? null : _openGpsReview,
              icon: Icon(_gpsConfirmed ? Icons.check_circle : Icons.map_outlined, size: 18),
              label: Text(_gpsConfirmed ? 'Punto confirmado' : 'Revisar en el mapa'),
            ),
          TextButton.icon(
            onPressed: _locating ? null : _locate,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar'),
          ),
        ]),
      ]),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.optional = false});
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
