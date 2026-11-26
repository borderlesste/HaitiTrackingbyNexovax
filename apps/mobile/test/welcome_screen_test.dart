import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haiti_tracking/features/auth/welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('La bienvenida muestra el lema, los botones y cambia de idioma', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(412, 846));
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    await tester.pump();

    expect(find.text('El mapa colaborativo\nde direcciones de Haití'), findsOneWidget);
    expect(find.text('Comenzar'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);

    await tester.tap(find.text('ES'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Français').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Commencer'), findsOneWidget);
    expect(find.text('FR'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_lang'), 'fr');
  });
}
