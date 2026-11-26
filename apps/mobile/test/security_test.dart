import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haiti_tracking/core/evidence_upload.dart';
import 'package:haiti_tracking/features/auth/login_screen.dart';
import 'package:haiti_tracking/features/auth/recover_password_screen.dart';
import 'package:haiti_tracking/features/contributions/contribution_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'La cola separa cuentas, conserva borradores paralelos e ignora los v1 sin dueño',
      () async {
    const legacy = ['{"id":"sin-propietario"}'];
    SharedPreferences.setMockInitialValues(
        {'pending_contributions_v1': legacy});
    final store = DraftStore();
    final owner = _draft('a', 'one');
    final other = _draft('b', 'one');

    await Future.wait(
        [store.save(owner), store.save(_draft('a', 'two')), store.save(other)]);

    expect((await store.all('a')).map((draft) => draft.id),
        unorderedEquals(['one', 'two']));
    expect((await store.all('b')).single.userId, 'b');
    expect(await store.all('c'), isEmpty);
    await store.remove(owner);
    expect((await store.all('a')).single.id, 'two');
    expect((await store.all('b')).single.id, 'one');
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('pending_contributions_v1'),
        legacy);
  });

  test(
      'Recuperación por SMS no registra usuarios y responde igual ante estados de cuenta',
      () async {
    const phone = '+50937123456';
    for (final result in <AuthException?>[
      null,
      const AuthApiException('Account status', code: 'user_not_found'),
      const AuthApiException('Account status', code: 'signup_disabled'),
      const AuthApiException('Account status', code: 'user_banned'),
      const AuthApiException('Rate limit', statusCode: '429'),
      AuthRetryableFetchException(statusCode: '500'),
    ]) {
      final auth = _RecoveryAuth(result);
      await requestPasswordRecovery(auth, phone, byPhone: true);
      expect(auth.phone, phone);
      expect(auth.shouldCreateUser, isFalse);
    }
  });

  test(
      'Recuperación por correo usa el enlace existente y permite informar un fallo de red',
      () async {
    const email = 'account@example.invalid';
    final auth = _RecoveryAuth(
        const AuthApiException('Account status', code: 'user_not_found'));
    await requestPasswordRecovery(auth, email, byPhone: false);
    expect(auth.email, email);
    expect(auth.redirectTo, authRedirectUrl);

    await expectLater(
      requestPasswordRecovery(
          _RecoveryAuth(AuthRetryableFetchException()), email,
          byPhone: false),
      throwsA(isA<AuthRetryableFetchException>()),
    );
  });

  test(
      'Los archivos de evidencia deben contener datos y respetar el límite de 10 MiB',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('haiti-evidence-test');
    addTearDown(directory.delete);
    final file = await File('${directory.path}/photo.jpg').create();
    addTearDown(file.delete);
    await expectLater(inspectEvidence(file), throwsA(isA<InvalidEvidence>()));

    final handle = await file.open(mode: FileMode.write);
    addTearDown(handle.close);
    await handle.writeFrom([0xff, 0xd8, 0xff]);
    const ceiling = 10 * 1024 * 1024;
    await handle.truncate(ceiling);
    expect(await inspectEvidence(file), EvidenceType.jpeg);
    await handle.truncate(ceiling + 1);
    await expectLater(inspectEvidence(file), throwsA(isA<InvalidEvidence>()));
  });

  test('Las firmas determinan MIME y extensión según el flujo', () async {
    final directory =
        await Directory.systemTemp.createTemp('haiti-evidence-test');
    addTearDown(directory.delete);
    final file = await File('${directory.path}/photo.jpg').create();
    addTearDown(file.delete);

    await file.writeAsBytes([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    final picture = await inspectEvidence(file);
    expect(picture.extension, 'png');
    expect(picture.mimeType, 'image/png');

    await file.writeAsString('%PDF-1.7\n');
    await expectLater(inspectEvidence(file), throwsA(isA<InvalidEvidence>()));
    final document = await inspectEvidence(file, allowPdf: true);
    expect(document.extension, 'pdf');
    expect(document.mimeType, 'application/pdf');

    await file.writeAsString('not an image');
    await expectLater(
        inspectEvidence(file, allowPdf: true), throwsA(isA<InvalidEvidence>()));
    await file.writeAsBytes([0xff, 0xd8]);
    await expectLater(inspectEvidence(file), throwsA(isA<InvalidEvidence>()));
  });
}

ContributionDraft _draft(String userId, String id) => ContributionDraft(
      id: id,
      userId: userId,
      missionId: 'mission',
      missionTitle: 'Mission',
      name: 'Place',
      category: 'Shop',
      lat: 18.5,
      lng: -72.3,
      accuracyM: 5,
      capturedAt: DateTime.utc(2026),
      photoPath: '/photo.jpg',
    );

class _RecoveryAuth extends Fake implements GoTrueClient {
  _RecoveryAuth(this.result);

  final AuthException? result;
  String? phone;
  bool? shouldCreateUser;
  String? email;
  String? redirectTo;

  @override
  Future<void> signInWithOtp({
    String? email,
    String? phone,
    String? emailRedirectTo,
    bool? shouldCreateUser,
    Map<String, dynamic>? data,
    String? captchaToken,
    OtpChannel channel = OtpChannel.sms,
  }) async {
    this.phone = phone;
    this.shouldCreateUser = shouldCreateUser;
    if (result != null) throw result!;
  }

  @override
  Future<void> resetPasswordForEmail(String email,
      {String? redirectTo, String? captchaToken}) async {
    this.email = email;
    this.redirectTo = redirectTo;
    if (result != null) throw result!;
  }
}
