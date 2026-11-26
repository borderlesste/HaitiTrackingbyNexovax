import 'package:flutter/material.dart' hide Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:haiti_tracking/core/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('tr traduce textos exactos y con datos', () async {
    await Lang.set('fr');
    expect(tr('Mis aportes'), 'Mes contributions');
    expect(tr('Hola, Jean'), 'Bonjour, Jean');
    expect(tr('Aprobados (3)'), 'Approuvés (3)');
    expect(tr('Texto sin traducir'), 'Texto sin traducir');
    await Lang.set('ht');
    expect(tr('Mis aportes'), 'Kontribisyon m yo');
    await Lang.set('es');
    expect(tr('Mis aportes'), 'Mis aportes');
  });

  test('al instalar usa el idioma del teléfono si la app lo ofrece', () {
    expect(Lang.deviceLanguage(const [Locale('fr', 'HT')]), 'fr');
    expect(Lang.deviceLanguage(const [Locale('ht')]), 'ht');
    expect(Lang.deviceLanguage(const [Locale('de'), Locale('en', 'US')]), 'en');
    expect(Lang.deviceLanguage(const [Locale('pt', 'BR')]), 'es');
  });

  testWidgets('cambiar el idioma actualiza las pantallas abiertas', (tester) async {
    await Lang.set('es');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Mis aportes'))));
    expect(find.text('Mis aportes'), findsOneWidget);
    await tester.runAsync(() => Lang.set('en'));
    await tester.pump();
    expect(find.text('My contributions'), findsOneWidget);
    await tester.runAsync(() => Lang.set('es'));
  });
}
