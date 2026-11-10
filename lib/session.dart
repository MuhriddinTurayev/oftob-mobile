import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'offline.dart';
import 'webcache.dart';

import 'fcm.dart';
import 'push.dart';
import 'api.dart';
import 'company.dart';

/// Ilovaning ikki rejimi:
///  * **Platforma** (asosiy) — veb-dasturning o'zi ilova ichida ochiladi, hamma funksiya ishlaydi (login/parol bilan);
///  * **API kalit** (tezkor) — faqat asosiy bo'limlar, `/api/v1` orqali, mahalliy ekranlar.
class Session extends ChangeNotifier {
  Session({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage() {
    ApiClient.onUnauthorized = () {
      if ((api != null || papi != null) && !_signingOut) {
        kicked = true;
        signOut();
      }
    };
  }

  bool _signingOut = false;

  /// Seans boshqa qurilmadan yopilgani uchun chiqarildi — kirish ekranida tushuntiriladi
  bool kicked = false;

  /// Sinov uchun: `flutter run --dart-define=OFTOB_SERVER=http://10.0.2.2:8099` (emulyatordan kompyuterdagi serverga)
  static const defaultServer = String.fromEnvironment('OFTOB_SERVER', defaultValue: 'https://oftob.5-189-163-130.sslip.io');


  final FlutterSecureStorage _storage;

  // umumiy
  String serverUrl = defaultServer;
  bool loading = true;

  // oxirgi kirilgan korxonalar (qurilmada, tez almashtirish uchun)
  List<CompanyInfo> recent = [];

  String slug = ''; // oxirgi kirilgan kompaniya manzili

  // API kalit rejimi
  ApiClient? api;
  Me? me;
  String userName = ''; // kirgan xodim ismi (xodim kirishi bilan)
  int userId = 0; // kirgan xodim id ("mening vazifalarim" filtri uchun)
  String? photoUrl; // profil rasmi (token bilan olinadi); yo'q bo'lsa — bosh harflar

  bool get signedIn => api != null && me != null;

  // platforma administratori (kompaniyasiz) — alohida kalit va bo'limlar
  ApiClient? papi;
  Map<String, dynamic>? pme;

  bool get platformIn => papi != null && pme != null;

  /// Joriy kirgan foydalanuvchining API'si (xodim yoki platforma administratori)
  ApiClient? get anyApi => api ?? papi;

  Future<void> _platformConnect(String url, String key) async {
    final c = ApiClient(serverUrl: url, apiKey: key)..scope = '/platform';
    final me = Map<String, dynamic>.from((await c.pGet('/me') as Map?) ?? const {});
    papi?.close();
    papi = c;
    pme = me;
    Offline.disable();   // platforma ma'lumotlari telefonda saqlanmaydi
  }

  /// Platforma egasi kirishi: login + parol
  Future<void> platformSignIn({required String email, required String password}) async {
    final key = await ApiClient.platformLogin(serverUrl, email: email, password: password, device: defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone' : 'Android');
    await _platformConnect(serverUrl, key);
    await _storage.write(key: 'pkey', value: key);
    notifyListeners();
  }

  /// Ilova ochilganda oxirgi rejim tiklanadi.
  Future<void> restore() async {
    try {
      final mode = await _storage.read(key: 'mode');
      // Server manzili: eski versiyalar Keychain'ga turli (ba'zan noto'g'ri) manzillarni yozib ketgan — ularni e'tiborsiz qoldiramiz.
      // Faqat dasturchi sozlamasida ataylab kiritilgan manzil ('server_custom') hisobga olinadi, aks holda doim standart server.
      final custom = await _storage.read(key: 'server_custom');
      final url = (custom != null && custom.isNotEmpty) ? custom : defaultServer;
      serverUrl = url;
      slug = await _storage.read(key: 'slug') ?? '';
      try {
        final r = await _storage.read(key: 'recent');
        if (r != null) recent = (jsonDecode(r) as List).whereType<Map>().map((e) => CompanyInfo.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {
        recent = [];
      }
      // Eski versiya «sayt rejimi»ni Keychain'ga yozib qo'ygan (u ilova o'chirilganda ham qoladi). Endi ilova asosan mahalliy:
      // korxona xodimlari uchun sayt rejimi eslab qolinmaydi (har safar kirish oynasi), faqat platforma administratori (korxonasiz) saytda qoladi.
      // Sayt rejimi hech qachon o'zi tiklanmaydi: ilova doim mahalliy kirish oynasi (yoki saqlangan mahalliy sessiya) bilan ochiladi.
      {
        if (mode == 'web') await _storage.delete(key: 'mode');
        userName = await _storage.read(key: 'uname') ?? '';
        userId = int.tryParse(await _storage.read(key: 'uid') ?? '') ?? 0;
        final pkey = await _storage.read(key: 'pkey');
        if (pkey != null && pkey.isNotEmpty) {
          try {
            await _platformConnect(url, pkey);
          } on ApiException catch (e) {
            if (e.unauthorized) await _storage.delete(key: 'pkey');
          }
        }
        final key = await _storage.read(key: 'key');
        if (userId > 0 && slug.isNotEmpty) await Offline.init('${slug}_$userId'); // internet bo'lmasa ham oxirgi saqlangan ma'lumot bilan kiradi
        if (key != null && key.isNotEmpty) await _connect(url, key, persist: false);
      }
    } catch (_) {
      // saqlangan kalit ishlamadi — kirish oynasi ko'rsatiladi
      api = null;
      me = null;
    }
    loading = false;
    notifyListeners();
  }

  /// Korxonani ro'yxat boshiga qo'yadi (eng ko'pi bilan 6 ta)
  Future<void> rememberCompany(CompanyInfo c) async {
    recent = [c, ...recent.where((e) => e.slug != c.slug)].take(6).toList();
    await _storage.write(key: 'recent', value: jsonEncode(recent.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> forgetCompany(String slug) async {
    recent = recent.where((e) => e.slug != slug).toList();
    await _storage.write(key: 'recent', value: jsonEncode(recent.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  /// Dasturchi: server manzilini almashtirish (oddiy foydalanuvchiga ko'rsatilmaydi)
  Future<void> setServer(String url) async {
    serverUrl = ApiClient.normalizeUrl(url);
    await _storage.write(key: 'server_custom', value: serverUrl);
    notifyListeners();
  }

  /* ---------------- API kalit ---------------- */

  /// Kirish: xato bo'lsa [ApiException] tashlaydi.
  Future<void> signIn(String url, String key) async {
    await _connect(url, key.trim(), persist: true);
    notifyListeners();
  }

  Future<void> _connect(String url, String key, {required bool persist}) async {
    final client = ApiClient(serverUrl: url, apiKey: key);
    final m = await client.me(); // kalit noto'g'ri bo'lsa shu yerda xato
    api?.close();
    api = client;
    me = m;
    serverUrl = client.base;
    unawaited(loadProfile());
    if (persist) {
      await _storage.write(key: 'mode', value: 'api');
      await _storage.write(key: 'server', value: client.base);
      await _storage.write(key: 'key', value: key);
    }
  }

  /// Xodim kirishi (asosiy yo'l): korxona kodi + login + parol. Server shaxsiy kalit beradi, ilova shu kalit bilan ishlaydi.
  Future<void> staffSignIn({required String company, required String email, required String password}) async {
    final r = await ApiClient.login(serverUrl, company: company, email: email, password: password, device: defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone' : 'Android');
    await Offline.init('${r.companySlug}_${r.userId}');
    await _connect(r.serverUrl, r.token, persist: true);
    userName = r.userName;
    userId = r.userId;
    slug = r.companySlug;
    await _storage.write(key: 'uname', value: userName);
    await _storage.write(key: 'uid', value: '$userId');
    await _storage.write(key: 'slug', value: slug);
    notifyListeners();
  }

  /// Profil rasmini (va ismini) jimgina yangilaydi
  Future<void> loadProfile() async {
    final a = api;
    if (a == null) return;
    try {
      final d = await a.profile();
      photoUrl = d['photo_url'] as String?;
      final n = '${d['name'] ?? ''}';
      if (n.isNotEmpty && n != userName) userName = n;
      notifyListeners();
    } catch (_) {}
  }

  void setPhoto(String? url) {
    photoUrl = url;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    try {
      await _signOut();
    } finally {
      _signingOut = false;
    }
  }

  Future<void> _signOut() async {
    await Fcm.unregister(this); // bu telefonga endi push kelmasin
    await Push.stop(); // boshqa odam kirsa — oldingi foydalanuvchining xabarlari chiqmasin
    // platforma administratori
    final p = papi;
    if (p != null) {
      papi = null;
      pme = null;
      await _storage.delete(key: 'pkey');
      try {
        await WebViewCookieManager().clearCookies();
      } catch (_) {}
      notifyListeners();
      try {
        await p.pSend('POST', '/logout');
      } catch (_) {}
      p.close();
      if (api == null) return;
    }
    final a = api;
    api = null;
    me = null;
    photoUrl = null;
    userName = '';
    userId = 0;
    await _storage.delete(key: 'key');
    await _storage.delete(key: 'mode');
    await _storage.delete(key: 'uname');
    await _storage.delete(key: 'uid');
    try {
      await WebViewCookieManager().clearCookies(); // 3D sahifasi uchun ochilgan sayt seansi ham yopiladi
    } catch (_) {}
    await WebCache.reset();
    await Offline.clearCache(); // boshqa odam ko'rmasin; yuborilmagan sotuv/to'lovlar fayli qoladi
    Offline.disable();
    notifyListeners();
    if (a != null) {
      await a.logout();
      a.close();
    }
  }

  /// Til o'zgarganda: rol nomi kabi server matnlarini yangi tilda qayta olish (jim; xato bo'lsa eskisi qoladi)
  Future<void> refreshMe() async {
    final a = api;
    if (a == null || me == null) return;
    try {
      me = await a.me();
      notifyListeners();
    } catch (_) {}
  }

  /// Server 401 qaytarsa (kalit bekor qilingan) — chiqib ketamiz.
  Future<void> handleError(Object e) async {
    if (e is ApiException && e.unauthorized) await signOut();
  }
}
