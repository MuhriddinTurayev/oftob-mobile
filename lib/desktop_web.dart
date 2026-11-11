import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import 'l10n.dart';

/// Kompyuter (Windows): sahifa dasturning ICHIDA ochiladi (Windows'ning o'rnatilgan WebView2 dvigateli).
/// Sahifa telefondagi kabi dastur ichidagi kesh-proksi orqali ochiladi — internet bo'lmasa ham saqlangan nusxadan ishlaydi.
/// WebView2 topilmasa — oddiy brauzerda ochish tugmasi chiqadi.
class DesktopWeb extends StatefulWidget {
  const DesktopWeb({super.key, required this.url});

  final String url;

  @override
  State<DesktopWeb> createState() => _DesktopWebState();
}

class _DesktopWebState extends State<DesktopWeb> {
  final _c = WebviewController();
  StreamSubscription<LoadingState>? _sub;
  bool _ready = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final v = await WebviewController.getWebViewVersion();
      if (v == null || v.isEmpty) throw StateError('WebView2 yo\'q');
      await _c.initialize();
      await _c.setBackgroundColor(Colors.black);
      await _c.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      _sub = _c.loadingState.listen((s) {
        if (mounted) setState(() => _loading = s == LoadingState.loading);
      });
      await _c.loadUrl(widget.url);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.web_asset_off_rounded, size: 46, color: cs.outline),
            const SizedBox(height: 12),
            Text(tr("Sahifani dastur ichida ochib bo'lmadi"), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(tr("Kompyuteringizda «Microsoft Edge WebView2» topilmadi. Sahifani brauzerda ochishingiz mumkin."), textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_browser_rounded), label: Text(tr('Brauzerda ochish'))),
          ]),
        ),
      );
    }
    return Stack(children: [
      Positioned.fill(child: ColoredBox(color: Colors.black, child: _ready ? Webview(_c) : const SizedBox.shrink())),
      if (!_ready || _loading) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator()),
    ]);
  }
}
