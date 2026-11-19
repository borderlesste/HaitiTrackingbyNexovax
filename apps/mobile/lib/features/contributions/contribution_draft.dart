import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Aporte creado en el teléfono. Su [id] se usa como clave de idempotencia:
/// reenviarlo nunca crea un segundo aporte en el servidor.
class ContributionDraft {
  ContributionDraft({
    required this.id,
    required this.missionId,
    required this.missionTitle,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.capturedAt,
    required this.photoPath,
    this.addressReference,
    this.notes,
    this.isMocked = false,
    this.lastError,
  });

  final String id;
  final String missionId;
  final String missionTitle;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final double accuracyM;
  final DateTime capturedAt;
  final String photoPath;
  final String? addressReference;
  final String? notes;
  final bool isMocked;
  String? lastError;

  Map<String, dynamic> toJson() => {
        'id': id,
        'missionId': missionId,
        'missionTitle': missionTitle,
        'name': name,
        'category': category,
        'lat': lat,
        'lng': lng,
        'accuracyM': accuracyM,
        'capturedAt': capturedAt.toIso8601String(),
        'photoPath': photoPath,
        'addressReference': addressReference,
        'notes': notes,
        'isMocked': isMocked,
        'lastError': lastError,
      };

  factory ContributionDraft.fromJson(Map<String, dynamic> j) => ContributionDraft(
        id: j['id'] as String,
        missionId: j['missionId'] as String,
        missionTitle: (j['missionTitle'] ?? '') as String,
        name: j['name'] as String,
        category: j['category'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        accuracyM: (j['accuracyM'] as num).toDouble(),
        capturedAt: DateTime.parse(j['capturedAt'] as String),
        photoPath: j['photoPath'] as String,
        addressReference: j['addressReference'] as String?,
        notes: j['notes'] as String?,
        isMocked: (j['isMocked'] ?? false) as bool,
        lastError: j['lastError'] as String?,
      );
}

/// Aportes pendientes de enviar, guardados en el teléfono (para zonas sin conexión).
class DraftStore {
  static const _key = 'pending_contributions_v1';

  Future<List<ContributionDraft>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    return raw.map((s) => ContributionDraft.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
  }

  Future<void> save(ContributionDraft d) async {
    final list = (await all()).where((x) => x.id != d.id).toList()..add(d);
    await _write(list);
  }

  Future<void> remove(String id) async {
    await _write((await all()).where((x) => x.id != id).toList());
  }

  Future<void> _write(List<ContributionDraft> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, list.map((d) => jsonEncode(d.toJson())).toList());
  }
}

const placeCategories = [
  'Tienda / Mini Market',
  'Restaurante / Comida',
  'Farmacia',
  'Clínica / Hospital',
  'Escuela',
  'Iglesia / Templo',
  'Banco / Casa de cambio',
  'Gasolinera',
  'Taller / Ferretería',
  'Oficina pública',
  'Mercado',
  'Otro',
];
