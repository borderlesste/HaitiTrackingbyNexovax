import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/evidence_upload.dart';
import 'contribution_draft.dart';

class DuplicateCandidate {
  DuplicateCandidate({
    required this.isPending,
    required this.name,
    required this.category,
    required this.distanceM,
    this.code,
    this.similarity = 0,
  });

  final bool isPending;
  final String? code;
  final String name;
  final String category;
  final double distanceM;

  /// Parecido del nombre (0 a 1).
  final double similarity;

  /// Muy probablemente el mismo lugar.
  bool get likelySame => similarity >= .5 || distanceM <= 12;
}

enum SubmitResult { sent, savedOffline }

class ContributionService {
  ContributionService({DraftStore? store}) : store = store ?? DraftStore();

  final DraftStore store;
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<DuplicateCandidate>> checkDuplicates(double lat, double lng, String name) async {
    final rows = await _db.rpc('check_duplicates', params: {'lat': lat, 'lng': lng, 'place_name': name}) as List<dynamic>;
    return rows.map((r) {
      final m = r as Map<String, dynamic>;
      return DuplicateCandidate(
        isPending: m['source'] == 'pending',
        code: m['code'] as String?,
        name: m['name'] as String,
        category: m['category'] as String,
        distanceM: (m['distance_m'] as num).toDouble(),
        similarity: (m['name_similarity'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  /// Intenta enviar; si no hay conexión lo deja guardado en el teléfono.
  Future<SubmitResult> submit(ContributionDraft d) async {
    try {
      await _send(d);
      await store.remove(d);
      return SubmitResult.sent;
    } on PostgrestException {
      // Errores de validación del servidor: no tiene sentido reintentar a ciegas.
      d.lastError = 'El servidor rechazó el aporte.';
      await store.save(d);
      rethrow;
    } on InvalidEvidence {
      rethrow;
    } catch (_) {
      d.lastError = 'Sin conexión';
      await store.save(d);
      return SubmitResult.savedOffline;
    }
  }

  /// Reintenta todos los pendientes. Devuelve cuántos se enviaron.
  Future<int> syncPending() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 0;
    var sent = 0;
    for (final d in await store.all(uid)) {
      if (_db.auth.currentUser?.id != uid) break;
      try {
        await _send(d);
        await store.remove(d);
        sent++;
      } catch (e) {
        d.lastError = switch (e) {
          PostgrestException() => 'El servidor rechazó el aporte.',
          InvalidEvidence(:final message) => message,
          _ => 'Sin conexión',
        };
        await store.save(d);
      }
    }
    return sent;
  }

  Future<void> _send(ContributionDraft d) async {
    final uid = d.userId;
    final file = File(d.photoPath);
    final type = await inspectEvidence(file);
    if (_db.auth.currentUser?.id != uid) throw const AuthException('La sesión cambió');

    // Antes todos los borradores usaban .jpg, incluso si contenían PNG.
    final extension = d.photoPath.endsWith('.jpg') ? 'jpg' : type.extension;
    final objectPath = '$uid/${d.id}.$extension';
    try {
      await _db.storage.from('evidence').upload(objectPath, file,
          fileOptions: FileOptions(contentType: type.mimeType));
    } on StorageException catch (e) {
      // Si ya se subió en un intento anterior, seguimos.
      final already = e.statusCode == '409' || e.message.toLowerCase().contains('exists');
      if (!already) rethrow;
    }

    if (_db.auth.currentUser?.id != uid) throw const AuthException('La sesión cambió');
    try {
      await _db.from('mission_contributions').insert({
        'idempotency_key': d.id,
        'user_id': uid,
        'mission_id': d.missionId,
        'name': d.name,
        'category': d.category,
        'address_reference': d.addressReference,
        'notes': [if (d.notes != null && d.notes!.isNotEmpty) d.notes, if (d.isMocked) '[aviso: ubicación simulada detectada]']
            .join(' '),
        'location': 'SRID=4326;POINT(${d.lng} ${d.lat})',
        'accuracy_m': double.parse(d.accuracyM.toStringAsFixed(2)),
        'captured_at': d.capturedAt.toUtc().toIso8601String(),
        'photo_paths': [objectPath],
      });
    } on PostgrestException catch (e) {
      // 23505 = ya existe ese aporte (reintento): se considera enviado.
      if (e.code != '23505') rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> myContributions() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _db
        .from('mission_contributions')
        .select('id, name, category, status, review_reason, created_at, photo_paths, mission_id, address_reference, '
            'missions(title, commune, individual_reward_usd, completion_bonus_usd, required_approved_contributions, open_contribution)')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// URLs temporales de las fotos (el bucket de evidencias es privado).
  Future<Map<String, String>> photoUrls(Iterable<String> paths) async {
    final list = paths.toSet().toList();
    if (list.isEmpty) return const {};
    try {
      final signed = await _db.storage.from('evidence').createSignedUrls(list, 3600);
      return {for (final s in signed) s.path: s.signedUrl};
    } catch (_) {
      return const {};
    }
  }
}

/// Estado del aporte → (texto, tono) para las etiquetas.
const contributionStatusLabels = {
  'SUBMITTED': 'En revisión',
  'AUTO_CHECKED': 'En revisión',
  'HUMAN_REVIEW': 'En revisión',
  'APPROVED': 'Aprobado',
  'REJECTED': 'Rechazado',
  'NEEDS_CHANGES': 'Requiere cambios',
  'APPEALED': 'Apelado',
};

bool isInReview(String? s) => s == 'SUBMITTED' || s == 'AUTO_CHECKED' || s == 'HUMAN_REVIEW' || s == 'APPEALED';

/// Primera foto del aporte, si tiene.
String? firstPhoto(Map<String, dynamic> c) {
  final p = c['photo_paths'];
  if (p is List && p.isNotEmpty) return p.first as String;
  return null;
}

extension MissionContributions on ContributionService {
  /// Aportes del usuario en una misión (para "Aporte 2 de 5" y el progreso).
  Future<List<Map<String, dynamic>>> missionContributions(String missionId) async {
    final rows = await Supabase.instance.client
        .from('mission_contributions')
        .select('id, name, category, status, created_at, photo_paths')
        .eq('mission_id', missionId)
        .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }
}

/// Punto (lat, lng) de una columna geography que PostgREST devuelve como EWKB en hexadecimal.
(double, double)? parseEwkbPoint(Object? v) {
  if (v is Map && v['coordinates'] is List) {
    final c = v['coordinates'] as List;
    return ((c[1] as num).toDouble(), (c[0] as num).toDouble());
  }
  if (v is! String || v.length < 42) return null;
  try {
    final bytes = <int>[for (var i = 0; i + 1 < v.length; i += 2) int.parse(v.substring(i, i + 2), radix: 16)];
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final endian = bytes[0] == 1 ? Endian.little : Endian.big;
    final type = data.getUint32(1, endian);
    var offset = 5;
    if (type & 0x20000000 != 0) offset += 4; // SRID
    if (type & 0xFF != 1) return null; // solo puntos
    final x = data.getFloat64(offset, endian);
    final y = data.getFloat64(offset + 8, endian);
    return (y, x);
  } catch (_) {
    return null;
  }
}

extension ContributionDetail on ContributionService {
  /// Un aporte propio con todos sus datos.
  Future<Map<String, dynamic>> contribution(String id) async {
    final row = await Supabase.instance.client
        .from('mission_contributions')
        .select('*, missions(id, code, type, title, description, commune, radius_m, individual_reward_usd, '
            'completion_bonus_usd, required_approved_contributions, requirements, end_at, center, requires_on_site_evidence, '
            'open_contribution)')
        .eq('id', id)
        .single();
    return Map<String, dynamic>.from(row);
  }
}
