import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../missions/mission.dart';

/// Precisión máxima aceptada para enviar (metros).
const maxAccuracyM = 30.0;

/// Pide permiso y toma la mejor posición posible. Lanza un texto legible si no se puede.
Future<Position> captureBestPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw 'Activa la ubicación (GPS) del teléfono.';
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    throw 'Necesitamos tu ubicación solo para confirmar que estás en el lugar.';
  }
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 25)),
    );
  } catch (_) {
    throw 'No se pudo obtener la ubicación. Inténtalo al aire libre.';
  }
}

/// Resultado de comprobar un punto contra la misión.
class GpsCheck {
  GpsCheck(this.mission, this.position);
  final Mission mission;
  final Position position;

  LatLng get point => LatLng(position.latitude, position.longitude);

  double get distanceToCenter => const Distance().as(LengthUnit.Meter, mission.point, point);

  bool get accuracyOk => !mission.requiresOnSite || position.accuracy <= maxAccuracyM;

  bool get insideArea {
    if (!mission.requiresOnSite) return true;
    final r = mission.radiusM;
    if (r == null) return true;
    return distanceToCenter <= r + position.accuracy;
  }

  bool get notMocked => !position.isMocked;

  bool get ok => accuracyOk && insideArea && notMocked;
}
