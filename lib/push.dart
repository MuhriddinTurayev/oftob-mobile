import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'l10n.dart';

/// Fondagi tekshiruv (ilova yopiq bo'lsa ham): Android WorkManager har ~15 daqiqada ishga tushiradi.
@pragma('vm:entry-point')
void pushBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Push.checkNow();
    } catch (_) {}
    return true; // xato bo'lsa ham keyingi davr o'z vaqtida
  });
}

/// Telefonning o'ziga bildirishnoma (SMS kabi tepada chiqadi): yangi pul so'rovi, xarid hisoboti, vazifa, hisobot va h.k.
/// Manba — serverdagi bildirishnomalar lentasi (/notifications). Ilova ochiq bo'lsa — ichida (NotificationCenter),
/// yopiq yoki fonda bo'lsa — shu yerdan. Darhol (soniyalar ichida) xabar uchun — Telegram bot (tg_connect.dart).
class Push {
  static final _ln = FlutterLocalNotificationsPlugin();
  static const _store = FlutterSecureStorage();
  static const _task = 'oftob-notify';
  static bool _ready = false;

  /// Bildirishnoma bosilib ilova ochilgan bo'lsa — qaysi bo'limga o'tish (funds, tasks, ...)
  static final ValueNotifier<String?> openGo = ValueNotifier(null);

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const _channel = AndroidNotificationDetails(
    'oftob_main',
    'Bildirishnomalar',
    channelDescription: "Pul so'rovlari, hisobotlar, vazifalar",
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_stat_oftob',
    color: Color(0xFF2563EB),
  );

  static Future<void> _initPlugin() async {
    if (_ready) return;
    await _ln.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_oftob'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      onDidReceiveNotificationResponse: (r) => openGo.value = (r.payload ?? '').isEmpty ? 'notifications' : r.payload,
    );
    _ready = true;
  }

  /// Ilova ishga tushganda: bildirishnoma moduli va fondagi davriy tekshiruv
  static Future<void> init() async {
    if (!supported) return;
    try {
      await _initPlugin();
      final launch = await _ln.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final p = launch!.notificationResponse?.payload ?? '';
        openGo.value = p.isEmpty ? 'notifications' : p;
      }
      if (Platform.isAndroid) {
        await Workmanager().initialize(pushBackgroundDispatcher);
        await Workmanager().registerPeriodicTask(
          _task,
          _task,
          frequency: const Duration(minutes: 15),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
          constraints: Constraints(networkType: NetworkType.connected),
        );
      }
    } catch (e) {
      debugPrint('push init: $e');
    }
  }

  /// Ruxsat so'rash (Android 13+ va iPhone). true — ruxsat bor
  static Future<bool> askPermission() async {
    if (!supported) return false;
    try {
      await _initPlugin();
      if (Platform.isAndroid) {
        final a = _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await a?.requestNotificationsPermission() ?? true;
      }
      final i = _ln.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await i?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enabled() async {
    if (!supported) return false;
    try {
      if (Platform.isAndroid) {
        return await _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled() ?? true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ilova fonga o'tganda: 1 daqiqadan keyin bir martalik tekshiruv (davriy 15 daqiqani kutmasdan)
  static Future<void> soon() async {
    if (!supported || !Platform.isAndroid) return;
    try {
      await Workmanager().registerOneOffTask('$_task-soon', '$_task-soon',
          initialDelay: const Duration(minutes: 1), existingWorkPolicy: ExistingWorkPolicy.replace, constraints: Constraints(networkType: NetworkType.connected));
    } catch (_) {}
  }

  /// Chiqishda: fondagi tekshiruv to'xtaydi, eski xabarlar o'chadi
  static Future<void> stop() async {
    if (!supported) return;
    try {
      if (Platform.isAndroid) await Workmanager().cancelAll();
      await _ln.cancelAll();
    } catch (_) {}
  }

  /// Serverdan yangi bildirishnomalarni olib, ko'rilmaganlarini telefonga chiqaradi (fonda ham, ilovada ham ishlaydi)
  static Future<int> checkNow() async {
    if (!supported) return 0;
    final server = await _store.read(key: 'server');
    final key = await _store.read(key: 'key');
    final uid = await _store.read(key: 'uid') ?? '0';
    if (server == null || key == null || server.isEmpty || key.isEmpty) return 0;
    await L.load();
    final r = await http
        .get(Uri.parse('$server/api/v1/notifications?lang=${L.code}'), headers: {'Authorization': 'Bearer $key', 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) return 0;
    final data = (jsonDecode(r.body) as Map)['data'];
    final list = (data is List ? data : const []).whereType<Map>().toList();
    if (list.isEmpty) return 0;
    final markKey = 'push_mark_$uid';
    final seen = await _store.read(key: 'notif_seen_$uid') ?? ''; // ilovada o'qilganlar
    var mark = await _store.read(key: markKey) ?? '';
    final latest = list.map((e) => '${e['at']}').reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    if (mark.isEmpty) {
      // birinchi marta: eskilarini ko'rsatmaymiz, faqat bundan keyingi yangilarini
      await _store.write(key: markKey, value: latest);
      return 0;
    }
    final floor = seen.compareTo(mark) > 0 ? seen : mark;
    final fresh = list.where((e) => '${e['at']}'.compareTo(floor) > 0).toList()..sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
    await _store.write(key: markKey, value: latest.compareTo(mark) > 0 ? latest : mark);
    if (fresh.isEmpty) return 0;
    await _initPlugin();
    final show = fresh.length > 4 ? fresh.sublist(fresh.length - 4) : fresh;
    for (final e in show) {
      await _ln.show(
        '${e['id']}'.hashCode & 0x7fffffff,
        tr('${e['title']}'),
        '${e['body'] ?? ''}',
        const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true)),
        payload: '${e['go'] ?? ''}',
      );
    }
    if (fresh.length > show.length) {
      await _ln.show(
        1,
        tr('Yangi bildirishnomalar'),
        '${fresh.length} ${tr('ta yangi voqea')}',
        const NotificationDetails(android: _channel),
        payload: 'notifications',
      );
    }
    return fresh.length;
  }
}
