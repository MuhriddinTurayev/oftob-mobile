import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../l10n.dart';
import '../session.dart';
import '../theme.dart';

/* Platforma administratori: parolni tiklash (email), pochta (SMTP), to'lov rekvizitlari, SI kalitlarini ulash */

List<Map<String, dynamic>> _maps(Object? v) => ((v as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

void _snack(BuildContext context, String t) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(t)));

/* ---------------------------------------- Parolni unutdim (email) ---------------------------------------- */

class PlatformForgotScreen extends StatefulWidget {
  const PlatformForgotScreen({super.key, required this.serverUrl, this.email = ''});
  final String serverUrl;
  final String email;

  @override
  State<PlatformForgotScreen> createState() => _PlatformForgotScreenState();
}

class _PlatformForgotScreenState extends State<PlatformForgotScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _pass = TextEditingController();
  bool _sent = false, _busy = false, _hide = true;
  String? _err;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (!_sent) {
        await ApiClient.platformPublic(widget.serverUrl, '/forgot', {'email': _email.text.trim()});
        setState(() => _sent = true);
      } else {
        await ApiClient.platformPublic(widget.serverUrl, '/reset', {'email': _email.text.trim(), 'code': _code.text.trim(), 'password': _pass.text});
        if (!mounted) return;
        _snack(context, tr("Parol o'zgartirildi. Yangi parol bilan kiring."));
        Navigator.pop(context, _email.text.trim());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Parolni tiklash')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Text(_sent ? tr("Emailga 6 xonali kod yuborildi (10 daqiqa amal qiladi). Kodni va yangi parolni kiriting.") : tr('Platforma administratori emailini kiriting — unga parolni tiklash kodi keladi.'),
              style: TextStyle(color: cs.outline)),
          const SizedBox(height: 16),
          Glass(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(controller: _email, enabled: !_sent, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: InputDecoration(labelText: tr('Email'), prefixIcon: const Icon(Icons.alternate_email_rounded))),
              if (_sent) ...[
                const SizedBox(height: 12),
                TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, decoration: InputDecoration(labelText: tr('Emaildagi kod'), prefixIcon: const Icon(Icons.pin_rounded), counterText: '')),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    labelText: tr('Yangi parol'),
                    helperText: tr('Kamida 8 belgi, harf va raqam'),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded)),
                  ),
                ),
              ],
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700))),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _go,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(_sent ? tr("Parolni o'zgartirish") : tr('Kod yuborish')),
                ),
              ),
              if (_sent) TextButton(onPressed: _busy ? null : () => setState(() => _sent = false), child: const Text('Kodni qayta yuborish')),
            ]),
          ),
        ],
      ),
    );
  }
}

/* ---------------------------------------- Pochta (SMTP) ---------------------------------------- */

class MailSettingsScreen extends StatefulWidget {
  const MailSettingsScreen({super.key, required this.session});
  final Session session;

  @override
  State<MailSettingsScreen> createState() => _MailSettingsScreenState();
}

class _MailSettingsScreenState extends State<MailSettingsScreen> {
  final _host = TextEditingController(), _port = TextEditingController(), _user = TextEditingController(), _pass = TextEditingController();
  final _from = TextEditingController(), _name = TextEditingController(), _to = TextEditingController();
  String _enc = 'tls';
  bool _loading = true, _busy = false, _hasPass = false, _on = false;
  List<Map<String, dynamic>> _presets = const [];
  String? _help;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _pass, _from, _name, _to]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Map d) {
    _host.text = '${d['host'] ?? ''}';
    _port.text = '${d['port'] ?? ''}';
    _user.text = '${d['username'] ?? ''}';
    _from.text = '${d['from_address'] ?? ''}';
    _name.text = '${d['from_name'] ?? ''}';
    _enc = '${d['encryption'] ?? 'tls'}';
    _hasPass = d['has_password'] == true;
    _on = d['enabled'] == true;
    _presets = _maps(d['presets']);
    _pass.clear();
  }

  Future<void> _load() async {
    try {
      final d = await s.papi!.pGet('/mail') as Map;
      if (mounted) setState(() => _fill(d));
    } catch (e) {
      await s.handleError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final d = await s.papi!.pSend('POST', '/mail', {
        'host': _host.text.trim(), 'port': int.tryParse(_port.text.trim()), 'encryption': _enc, 'username': _user.text.trim(),
        'password': _pass.text.trim().isEmpty ? null : _pass.text.trim(), 'from_address': _from.text.trim().isEmpty ? null : _from.text.trim(), 'from_name': _name.text.trim(),
      }) as Map;
      setState(() => _fill(d));
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, tr('Saqlandi'));
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (_to.text.trim().isEmpty) return _snack(context, tr('Qaysi emailga yuborilsin?'));
    setState(() => _busy = true);
    try {
      await s.papi!.pSend('POST', '/mail/test', {'to': _to.text.trim()});
      if (mounted) _snack(context, tr('Sinov xati yuborildi — pochtani tekshiring'));
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
      children: [
        GlassRow(
          margin: EdgeInsets.zero,
          tint: (_on ? Brand.green : Colors.orange).withValues(alpha: 0.12),
          child: Row(children: [
            Icon(_on ? Icons.mark_email_read_rounded : Icons.mail_lock_rounded, color: _on ? Brand.green : Colors.orange.shade800),
            const SizedBox(width: 10),
            Expanded(child: Text(_on ? tr('Pochta ulangan — parolni tiklash kodlari emailga boradi') : tr('Pochta ulanmagan — parolni tiklash email orqali ishlamaydi'), style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final p in _presets)
            ActionChip(
              label: Text('${p['name']}'),
              onPressed: () => setState(() {
                _host.text = '${p['host']}';
                _port.text = '${p['port']}';
                _enc = '${p['encryption']}';
                _help = '${p['help']}';
              }),
            ),
        ]),
        if (_help != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_help!, style: TextStyle(color: cs.outline, fontSize: 12.5))),
        const SizedBox(height: 10),
        Glass(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            TextField(controller: _host, autocorrect: false, decoration: InputDecoration(labelText: tr('SMTP server'), hintText: 'smtp.gmail.com')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Port'), hintText: '587'))),
              const SizedBox(width: 10),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'tls', label: Text('TLS')), ButtonSegment(value: 'ssl', label: Text('SSL'))],
                selected: {_enc},
                onSelectionChanged: (v) => setState(() => _enc = v.first),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _user, autocorrect: false, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('Login (email)'))),
            const SizedBox(height: 10),
            TextField(controller: _pass, obscureText: true, autocorrect: false, decoration: InputDecoration(labelText: tr('Parol (ilova paroli)'), helperText: _hasPass ? tr("Saqlangan — o'zgartirmasangiz bo'sh qoldiring") : null)),
            const SizedBox(height: 10),
            TextField(controller: _from, autocorrect: false, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('Kimdan (email)'))),
            const SizedBox(height: 10),
            TextField(controller: _name, decoration: InputDecoration(labelText: tr('Kimdan (nom)'), hintText: 'Oftob')),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_rounded), label: const Text('Saqlash'))),
          ]),
        ),
        const SizedBox(height: 12),
        Glass(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(child: TextField(controller: _to, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('Sinov xati — qaysi emailga')))),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _busy ? null : _test, child: const Text('Yuborish')),
          ]),
        ),
      ],
    );
  }
}

/* ---------------------------------------- To'lov rekvizitlari ---------------------------------------- */

class PayDetailsScreen extends StatefulWidget {
  const PayDetailsScreen({super.key, required this.session});
  final Session session;

  @override
  State<PayDetailsScreen> createState() => _PayDetailsScreenState();
}

class _PayDetailsScreenState extends State<PayDetailsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await s.papi!.pGet('/pay-details');
      if (mounted) setState(() => _items = _maps(d));
    } catch (e) {
      await s.handleError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      final d = await s.papi!.pSend('POST', '/pay-details', {'items': _items});
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _items = _maps(d));
      if (mounted) _snack(context, tr('Saqlandi'));
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    }
  }

  Future<void> _edit([int? i]) async {
    final x = i == null ? <String, dynamic>{'type': 'card'} : Map<String, dynamic>.from(_items[i]);
    String type = '${x['type'] ?? 'card'}';
    final title = TextEditingController(text: '${x['title'] ?? ''}'), number = TextEditingController(text: '${x['number'] ?? ''}');
    final holder = TextEditingController(text: '${x['holder'] ?? ''}'), bank = TextEditingController(text: '${x['bank'] ?? ''}'), extra = TextEditingController(text: '${x['extra'] ?? ''}');
    final ok = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(c).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'card', label: Text(tr('Karta')), icon: const Icon(Icons.credit_card_rounded, size: 18)),
                  ButtonSegment(value: 'account', label: Text(tr('Hisob raqami')), icon: const Icon(Icons.account_balance_rounded, size: 18)),
                ],
                selected: {type},
                onSelectionChanged: (v) => set(() => type = v.first),
              ),
              const SizedBox(height: 12),
              TextField(controller: title, decoration: InputDecoration(labelText: tr('Nomi'), hintText: type == 'card' ? 'Uzcard / Humo / Visa' : tr('Bank hisobi'))),
              const SizedBox(height: 10),
              TextField(controller: number, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: type == 'card' ? tr('Karta raqami') : tr('Hisob raqami'))),
              const SizedBox(height: 10),
              TextField(controller: holder, decoration: InputDecoration(labelText: tr('Oluvchi (F.I.Sh. yoki tashkilot)'))),
              const SizedBox(height: 10),
              TextField(controller: bank, decoration: InputDecoration(labelText: tr('Bank, MFO, INN'))),
              const SizedBox(height: 10),
              TextField(controller: extra, decoration: InputDecoration(labelText: tr("Izoh (masalan: to'lov maqsadi)"))),
              const SizedBox(height: 16),
              Row(children: [
                if (i != null) IconButton.outlined(onPressed: () => Navigator.pop(c, 'delete'), icon: Icon(Icons.delete_outline_rounded, color: Theme.of(c).colorScheme.error)),
                if (i != null) const SizedBox(width: 8),
                Expanded(child: FilledButton(onPressed: () => Navigator.pop(c, 'save'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('Saqlash'))),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (ok == null) return;
    setState(() {
      final row = {'type': type, 'title': title.text.trim(), 'number': number.text.trim(), 'holder': holder.text.trim(), 'bank': bank.text.trim(), 'extra': extra.text.trim()};
      if (ok == 'delete' && i != null) {
        _items.removeAt(i);
      } else if (number.text.trim().isNotEmpty) {
        i == null ? _items.add(row) : _items[i] = row;
      }
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
      children: [
        Text("Kompaniyalar «Tarif va to'lov» da shu rekvizitlarni ko'radi, to'laydi va chekni yuklaydi. Siz «To'lovlarni tasdiqlash» da tasdiqlaysiz.", style: TextStyle(color: cs.outline, fontSize: 13)),
        const SizedBox(height: 12),
        for (var i = 0; i < _items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassRow(
              margin: EdgeInsets.zero,
              onTap: () => _edit(i),
              child: Row(children: [
                IconTile(icon: _items[i]['type'] == 'account' ? Icons.account_balance_rounded : Icons.credit_card_rounded, color: Brand.blue, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_items[i]['number']}', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                    Text([_items[i]['title'], _items[i]['holder'], _items[i]['bank']].where((x) => '${x ?? ''}'.isNotEmpty).join(' · '), style: TextStyle(color: cs.outline, fontSize: 12.5)),
                  ]),
                ),
                Icon(Icons.edit_rounded, size: 18, color: cs.outline),
              ]),
            ),
          ),
        if (_items.length < 6)
          OutlinedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text("Rekvizit qo'shish"), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
      ],
    );
  }
}

/* ---------------------------------------- Platforma SI kaliti qo'shish/tahrirlash ---------------------------------------- */

Future<bool> editPlatformAiKey(BuildContext context, Session s, List<Map<String, dynamic>> catalog, {Map<String, dynamic>? provider}) async {
  if (catalog.isEmpty) return false;
  var drv = provider != null
      ? Map<String, dynamic>.from(catalog.firstWhere((c) => c['driver'] == provider['driver'], orElse: () => catalog.first))
      : Map<String, dynamic>.from(catalog.first);
  final key = TextEditingController();
  final model = TextEditingController(text: '${provider?['model'] ?? ''}');
  final baseUrl = TextEditingController();
  var active = provider == null ? true : provider['active'] == true;
  var def = provider?['default'] == true;
  bool canVoice(Map x) => ((x['can'] as List?) ?? const []).contains('voice');
  final r = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final cs = Theme.of(c).colorScheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(c).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(provider == null ? tr('Platforma kaliti ulash') : '${provider['name']}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Chat uchun: DeepSeek, ChatGPT, Claude, Gemini. Ovoz uchun: Gemini yoki ChatGPT. Kalit darhol tekshiriladi.', style: TextStyle(color: cs.outline, fontSize: 12.5)),
              const SizedBox(height: 12),
              if (provider == null)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final x in catalog)
                    ChoiceChip(
                      label: Text('${x['name']}'.split(' (').first),
                      avatar: Icon(canVoice(x) ? Icons.graphic_eq_rounded : Icons.chat_bubble_outline_rounded, size: 16),
                      selected: drv['driver'] == x['driver'],
                      showCheckmark: false,
                      onSelected: (_) => set(() => drv = Map<String, dynamic>.from(x)),
                    ),
                ]),
              const SizedBox(height: 10),
              Glass(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(canVoice(drv) ? tr('Chat va ovoz uchun') : tr('Faqat chat uchun (ovozni tushunmaydi)'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${drv['help'] ?? ''}', style: const TextStyle(fontSize: 13)),
                  if ('${drv['key_url'] ?? ''}'.isNotEmpty)
                    TextButton.icon(onPressed: () => launchUrl(Uri.parse('${drv['key_url']}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Kalitni olish')),
                ]),
              ),
              const SizedBox(height: 10),
              TextField(controller: key, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: provider == null ? tr('API kalit') : tr("Yangi kalit (o'zgartirmasangiz bo'sh)"), prefixIcon: const Icon(Icons.key_rounded))),
              const SizedBox(height: 10),
              TextField(controller: model, autocorrect: false, decoration: InputDecoration(labelText: tr('Model (ixtiyoriy)'), hintText: '${drv['model'] ?? ''}')),
              if (drv['driver'] == 'compatible') ...[
                const SizedBox(height: 10),
                TextField(controller: baseUrl, autocorrect: false, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: tr('API manzili'), hintText: 'https://…/v1')),
              ],
              SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => set(() => active = v), title: Text(tr('Yoqilgan'))),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: def, onChanged: (v) => set(() => def = v), title: Text(tr('Asosiy (birinchi navbatda shu ishlaydi)'))),
              const SizedBox(height: 10),
              Row(children: [
                if (provider != null) IconButton.outlined(onPressed: () => Navigator.pop(c, 'delete'), icon: Icon(Icons.delete_outline_rounded, color: cs.error)),
                if (provider != null) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(c, 'save'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    icon: const Icon(Icons.verified_user_rounded),
                    label: Text(provider == null ? tr('Tekshirish va ulash') : tr('Saqlash')),
                  ),
                ),
              ]),
            ]),
          ),
        );
      },
    ),
  );
  if (r == null || !context.mounted) return false;
  if (r == 'save' && provider == null && key.text.trim().length < 8) {
    _snack(context, tr("Kalitni to'liq kiriting"));
    return false;
  }
  showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))));
  try {
    if (r == 'delete') {
      await s.papi!.pSend('DELETE', '/ai/providers/${provider!['id']}');
    } else {
      final body = {
        'driver': drv['driver'], 'api_key': key.text.trim().isEmpty ? null : key.text.trim(), 'model': model.text.trim(),
        'base_url': baseUrl.text.trim().isEmpty ? null : baseUrl.text.trim(), 'is_active': active, 'is_default': def,
      };
      if (provider == null) {
        await s.papi!.pSend('POST', '/ai/providers', body);
      } else {
        await s.papi!.pSend('PUT', '/ai/providers/${provider['id']}', body);
      }
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    HapticFeedback.mediumImpact();
    if (context.mounted) _snack(context, r == 'delete' ? tr("Kalit o'chirildi") : tr('Kalit tekshirildi va saqlandi'));
    return true;
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await s.handleError(e);
    if (context.mounted) _snack(context, e is ApiException ? e.message : '$e');
    return false;
  }
}
