import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import '../api.dart';
import '../company.dart';
import '../session.dart';
import 'staff_login.dart';
import '../platform/platform_home.dart';
import '../l10n.dart';
import '../widgets.dart';

/// Kirish: foydalanuvchi faqat korxonani tanlaydi (kod yozadi yoki oxirgilaridan bosadi).
/// Server manzili, port va boshqa texnik narsalar ko'rsatilmaydi.
/// Dasturchi sozlamalari — logotipni uzoq bosganda.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Qaysi nusxa ishlayotganini ko'rsatadi: «Mahalliy ilova» + GitHub yig'ish raqami (Actions `BUILD_SHA` beradi).
const _sha = String.fromEnvironment('BUILD_SHA', defaultValue: 'dev');
final _version = 'Mahalliy ilova · ${_sha.length > 7 ? _sha.substring(0, 7) : _sha}';

class _LoginScreenState extends State<LoginScreen> {
  final _code = TextEditingController();
  CompanyInfo? _found;
  bool _busy = false;
  String? _error;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    // boshqa qurilmadan «seansni yopish» bosilgan bo'lsa — nima bo'lganini tushuntiramiz
    if (s.kicked) {
      s.kicked = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 6), content: Text(tr("Bu qurilmadagi seans yopildi (boshqa qurilmadan yoki parol o'zgargan). Qaytadan kiring."))));
        }
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final code = parseCompanyCode(_code.text);
    if (code == null) {
      setState(() {
        _found = null;
        _error = 'Korxona kodini yozing, masalan: navruz-qurilish';
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _found = null;
    });
    try {
      final c = await lookupCompany(s.serverUrl, code);
      if (!mounted) return;
      setState(() {
        _found = c;
        _error = c == null ? 'Bunday korxona topilmadi. Kodni tekshiring.\n(server: ${Uri.parse(s.serverUrl).host})' : null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(CompanyInfo c) async {
    HapticFeedback.selectionClick();
    await s.rememberCompany(c);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StaffLoginScreen(session: s, company: c)));
  }

  void _developer() {
    final url = TextEditingController(text: s.serverUrl);
    final key = TextEditingController();
    String? err;
    bool busy = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Dasturchi sozlamalari', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Oddiy foydalanuvchi uchun emas.', style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
            const SizedBox(height: 16),
            TextField(controller: url, keyboardType: TextInputType.url, autocorrect: false, decoration: InputDecoration(labelText: tr('Server'), border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: key, obscureText: true, autocorrect: false, decoration: InputDecoration(labelText: tr('API kalit (ixtiyoriy)'), border: OutlineInputBorder())),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      set(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        if (key.text.trim().isNotEmpty) {
                          await s.signIn(url.text, key.text);
                        } else {
                          await s.setServer(url.text);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      } on ApiException catch (e) {
                        set(() {
                          err = e.message;
                          busy = false;
                        });
                      }
                    },
              child: const Text('Saqlash'),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onLongPress: _developer,
                    behavior: HitTestBehavior.opaque,
                    child: Column(children: [
                      Image.asset('assets/logo.png', height: 96),
                      const SizedBox(height: 10),
                      Text('Oftob Building', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('Xush kelibsiz', style: TextStyle(color: cs.outline)),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  const Center(child: LangSwitch()),
                  const SizedBox(height: 22),
                  Text('Korxonani tanlang', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  if (s.recent.isNotEmpty) ...[
                    for (final c in s.recent)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CompanyTile(c, onTap: () => _open(c), onRemove: () => s.forgetCompany(c.slug)),
                      ),
                    const SizedBox(height: 8),
                    Text('Boshqa korxona', style: TextStyle(color: cs.outline, fontSize: 13)),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _code,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    onChanged: (_) => setState(() {
                      _found = null;
                      _error = null;
                    }),
                    decoration: InputDecoration(
                      hintText: tr('Korxona kodi'),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      suffixIcon: _busy
                          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                          : IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
                    ),
                  ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: cs.error))),
                  if (_found != null) ...[
                    const SizedBox(height: 12),
                    _CompanyTile(_found!, onTap: () => _open(_found!), highlight: true),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    'Korxona kodini rahbaringizdan oling. U korxona havolasining boshidagi so\'z.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.outline, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlatformLoginScreen(session: widget.session))),
                      icon: Icon(Icons.admin_panel_settings_outlined, size: 18, color: cs.outline),
                      label: Text('Platforma administratori kirishi', style: TextStyle(color: cs.outline, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_version, textAlign: TextAlign.center, style: TextStyle(color: cs.outline.withValues(alpha: 0.7), fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile(this.c, {required this.onTap, this.onRemove, this.highlight = false});

  final CompanyInfo c;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: highlight ? cs.primaryContainer : cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            CircleAvatar(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, child: Text(c.initials, style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: 14),
            Expanded(child: Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (onRemove != null) IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.close, size: 18, color: cs.outline), onPressed: onRemove, tooltip: tr('Ro\'yxatdan olib tashlash')),
            Icon(Icons.chevron_right, color: cs.outline),
          ]),
        ),
      ),
    );
  }
}
