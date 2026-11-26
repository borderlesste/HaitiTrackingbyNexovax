import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso a datos del Desarrollador. Las claves secretas nunca se guardan en la app ni en la base:
/// el servidor guarda solo su hash y devuelve el secreto una única vez al crearlo o rotarlo.
class DeveloperRepo {
  SupabaseClient get _db => Supabase.instance.client;
  String get uid => _db.auth.currentUser!.id;

  Future<Map<String, dynamic>?> profile() async =>
      await _db.from('developer_profiles').select().eq('user_id', uid).maybeSingle();

  Future<void> register({required String name, required String useCase, String? company, String? country, String? website}) =>
      _db.rpc('register_developer', params: {
        'p_display_name': name,
        'p_use_case': useCase,
        'p_accept_terms': true,
        'p_company': company,
        'p_country': country,
        'p_website': website,
      });

  Future<void> updateProfile(Map<String, dynamic> values) => _db.from('developer_profiles').update(values).eq('user_id', uid);

  Future<List<Map<String, dynamic>>> projects() async =>
      List.from(await _db.from('api_projects').select().eq('owner_id', uid).order('created_at'));

  Future<void> createProject(String name, String use, String environment) => _db.rpc('create_api_project',
      params: {'p_name': name, 'p_intended_use': use, 'p_accept_terms': true, 'p_environment': environment});

  Future<void> updateProject(String id, String name, String use) =>
      _db.rpc('update_api_project', params: {'p_project': id, 'p_name': name, 'p_intended_use': use});

  Future<List<Map<String, dynamic>>> keys(String projectId) async => List.from(await _db
      .from('developer_api_keys')
      .select('id, project_id, prefix, created_at, revoked_at, last_used_at')
      .eq('project_id', projectId)
      .order('created_at', ascending: false));

  Future<List<Map<String, dynamic>>> allKeys(List<String> projectIds) async {
    if (projectIds.isEmpty) return const [];
    return List.from(await _db
        .from('developer_api_keys')
        .select('id, project_id, prefix, created_at, revoked_at, last_used_at')
        .inFilter('project_id', projectIds)
        .order('created_at', ascending: false));
  }

  Future<String> createKey(String projectId) async => await _db.rpc('create_api_key', params: {'p_project': projectId}) as String;
  Future<String> rotateKey(String keyId) async => await _db.rpc('rotate_api_key', params: {'p_key': keyId}) as String;
  Future<void> revokeKey(String keyId) => _db.rpc('revoke_api_key', params: {'p_key': keyId});

  /// Consumo de los últimos [days] días de los proyectos dados.
  Future<List<Map<String, dynamic>>> usage(List<String> projectIds, {int days = 30}) async {
    if (projectIds.isEmpty) return const [];
    final from = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(Duration(days: days - 1)));
    return List.from(await _db.from('api_usage').select().inFilter('project_id', projectIds).gte('day', from).order('day'));
  }

  Future<List<dynamic>> testNearby(String projectId, double lat, double lng, double radius, int limit) async =>
      await _db.rpc('api_test_places_nearby',
          params: {'p_project': projectId, 'p_lat': lat, 'p_lng': lng, 'p_radius_m': radius, 'p_limit': limit}) as List<dynamic>;
}

String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

/// Suma por día: {yyyy-MM-dd: (solicitudes, errores)}.
Map<String, (int, int)> usageByDay(List<Map<String, dynamic>> rows, {String? projectId}) {
  final out = <String, (int, int)>{};
  for (final r in rows) {
    if (projectId != null && r['project_id'] != projectId) continue;
    final d = r['day'] as String;
    final prev = out[d] ?? (0, 0);
    out[d] = (prev.$1 + (r['requests'] as num).toInt(), prev.$2 + ((r['errors'] as num?) ?? 0).toInt());
  }
  return out;
}

List<DateTime> lastDays(int n) {
  final now = DateTime.now();
  return [for (var i = n - 1; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
}
