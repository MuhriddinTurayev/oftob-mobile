import 'dart:async';

import 'package:flutter/foundation.dart';

import 'offline.dart';
import 'push.dart';
import 'session.dart';

/// Real vaqt «puls»i: har 2 soniyada serverdan hamma sohalar uchun kichik belgilar (/pulse) so'raladi.
/// Biror belgi o'zgarsa — shu sohaning ma'lumoti o'zgargan (botdan Keldim, boshqa xodim vazifa o'zgartirdi, kassaga pul tushdi...):
/// tegishli ekranlar jimgina qayta yuklanadi. Ma'lumotning o'zi yuklanmaydi — faqat belgi, shuning uchun juda yengil.
class Pulse {
  static final leads = ValueNotifier<int>(0);
  static final state = ValueNotifier<int>(0); // obyektlar, xonadonlar, lid bosqichlari, xodimlar ro'yxati
  static final shift = ValueNotifier<int>(0); // mening smenam
  static final attendance = ValueNotifier<int>(0);
  static final tasks = ValueNotifier<int>(0);
  static final cash = ValueNotifier<int>(0);
  static final funds = ValueNotifier<int>(0);

  /// Istalgan o'zgarish (bosh sahifa va bildirishnomalar uchun; 1 soniya ichidagilar birlashadi)
  static final any = ValueNotifier<int>(0);

  static Timer? _t;
  static Timer? _debounce;
  static Map<String, String>? _last;
  static bool _busy = false;
  static int _fails = 0;
  static bool _legacy = false; // eski server: faqat lidlar pulsi

  static ValueNotifier<int>? _of(String k) => switch (k) {
        'leads' => leads,
        'state' => state,
        'shift' => shift,
        'attendance' => attendance,
        'tasks' => tasks,
        'cash' => cash,
        'funds' => funds,
        _ => null,
      };

  static void start(Session s) {
    stop();
    _last = null;
    _fails = 0;
    _legacy = false;
    _t = Timer.periodic(const Duration(seconds: 2), (_) => _poll(s));
    _poll(s);
  }

  static void stop() {
    _t?.cancel();
    _t = null;
    _debounce?.cancel();
  }

  static Future<void> _poll(Session s) async {
    final api = s.api;
    if (api == null || _busy || !Offline.online.value) return;
    _busy = true;
    try {
      Map<String, String>? cur;
      if (!_legacy) {
        cur = await api.pulse();
        if (cur == null) _legacy = true;
      }
      if (_legacy) {
        final seq = await api.leadSeq();
        if (seq == null) {
          stop(); // juda eski server: puls yo'q
          return;
        }
        cur = {'leads': '$seq'};
      }
      _fails = 0;
      final prev = _last;
      _last = cur;
      if (prev == null) return;
      var changed = false;
      for (final e in cur!.entries) {
        if (prev[e.key] != e.value) {
          final n = _of(e.key);
          if (n != null) {
            n.value++;
            changed = true;
          }
        }
      }
      if (changed) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 900), () {
          any.value++;
          Push.foregroundPing.value++; // bildirishnomalar markazi ham darhol so'raydi
        });
      }
    } catch (_) {
      if (++_fails >= 30) stop();
    } finally {
      _busy = false;
    }
  }
}