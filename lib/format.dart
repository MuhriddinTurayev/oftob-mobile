/// Raqamlarni `10 000 000` ko'rinishida yozadi (veb-dasturdagidek).
String money(num? v) {
  if (v == null) return '—';
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

/// Kvartira maydoni: 54.5 → "54,5"
String area(num? v) {
  if (v == null) return '—';
  final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
  return s;
}

String aptStatus(String? s) => switch (s) {
      'free' => 'Bo\'sh',
      'booked' => 'Bron',
      'sold' => 'Sotilgan',
      'reserve' => 'Zaxira',
      _ => s ?? '',
    };

String taskStatus(String? s) => switch (s) {
      'todo' => 'Qilish kerak',
      'doing' => 'Jarayonda',
      'review' => 'Tekshiruvda',
      'done' => 'Bajarildi',
      _ => s ?? '',
    };

String formatDate(String? iso) {
  if (iso == null || iso.length < 10) return '';
  final d = iso.substring(0, 10).split('-');
  if (d.length != 3) return iso;
  return '${d[2]}.${d[1]}.${d[0]}';
}

/// Xonalar soni: 0 — tijorat xonasi
String roomsLabel(Object? rooms) => '$rooms' == '0' ? 'Tijorat' : '$rooms xona';

/// Masofa: 540 m, 12,5 km
String distLabel(num m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
