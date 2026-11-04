import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'api.dart';
import 'company.dart';

/// Ilovaning ikki rejimi:
///  * **Platforma** (asosiy) — veb-dasturning o'zi ilova ichida ochiladi, hamma funksiya ishlaydi (login/parol bilan);
///  * **API kalit** (tezkor) — faqat asosiy bo'limlar, `/api/v1` orqali, mahalliy ekranlar.
class Session extends ChangeNotifier {
  Session({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const defaultServer = 'https://oftob.5-189-163-130.sslip.io';

  /// Ilovaning avvalgi versiyalarida xato yozilgan manzillar (platforma u yerda emas).
  static const _badServers = ['37-60-247-120'];

  final FlutterSecureStorage _storage;

  // umumiy
  String serverUrl = defaultServer;
  bool loading = true;

  // oxirgi kirilgan korxonalar (qurilmada, tez almashtirish uchun)
  List<CompanyInfo> recent = [];

  // platforma (WebView) rejimi
  bool webActive = false;
  String slug = ''; // kompaniya manzili: /c/<slug>

  // API kalit rejimi
  ApiClient? api;
  Me? me;

  bool get signedIn => api != null && me != null;

  /// Ilova ochilganda oxirgi rejim tiklanadi.
  Future<void> restore() async {
    try {
      final mode = await _storage.read(key: 'mode');
      var url = await _storage.read(key: 'server');
      // Eski ilova versiyasi noto'g'ri manzilni saqlab qo'ygan (iPhone Keychain ilova o'chirilganda ham saqlaydi) — to'g'rilaymiz.
      if (url != null && _badServers.any(url.contains)) {
        url = defaultServer;
        await _storage.write(key: 'server', value: url);
      }
      if (url != null && url.isNotEmpty) serverUrl = url;
      slug = await _storage.read(key: 'slug') ?? '';
      try {
        final r = await _storage.read(key: 'recent');
        if (r != null) recent = (jsonDecode(r) as List).whereType<Map>().map((e) => CompanyInfo.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {
        recent = [];
      }
      if (mode == 'web') {
        webActive = true;
      } else {
        final key = await _storage.read(key: 'key');
        if (url != null && key != null && key.isNotEmpty) await _connect(url, key, persist: false);
      }
    } catch (_) {
      // saqlangan kalit ishlamadi — kirish oynasi ko'rsatiladi
      api = null;
      me = null;
    }
    loading = false;
    notifyListeners();
  }

  /* ---------------- platforma (WebView) ---------------- */

  Future<void> startWeb(String url, String companySlug) async {
    serverUrl = ApiClient.normalizeUrl(url);
    slug = companySlug.trim().toLowerCase().replaceAll(RegExp(r'^/+|/+$'), '').replaceFirst(RegExp(r'^c/'), '');
    webActive = true;
    await _storage.write(key: 'mode', value: 'web');
    await _storage.write(key: 'server', value: serverUrl);
    await _storage.write(key: 'slug', value: slug);
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
    await _storage.write(key: 'server', value: serverUrl);
    notifyListeners();
  }

  /// Platformadan chiqish: cookie (kirish) o'chadi, kirish oynasiga qaytadi.
  Future<void> leaveWeb() async {
    webActive = false;
    await _storage.delete(key: 'mode');
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
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
    if (persist) {
      await _storage.write(key: 'mode', value: 'api');
      await _storage.write(key: 'server', value: client.base);
      await _storage.write(key: 'key', value: key);
    }
  }

  Future<void> signOut() async {
    api?.close();
    api = null;
    me = null;
    await _storage.delete(key: 'key');
    await _storage.delete(key: 'mode');
    notifyListeners();
  }

  /// Server 401 qaytarsa (kalit bekor qilingan) — chiqib ketamiz.
  Future<void> handleError(Object e) async {
    if (e is ApiException && e.unauthorized) await signOut();
  }
}
