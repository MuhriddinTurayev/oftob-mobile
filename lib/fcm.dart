import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firebase_config.dart';
import 'push.dart';
import 'session.dart';

/// Firebase Cloud Messaging: server voqea bo'lishi bilan Google orqali telefonga push yuboradi —
/// ilova yopiq yoki telefon qulflangan (Doze) bo'lsa ham soniyalar ichida keladi. Hozircha Android
/// (iPhone uchun Apple Developer akkaunti va APNs kaliti kerak).
class Fcm {
  static bool _ready = false;
  static String? _token;

  static bool get supported => !kIsWeb && Platform.isAndroid && FirebaseConfig.ready;

  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: FirebaseConfig.apiKey,
          appId: FirebaseConfig.appId,
          messagingSenderId: FirebaseConfig.messagingSenderId,
          projectId: FirebaseConfig.projectId,
        ),
      );
      _ready = true;
      // push bosilib ilova ochildi — tegishli bo'lim
      FirebaseMessaging.onMessageOpenedApp.listen((m) => Push.openGo.value = _go(m));
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) Push.openGo.value = _go(first);
      // ilova ochiq paytda kelgan push: ilova o'zi lentani yangilab, tepada banner chiqaradi
      FirebaseMessaging.onMessage.listen((_) => Push.foregroundPing.value++);
    } catch (e) {
      debugPrint('fcm init: $e');
    }
  }

  static String _go(RemoteMessage m) {
    final g = '${m.data['go'] ?? ''}';
    return g.isEmpty ? 'notifications' : g;
  }

  /// Kirgandan keyin: telefon manzilini serverga yuborish (va yangilanganda qayta)
  static Future<void> register(Session s) async {
    if (!_ready || s.api == null) return;
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t == null || t.isEmpty) return;
      _token = t;
      await _send(s, t);
      FirebaseMessaging.instance.onTokenRefresh.listen((nt) {
        _token = nt;
        _send(s, nt);
      });
    } catch (e) {
      debugPrint('fcm token: $e');
    }
  }

  static Future<void> _send(Session s, String t) async {
    final api = s.api;
    if (api == null) return;
    try {
      final r = await api.aSend('POST', '/me/push-token', {'token': t, 'platform': 'android'});
      // server push yubora oladi — fondagi qo'shimcha tekshiruv takror xabar chiqarmasin
      await Push.setFcmOn(r is Map && r['fcm'] == true);
    } catch (_) {}
  }

  /// Chiqishda: bu telefonga endi push kelmasin
  static Future<void> unregister(Session s) async {
    if (!_ready) return;
    final t = _token;
    try {
      if (t != null && s.api != null) await s.api!.aSend('POST', '/me/push-token/delete', {'token': t});
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
    await Push.setFcmOn(false);
  }
}
