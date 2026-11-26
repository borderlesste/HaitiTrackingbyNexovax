import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Aporte creado en el teléfono. Su [id] se usa como clave de idempotencia:
/// reenviarlo nunca crea un segundo aporte en el servidor.
class ContributionDraft {
  ContributionDraft({
    required this.id,
    required this.userId,
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
  final String userId;
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
        'userId': userId,
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
        userId: j['userId'] as String,
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
  // Los borradores v1 no guardaban su propietario y no se pueden reasignar.
  String _prefix(String userId) => 'pending_contributions_v2:$userId:';
  String _key(ContributionDraft draft) => '${_prefix(draft.userId)}${draft.id}';

  Future<List<ContributionDraft>> all(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _prefix(userId);
    return prefs.getKeys().where((key) => key.startsWith(prefix)).map((key) {
      return ContributionDraft.fromJson(jsonDecode(prefs.getString(key)!) as Map<String, dynamic>);
    }).where((draft) => draft.userId == userId).toList();
  }

  Future<void> save(ContributionDraft d) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key(d), jsonEncode(d.toJson()))) {
      throw StateError('No se pudo guardar el aporte en el teléfono.');
    }
  }

  Future<void> remove(ContributionDraft d) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(d));
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
