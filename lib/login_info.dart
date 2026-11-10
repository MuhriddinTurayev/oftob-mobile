import 'dart:convert';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as w show Text;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'l10n.dart';
import 'session.dart';
import 'theme.dart';

/// Kirish oynasidagi «Kirish uchun bog'laning» ma'lumoti (platforma admini sozlaydi; bo'sh — ko'rinmaydi)
class LoginInfo {
  const LoginInfo({this.note = '', this.phone = '', this.telegram = ''});

  final String note, phone, telegram;

  bool get isEmpty => note.isEmpty && phone.isEmpty && telegram.isEmpty;

  factory LoginInfo.fromJson(Map m) => LoginInfo(note: '${m['note'] ?? ''}'.trim(), phone: '${m['phone'] ?? ''}'.trim(), telegram: '${m['telegram'] ?? ''}'.trim().replaceFirst('@', ''));

  Map<String, String> toJson() => {'note': note, 'phone': phone, 'telegram': telegram};

  static const _store = FlutterSecureStorage();

  /// Oxirgi saqlangan nusxa (internet bo'lmasa ham darhol ko'rinadi), keyin serverdan yangisi
  static Future<LoginInfo?> cached() async {
    try {
      final r = await _store.read(key: 'login_info');
      return r == null ? null : LoginInfo.fromJson(jsonDecode(r) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<LoginInfo?> fetch(String serverUrl) async {
    final m = await ApiClient.loginInfo(serverUrl);
    if (m == null) return null;
    final i = LoginInfo.fromJson(m);
    try {
      await _store.write(key: 'login_info', value: jsonEncode(i.toJson()));
    } catch (_) {}
    return i;
  }
}

/// Kirish oynasidagi blok: izoh + «Qo'ng'iroq qilish» / «Telegram» tugmalari
class LoginInfoCard extends StatefulWidget {
  const LoginInfoCard({super.key, required this.serverUrl});

  final String serverUrl;

  @override
  State<LoginInfoCard> createState() => _LoginInfoCardState();
}

class _LoginInfoCardState extends State<LoginInfoCard> {
  LoginInfo? _i;

  @override
  void initState() {
    super.initState();
    LoginInfo.cached().then((c) {
      if (mounted && c != null && _i == null) setState(() => _i = c);
    });
    LoginInfo.fetch(widget.serverUrl).then((f) {
      if (mounted && f != null) setState(() => _i = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final i = _i;
    if (i == null || i.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Glass(
      radius: 22,
      shadow: false,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const IconTile(icon: Icons.support_agent_rounded, color: Brand.teal, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Kirish uchun bog'laning", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              if (i.note.isNotEmpty) ...[
                const SizedBox(height: 3),
                // izohni platforma admini yozadi — tarjima qilinmaydi
                w.Text(i.note, style: TextStyle(color: cs.outline, fontSize: 13, height: 1.3)),
              ],
            ]),
          ),
        ]),
        if (i.phone.isNotEmpty || i.telegram.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            if (i.phone.isNotEmpty)
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse('tel:${i.phone.replaceAll(RegExp(r'[^0-9+]'), '')}')),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: FittedBox(fit: BoxFit.scaleDown, child: w.Text(i.phone, maxLines: 1)),
                ),
              ),
            if (i.phone.isNotEmpty && i.telegram.isNotEmpty) const SizedBox(width: 8),
            if (i.telegram.isNotEmpty)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://t.me/${i.telegram}'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Telegram'),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Platforma admini: kirish oynasidagi blokni o'zgartirish yoki o'chirish
class LoginInfoSettingsScreen extends StatefulWidget {
  const LoginInfoSettingsScreen({super.key, required this.session});

  final Session session;

  @override
  State<LoginInfoSettingsScreen> createState() => _LoginInfoSettingsScreenState();
}

class _LoginInfoSettingsScreenState extends State<LoginInfoSettingsScreen> {
  final _note = TextEditingController();
  final _phone = TextEditingController();
  final _tg = TextEditingController();
  bool _loading = true, _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    _phone.dispose();
    _tg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = Map<String, dynamic>.from((await widget.session.papi!.pGet('/login-info')) as Map);
      _note.text = '${d['note'] ?? ''}';
      _phone.text = '${d['phone'] ?? ''}';
      _tg.text = '${d['telegram'] ?? ''}';
    } catch (e) {
      _err = e is ApiException ? e.message : '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save({bool clear = false}) async {
    if (clear) {
      _note.clear();
      _phone.clear();
      _tg.clear();
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.session.papi!.pSend('POST', '/login-info', {'note': _note.text.trim(), 'phone': _phone.text.trim(), 'telegram': _tg.text.trim()});
      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(clear ? tr("Blok o'chirildi — kirish oynasida ko'rinmaydi") : tr('Saqlandi'))));
      }
    } catch (e) {
      await widget.session.handleError(e);
      _err = e is ApiException ? e.message : '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Kirish oynasi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom), children: [
              Text("Ilovani yuklab olgan odam birinchi ekranda shu ma'lumotni ko'radi: kimga qo'ng'iroq qilib, kirish olishni. Bo'sh maydon ko'rinmaydi.",
                  style: TextStyle(color: cs.outline, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(controller: _note, maxLines: 3, maxLength: 300, decoration: InputDecoration(labelText: tr('Matn'), hintText: tr("Masalan: Kirish uchun korxona kodi va login kerak. Ulanish va demo uchun qo'ng'iroq qiling."))),
              const SizedBox(height: 10),
              TextField(controller: _phone, keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]'))], decoration: InputDecoration(labelText: tr('Telefon'), hintText: '+998 90 123 45 67')),
              const SizedBox(height: 12),
              TextField(controller: _tg, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[@A-Za-z0-9_]'))], decoration: const InputDecoration(labelText: 'Telegram', hintText: '@oftob_support')),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: w.Text(_err!, style: TextStyle(color: cs.error))),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.check_rounded), label: const Text('Saqlash'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _save(clear: true),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text("Blokni o'chirish"),
                style: OutlinedButton.styleFrom(foregroundColor: cs.error, minimumSize: const Size.fromHeight(50)),
              ),
            ]),
    );
  }
}
