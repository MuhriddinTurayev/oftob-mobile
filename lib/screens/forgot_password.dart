import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import '../api.dart';
import '../company.dart';
import '../session.dart';
import '../l10n.dart';

/// Parolni tiklash: 6 xonali kod xodimning emailiga va Telegram'iga (qaysi biri ulangan bo'lsa) yuboriladi (10 daqiqa amal qiladi), kod + yangi parol kiritiladi.
/// Muvaffaqiyatli bo'lsa `true` bilan yopiladi — kirish ekrani "yangi parol bilan kiring" deydi.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.session, required this.company, this.login = ''});

  final Session session;
  final CompanyInfo company;
  final String login;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _login = TextEditingController(text: widget.login);
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  bool _show = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _login.dispose();
    _code.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) t.cancel();
    });
  }

  void _fail(String m) {
    if (!mounted) return;
    setState(() {
      _error = m;
      _busy = false;
    });
  }

  Future<void> _send() async {
    final login = _login.text.trim();
    if (login.isEmpty) {
      setState(() => _error = 'Email yoki telefonni kiriting.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.forgot(widget.session.serverUrl, company: widget.company.slug, login: login);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _busy = false;
      });
      _startCooldown();
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail("Yuborib bo'lmadi. Internetni tekshiring.");
    }
  }

  Future<void> _reset() async {
    final code = _code.text.trim();
    final p = _pass.text;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Email yoki Telegram\'dagi 6 xonali kodni kiriting.');
      return;
    }
    if (p.length < 8 || !RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
      setState(() => _error = "Parol kamida 8 belgi, harf va raqamdan iborat bo'lsin.");
      return;
    }
    if (p != _pass2.text) {
      setState(() => _error = 'Ikkala parol bir xil emas.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.resetPassword(widget.session.serverUrl, company: widget.company.slug, login: _login.text.trim(), code: code, password: p);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail("Parolni o'zgartirib bo'lmadi. Internetni tekshiring.");
    }
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: tr(label),
        prefixIcon: Icon(icon),
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );

  Widget _spinnerOr(String text) => _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Parolni tiklash', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(widget.company.name, style: TextStyle(color: cs.outline)),
                const SizedBox(height: 22),
                TextField(
                  controller: _login,
                  enabled: !_sent && !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: _dec('Email yoki telefon', Icons.person_outline),
                ),
                if (!_sent) ...[
                  const SizedBox(height: 10),
                  Text("Tasdiqlash kodi hisobingizdagi emailga va (ulangan bo'lsa) Telegram'ga yuboriladi. Ikkalasi ham bo'lmasa — rahbaringizga murojaat qiling, u yangi parol beradi.", style: TextStyle(color: cs.outline, fontSize: 13.5)),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: _busy ? null : _send, child: _spinnerOr('Kod yuborish')),
                ] else ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                    child: const Text("Agar hisob topilsa, 6 xonali kod emailingizga va Telegram'ga yuborildi (10 daqiqa amal qiladi). Emailda «Spam» papkasini ham tekshiring. Kod kelmasa — rahbaringizga murojaat qiling."),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec('Tasdiqlash kodi', Icons.sms_outlined).copyWith(counterText: ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: !_show,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: _dec('Yangi parol', Icons.lock_outline).copyWith(
                      helperText: tr('Kamida 8 belgi, harf va raqam'),
                      suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _show = !_show)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _pass2, obscureText: !_show, autocorrect: false, enableSuggestions: false, onSubmitted: (_) => _reset(), decoration: _dec('Yangi parolni takrorlang', Icons.lock_reset)),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: _busy ? null : _reset, child: _spinnerOr("Parolni o'zgartirish")),
                  const SizedBox(height: 6),
                  TextButton(onPressed: _busy || _cooldown > 0 ? null : _send, child: Text(_cooldown > 0 ? 'Kodni qayta yuborish ($_cooldown s)' : 'Kodni qayta yuborish')),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Icon(Icons.error_outline, size: 20, color: cs.onErrorContainer),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!, style: TextStyle(color: cs.onErrorContainer))),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
