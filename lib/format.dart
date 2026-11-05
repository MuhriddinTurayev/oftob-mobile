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

/// "5 daqiqa oldin", "Kecha 14:30", "03.11 09:10"
String timeAgo(String? iso) {
  final t = DateTime.tryParse(iso ?? '')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  String two(int v) => v.toString().padLeft(2, '0');
  if (d.inMinutes < 1) return 'hozir';
  if (d.inMinutes < 60) return '${d.inMinutes} daqiqa oldin';
  if (d.inHours < 24 && DateTime.now().day == t.day) return '${d.inHours} soat oldin';
  final y = DateTime.now().subtract(const Duration(days: 1));
  if (t.year == y.year && t.month == y.month && t.day == y.day) return 'Kecha ${two(t.hour)}:${two(t.minute)}';
  return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}
