import 'package:flutter_test/flutter_test.dart';
import 'package:haiti_tracking/features/missions/mission.dart';
import 'package:haiti_tracking/features/rewards/rewards_screen.dart';

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
      'radius_m': 800,
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
    expect(m.radiusM, 800);
    expect(m.point.latitude, 18.5401);
  });

  test('cents/money suman dinero sin errores de float', () {
    // 0.1 + 0.2 en float da 0.30000000000000004; en centavos es exacto.
    expect(cents('0.10') + cents(0.2), 30);
    expect(cents(0.25) * 5 + cents('1.00'), 225);
    expect(money(225), '\$2.25');
    expect(money(500 - 225), '\$2.75');
    expect(cents('-0.05'), -5);
    expect(cents(3), 300);
  });
}
