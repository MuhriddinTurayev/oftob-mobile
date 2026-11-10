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
  static const _iosTask = 'uz.oftob.notify';
  static bool _ready = false;

  /// Bildirishnoma bosilib ilova ochilgan bo'lsa — qaysi bo'limga o'tish (funds, tasks, ...)
  static final ValueNotifier<String?> openGo = ValueNotifier(null);

  /// Ilova ochiq paytda Firebase push keldi — lentani darhol yangilash uchun
  static final ValueNotifier<int> foregroundPing = ValueNotifier(0);

  /// Server Firebase orqali push yubora oladi (bu telefon ro'yxatdan o'tgan) — fondagi tekshiruv takror ko'rsatmaydi
  static bool fcmOn = false;

  static Future<void> setFcmOn(bool v) async {
    fcmOn = v;
    await _bgWrite('fcm_on', v ? '1' : '0');
  }

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
      // Firebase push shu kanal orqali chiqadi (oldindan yaratiladi: ovoz, yuqori muhimlik)
      if (Platform.isAndroid) {
        await _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(const AndroidNotificationChannel(
            'oftob_main', 'Bildirishnomalar',
            description: "Pul so'rovlari, hisobotlar, vazifalar", importance: Importance.high));
      }
      fcmOn = (await _bgRead('fcm_on')) == '1';
      final launch = await _ln.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final p = launch!.notificationResponse?.payload ?? '';
        openGo.value = p.isEmpty ? 'notifications' : p;
      }
      await Workmanager().initialize(pushBackgroundDispatcher);
      if (Platform.isAndroid) {
        await Workmanager().registerPeriodicTask(
          _task,
          _task,
          frequency: const Duration(minutes: 15),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
          constraints: Constraints(networkType: NetworkType.connected),
        );
      } else {
        // iPhone: BGAppRefresh (AppDelegate va Info.plist'da «uz.oftob.notify»). Qachon ishga tushishini iPhone o'zi hal qiladi —
        // odatda ilova tez-tez ishlatilsa, kuniga bir necha marta. Darhol xabar uchun — Telegram bot.
        await Workmanager().registerPeriodicTask(_iosTask, _iosTask, frequency: const Duration(minutes: 15), initialDelay: const Duration(minutes: 15));
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
      await Workmanager().cancelAll();
      await _ln.cancelAll();
    } catch (_) {}
  }

  /// iPhone: telefon qulflangan paytda ham fondagi tekshiruv o'qiy olishi uchun kirish ma'lumotlarining nusxasi
  /// «birinchi qulf ochilgandan keyin» ruxsati bilan saqlanadi (oddiy kalitlar qulflangan telefonda o'qilmaydi).
  static const _bgOpts = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  static Future<String?> _bgRead(String k) async {
    try {
      return await _store.read(key: 'bg_$k', iOptions: _bgOpts);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _bgWrite(String k, String v) async {
    try {
      await _store.write(key: 'bg_$k', value: v, iOptions: _bgOpts);
    } catch (_) {}
  }

  /// Ilova ochiq paytda chaqiriladi (kirgandan keyin va fonga o'tishda): server, kalit, foydalanuvchi, til nusxasi
  static Future<void> syncCreds() async {
    if (!supported) return;
    try {
      for (final k in const ['server', 'key', 'uid', 'lang']) {
        final v = await _store.read(key: k);
        if (v != null && v.isNotEmpty) await _bgWrite(k, v);
      }
    } catch (_) {}
  }

  /// Bildirishnomalarni telefon tepasida ko'rsatish (ilova ochiq bo'lsa ham — Telegram kabi banner, ovoz bilan).
  /// Ko'rsatilganlar belgilanadi — fondagi tekshiruv ularni qayta chiqarmaydi.
  static Future<bool> showItems(List<Map> fresh, {String uid = ''}) async {
    if (!supported || fresh.isEmpty) return false;
    try {
      await _initPlugin();
      if (!await enabled()) return false;
      final list = [...fresh]..sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
      final show = list.length > 4 ? list.sublist(list.length - 4) : list;
      for (final e in show) {
        await _ln.show(
          '${e['id']}'.hashCode & 0x7fffffff,
          tr('${e['title']}'),
          '${e['body'] ?? ''}',
          const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true, presentSound: true)),
          payload: '${e['go'] ?? ''}',
        );
      }
      if (list.length > show.length) {
        await _ln.show(1, tr('Yangi bildirishnomalar'), '${list.length} ${tr('ta yangi voqea')}',
            const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true)), payload: 'notifications');
      }
      if (uid.isNotEmpty) {
        final latest = list.last['at'].toString();
        final mark = await _bgRead('push_mark_$uid') ?? '';
        if (latest.compareTo(mark) > 0) await _bgWrite('push_mark_$uid', latest);
      }
      return true;
    } catch (e) {
      debugPrint('push show: $e');
      return false;
    }
  }

  /// Serverdan yangi bildirishnomalarni olib, ko'rilmaganlarini telefonga chiqaradi (fonda — ilova yopiq bo'lsa ham)
  static Future<int> checkNow() async {
    if (!supported) return 0;
    // avval qulflangan telefonda ham o'qiladigan nusxa, bo'lmasa — oddiy kalitlar
    Future<String?> rd(String k) async {
      final v = await _bgRead(k);
      if (v != null && v.isNotEmpty) return v;
      try {
        return await _store.read(key: k);
      } catch (_) {
        return null;
      }
    }

    if ((await _bgRead('fcm_on')) == '1') return 0; // Firebase push o'zi keladi — takrorlamaymiz
    final server = await rd('server');
    final key = await rd('key');
    final uid = await rd('uid') ?? '0';
    if (server == null || key == null || server.isEmpty || key.isEmpty) return 0;
    final lang = await rd('lang');
    if (lang != null && L.codes.contains(lang)) {
      await L.set(lang);
    } else {
      await L.load();
    }
    final r = await http
        .get(Uri.parse('$server/api/v1/notifications?lang=${L.code}'), headers: {'Authorization': 'Bearer $key', 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) return 0;
    final data = (jsonDecode(r.body) as Map)['data'];
    final list = (data is List ? data : const []).whereType<Map>().toList();
    if (list.isEmpty) return 0;
    final markKey = 'push_mark_$uid';
    var seen = '';
    try {
      seen = await _store.read(key: 'notif_seen_$uid') ?? ''; // ilovada o'qilganlar (qulflangan iPhone'da o'qilmasligi mumkin — muhim emas)
    } catch (_) {}
    final mark = await _bgRead(markKey) ?? '';
    final latest = list.map((e) => '${e['at']}').reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    if (mark.isEmpty) {
      // birinchi marta: eskilarini ko'rsatmaymiz, faqat bundan keyingi yangilarini
      await _bgWrite(markKey, latest);
      return 0;
    }
    final floor = seen.compareTo(mark) > 0 ? seen : mark;
    final fresh = list.where((e) => '${e['at']}'.compareTo(floor) > 0).toList();
    await _bgWrite(markKey, latest.compareTo(mark) > 0 ? latest : mark);
    if (fresh.isEmpty) return 0;
    await showItems(fresh);
    return fresh.length;
  }
}
