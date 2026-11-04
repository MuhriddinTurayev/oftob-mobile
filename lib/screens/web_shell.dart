import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart' as android;
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart' as wk;

import '../session.dart';

/// Platformaning o'zi (veb-dastur) ilova ichida: hamma bo'lim, rol va huquqlar xuddi saytdagidek ishlaydi.
class WebShell extends StatefulWidget {
  const WebShell({super.key, required this.session});

  final Session session;

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  late final WebViewController _c;
  int _progress = 0;
  String _title = 'Oftob CRM';
  bool _canGoBack = false;
  bool _failed = false;
  bool _triedCompanyLink = false;

  Session get s => widget.session;
  Uri get _server => Uri.parse(s.serverUrl);
  Uri get _start => s.slug.isEmpty ? _server.resolve('/login') : _server.resolve('/c/${s.slug}');

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        onPageStarted: (_) => mounted ? setState(() => _failed = false) : null,
        onPageFinished: (_) => _refreshState(),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            if (mounted) setState(() => _failed = true);
          }
        },
        onNavigationRequest: _onNavigate,
      ));
    _setupAndroid();
    _setupIos();
    _c.loadRequest(_start);
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
    // boshqa sayt (Telegram, Instagram …) — brauzerda
    if (uri.host != _server.host && req.isMainFrame) {
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

  Future<void> _refreshState() async {
    final back = await _c.canGoBack();
    final t = await _c.getTitle();
    if (!mounted) return;
    setState(() {
      _canGoBack = back;
      if (t != null && t.isNotEmpty) _title = t.split('—').first.trim();
      _progress = 100;
    });
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
      case 'logout':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Chiqish'),
            content: const Text('Hisobdan chiqib, server tanlash oynasiga qaytasizmi?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Yo\'q')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Chiqish')),
            ],
          ),
        );
        if (ok == true) await s.leaveWeb();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _c.canGoBack()) await _c.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 44,
          title: Text(_title, style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis),
          bottom: _progress < 100
              ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress / 100, minHeight: 2))
              : null,
          actions: [
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'home', child: Text('Bosh sahifa')),
                PopupMenuItem(value: 'reload', child: Text('Yangilash')),
                PopupMenuItem(value: 'browser', child: Text('Brauzerda ochish')),
                PopupMenuItem(value: 'logout', child: Text('Chiqish / server')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _failed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off, size: 48),
                      const SizedBox(height: 12),
                      Text('Serverga ulanib bo\'lmadi:\n${s.serverUrl}', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(onPressed: () => _c.loadRequest(_start), icon: const Icon(Icons.refresh), label: const Text('Qayta urinish')),
                      TextButton(onPressed: s.leaveWeb, child: const Text('Serverni o\'zgartirish')),
                    ]),
                  ),
                )
              : WebViewWidget(controller: _c),
        ),
      ),
    );
  }
}
