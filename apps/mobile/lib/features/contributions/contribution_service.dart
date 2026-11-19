import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'contribution_draft.dart';

class DuplicateCandidate {
  DuplicateCandidate({required this.isPending, required this.name, required this.category, required this.distanceM, this.code});

  final bool isPending;
  final String? code;
  final String name;
  final String category;
  final double distanceM;
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
      );
    }).toList();
  }

  /// Intenta enviar; si no hay conexión lo deja guardado en el teléfono.
  Future<SubmitResult> submit(ContributionDraft d) async {
    try {
      await _send(d);
      await store.remove(d.id);
      return SubmitResult.sent;
    } on PostgrestException catch (e) {
      // Errores de validación del servidor: no tiene sentido reintentar a ciegas.
      d.lastError = e.message;
      await store.save(d);
      rethrow;
    } catch (e) {
      d.lastError = 'Sin conexión';
      await store.save(d);
      return SubmitResult.savedOffline;
    }
  }

  /// Reintenta todos los pendientes. Devuelve cuántos se enviaron.
  Future<int> syncPending() async {
    var sent = 0;
    for (final d in await store.all()) {
      try {
        await _send(d);
        await store.remove(d.id);
        sent++;
      } catch (e) {
        d.lastError = e is PostgrestException ? e.message : 'Sin conexión';
        await store.save(d);
      }
    }
    return sent;
  }

  Future<void> _send(ContributionDraft d) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Sesión no iniciada');

    final objectPath = '$uid/${d.id}.jpg';
    try {
      await _db.storage.from('evidence').upload(objectPath, File(d.photoPath),
          fileOptions: const FileOptions(contentType: 'image/jpeg'));
    } on StorageException catch (e) {
      // Si ya se subió en un intento anterior, seguimos.
      final already = e.statusCode == '409' || e.message.toLowerCase().contains('exists');
      if (!already) rethrow;
    }

    try {
      await _db.from('mission_contributions').insert({
        'idempotency_key': d.id,
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
    final rows = await _db
        .from('mission_contributions')
        .select('id, name, category, status, review_reason, created_at, missions(title)')
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }
}
