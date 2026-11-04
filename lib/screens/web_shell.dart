import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart' as android;
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart' as wk;

import '../session.dart';

/// Platformaning o'zi (veb-dastur) ilova ichida: hamma bo'lim, rol va huquqlar xuddi saytdagidek ishlaydi.
/// Ilova o'z panelini qo'shmaydi: ekran to'liq saytning mobil dizayniga beriladi (yuqori panel, pastki menyu — saytniki).
/// Ilova sifatida sezilishi uchun: brauzer belgilari yo'q (kattalashtirish, matn belgilash, bosish "soyasi"),
/// holat paneli sahifa rangiga moslanadi, ochilishda ilova ekrani ko'rsatiladi.
class WebShell extends StatefulWidget {
  const WebShell({super.key, required this.session});

  final Session session;

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> with WidgetsBindingObserver {
  late final WebViewController _c;
  int _progress = 0;
  bool _canGoBack = false;
  bool _failed = false;
  bool _ready = false; // birinchi sahifa yuklandi — ilova ekrani yo'qoladi
  bool _triedCompanyLink = false;
  bool _showBar = false; // yuklanish chizig'i faqat uzoq (700 ms+) to'liq yuklanishda
  Timer? _barTimer;
  DateTime? _lastRecover;
  Color _bg = const Color(0xFFF4F5FA);

  Session get s => widget.session;
  Uri get _server => Uri.parse(s.serverUrl);
  Uri get _start => s.slug.isEmpty ? _server.resolve('/login') : _server.resolve('/c/${s.slug}');

  /// Brauzer belgilarini olib tashlaydi: kattalashtirish, matn belgilash, bosish soyasi, tortib yangilanish "sakrashi".
  static const _appJs = r'''
(function () {
  if (window.__oftobApp) return; window.__oftobApp = 1;
  var vp = 'width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover';
  var m = document.querySelector('meta[name=viewport]');
  if (m) { m.setAttribute('content', vp); } else { m = document.createElement('meta'); m.name = 'viewport'; m.content = vp; document.head.appendChild(m); }
  var st = document.createElement('style');
  st.textContent = 'html{-webkit-text-size-adjust:100%;overscroll-behavior-x:none}'
    + '*{-webkit-tap-highlight-color:transparent;-webkit-touch-callout:none}'
    + 'body{-webkit-user-select:none;user-select:none}'
    + 'input,textarea,[contenteditable=true]{-webkit-user-select:text;user-select:text}'
    + 'a,button,[role=button],select,label,summary{touch-action:manipulation}';
  document.head.appendChild(st);
  document.documentElement.classList.add('in-app');
})();
''';

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_bg)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() => _failed = false);
          _barTimer?.cancel();
          _barTimer = Timer(const Duration(milliseconds: 700), () {
            if (mounted && _progress < 100) setState(() => _showBar = true);
          });
        },
        onPageFinished: (_) => _onLoaded(),
        onWebResourceError: (e) {
          if (!(e.isForMainFrame ?? true)) return;
          // WKWebView kontent jarayoni xotira yoki tizim sabab o'chirilsa (oq ekran) — xato ko'rsatmay, sahifani qayta ochamiz
          if (e.errorType == WebResourceErrorType.webContentProcessTerminated) {
            _recover();
            return;
          }
          if (mounted) setState(() => _failed = true);
        },
        onNavigationRequest: _onNavigate,
      ));
    WidgetsBinding.instance.addObserver(this);
    _setupAndroid();
    _setupIos();
    _setupMedia();
    _boot();
  }

  /// Sayt "ilova ichidaman" ekanini birinchi chizishdan oldin biladi (cookie): sahifa "veb ko'rinishida" yonib o'tmaydi.
  Future<void> _boot() async {
    try {
      await WebViewCookieManager().setCookie(WebViewCookie(
        name: 'oftob_app',
        value: !kIsWeb && Platform.isIOS ? 'ios' : 'android',
        domain: _server.host,
        path: '/',
      ));
    } catch (_) {}
    await _c.loadRequest(_start);
  }

  @override
  void dispose() {
    _barTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _health();
  }

  /// Ilova orqa fondan qaytganda sahifa tirikligini tekshiradi (iOS xotira tanqisligida kontent jarayonini o'ldiradi).
  Future<void> _health() async {
    try {
      final r = await _c.runJavaScriptReturningResult('document.readyState').timeout(const Duration(seconds: 3));
      final t = '$r';
      if (!t.contains('complete') && !t.contains('interactive') && !t.contains('loading')) _recover();
    } catch (_) {
      _recover();
    }
  }

  /// Joriy sahifani qayta ochish (5 soniyada bir martadan ko'p emas — cheksiz aylanmasligi uchun).
  Future<void> _recover() async {
    final now = DateTime.now();
    if (_lastRecover != null && now.difference(_lastRecover!) < const Duration(seconds: 5)) return;
    _lastRecover = now;
    String? u;
    try {
      u = await _c.currentUrl();
    } catch (_) {}
    final uri = u == null ? null : Uri.tryParse(u);
    await _c.loadRequest(uri != null && uri.hasScheme ? uri : _start);
  }

  /// Mikrofon/kamera: faqat o'z sahifalarimiz so'raydi (tashqi saytlar brauzerga o'tadi), shuning uchun WebKit'ning
  /// har safargi qo'shimcha so'rovi o'rniga ruxsat beramiz. iOS'ning o'z (tizim) so'rovi baribir bir marta chiqadi.
  void _setupMedia() {
    _c.platform.setOnPlatformPermissionRequest((request) async {
      await request.grant();
    });
  }

  /// GPS (xodimlar kelgan/ketgan belgisi) va rasm tanlash Android WebView'da ishlashi uchun.
  void _setupAndroid() {
    if (kIsWeb || !Platform.isAndroid) return;
    final p = _c.platform;
    if (p is android.AndroidWebViewController) {
      p.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          var perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
          final ok = perm == LocationPermission.always || perm == LocationPermission.whileInUse;
          return android.GeolocationPermissionsResponse(allow: ok, retain: ok);
        },
      );
    }
  }

  /// iPhone: ekran chetidan surib orqaga qaytish (Safari'dagidek).
  void _setupIos() {
    if (kIsWeb || !Platform.isIOS) return;
    final p = _c.platform;
    if (p is wk.WebKitWebViewController) p.setAllowsBackForwardNavigationGestures(true);
  }

  Future<NavigationDecision> _onNavigate(NavigationRequest req) async {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;

    // tel:, mailto:, tg:, whatsapp: … — tashqi ilovada
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      if (uri.scheme != 'about' && uri.scheme != 'data' && uri.scheme != 'blob') {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'blob' ? NavigationDecision.navigate : NavigationDecision.prevent;
    }
    // boshqa sayt (Telegram, Instagram …) — brauzerda. Platformaning o'z kompaniya manzillari
    // (nom.oftob….sslip.io) ilova ichida qoladi.
    final own = uri.host == _server.host || uri.host.endsWith('.${_server.host}');
    if (!own && req.isMainFrame) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return NavigationDecision.prevent;
    }
    // Kompaniya xodimi: umumiy /login (faqat platforma egalari uchun) o'rniga kompaniya havolasi
    if (s.slug.isNotEmpty && !_triedCompanyLink && uri.host == _server.host && uri.path == '/login' && req.isMainFrame) {
      _triedCompanyLink = true;
      _c.loadRequest(_server.resolve('/c/${s.slug}'));
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  /// Sahifa yuklandi: ilova ko'rinishi, orqaga tugmasi holati, holat paneli rangi sahifaga moslanadi.
  Future<void> _onLoaded() async {
    try {
      await _c.runJavaScript(_appJs);
      await _c.runJavaScript("document.documentElement.classList.add('in-${!kIsWeb && Platform.isIOS ? 'ios' : 'android'}')");
    } catch (_) {}
    final back = await _c.canGoBack();
    Color? bg;
    try {
      final raw = await _c.runJavaScriptReturningResult('getComputedStyle(document.body).backgroundColor');
      bg = _parseColor('$raw');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _canGoBack = back;
      _progress = 100;
      _showBar = false;
      _ready = true;
      if (bg != null) _bg = bg;
    });
    // holat paneli yozuvlari: qorong'i fonda oq, yorug' fonda qora
    final dark = ThemeData.estimateBrightnessForColor(_bg) == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
  }

  /// "rgb(244, 245, 250)" / "rgba(0, 0, 0, 0)" → rang (shaffof bo'lsa — null)
  static Color? _parseColor(String raw) {
    final m = RegExp(r'rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)(?:[,\s/]+([\d.]+))?').firstMatch(raw);
    if (m == null) return null;
    final a = m.group(4) == null ? 1.0 : double.tryParse(m.group(4)!) ?? 1.0;
    if (a < 0.5) return null;
    return Color.fromARGB(255, int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'home':
        await _c.loadRequest(_start);
      case 'reload':
        await _c.reload();
      case 'browser':
        final u = await _c.currentUrl();
        if (u != null) await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
      case 'server':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Korxonani almashtirish'),
            content: const Text('Hisobdan chiqib, korxona tanlash oynasiga qaytasizmi?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Yo\'q')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Chiqish')),
            ],
          ),
        );
        if (ok == true) await s.leaveWeb();
    }
  }

  /// Holat paneli (soat, batareya) ustini uzoq bosish — ilova menyusi: bosh sahifa, yangilash, server, chiqish.
  /// Saytning o'z paneli ustida ikkinchi panel bo'lmasligi uchun menyu yashirin.
  void _openMenu() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in const [
            ('home', Icons.home_outlined, 'Bosh sahifa'),
            ('reload', Icons.refresh, 'Yangilash'),
            ('browser', Icons.open_in_browser, 'Brauzerda ochish'),
            ('server', Icons.swap_horiz, 'Korxonani almashtirish'),
          ])
            ListTile(
              leading: Icon(e.$2),
              title: Text(e.$3),
              onTap: () {
                Navigator.pop(ctx);
                _menu(e.$1);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _c.canGoBack()) await _c.goBack();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                child: _failed
                    ? _ErrorView(onRetry: () => _c.loadRequest(_start), onChange: s.leaveWeb)
                    : WebViewWidget(controller: _c),
              ),
            ),
            // yuklanish chizig'i — faqat to'liq yuklanishda (sahifalar orasida o'tish saytning o'zida silliq)
            if (_showBar && _progress < 100 && _ready)
              Positioned(top: top, left: 0, right: 0, child: LinearProgressIndicator(value: _progress / 100, minHeight: 2, backgroundColor: Colors.transparent)),
            // holat paneli ustida uzoq bosish → ilova menyusi
            Positioned(top: 0, left: 0, right: 0, height: top < 24 ? 24 : top, child: GestureDetector(behavior: HitTestBehavior.translucent, onLongPress: _openMenu)),
            // birinchi yuklanish: ilova ekrani
            if (!_ready)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.apartment, size: 72, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 12),
                      Text('Oftob CRM', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 28),
                      const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry, required this.onChange});

  final VoidCallback onRetry;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          const Text('Aloqa yo\'q.\nInternetni tekshirib, qayta urinib ko\'ring.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Qayta urinish')),
          TextButton(onPressed: onChange, child: const Text('Korxonani almashtirish')),
        ]),
      ),
    );
  }
}
