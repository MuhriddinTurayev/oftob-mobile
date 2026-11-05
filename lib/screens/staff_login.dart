import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../company.dart';
import '../session.dart';
import 'forgot_password.dart';

/// Xodim kirishi: korxona tanlangan, endi login (email yoki telefon) va parol.
/// Parol qurilmada saqlanmaydi: server shaxsiy kalit beradi, ilova faqat shu kalitni saqlaydi.
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key, required this.session, required this.company});

  final Session session;
  final CompanyInfo company;

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final _login = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _forgot() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ForgotPasswordScreen(session: widget.session, company: widget.company, login: _login.text.trim())));
    if (ok == true && mounted) {
      _pass.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Parol o'zgartirildi. Yangi parol bilan kiring.")));
    }
  }

  Future<void> _submit() async {
    final login = _login.text.trim();
    if (login.isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Login va parolni kiriting.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.staffSignIn(company: widget.company.slug, email: login, password: _pass.text);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Kirib bo\'lmadi. Internetni tekshiring.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.company;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      CircleAvatar(radius: 26, backgroundColor: cs.primary, foregroundColor: cs.onPrimary, child: Text(c.initials, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 14),
                      Expanded(child: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                    ]),
                    const SizedBox(height: 28),
                    Text('Kirish', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Rahbar bergan login va parol bilan kiring.', style: TextStyle(color: cs.outline)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _login,
                      autofillHints: const [AutofillHints.username, AutofillHints.email, AutofillHints.telephoneNumber],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _passFocus.requestFocus(),
                      decoration: _dec(context, 'Email yoki telefon', Icons.person_outline),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass,
                      focusNode: _passFocus,
                      autofillHints: const [AutofillHints.password],
                      obscureText: !_show,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _submit(),
                      decoration: _dec(context, 'Parol', Icons.lock_outline).copyWith(
                        suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _show = !_show)),
                      ),
                    ),
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: _busy ? null : _forgot, child: const Text('Parolni unutdingizmi?')),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Kirish', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(BuildContext context, String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );
}
