import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Actualizaciones desde Google Play: si hay una versión nueva se descarga en segundo plano
/// y se instala al terminar (Play muestra su propio aviso). Si la versión instalada es muy
/// vieja (prioridad alta en Play Console o 30 días sin actualizar) la actualización es obligatoria.
/// Fuera de Play (APK por USB) no hace nada.
class AppUpdate {
  AppUpdate._();

  static bool _checked = false;

  static Future<void> check() async {
    if (_checked || kIsWeb || !Platform.isAndroid || kDebugMode) return;
    _checked = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      final mustUpdate = (info.updatePriority >= 4 || (info.clientVersionStalenessDays ?? 0) >= 30) &&
          info.immediateUpdateAllowed;
      if (mustUpdate) {
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (_) {
      // Sin Play Store (instalación por USB o emulador): se ignora.
    }
  }
}
