import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/evidence_upload.dart';

/// Acceso a datos de la experiencia Empresa. Los permisos los comprueba siempre el servidor (RLS y funciones).
class CompanyRepo {
  SupabaseClient get _db => Supabase.instance.client;
  String get uid => _db.auth.currentUser!.id;

  Future<Map<String, dynamic>?> myOrganization() async {
    final rows = await _db.from('organizations').select().order('created_at').limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> register(Map<String, String?> f) => _db.rpc('register_organization', params: {
        'p_name': f['name'],
        'p_sector': f['sector'],
        'p_representative': f['representative'],
        'p_legal_id': f['legal_id'],
        'p_phone': f['phone'],
        'p_email': f['email'],
        'p_address': f['address'],
        'p_commune': f['commune'],
      });

  Future<void> updateRegistration(String orgId, Map<String, String?> f) =>
      _db.rpc('update_organization_registration', params: {
        'p_org': orgId,
        'p_name': f['name'],
        'p_sector': f['sector'],
        'p_representative': f['representative'],
        'p_legal_id': f['legal_id'],
        'p_phone': f['phone'],
        'p_email': f['email'],
        'p_address': f['address'],
        'p_commune': f['commune'],
        'p_website': f['website'],
      });

  Future<void> updateContact(String orgId, {String? phone, String? email, String? address, String? website}) =>
      _db.from('organizations').update({
        'contact_phone': phone,
        'contact_email': email,
        'address': address,
        'website': website,
      }).eq('id', orgId);

  // --- Documentos de verificación -----------------------------------------
  Future<List<Map<String, dynamic>>> documents(String orgId) async =>
      List.from(await _db.from('organization_documents').select().eq('org_id', orgId).order('created_at', ascending: false));

  Future<void> uploadDocument(String orgId, String docType, File file, String fileName) async {
    final userId = uid;
    final type = await inspectEvidence(file, allowPdf: true);
    final path = '$userId/org-docs/${const Uuid().v4()}.${type.extension}';
    await _db.storage.from('evidence').upload(path, file,
        fileOptions: FileOptions(contentType: type.mimeType));
    await _db.from('organization_documents').insert({
      'org_id': orgId,
      'doc_type': docType,
      'storage_path': path,
      'file_name': fileName,
      'uploaded_by': userId,
    });
  }

  // --- Establecimientos ----------------------------------------------------
  Future<List<Map<String, dynamic>>> establishments(String orgId) async =>
      List.from(await _db.from('org_establishments_view').select().eq('org_id', orgId).order('created_at', ascending: false));

  Future<List<Map<String, dynamic>>> claims(String orgId) async =>
      List.from(await _db.from('place_claims_view').select().eq('org_id', orgId).order('created_at', ascending: false));

  Future<String> uploadPhoto(File file) async {
    final userId = uid;
    final type = await inspectEvidence(file);
    final path = '$userId/establishments/${const Uuid().v4()}.${type.extension}';
    await _db.storage.from('evidence').upload(path, file, fileOptions: FileOptions(contentType: type.mimeType));
    return path;
  }

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

  Future<String> saveEstablishment({
    String? id,
    required String orgId,
    required String name,
    required String category,
    required double lat,
    required double lng,
    double? accuracyM,
    String description = '',
    String? address,
    String? commune,
    String? phone,
    String? hours,
    required List<String> photoPaths,
  }) async {
    final r = await _db.rpc('save_establishment', params: {
      'p_id': id,
      'p_org': orgId,
      'p_name': name,
      'p_category': category,
      'p_lat': lat,
      'p_lng': lng,
      'p_accuracy_m': accuracyM == null ? null : double.parse(accuracyM.toStringAsFixed(2)),
      'p_description': description,
      'p_address': address,
      'p_commune': commune,
      'p_phone': phone,
      'p_opening_hours': hours,
      'p_photo_paths': photoPaths,
    });
    return r as String;
  }

  Future<List<Map<String, dynamic>>> searchPlaces(String q) async {
    final clean = q.trim().replaceAll(RegExp(r'[,()%*]'), ' ');
    if (clean.length < 2) return const [];
    return List.from(await _db.from('places').select('id, code, name, category, commune').or('code.ilike.%$clean%,name.ilike.%$clean%').limit(30));
  }

  Future<void> claimPlace(String orgId, String placeId, String? evidence) =>
      _db.from('place_claims').insert({'org_id': orgId, 'place_id': placeId, 'evidence': evidence});

  // --- Misiones solicitadas ------------------------------------------------
  Future<List<Map<String, dynamic>>> missionRequests(String orgId) async =>
      List.from(await _db.from('campaign_requests_view').select().eq('org_id', orgId).order('created_at', ascending: false));

  Future<void> requestMission(Map<String, dynamic> values) => _db.from('campaign_requests').insert(values);

  // --- Usuarios autorizados -----------------------------------------------
  Future<List<Map<String, dynamic>>> members(String orgId) async =>
      List.from(await _db.from('organization_members_view').select().eq('org_id', orgId).order('created_at'));

  Future<void> addMember(String orgId, String contact) =>
      _db.rpc('add_organization_member', params: {'p_org': orgId, 'p_contact': contact});

  Future<void> removeMember(String orgId, String userId) =>
      _db.rpc('remove_organization_member', params: {'p_org': orgId, 'p_user': userId});
}

const companySectors = ['Comercio', 'Salud', 'Alimentación', 'Transporte', 'Banca y finanzas', 'Educación', 'Logística', 'Turismo', 'Otro'];

const orgDocTypes = {
  'LEGAL_REGISTRATION': 'Registro de comercio / patente',
  'TAX_ID': 'Número fiscal (NIF)',
  'REPRESENTATIVE_ID': 'Identificación del representante',
  'PROOF_OF_ADDRESS': 'Comprobante de dirección',
  'OTHER': 'Otro documento',
};
