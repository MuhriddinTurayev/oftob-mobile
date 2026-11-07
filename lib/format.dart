import 'package:flutter/services.dart';

import 'l10n.dart';
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

/// «8 soat 12 daq» / «35 daq»
String durationText(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? '$h ${tr('soat')} $m ${tr('daq')}' : '$m ${tr('daq')}';
}

/// Kelgan vaqt: serverning aniq vaqti (`<key>_ts`, UTC), bo'lmasa «HH:MM» bugungi sana bilan
DateTime? shiftMoment(Map m, String key) {
  final ts = DateTime.tryParse('${m['${key}_ts'] ?? ''}');
  if (ts != null) return ts.toLocal();
  final hm = '${m[key] ?? ''}'.split(':');
  if (hm.length < 2) return null;
  final h = int.tryParse(hm[0]), mi = int.tryParse(hm[1]);
  if (h == null || mi == null) return null;
  final n = DateTime.now();
  var d = DateTime(n.year, n.month, n.day, h, mi);
  if (d.isAfter(n.add(const Duration(minutes: 2)))) d = d.subtract(const Duration(days: 1));
  return d;
}


/// "32010" → "32 010" (matn maydonlarini oldindan to'ldirish uchun)
String groupDigits(String digits) {
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
    b.write(digits[i]);
  }
  return b.toString();
}

String fmtInput(num? v) => (v == null || v <= 0) ? '' : groupDigits(v.round().toString());

/// Summa kiritilayotganda raqamlar avtomatik minglik bo'shliq bilan ajratiladi: 1 000, 25 000 000.
/// [decimal] — kasr qismi ham mumkin (nuqta bilan). Tahlil kodlari bo'shliqni tashlab yuboradi.
class ThousandsFormatter extends TextInputFormatter {
  const ThousandsFormatter({this.decimal = false});

  final bool decimal;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text;
    var caret = newValue.selection.end;
    if (caret < 0 || caret > raw.length) caret = raw.length;
    bool isDigit(int c) => c >= 48 && c <= 57;
    // kursordan oldin nechta raqam bor
    var before = 0;
    for (var i = 0; i < caret; i++) {
      if (isDigit(raw.codeUnitAt(i))) before++;
    }
    var intPart = StringBuffer();
    var frac = StringBuffer();
    var hasDot = false;
    for (final c in raw.codeUnits) {
      if (isDigit(c)) {
        (hasDot ? frac : intPart).writeCharCode(c);
      } else if (decimal && !hasDot && (c == 46 || c == 44)) {
        hasDot = true;
      }
    }
    var ip = intPart.toString().replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final out = StringBuffer(groupDigits(ip));
    if (hasDot) out.write('.${frac.toString()}');
    final text = out.toString();
    // kursorni shu raqamdan keyingi joyga qo'yamiz
    var pos = 0, seen = 0;
    if (before > 0) {
      for (var i = 0; i < text.length; i++) {
        if (isDigit(text.codeUnitAt(i))) seen++;
        pos = i + 1;
        if (seen >= before) break;
      }
    }
    if (before == 0 && hasDot) pos = 0;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: pos.clamp(0, text.length)));
  }
}

/// ISO vaqt → «07.11.2026 14:20» (telefon vaqt zonasida)
String formatDateTime(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return iso ?? '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}
