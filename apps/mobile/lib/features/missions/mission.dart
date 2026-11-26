import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/money.dart';

class Mission {
  Mission({
    required this.id,
    required this.code,
    required this.type,
    required this.title,
    required this.description,
    required this.commune,
    required this.point,
    required this.radiusM,
    required this.rewardUsd,
    required this.bonusUsd,
    required this.requiredContributions,
    required this.requirements,
    required this.endAt,
    required this.distanceM,
    this.requiresOnSite = true,
  });

  final String id;
  final String code;
  final String type;
  final String title;
  final String description;
  final String? commune;
  final LatLng point;
  final int? radiusM;
  // Los montos llegan de numeric como texto o número; se muestran tal cual, sin cálculos en float.
  final String rewardUsd;
  final String bonusUsd;
  final int requiredContributions;
  final String requirements;
  final DateTime? endAt;
  final double distanceM;
  /// Si es false (misiones remotas o de prueba), la app no exige estar dentro del área.
  final bool requiresOnSite;

  bool get isPriority => type == 'PRIORITY_PLACE';
  bool get hasBonus => bonusUsd != '0' && bonusUsd != '0.00';

  int get rewardCents => cents(rewardUsd);
  int get bonusCents => cents(bonusUsd);

  /// Todo lo que se puede ganar: cada aporte aprobado + bono por completar.
  int get totalCents => rewardCents * requiredContributions + bonusCents;

  factory Mission.fromRow(Map<String, dynamic> r) => Mission(
        id: r['id'] as String,
        code: r['code'] as String,
        type: r['type'] as String,
        title: r['title'] as String,
        description: (r['description'] ?? '') as String,
        commune: r['commune'] as String?,
        point: LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
        radiusM: (r['radius_m'] as num?)?.toInt(),
        rewardUsd: _money(r['individual_reward_usd']),
        bonusUsd: _money(r['completion_bonus_usd']),
        requiredContributions: (r['required_approved_contributions'] as num).toInt(),
        requirements: (r['requirements'] ?? '') as String,
        endAt: r['end_at'] == null ? null : DateTime.parse(r['end_at'] as String),
        distanceM: (r['distance_m'] as num).toDouble(),
        requiresOnSite: (r['requires_on_site_evidence'] ?? true) as bool,
      );

  static String _money(Object? v) {
    final s = v.toString();
    if (!s.contains('.')) return '$s.00';
    final parts = s.split('.');
    return '${parts[0]}.${parts[1].padRight(2, '0').substring(0, 2)}';
  }
}

/// Centro de Port-au-Prince: se usa si el usuario no comparte su ubicación.
const portAuPrince = LatLng(18.5392, -72.3350);

class MissionsRepository {
  final _db = Supabase.instance.client;

  Future<List<Mission>> nearby(LatLng center, {double radiusKm = 25}) async {
    final rows = await _db.rpc('missions_nearby', params: {
      'lat': center.latitude,
      'lng': center.longitude,
      'radius_km': radiusKm,
    }) as List<dynamic>;
    return rows.map((r) => Mission.fromRow(r as Map<String, dynamic>)).toList();
  }
}

/// Total posible de la misión sin el símbolo: "2.25".
String missionTotal(Mission m) => money(m.totalCents).substring(1);

/// Misión a partir de la fila de `missions` (con `center` en EWKB) que llega unida a un aporte.
Mission? missionFromJoin(Map<String, dynamic>? r, (double, double)? Function(Object?) parsePoint) {
  if (r == null) return null;
  final pt = parsePoint(r['center']);
  if (pt == null) return null;
  return Mission.fromRow({
    ...r,
    'code': r['code'] ?? '',
    'type': r['type'] ?? 'BATCH_ZONE',
    'lat': pt.$1,
    'lng': pt.$2,
    'distance_m': 0,
  });
}
