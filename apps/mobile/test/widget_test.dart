import 'package:flutter_test/flutter_test.dart';
import 'package:haiti_tracking/features/missions/mission.dart';

void main() {
  test('Mission.fromRow lee montos exactos y coordenadas', () {
    final m = Mission.fromRow({
      'id': 'x',
      'code': 'MIS-DEL-0001',
      'type': 'BATCH_ZONE',
      'title': 'Documentar cinco comercios',
      'description': '',
      'commune': 'Delmas',
      'lat': 18.5401,
      'lng': -72.2973,
      'individual_reward_usd': 0.25,
      'completion_bonus_usd': 1,
      'required_approved_contributions': 5,
      'requirements': 'GPS + foto',
      'end_at': null,
      'distance_m': 1200.5,
    });
    expect(m.rewardUsd, '0.25');
    expect(m.bonusUsd, '1.00');
    expect(m.hasBonus, isTrue);
    expect(m.point.latitude, 18.5401);
  });
}
