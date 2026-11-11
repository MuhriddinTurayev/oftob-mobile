import 'dart:async';

import 'package:flutter/foundation.dart';

import 'offline.dart';
import 'push.dart';
import 'session.dart';

/// Lidlar «pulsi»: har 2 soniyada serverdan oxirgi lid raqamini so'raydi (bir necha bayt). Raqam o'zgarsa — yangi lid kelgan:
/// ro'yxatlar darhol yangilanadi va bildirishnoma markazi (banner/tovush) shu zahoti ishga tushadi. Telegram'dagi kabi — 1–2 soniya.
class LeadPulse {
  /// Yangi lid kelganda oshadi; ro'yxat ekranlari shuni tinglaydi
  static final tick = ValueNotifier<int>(0);

  static Timer? _t;
  static int? _last;
  static bool _busy = false;
  static int _fails = 0;

  static void start(Session s) {
    stop();
    _last = null;
    _fails = 0;
    _t = Timer.periodic(const Duration(seconds: 2), (_) => _poll(s));
    _poll(s);
  }

  static void stop() {
    _t?.cancel();
    _t = null;
  }

  static Future<void> _poll(Session s) async {
    final api = s.api;
    if (api == null || _busy || !Offline.online.value) return;
    _busy = true;
    try {
      final seq = await api.leadSeq();
      if (seq == null) {
        stop(); // eski server: puls yo'q — ro'yxat o'zi vaqti-vaqti bilan yangilanadi
        return;
      }
      _fails = 0;
      final prev = _last;
      _last = seq;
      if (prev != null && seq != prev) {
        tick.value++;
        Push.foregroundPing.value++; // bildirishnomalar markazi darhol so'raydi (banner/tizim bildirishnomasi)
      }
    } catch (_) {
      if (++_fails >= 30) stop(); // uzoq vaqt javob bermasa — to'xtaydi (internet qaytganda ekran qayta ishga tushiradi)
    } finally {
      _busy = false;
    }
  }
}