import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'api.dart';

/// Ilovaning ikki rejimi:
///  * **Platforma** (asosiy) — veb-dasturning o'zi ilova ichida ochiladi, hamma funksiya ishlaydi (login/parol bilan);
///  * **API kalit** (tezkor) — faqat asosiy bo'limlar, `/api/v1` orqali, mahalliy ekranlar.
class Session extends ChangeNotifier {
  Session({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const defaultServer = 'https://oftob.37-60-247-120.sslip.io';

  final FlutterSecureStorage _storage;

  // umumiy
  String serverUrl = defaultServer;
  bool loading = true;

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
      final url = await _storage.read(key: 'server');
      if (url != null && url.isNotEmpty) serverUrl = url;
      slug = await _storage.read(key: 'slug') ?? '';
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
