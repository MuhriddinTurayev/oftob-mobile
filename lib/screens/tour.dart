import 'package:flutter/material.dart' hide Text;

import 'package:webview_flutter/webview_flutter.dart';

import '../session.dart';
import '../webcache.dart';
import '../widgets.dart';
import '../l10n.dart';

/// Saytdagi 3D va 360° sahifasini ilova ichida ochadi. Server 90 soniyalik bir martalik havola beradi
/// (shaxsiy kalit bilan) — parol so'ralmaydi, havola faqat shu sahifaga olib boradi.
class TourScreen extends StatefulWidget {
  const TourScreen({super.key, required this.session, required this.objectId, required this.view, required this.title, this.apartment});

  final Session session;
  final String objectId;
  final String view; // '3d' | 'locate'
  final String title;
  final String? apartment;

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  WebViewController? _c;
  String? _error;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _progress = 0;
    });
    try {
      // sahifa telefon ichidagi kesh-proksi orqali ochiladi: internet bo'lmasa saqlangan nusxadan ishlaydi
      final url = await WebCache.viewUrl(widget.session, widget.objectId, widget.view, apartment: widget.apartment);
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) setState(() => _error = 'Sahifani ochib bo\'lmadi. Internetni tekshiring.');
          },
        ));
      await c.loadRequest(Uri.parse(url));
      if (mounted) setState(() => _c = c);
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [IconButton(onPressed: _open, icon: const Icon(Icons.refresh))]),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _open)
          : Stack(children: [
              if (_c != null) WebViewWidget(controller: _c!),
              if (_c == null || _progress < 100) LinearProgressIndicator(value: _c == null ? null : _progress / 100),
            ]),
    );
  }
}
