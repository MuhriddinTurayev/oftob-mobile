import 'dart:io' show Platform;
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// «Yengil rejim»: kuchsiz kompyuterlar (ofis kompyuterlari, eski video-karta) uchun. Shisha gradientlari, soyalar, xira qilish,
/// o'tish animatsiyalari va fon dog'lari o'chadi — tekis ranglar, shu sababli GPU deyarli yuklanmaydi.
/// Ilova birinchi daqiqalarda kadr tezligini o'zi o'lchaydi: sekin bo'lsa yengil rejimga o'tadi va eslab qoladi.
/// Qo'lda: yon menyudagi chaqmoq tugmasi (yoqish / o'chirish).
class Lite {
  static final on = ValueNotifier<bool>(false);
  static const _store = FlutterSecureStorage();

  /// 'auto' (o'lchab o'zi hal qiladi), 'on', 'off'
  static String mode = 'auto';
  static bool get desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<void> load() async {
    if (!desktop) return;
    try {
      // Standart — YOQIQ: ofis kompyuterlarida qotmasligi muhimroq. O'chirish: yon menyudagi chaqmoq tugmasi.
      mode = await _store.read(key: 'lite_mode') ?? 'on';
      final auto = await _store.read(key: 'lite_auto') == '1';
      on.value = mode == 'on' || (mode == 'auto' && auto);
    } catch (_) {
      on.value = true;
    }
  }

  /// Qo'lda: yoqish yoki o'chirish (avtomatik o'lchash to'xtaydi)
  static Future<void> setManual(bool v) async {
    mode = v ? 'on' : 'off';
    on.value = v;
    try {
      await _store.write(key: 'lite_mode', value: mode);
    } catch (_) {}
  }

  /// Animatsiya davomiyligi: yengil rejimda — nol
  static Duration d(Duration x) => x; // animatsiyalar yengil rejimda ham qoladi (faqat siljish/shaffoflik — arzon); og'ir narsalar (xira, soya, gradient) o'chadi

  /* ---------------- kadr tezligini o'lchash ---------------- */

  static final _totals = <int>[];
  static int _skip = 70; // ochilish animatsiyasi va birinchi chizishlar hisobga olinmaydi
  static bool _watching = false;

  static void startMonitor() {
    if (!desktop || _watching || mode != 'auto' || on.value) return;
    _watching = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> list) {
    for (final t in list) {
      if (_skip > 0) {
        _skip--;
        continue;
      }
      _totals.add((t.buildDuration + t.rasterDuration).inMicroseconds);
    }
    if (_totals.length < 150) return;
    // 150 ta kadr yig'ildi — qaror
    final n = _totals.length;
    final slow = _totals.where((x) => x > 33000).length; // 30 kadr/s dan sekin
    final avg = _totals.reduce((a, b) => a + b) / n;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _watching = false;
    _totals.clear();
    if (slow / n > 0.10 || avg > 20000) {
      on.value = true;
      _store.write(key: 'lite_auto', value: '1').catchError((_) {});
      debugPrint('LITE: yoqildi (sekin kadrlar $slow/$n, o\'rtacha ${(avg / 1000).toStringAsFixed(1)} ms)');
    } else {
      debugPrint('LITE: kerak emas (sekin kadrlar $slow/$n, o\'rtacha ${(avg / 1000).toStringAsFixed(1)} ms)');
    }
  }
}

/// Yengil rejim o'zgarsa, shunga tayangan hamma vidjetlar qayta chiziladi
class LiteScope extends InheritedNotifier<ValueNotifier<bool>> {
  LiteScope({super.key, required super.child}) : super(notifier: Lite.on);

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LiteScope>()?.notifier?.value ?? false;
}