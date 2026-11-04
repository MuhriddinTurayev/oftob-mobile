import 'package:flutter/material.dart';

import '../api.dart';
import '../session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _url = TextEditingController(text: widget.session.serverUrl);
  late final _slug = TextEditingController(text: widget.session.slug);
  final _key = TextEditingController();
  bool _full = true; // true — Platforma (to'liq), false — API kalit (tezkor)
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _slug.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_url.text.trim().isEmpty) {
      setState(() => _error = 'Server manzilini kiriting.');
      return;
    }
    if (_full) {
      await widget.session.startWeb(_url.text, _slug.text);
      return;
    }
    if (_key.text.trim().isEmpty) {
      setState(() => _error = 'API kalitni kiriting.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.signIn(_url.text, _key.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.apartment, size: 64, color: cs.primary),
                  const SizedBox(height: 12),
                  Text('Oftob CRM', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Qurilish va sotuv boshqaruvi', textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Platforma'), icon: Icon(Icons.dashboard_outlined)),
                      ButtonSegment(value: false, label: Text('API kalit'), icon: Icon(Icons.key_outlined)),
                    ],
                    selected: {_full},
                    onSelectionChanged: (v) => setState(() {
                      _full = v.first;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Server manzili', prefixIcon: Icon(Icons.dns_outlined), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  if (_full) ...[
                    TextField(
                      controller: _slug,
                      autocorrect: false,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Kompaniya manzili (ixtiyoriy)',
                        hintText: 'masalan: navruz',
                        helperText: 'Xodimlar uchun: erp/c/… dagi so\'z. Platforma egasi bo\'sh qoldiradi.',
                        prefixIcon: Icon(Icons.business_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else
                    TextField(
                      controller: _key,
                      obscureText: _hide,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'API kalit (oft_…)',
                        prefixIcon: const Icon(Icons.key_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide)),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: cs.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Kirish'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _full
                        ? 'Platformaning hamma bo\'limlari ochiladi. Email va parolni keyingi oynada kiritasiz.'
                        : 'Tezkor rejim: faqat obyektlar, lidlar, kassa, ombor, vazifalar. Kalit: Kompaniya → API va integratsiyalar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.outline, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
