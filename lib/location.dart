import 'package:geolocator/geolocator.dart';

/// Telefonning hozirgi joylashuvi: ruxsat so'raydi, aniq koordinata qaytaradi. Ruxsat berilmasa yoki olinmasa — null va sabab.
class Fix {
  const Fix(this.lat, this.lng, this.acc, {this.mocked = false});
  final double lat;
  final double lng;
  final double acc;

  /// Soxta joylashuv (Fake GPS ilovasi, emulyator): Android — isMocked, iOS 15+ — isSimulatedBySoftware
  final bool mocked;
}

class FixResult {
  const FixResult.ok(Fix this.fix) : error = null;
  const FixResult.fail(String this.error) : fix = null;
  final Fix? fix;
  final String? error;
}

/// [real] — «Keldim» uchun: soxta joylashuv (Fake GPS) qabul qilinmaydi, joylashuv har safar yangidan o'lchanadi
Future<FixResult> currentFix({bool real = false}) async {
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
    if (real && p.isMocked) {
      return const FixResult.fail("Telefonda soxta joylashuv (Fake GPS) yoqilgan. Uni o'chiring — «Keldim» faqat haqiqiy joylashuv bilan belgilanadi.");
    }
    if (real && DateTime.now().difference(p.timestamp).inMinutes.abs() > 2) {
      return const FixResult.fail("Joylashuv eskirgan. Ochiq joyda bir necha soniya kutib, qayta bosing.");
    }
    return FixResult.ok(Fix(p.latitude, p.longitude, p.accuracy, mocked: p.isMocked));
  } catch (_) {
    return const FixResult.fail('Joylashuvni aniqlab bo\'lmadi. Ochiq joyda qayta urinib ko\'ring.');
  }
}
