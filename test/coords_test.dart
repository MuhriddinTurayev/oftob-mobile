import 'package:flutter_test/flutter_test.dart';
import 'package:oftob_mobile/screens/map_picker.dart';

void main() {
  test('koordinata formatlari', () {
    final a = parseCoords("41°16'39.2\"N 69°13'03.9\"E")!;
    expect(a.latitude, closeTo(41.277556, 1e-5));
    expect(a.longitude, closeTo(69.21775, 1e-5));
    final b = parseCoords('https://www.google.com/maps/place//@41.277548,69.2151761,17z/data=!4m6!1m5!3m4!2zNDHCsDE2JzM5LjIiTiA2OcKwMTMnMDMuOSJF!8m2!3d41.277548!4d69.217751?entry=ttu')!;
    expect(b.longitude, closeTo(69.217751, 1e-6));
    expect(parseCoords('41.277548, 69.217751')!.latitude, closeTo(41.277548, 1e-6));
    expect(parseCoords('https://yandex.uz/maps/?ll=69.217751%2C41.277548&z=17')!.latitude, closeTo(41.277548, 1e-6));
    expect(parseCoords('salom'), isNull);
  });
}
