import 'package:geolocator/geolocator.dart';

/// Telefonning hozirgi joylashuvi: ruxsat so'raydi, aniq koordinata qaytaradi. Ruxsat berilmasa yoki olinmasa — null va sabab.
class Fix {
  const Fix(this.lat, this.lng, this.acc);
  final double lat;
  final double lng;
  final double acc;
}

class FixResult {
  const FixResult.ok(Fix this.fix) : error = null;
  const FixResult.fail(String this.error) : fix = null;
  final Fix? fix;
  final String? error;
}

Future<FixResult> currentFix() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const FixResult.fail('Telefonda joylashuv (GPS) o\'chirilgan. Sozlamalardan yoqing.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return const FixResult.fail('Joylashuvga ruxsat berilmadi.');
    if (perm == LocationPermission.deniedForever) {
      return const FixResult.fail('Joylashuv ruxsati o\'chirilgan. Sozlamalar → Oftob Building → Joylashuv dan yoqing.');
    }
    final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
    return FixResult.ok(Fix(p.latitude, p.longitude, p.accuracy));
  } catch (_) {
    return const FixResult.fail('Joylashuvni aniqlab bo\'lmadi. Ochiq joyda qayta urinib ko\'ring.');
  }
}
