import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/contribution_draft.dart' show placeCategories;
import '../contributions/gps.dart';
import '../missions/mission.dart' show portAuPrince;
import 'company_repo.dart';

/// Pantallas 19 y 20: Registrar / Editar establecimiento (nombre, dirección, categoría, GPS y fotografías).
/// Cada guardado vuelve a revisión del equipo antes de publicarse en el mapa.
class EstablishmentFormScreen extends StatefulWidget {
  const EstablishmentFormScreen({super.key, required this.orgId, this.existing});
  final String orgId;
  final Map<String, dynamic>? existing;

  @override
  State<EstablishmentFormScreen> createState() => _EstablishmentFormScreenState();
}

class _EstablishmentFormScreenState extends State<EstablishmentFormScreen> {
  final _repo = CompanyRepo();
  final _form = GlobalKey<FormState>();
  final _map = MapController();
  Map<String, dynamic>? get _e => widget.existing;
  late final _name = TextEditingController(text: _e?['name'] as String?);
  late final _desc = TextEditingController(text: _e?['description'] as String?);
  late final _address = TextEditingController(text: _e?['address'] as String?);
  late final _phone = TextEditingController(text: (_e?['phone'] as String?)?.replaceFirst('+509', ''));
  late final _hours = TextEditingController(text: _e?['opening_hours'] as String?);
  late String? _category = placeCategories.contains(_e?['category']) ? _e!['category'] as String : null;
  late String? _commune = haitiCommunes.contains(_e?['commune']) ? _e!['commune'] as String : null;
  late LatLng? _point = _e == null ? null : LatLng((_e!['lat'] as num).toDouble(), (_e!['lng'] as num).toDouble());
  double? _accuracy;
  bool _fromGps = false;
  late final List<String> _remotePhotos = List<String>.from(_e?['photo_paths'] as List? ?? const []);
  final List<File> _newPhotos = [];
  Map<String, String> _urls = const {};
  bool _locating = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo.photoUrls(_remotePhotos).then((u) {
      if (mounted) setState(() => _urls = u);
    });
  }

  Future<void> _useGps() async {
    setState(() => _locating = true);
    try {
      final p = await captureBestPosition();
      setState(() {
        _point = LatLng(p.latitude, p.longitude);
        _accuracy = p.accuracy;
        _fromGps = true;
      });
      _map.move(_point!, 17);
    } catch (e) {
      if (mounted) snack(context, e is String ? e : 'No se pudo obtener la ubicación.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_remotePhotos.length + _newPhotos.length >= 5) return snack(context, 'Máximo 5 fotos.');
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 70);
    if (picked != null) setState(() => _newPhotos.add(File(picked.path)));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_point == null) return setState(() => _error = 'Marca la ubicación en el mapa o usa el GPS.');
    if (_remotePhotos.isEmpty && _newPhotos.isEmpty) return setState(() => _error = 'Agrega al menos una foto del frente del local.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uploaded = <String>[];
      for (final f in _newPhotos) {
        uploaded.add(await _repo.uploadPhoto(f));
      }
      await _repo.saveEstablishment(
        id: _e?['id'] as String?,
        orgId: widget.orgId,
        name: _name.text.trim(),
        category: _category!,
        lat: _point!.latitude,
        lng: _point!.longitude,
        accuracyM: _fromGps ? _accuracy : (_e?['accuracy_m'] as num?)?.toDouble(),
        description: _desc.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        commune: _commune,
        phone: normalizeHaitiPhone(_phone.text),
        hours: _hours.text.trim().isEmpty ? null : _hours.text.trim(),
        photoPaths: [..._remotePhotos, ...uploaded],
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => _SavedScreen(name: _name.text.trim(), editing: _e != null)));
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo guardar. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _e != null;
    return HtScaffold(
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            ScreenTitle(editing ? 'Editar establecimiento' : 'Registrar establecimiento',
                icon: editing ? Icons.edit_location_alt_outlined : Icons.add_business_outlined,
                subtitle: editing ? 'Los cambios se revisan antes de publicarse.' : 'Tu negocio aparecerá en el mapa tras la revisión.'),
            if (editing && _e!['status'] == 'REJECTED' && _e!['review_reason'] != null) ...[
              const SizedBox(height: 12),
              InfoBanner('Motivo del rechazo: ${_e!['review_reason']}', warning: true),
            ],
            const SizedBox(height: 8),
            const FieldLabel('Nombre del establecimiento', required: true),
            TextFormField(controller: _name, decoration: const InputDecoration(prefixIcon: Icon(Icons.storefront_outlined)),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Obligatorio' : null),
            const FieldLabel('Categoría', required: true),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined)),
              hint: const Text('Elige la categoría'),
              items: [for (final c in placeCategories) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _category = v),
              validator: (v) => v == null ? 'Elige la categoría' : null,
            ),
            const FieldLabel('Dirección / referencia'),
            TextFormField(controller: _address, decoration: const InputDecoration(prefixIcon: Icon(Icons.signpost_outlined), hintText: 'Ej.: Rue Delmas 33, frente al mercado')),
            const FieldLabel('Comuna', required: true),
            DropdownButtonFormField<String>(
              initialValue: _commune,
              isExpanded: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.location_city_outlined)),
              hint: const Text('Elige la comuna'),
              items: [for (final c in haitiCommunes) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _commune = v),
              validator: (v) => v == null ? 'Elige la comuna' : null,
            ),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const FieldLabel('Teléfono'),
                  TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(prefixText: '+509 ')),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const FieldLabel('Horario'),
                  TextFormField(controller: _hours, decoration: const InputDecoration(hintText: 'Lun–Sáb 8–18 h')),
                ]),
              ),
            ]),
            const FieldLabel('Descripción'),
            TextFormField(controller: _desc, maxLines: 2, decoration: const InputDecoration(hintText: 'Opcional')),
            const FieldLabel('Ubicación (GPS)', required: true),
            const Text('Toca el mapa para marcar la entrada del local, o usa el GPS si estás allí.', style: TextStyle(color: HtColors.muted)),
            const SizedBox(height: 8),
            SizedBox(
              height: 230,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _point ?? portAuPrince,
                    initialZoom: _point == null ? 13 : 17,
                    onTap: (_, p) => setState(() {
                      _point = p;
                      _fromGps = false;
                    }),
                  ),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.nexovax.haititracking'),
                    if (_point != null)
                      MarkerLayer(markers: [
                        Marker(point: _point!, width: 44, height: 44, alignment: Alignment.topCenter, child: const Icon(Icons.location_on, color: HtColors.red, size: 44)),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            HtCard(
              color: _point == null ? Colors.white : HtColors.greenSoft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Icon(Icons.my_location, color: _point == null ? HtColors.muted : HtColors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _point == null
                        ? 'Sin ubicación'
                        : '${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)}'
                            '${_fromGps && _accuracy != null ? '  ±${_accuracy!.round()} m' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _locating ? null : _useGps,
                  icon: _locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.gps_fixed),
                  label: const Text('Usar GPS'),
                ),
              ]),
            ),
            const FieldLabel('Fotografías', required: true),
            SizedBox(
              height: 96,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final p in _remotePhotos)
                  _Thumb(
                    image: _urls[p] == null ? null : NetworkImage(_urls[p]!),
                    onRemove: () => setState(() => _remotePhotos.remove(p)),
                  ),
                for (final f in _newPhotos) _Thumb(image: FileImage(f), onRemove: () => setState(() => _newPhotos.remove(f))),
                _AddPhoto(onCamera: () => _addPhoto(ImageSource.camera), onGallery: () => _addPhoto(ImageSource.gallery)),
              ]),
            ),
            const SizedBox(height: 6),
            const Text('Frente del local con el letrero visible. Sin personas identificables.', style: TextStyle(color: HtColors.muted, fontSize: 13)),
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: HtColors.red))],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(editing ? 'Guardar cambios' : 'Enviar a revisión'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.onRemove});
  final ImageProvider? image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 96,
            height: 96,
            color: HtColors.blueSoft,
            child: image == null ? const Icon(Icons.image_outlined, color: HtColors.blue) : Image(image: image!, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: InkWell(
            onTap: onRemove,
            child: const CircleAvatar(radius: 12, backgroundColor: Colors.white, child: Icon(Icons.close, size: 16, color: HtColors.text)),
          ),
        ),
      ]),
    );
  }
}

class _AddPhoto extends StatelessWidget {
  const _AddPhoto({required this.onCamera, required this.onGallery});
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto'), onTap: () {
              Navigator.pop(ctx);
              onCamera();
            }),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de galería'), onTap: () {
              Navigator.pop(ctx);
              onGallery();
            }),
          ]),
        ),
      ),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HtColors.blue, width: 1.4),
        ),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_a_photo_outlined, color: HtColors.blue),
          SizedBox(height: 4),
          Text('Agregar', style: TextStyle(color: HtColors.blue, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _SavedScreen extends StatelessWidget {
  const _SavedScreen({required this.name, required this.editing});
  final String name;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    return HtScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        children: [
          const Center(child: SuccessMark()),
          const SizedBox(height: 12),
          Text(editing ? '¡Cambios enviados!' : '¡Establecimiento enviado!',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('"$name" está en revisión. Aparecerá en el mapa cuando el equipo lo apruebe.',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: HtColors.muted, height: 1.4)),
          const SizedBox(height: 20),
          const HtCard(child: KvRow('Estado', '', icon: Icons.schedule, trailing: StatusChip('En revisión', tone: ChipTone.review))),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.list),
            label: const Text('Ver mis establecimientos'),
          ),
        ],
      ),
    );
  }
}
