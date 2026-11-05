import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'l10n_dict.dart';

/// Ilova tili: o'zbekcha (asos), ruscha, tojikcha. Matnlar kodda o'zbekcha yoziladi; ruscha/tojikcha ko'rinish
/// ekranga chiqarish paytida [tr] orqali lug'atdan olinadi. Server matnlari (rol, birlik, xato) `lang` parametri bilan o'zi shu tilda keladi.
class L {
  static const codes = ['uz', 'ru', 'tg'];
  static final ValueNotifier<String> notifier = ValueNotifier('uz');
  static const _storage = FlutterSecureStorage();

  static String get code => notifier.value;

  static String name(String c) => const {'uz': "O'zbekcha", 'ru': 'Русский', 'tg': 'Тоҷикӣ'}[c] ?? c;

  /// Saqlangan til; yo'q bo'lsa — telefon tili (ru/tg bo'lsa), aks holda o'zbekcha.
  static Future<void> load() async {
    String c = 'uz';
    try {
      final saved = await _storage.read(key: 'lang');
      if (saved != null && codes.contains(saved)) {
        c = saved;
      } else {
        final dev = ui.PlatformDispatcher.instance.locale.languageCode;
        if (dev == 'ru' || dev == 'tg') c = dev;
      }
    } catch (_) {}
    _apply(c);
  }

  static Future<void> set(String c) async {
    if (!codes.contains(c) || c == code) return;
    _apply(c);
    try {
      await _storage.write(key: 'lang', value: c);
    } catch (_) {}
  }

  static void _apply(String c) {
    _cache.clear();
    ApiClient.lang = c; // server matnlari ham shu tilda keladi
    notifier.value = c;
  }
}

final Map<String, String> _cache = {};
final Map<String, RegExp> _re = {};
List<String>? _keys;

/// O'zbekcha matnni joriy tilga o'giradi: avval butun matn, keyin (raqam/ism kabi o'zgaruvchan qismlar bor matnlar uchun) ma'lum so'z va iboralar bo'yicha.
String tr(String s) {
  final c = L.code;
  if (c == 'uz' || s.isEmpty) return s;
  return _cache.putIfAbsent(s, () => _translate(s, c == 'ru' ? 0 : 1));
}

String _translate(String s, int i) {
  final exact = kDict[s.trim()];
  if (exact != null) {
    final lead = s.substring(0, s.length - s.trimLeft().length);
    final trail = s.substring(s.trimRight().length);
    return '$lead${exact[i]}$trail';
  }
  _keys ??= (kDict.keys.toList()..sort((a, b) => b.length.compareTo(a.length)));
  var out = s;
  for (final k in _keys!) {
    if (!out.contains(k)) continue;
    final re = _re.putIfAbsent(k, () {
      final letter = RegExp(r'\p{L}', unicode: true);
      final pre = letter.hasMatch(k[0]) ? r"(?<![\p{L}'’‘ʻʼ])" : '';
      final post = letter.hasMatch(k[k.length - 1]) ? r"(?![\p{L}'’‘ʻʼ])" : '';
      return RegExp('$pre${RegExp.escape(k)}$post', unicode: true);
    });
    out = out.replaceAllMapped(re, (_) => kDict[k]![i]);
  }
  return out;
}

/// Material uchun til: tojikcha qo'llab-quvvatlansa — tojikcha, aks holda ruscha (kirill).
m.Locale materialLocale(String c, bool Function(m.Locale) supported) {
  if (c == 'tg') return supported(const m.Locale('tg')) ? const m.Locale('tg') : const m.Locale('ru');
  return m.Locale(c);
}

/// Flutter'ning `Text` o'rniga: matnni joriy tilga o'giradi. Qolgan hamma parametrlar o'sha-o'sha.
class Text extends m.StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.softWrap,
    this.textScaler,
    this.semanticsLabel,
  });

  final String data;
  final m.TextStyle? style;
  final m.TextAlign? textAlign;
  final m.TextOverflow? overflow;
  final int? maxLines;
  final bool? softWrap;
  final m.TextScaler? textScaler;
  final String? semanticsLabel;

  @override
  m.Widget build(m.BuildContext context) => m.Text(tr(data), style: style, textAlign: textAlign, overflow: overflow, maxLines: maxLines, softWrap: softWrap, textScaler: textScaler, semanticsLabel: semanticsLabel);
}
