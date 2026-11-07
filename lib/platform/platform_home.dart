import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api.dart';
import '../format.dart';
import '../l10n.dart';
import '../motion.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import '../screens/notifications.dart';
import '../screens/support.dart';
import 'platform_extra.dart';
import 'platform_more.dart';

/// Platforma administratori (super admin) uchun ilova: veb-admin paneldagi ishlar — kompaniyalar, to'lovlar, tariflar,
/// saytdan arizalar, yordam. Murakkab bo'limlar (sayt matnlari, blog, API, bazalar, administratorlar) «To'liq panel» orqali
/// ilova ichida veb-sahifa bo'lib ochiladi (bir martalik xavfsiz havola, parol so'ralmaydi).
class PlatformHome extends StatefulWidget {
  const PlatformHome({super.key, required this.session});

  final Session session;

  @override
  State<PlatformHome> createState() => _PlatformHomeState();
}

class _PTab {
  const _PTab(this.label, this.icon, this.active);
  final String label;
  final IconData icon;
  final IconData active;
}

class _PlatformHomeState extends State<PlatformHome> {
  int _index = 0;
  final _refresh = ValueNotifier<int>(0);
  late final NotificationCenter _nc = NotificationCenter(widget.session, onFresh: _fresh);

  Session get s => widget.session;
  ApiClient get api => s.papi!;
  Map<String, dynamic> get me => s.pme ?? const {};
  bool can(String p) => ((me['perms'] as List?) ?? const []).contains(p);

  static const _tabs = [
    _PTab('Obzor', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
    _PTab('Kompaniyalar', Icons.apartment_outlined, Icons.apartment_rounded),
    _PTab('Arizalar', Icons.move_to_inbox_outlined, Icons.move_to_inbox_rounded),
    _PTab('Yordam', Icons.support_agent_outlined, Icons.support_agent),
  ];

  @override
  void initState() {
    super.initState();
    _nc.start();
  }

  @override
  void dispose() {
    _nc.dispose();
    _refresh.dispose();
    super.dispose();
  }

  void _fresh(List<Map<String, dynamic>> fresh) {
    if (!mounted) return;
    _refresh.value++;
    // Yordam bo'limida turgan bo'lsa — yozishma o'zi yangilanadi, pastki xabar yozish maydonini to'smasin
    final shown = _index == 3 ? fresh.where((f) => f['type'] != 'support').toList() : fresh;
    if (shown.isEmpty) return;
    HapticFeedback.mediumImpact();
    final f = shown.first;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Text('${tr('${f['title']}')}: ${f['body']}', maxLines: 2, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(label: tr("Ko'rish"), onPressed: _openNotifications),
      ));
  }

  void _openNotifications() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NotificationsScreen(center: _nc, onGo: _go)));
  }

  void _go(String go) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (go == 'billing') {
      openPlatformPage(context, tr("To'lovlarni tasdiqlash"), ClaimsScreen(session: s));
      return;
    }
    if (go == 'ai') {
      openPlatformPage(context, tr("Sun'iy intellekt"), PlatformAiScreen(session: s));
      return;
    }
    final i = switch (go) { 'companies' => 1, 'leads' => 2, 'support' => 3, _ => 0 };
    setState(() => _index = i);
  }

  Widget _header(int i) {
    final cs = Theme.of(context).colorScheme;
    final name = '${me['name'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        if (i == 0) ...[
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Brand.green, Color(0xFF16A05A)])),
            child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Platforma administratori', style: TextStyle(color: cs.outline, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
            ]),
          ),
        ] else
          Expanded(child: Text(i == _tabs.length ? 'Yana' : _tabs[i].label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
        ListenableBuilder(
          listenable: _nc,
          builder: (context, _) => GlassIconButton(
            badge: _nc.unread,
            tooltip: tr('Bildirishnomalar'),
            onTap: _openNotifications,
            icon: Icon(_nc.unread > 0 ? Icons.notifications_active : Icons.notifications_none, size: 24, color: cs.onSurface),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i = _index.clamp(0, _tabs.length);
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _header(i),
          Expanded(
            child: NavInset(
              inset: NavInset.bar,
              child: AnimatedTabs(index: i, children: [
                _Overview(session: s, refresh: _refresh, onTab: (t) => setState(() => _index = t)),
                _Companies(session: s, refresh: _refresh),
                _Leads(session: s, refresh: _refresh),
                SupportScreen(session: s),
                _More(session: s, can: can),
              ]),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: GlassNavBar(
        index: i,
        onTap: (v) {
          setState(() => _index = v);
          if (v <= 2) _refresh.value++; // bo'limga qaytilganda ma'lumot yangilanadi
        },
        items: [
          for (final t in _tabs) NavItem(t.label, t.icon, t.active),
          const NavItem('Yana', Icons.grid_view_outlined, Icons.grid_view_rounded),
        ],
      ),
    );
  }
}

/* ---------------- umumiy kichik bo'laklar ---------------- */

/// Valyuta nomi joriy tilda (bazada «сум» / «UZS» bo'lib yozilgan bo'lishi mumkin)
String curName(Object? c) {
  final v = '${c ?? ''}'.trim();
  return switch (v.toLowerCase()) { 'сум' || 'uzs' || "so'm" || 'som' => tr("so'm"), 'usd' || '\$' => 'USD', _ => v };
}

Color stateColor(String st, ColorScheme cs) => switch (st) {
      'active' => Colors.green.shade600,
      'trial' => Brand.blue,
      'expired' => Colors.orange.shade700,
      'suspended' => cs.error,
      _ => cs.outline,
    };

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
      );
}

/// Kompaniya qatori (obzor va ro'yxat uchun bir xil)
class _WsRow extends StatelessWidget {
  const _WsRow({required this.w, required this.onTap});
  final Map<String, dynamic> w;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = '${w['state']}';
    final days = (w['days_left'] as num?)?.toInt();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassRow(
        margin: EdgeInsets.zero,
        onTap: onTap,
        child: Row(children: [
          IconTile(icon: Icons.apartment_rounded, color: stateColor(st, cs), size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${w['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                [if (w['plan'] != null) '${w['plan']}', if (days != null) '${tr('qoldi')}: $days ${tr('kun')}', if (w['users'] != null) '${w['users']} ${tr('xodim')}'].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.outline, fontSize: 12.5),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _Chip('${w['state_label'] ?? st}', stateColor(st, cs)),
            if (w['plan_request'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: _Chip(tr("Tarif so'radi"), Brand.purple)),
          ]),
        ]),
      ),
    );
  }
}

Future<void> openCompany(BuildContext context, Session s, int id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CompanyPage(session: s, id: id)));

/* ---------------- Obzor ---------------- */

class _Overview extends StatefulWidget {
  const _Overview({required this.session, required this.refresh, required this.onTab});
  final Session session;
  final ValueNotifier<int> refresh;
  final void Function(int) onTab;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  final Key _k = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final cs = Theme.of(context).colorScheme;
    return FutureBody<dynamic>(
      key: _k,
      session: s,
      refresh: widget.refresh,
      load: () => s.papi!.pGet('/dashboard'),
      builder: (context, raw, reload) {
        final d = Map<String, dynamic>.from(raw as Map);
        final cur = curName(d['currency']);
        List<Map<String, dynamic>> l(String k) => ((d[k] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        Widget stat(String t, Object v, Color c, {VoidCallback? onTap}) => Expanded(
              child: Glass(
                radius: 18,
                onTap: onTap,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(children: [
                  Text('$v', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
                  const SizedBox(height: 2),
                  Text(t, style: TextStyle(fontSize: 11.5, color: cs.outline, fontWeight: FontWeight.w700)),
                ]),
              ),
            );
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 4, 16, NavInset.listBottom(context)),
            children: [
              HeroGlass(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const IconTile(icon: Icons.payments_rounded, color: Brand.green, size: 40),
                    const SizedBox(width: 10),
                    Expanded(child: Text("Shu oy to'lovlar", style: TextStyle(color: context.inkSoft, fontWeight: FontWeight.w700))),
                  ]),
                  const SizedBox(height: 10),
                  Text('${money(d['paid_month'] as num?)} $cur', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: context.ink, letterSpacing: -0.5)),
                  const SizedBox(height: 4),
                  Text('${tr('Yil boshidan')}: ${money(d['paid_year'] as num?)} · MRR: ${money(d['mrr'] as num?)}', style: TextStyle(color: context.inkSoft, fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                stat(tr('Jami'), d['total'] ?? 0, cs.primary, onTap: () => widget.onTab(1)),
                const SizedBox(width: 8),
                stat(tr('Faol'), d['active'] ?? 0, Colors.green.shade600, onTap: () => widget.onTab(1)),
                const SizedBox(width: 8),
                stat(tr('Sinov'), d['trial'] ?? 0, Brand.blue, onTap: () => widget.onTab(1)),
                const SizedBox(width: 8),
                stat(tr('Tugagan'), d['expired'] ?? 0, Colors.orange.shade700, onTap: () => widget.onTab(1)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                stat(tr('Yangi arizalar'), d['new_leads'] ?? 0, Brand.purple, onTap: () => widget.onTab(2)),
                const SizedBox(width: 8),
                stat(tr('Yordam'), d['support_unread'] ?? 0, Brand.teal, onTap: () => widget.onTab(3)),
                const SizedBox(width: 8),
                stat(tr('Xodimlar'), d['users'] ?? 0, cs.primary),
                const SizedBox(width: 8),
                stat(tr('AI so\'rov'), d['ai_month'] ?? 0, Brand.orange),
              ]),
              if (((d['claims_pending'] as num?) ?? 0) > 0 || ((d['ai_requests_pending'] as num?) ?? 0) > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  stat(tr("To'lov tasdig'i"), d['claims_pending'] ?? 0, Brand.green, onTap: () => openPlatformPage(context, tr("To'lovlarni tasdiqlash"), ClaimsScreen(session: s)).then((_) => reload())),
                  const SizedBox(width: 8),
                  stat(tr('AI arizalar'), d['ai_requests_pending'] ?? 0, Brand.purple, onTap: () => openPlatformPage(context, tr("Sun'iy intellekt"), PlatformAiScreen(session: s)).then((_) => reload())),
                ]),
              ],
              for (final (title, key) in [("Tarif so'raganlar", 'requests'), ('Muddati tugayapti', 'ending'), ('Yangi kompaniyalar', 'latest')])
                if (l(key).isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 8), child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                  for (final w in l(key)) _WsRow(w: w, onTap: () => openCompany(context, s, (w['id'] as num).toInt()).then((_) => reload())),
                ],
            ],
          ),
        );
      },
    );
  }
}

/* ---------------- Kompaniyalar ---------------- */

class _Companies extends StatefulWidget {
  const _Companies({required this.session, required this.refresh});
  final Session session;
  final ValueNotifier<int> refresh;

  @override
  State<_Companies> createState() => _CompaniesState();
}

class _CompaniesState extends State<_Companies> {
  String _q = '';
  String _st = '';
  Key _k = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          onChanged: (v) => setState(() => _q = v.trim()),
          decoration: InputDecoration(hintText: tr('Qidirish: nom, manzil, telefon'), prefixIcon: const Icon(Icons.search), isDense: true, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final (id, t) in [('', 'Hammasi'), ('active', 'Faol'), ('trial', 'Sinov'), ('expired', 'Tugagan'), ('suspended', "To'xtatilgan")])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(t), selected: _st == id, showCheckmark: false, onSelected: (_) => setState(() => _st = id)),
            ),
        ]),
      ),
      Expanded(
        child: FutureBody<dynamic>(
          key: ValueKey('$_k|$_st'),
          session: s,
          refresh: widget.refresh,
          load: () => s.papi!.pGet('/companies', {'state': _st.isEmpty ? null : _st}),
          builder: (context, raw, reload) {
            final all = ((raw as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            final q = _q.toLowerCase();
            final list = q.isEmpty ? all : all.where((w) => '${w['name']} ${w['slug']} ${w['phone']}'.toLowerCase().contains(q)).toList();
            return RefreshIndicator(
              onRefresh: () async => setState(() => _k = UniqueKey()),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 6, 16, NavInset.listBottom(context)),
                children: [
                  if (list.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Kompaniya topilmadi'))),
                  for (final w in list) _WsRow(w: w, onTap: () => openCompany(context, s, (w['id'] as num).toInt()).then((_) => setState(() => _k = UniqueKey()))),
                ],
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// Kompaniya sahifasi: holat, tarif, muddatlar, AI, valyuta, to'lov yozish, xodimlar, to'lovlar
class CompanyPage extends StatefulWidget {
  const CompanyPage({super.key, required this.session, required this.id});
  final Session session;
  final int id;

  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

class _CompanyPageState extends State<CompanyPage> {
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _aiLimit = TextEditingController();
  String _status = 'active';
  int? _plan, _aiProvider, _aiVoice;
  String? _currency, _trial, _paid;
  bool _aiLocked = false, _observer = false, _clearReq = false;

  Session get s => widget.session;

  // ro'yxatda yo'q (eski) valyuta yuborilmaydi — server uni o'zgartirmaydi
  bool get _curOk => ((_d?['currencies'] as List?) ?? const []).any((c) => c is Map && c['code'] == _currency);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _note, _aiLimit]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Map<String, dynamic> d) {
    _d = d;
    _name.text = '${d['name'] ?? ''}';
    _phone.text = '${d['phone'] ?? ''}';
    _note.text = '${d['note'] ?? ''}';
    _aiLimit.text = d['ai_limit'] == null ? '' : '${d['ai_limit']}';
    _status = '${d['status'] ?? 'active'}';
    _plan = (d['plan_id'] as num?)?.toInt();
    _aiProvider = (d['ai_provider_id'] as num?)?.toInt();
    _aiVoice = (d['ai_voice_provider_id'] as num?)?.toInt();
    _currency = d['currency'] as String?;
    _trial = d['trial_ends_at'] as String?;
    _paid = d['paid_until'] as String?;
    _aiLocked = d['ai_locked'] == true;
    _observer = d['boss_observer'] == true;
    _clearReq = false;
  }

  Future<void> _load() async {
    try {
      final d = Map<String, dynamic>.from(await s.papi!.pGet('/companies/${widget.id}') as Map);
      if (mounted) setState(() => _fill(d));
    } catch (e) {
      await s.handleError(e);
      if (mounted) setState(() => _err = '$e');
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final d = await s.papi!.pSend('PUT', '/companies/${widget.id}', {
        'name': _name.text.trim(), 'phone': _phone.text.trim(), 'plan_id': _plan, 'status': _status, 'trial_ends_at': _trial, 'paid_until': _paid,
        'note': _note.text.trim(), 'ai_provider_id': _aiProvider, 'ai_voice_provider_id': _aiVoice, 'ai_limit': _aiLimit.text.trim().isEmpty ? null : int.tryParse(_aiLimit.text.trim()),
        'currency': _curOk ? _currency : null, 'boss_observer': _observer, 'ai_locked': _aiLocked, 'clear_request': _clearReq,
      });
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _fill(Map<String, dynamic>.from(d as Map)));
      _snack(tr('Saqlandi'));
    } catch (e) {
      await s.handleError(e);
      _snack(e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickDate(String? cur) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: DateTime(now.year - 3), lastDate: DateTime(now.year + 5), initialDate: DateTime.tryParse(cur ?? '') ?? now);
    if (d == null) return cur;
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pay() async {
    final d = _d!;
    final plans = ((d['plans'] as List?) ?? const []).whereType<Map>().toList();
    int? plan = _plan ?? (plans.isNotEmpty ? (plans.first['id'] as num).toInt() : null);
    int months = 1;
    // kompaniya tarif so'ragan bo'lsa — o'sha tarif va muddat oldindan tanlanadi
    final req = d['plan_request'];
    if (req is Map) {
      final pid = (req['plan_id'] as num?)?.toInt();
      if (pid != null && plans.any((x) => (x['id'] as num).toInt() == pid)) plan = pid;
      final m = (req['months'] as num?)?.toInt();
      if (m != null && [1, 3, 6, 12].contains(m)) months = m;
    }
    String price() {
      final p = plans.where((x) => (x['id'] as num).toInt() == plan).firstOrNull;
      final m = (p?['price_month'] as num?) ?? 0;
      return p == null ? '' : fmtInput(m * months);
    }
    final amount = TextEditingController(text: price());
    final note = TextEditingController();
    String method = 'Click';
    final now = DateTime.now();
    String date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final idem = 'app-${DateTime.now().microsecondsSinceEpoch}';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("To'lov yozish va muddatni uzaytirish", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: plan,
                decoration: InputDecoration(labelText: tr('Tarif')),
                items: [for (final p in plans) DropdownMenuItem(value: (p['id'] as num).toInt(), child: Text('${p['title']} · ${money(p['price_month'] as num?)} ${curName(p['currency'])}'))],
                onChanged: (v) => set(() {
                  plan = v;
                  amount.text = price();
                }),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final m in [1, 3, 6, 12])
                  ChoiceChip(
                    label: Text('$m ${tr('oy')}'),
                    selected: months == m,
                    showCheckmark: false,
                    onSelected: (_) => set(() {
                      months = m;
                      amount.text = price();
                    }),
                  ),
              ]),
              const SizedBox(height: 10),
              TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Summa'))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final m in ['Click', 'Payme', 'Naqd', "Bank o'tkazmasi", 'Karta']) ChoiceChip(label: Text(m), selected: method == m, showCheckmark: false, onSelected: (_) => set(() => method = m)),
              ]),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final v = await _pickDate(date);
                  if (v != null) set(() => date = v);
                },
                icon: const Icon(Icons.event_rounded),
                label: Text('${tr("To'langan sana")}: ${formatDate(date)}'),
              ),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: InputDecoration(labelText: tr('Izoh (ixtiyoriy)'))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yozish va uzaytirish'))),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || plan == null) return;
    setState(() => _busy = true);
    try {
      final d2 = await s.papi!.pSend('POST', '/companies/${widget.id}/pay', {
        'plan_id': plan, 'months': months, 'amount': num.tryParse(amount.text.replaceAll(' ', '')) ?? 0, 'method': method, 'paid_at': date, 'note': note.text.trim(), 'idem': idem,
      });
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _fill(Map<String, dynamic>.from(d2 as Map)));
      _snack('${tr("To'lov yozildi")} · ${tr('Muddat')}: ${formatDate('${_d?['paid_until'] ?? ''}')}');
    } catch (e) {
      await s.handleError(e);
      _snack(e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = _d;
    Widget body;
    if (d == null) {
      body = _err != null ? ErrorView(message: _err!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    } else {
      final plans = ((d['plans'] as List?) ?? const []).whereType<Map>().toList();
      final provs = ((d['ai_providers'] as List?) ?? const []).whereType<Map>().toList();
      final curs = ((d['currencies'] as List?) ?? const []).whereType<Map>().toList();
      final users = ((d['users'] as List?) ?? const []).whereType<Map>().toList();
      final pays = ((d['payments'] as List?) ?? const []).whereType<Map>().toList();
      final st = d['stats'] is Map ? d['stats'] as Map : const {};
      final state = '${d['state']}';
      Widget section(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 8), child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)));
      body = ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
        children: [
          HeroGlass(
            tint: stateColor(state, cs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${d['name']}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: context.ink))),
                _Chip('${d['state_label'] ?? state}', stateColor(state, cs)),
              ]),
              const SizedBox(height: 4),
              Text('/c/${d['slug']} · ${d['plan'] ?? '—'}${d['days_left'] != null ? ' · ${tr('qoldi')} ${d['days_left']} ${tr('kun')}' : ''}', style: TextStyle(color: context.inkSoft, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(spacing: 14, runSpacing: 6, children: [
                Text('${tr('Obyektlar')}: ${st['objects'] ?? '—'}', style: TextStyle(color: context.inkSoft, fontWeight: FontWeight.w700)),
                Text('${tr('Xodimlar')}: ${users.length}', style: TextStyle(color: context.inkSoft, fontWeight: FontWeight.w700)),
                Text('AI: ${d['ai_used'] ?? 0}${d['ai_limit'] != null ? ' / ${d['ai_limit']}' : ''}', style: TextStyle(color: context.inkSoft, fontWeight: FontWeight.w700)),
                if (st['balance'] != null) Text('${tr('Kassa')}: ${money(st['balance'] as num?)} ${curName(st['currency'])}', style: TextStyle(color: context.inkSoft, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          if (d['plan_request'] != null) ...[
            const SizedBox(height: 10),
            GlassRow(
              margin: EdgeInsets.zero,
              tint: Brand.purple.withValues(alpha: 0.14),
              child: Row(children: [
                const Icon(Icons.campaign_rounded, color: Brand.purple),
                const SizedBox(width: 10),
                Expanded(child: Text('${tr("Tarif so'radi")}: ${(d['plan_request'] is Map ? d['plan_request'] as Map : null)?['plan'] ?? ''} ${(d['plan_request'] is Map ? d['plan_request'] as Map : null)?['months'] != null ? '· ${(d['plan_request'] as Map)['months']} ${tr('oy')}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: _busy ? null : _pay, icon: const Icon(Icons.add_card_rounded, size: 20), label: const Text("To'lov yozish"))),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => openWebAdmin(context, s, '/admin/companies/${widget.id}', '${d['name']}'),
                icon: const Icon(Icons.open_in_browser_rounded, size: 20),
                label: const Text("To'liq sahifa"),
              ),
            ),
          ]),
          section('Sozlamalar'),
          Glass(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              TextField(controller: _name, decoration: InputDecoration(labelText: tr('Nomi'))),
              const SizedBox(height: 10),
              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Telefon'))),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'trial', label: Text(tr('Sinov'))),
                    ButtonSegment(value: 'active', label: Text(tr('Faol'))),
                    ButtonSegment(value: 'suspended', label: Text(tr("To'xtatilgan"))),
                  ],
                  selected: {_status},
                  onSelectionChanged: (v) => setState(() => _status = v.first),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _plan,
                decoration: InputDecoration(labelText: tr('Tarif')),
                items: [for (final p in plans) DropdownMenuItem(value: (p['id'] as num).toInt(), child: Text('${p['title']}'))],
                onChanged: (v) => setState(() => _plan = v),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final v = await _pickDate(_trial);
                      setState(() => _trial = v);
                    },
                    child: Text('${tr('Sinov')}: ${_trial == null ? '—' : formatDate(_trial)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final v = await _pickDate(_paid);
                      setState(() => _paid = v);
                    },
                    child: Text("${tr("To'langan")}: ${_paid == null ? '—' : formatDate(_paid)}", maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: InputDecoration(labelText: tr('Kompaniya valyutasi')),
                items: [
                  if (_currency != null && !curs.any((c) => c['code'] == _currency)) DropdownMenuItem(value: _currency, child: Text(_currency!)),
                  for (final c in curs) DropdownMenuItem(value: '${c['code']}', child: Text('${c['name']} (${c['code']})')),
                ],
                onChanged: (v) => setState(() => _currency = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: _aiProvider,
                decoration: InputDecoration(labelText: tr('AI ulanishi')),
                items: [DropdownMenuItem<int?>(value: null, child: Text(tr('Platforma bo\'yicha standart'))), for (final p in provs) DropdownMenuItem<int?>(value: (p['id'] as num).toInt(), child: Text('${p['name']}'))],
                onChanged: (v) => setState(() => _aiProvider = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: provs.any((p) => (p['id'] as num).toInt() == _aiVoice && p['voice'] == true) ? _aiVoice : null,
                decoration: InputDecoration(labelText: tr('Ovoz uchun ulanish'), helperText: tr('Ovozni faqat Gemini va ChatGPT tushunadi')),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(tr("Platforma bo'yicha standart"))),
                  for (final p in provs.where((p) => p['voice'] == true)) DropdownMenuItem<int?>(value: (p['id'] as num).toInt(), child: Text('${p['name']}')),
                ],
                onChanged: (v) => setState(() => _aiVoice = v),
              ),
              const SizedBox(height: 10),
              TextField(controller: _aiLimit, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('AI limiti (oyiga)'), helperText: tr("Bo'sh — tarif bo'yicha, 0 — cheklovsiz"))),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _aiLocked, onChanged: (v) => setState(() => _aiLocked = v), title: Text(tr("Kompaniya AI'ni o'zi almashtira olmaydi"))),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _observer, onChanged: (v) => setState(() => _observer = v), title: Text(tr('Rahbar faqat kuzatadi'))),
              if (d['plan_request'] != null) CheckboxListTile(contentPadding: EdgeInsets.zero, value: _clearReq, onChanged: (v) => setState(() => _clearReq = v == true), title: Text(tr("Tarif so'rovini yopish"))),
              TextField(controller: _note, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: tr('Izoh (faqat siz ko\'rasiz)'))),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
                  label: const Text('Saqlash'),
                ),
              ),
            ]),
          ),
          if (users.isNotEmpty) section('${tr('Xodimlar')} (${users.length})'),
          for (final u in users)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassRow(
                margin: EdgeInsets.zero,
                child: Row(children: [
                  CircleAvatar(radius: 17, backgroundColor: cs.primary.withValues(alpha: 0.12), child: Text('${u['name']}'.isEmpty ? '?' : '${u['name']}'[0].toUpperCase(), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${u['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${u['role']} · ${u['login'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                    ]),
                  ),
                  if (u['active'] != true) _Chip(tr("O'chirilgan"), cs.error),
                ]),
              ),
            ),
          if (pays.isNotEmpty) section("To'lovlar"),
          for (final p in pays) _PayRow(p: Map<String, dynamic>.from(p)),
        ],
      );
    }
    return Scaffold(backgroundColor: Colors.transparent, appBar: AppBar(title: Text(d == null ? tr('Kompaniya') : '${d['name']}')), body: body);
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow({required this.p, this.showCompany = false, this.onDelete});
  final Map<String, dynamic> p;
  final bool showCompany;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassRow(
        margin: EdgeInsets.zero,
        child: Row(children: [
          const IconTile(icon: Icons.south_west_rounded, color: Colors.green, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(showCompany ? '${p['company'] ?? '—'}' : '${p['plan'] ?? ''} · ${p['months']} ${tr('oy')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${formatDate('${p['paid_at']}')} · ${p['method'] ?? ''}${showCompany ? ' · ${p['plan'] ?? ''} · ${p['months']} ${tr('oy')}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
            ]),
          ),
          Text('+${money(p['amount'] as num?)} ${curName(p['currency'])}', style: TextStyle(color: Colors.green.shade600, fontWeight: FontWeight.w800)),
          if (onDelete != null) IconButton(onPressed: onDelete, icon: Icon(Icons.delete_outline_rounded, color: cs.error, size: 20), visualDensity: VisualDensity.compact),
        ]),
      ),
    );
  }
}

/* ---------------- Saytdan arizalar ---------------- */

class _Leads extends StatefulWidget {
  const _Leads({required this.session, required this.refresh});
  final Session session;
  final ValueNotifier<int> refresh;

  @override
  State<_Leads> createState() => _LeadsState();
}

class _LeadsState extends State<_Leads> {
  String _st = '';
  Key _k = UniqueKey();

  Session get s => widget.session;

  Future<void> _open(Map<String, dynamic> l, List<Map<String, dynamic>> statuses) async {
    String st = '${l['status']}';
    final note = TextEditingController(text: '${l['note'] ?? ''}');
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${l['name'] ?? '—'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text([l['company'], l['role'], l['objects'], l['budget'], l['source']].where((x) => x != null && '$x'.isNotEmpty).join(' · '), style: TextStyle(color: Theme.of(c).colorScheme.outline)),
            const SizedBox(height: 10),
            if ('${l['phone'] ?? ''}'.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: '${l['phone']}'.replaceAll(RegExp(r'[^0-9+]'), '')), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.call_rounded),
                label: Text('${l['phone']}'),
              ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final x in statuses) ChoiceChip(label: Text('${x['name']}'), selected: st == x['id'], showCheckmark: false, onSelected: (_) => set(() => st = '${x['id']}')),
            ]),
            const SizedBox(height: 10),
            TextField(controller: note, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: tr('Izoh'))),
            const SizedBox(height: 14),
            Row(children: [
              IconButton.outlined(onPressed: () => Navigator.pop(c, 'delete'), icon: Icon(Icons.delete_outline_rounded, color: Theme.of(c).colorScheme.error)),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Saqlash'))),
            ]),
          ]),
        ),
      ),
    );
    if (r == null || !mounted) return;
    if (r == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Arizani o'chirish"),
          content: Text('${l['name'] ?? ''} · ${l['phone'] ?? ''}'),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text("O'chirish"))],
        ),
      );
      if (ok != true) return;
    }
    try {
      if (r == 'delete') {
        await s.papi!.pSend('DELETE', '/leads/${l['id']}');
      } else {
        await s.papi!.pSend('POST', '/leads/${l['id']}', {'status': st, 'note': note.text.trim()});
      }
      HapticFeedback.selectionClick();
      setState(() => _k = UniqueKey());
    } catch (e) {
      await s.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : '$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBody<dynamic>(
      key: ValueKey('$_k|$_st'),
      session: s,
      refresh: widget.refresh,
      load: () => s.papi!.pGet('/leads', {'status': _st.isEmpty ? null : _st}),
      builder: (context, raw, reload) {
        final d = Map<String, dynamic>.from(raw as Map);
        final items = ((d['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        final statuses = ((d['statuses'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        final counts = d['counts'] is Map ? d['counts'] as Map : const {};
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: NavInset.listBottom(context)),
            children: [
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                  Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(tr('Hammasi')), selected: _st.isEmpty, showCheckmark: false, onSelected: (_) => setState(() => _st = ''))),
                  for (final x in statuses)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text('${x['name']} ${counts['${x['id']}'] ?? 0}'), selected: _st == x['id'], showCheckmark: false, onSelected: (_) => setState(() => _st = '${x['id']}')),
                    ),
                ]),
              ),
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("Ariza yo'q"))),
              for (final l in items)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: GlassRow(
                    margin: EdgeInsets.zero,
                    onTap: () => _open(l, statuses),
                    child: Row(children: [
                      IconTile(icon: Icons.person_add_alt_1_rounded, color: l['status'] == 'new' ? Brand.purple : cs.outline, size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${l['name'] ?? '—'}${'${l['company'] ?? ''}'.isEmpty ? '' : ' · ${l['company']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('${l['phone'] ?? ''} · ${formatDateTime('${l['at'] ?? ''}')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                        ]),
                      ),
                      _Chip('${statuses.where((x) => x['id'] == l['status']).map((x) => x['name']).firstOrNull ?? l['status']}', l['status'] == 'new' ? Brand.purple : cs.outline),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/* ---------------- Yana: to'lovlar, tariflar, to'liq panel, profil ---------------- */

class _More extends StatelessWidget {
  const _More({required this.session, required this.can});
  final Session session;
  final bool Function(String) can;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final cs = Theme.of(context).colorScheme;
    final me = s.pme ?? const {};
    Widget row(IconData i, Color c, String t, String sub, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassRow(
            margin: EdgeInsets.zero,
            onTap: onTap,
            child: Row(children: [
              IconTile(icon: i, color: c, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.outline),
            ]),
          ),
        );
    void push(String title, Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(backgroundColor: Colors.transparent, appBar: AppBar(title: Text(title)), body: w)));
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, NavInset.listBottom(context)),
      children: [
        HeroGlass(
          child: Row(children: [
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Brand.green, Color(0xFF16A05A)])),
              child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${me['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: context.ink)),
                Text('${me['email'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.inkSoft, fontSize: 13)),
                Text(me['owner'] == true ? tr('Platforma egasi') : tr('Platforma administratori'), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // til va ko'rinish
        GlassRow(
          margin: EdgeInsets.zero,
          child: Row(children: [
            const IconTile(icon: Icons.contrast_rounded, color: Brand.purple, size: 42),
            const SizedBox(width: 12),
            const Expanded(child: Text("Ko'rinish", style: TextStyle(fontWeight: FontWeight.w800))),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (_, tm, _) => SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded, size: 18)),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 18)),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 18)),
                ],
                selected: {tm},
                onSelectionChanged: (v) => ThemeController.set(v.first),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        GlassRow(
          margin: EdgeInsets.zero,
          child: Row(children: [
            const IconTile(icon: Icons.translate_rounded, color: Brand.teal, size: 42),
            const SizedBox(width: 12),
            const Expanded(child: Text('Til', style: TextStyle(fontWeight: FontWeight.w800))),
            ValueListenableBuilder<String>(
              valueListenable: L.notifier,
              builder: (_, lang, _) => SegmentedButton<String>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [ButtonSegment(value: 'uz', label: Text('UZ')), ButtonSegment(value: 'ru', label: Text('RU')), ButtonSegment(value: 'tg', label: Text('TJ'))],
                selected: {lang},
                onSelectionChanged: (v) => L.set(v.first),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (can('payments')) row(Icons.receipt_long_rounded, Brand.green, "To'lovlar", "Barcha kompaniyalar to'lovlari", () => push(tr("To'lovlar"), _Payments(session: s))),
        if (can('payments')) row(Icons.verified_rounded, Brand.green, "To'lovlarni tasdiqlash", "Kompaniyalar yuborgan to'lovlar", () => push(tr("To'lovlarni tasdiqlash"), ClaimsScreen(session: s))),
        if (can('plans')) row(Icons.workspace_premium_rounded, Brand.orange, 'Tariflar', 'Narx, umrbod narx va limitlar', () => push(tr('Tariflar'), _Plans(session: s))),
        if (can('ai')) row(Icons.auto_awesome_rounded, Brand.purple, "Sun'iy intellekt", 'Kalitlar, real limitlar, arizalar', () => push(tr("Sun'iy intellekt"), PlatformAiScreen(session: s))),
        if (can('payments')) row(Icons.credit_card_rounded, Brand.blue, "To'lov rekvizitlari", "Kompaniyalar tarifni shu karta/hisobga to'laydi", () => push(tr("To'lov rekvizitlari"), PayDetailsScreen(session: s))),
        if (can('settings')) row(Icons.alternate_email_rounded, Brand.purple, 'Pochta (SMTP)', 'Parolni tiklash kodlari emailga', () => push(tr('Pochta (SMTP)'), MailSettingsScreen(session: s))),
        if (can('settings')) row(Icons.pin_rounded, Brand.teal, 'Kirish kodi', "Ilovada administrator kirishi uchun kod", () => changeGateCode(context, s)),
        Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 8), child: Text("To'liq panel (sayt bo'limlari)", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        for (final (perm, path, icon, color, title) in [
          ('', '/admin', Icons.space_dashboard_rounded, Brand.blue, 'Bosh panel'),
          ('ai', '/admin/ai', Icons.auto_awesome_rounded, Brand.purple, 'AI ulanishlari'),
          ('settings', '/admin/settings', Icons.tune_rounded, Brand.teal, 'Platforma sozlamalari'),
          ('site', '/admin/site', Icons.text_fields_rounded, Brand.orange, 'Sayt matnlari'),
          ('site', '/admin/posts', Icons.article_rounded, Brand.pink, 'Blog'),
          ('api', '/admin/api', Icons.hub_rounded, Brand.blue, 'API va integratsiyalar'),
          ('owner', '/admin/admins', Icons.manage_accounts_rounded, Brand.green, 'Administratorlar'),
        ])
          if (perm.isEmpty || (perm == 'owner' ? me['owner'] == true : can(perm))) row(icon, color, title, '', () => openWebAdmin(context, s, path, tr(title))),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Chiqish'),
                content: const Text('Hisobdan chiqasizmi?'),
                actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Yo'q")), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Chiqish'))],
              ),
            );
            if (ok == true) await s.signOut();
          },
          icon: Icon(Icons.logout_rounded, color: cs.error),
          label: Text('Hisobdan chiqish', style: TextStyle(color: cs.error)),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ],
    );
  }
}

class _Payments extends StatefulWidget {
  const _Payments({required this.session});
  final Session session;

  @override
  State<_Payments> createState() => _PaymentsState();
}

class _PaymentsState extends State<_Payments> {
  Key _k = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return FutureBody<dynamic>(
      key: _k,
      session: s,
      load: () => s.papi!.pGet('/payments'),
      builder: (context, raw, reload) {
        final d = Map<String, dynamic>.from(raw as Map);
        final items = ((d['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
          children: [
            HeroGlass(
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('Shu oy'), style: TextStyle(color: context.inkSoft)), Text(money(d['month'] as num?), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: context.ink))])),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('Yil boshidan'), style: TextStyle(color: context.inkSoft)), Text(money(d['year'] as num?), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: context.ink))])),
              ]),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("To'lov yo'q"))),
            for (final p in items)
              _PayRow(
                p: p,
                showCompany: true,
                onDelete: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text("To'lovni o'chirish"),
                      content: const Text("Yozuv o'chiriladi. Kompaniyaning muddati o'zgarmaydi."),
                      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text("O'chirish"))],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    await s.papi!.pSend('DELETE', '/payments/${p['id']}');
                    setState(() => _k = UniqueKey());
                  } catch (e) {
                    await s.handleError(e);
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

class _Plans extends StatefulWidget {
  const _Plans({required this.session});
  final Session session;

  @override
  State<_Plans> createState() => _PlansState();
}

class _PlansState extends State<_Plans> {
  Key _k = UniqueKey();

  Future<void> _edit(Map<String, dynamic> p) async {
    final s = widget.session;
    final pm = TextEditingController(text: fmtInput(p['price_month'] as num?));
    final py = TextEditingController(text: fmtInput(p['price_year'] as num?));
    final mo = TextEditingController(text: p['max_objects'] == null ? '' : '${p['max_objects']}');
    final mu = TextEditingController(text: p['max_users'] == null ? '' : '${p['max_users']}');
    final ai = TextEditingController(text: p['ai_requests'] == null ? '' : '${p['ai_requests']}');
    final td = TextEditingController(text: p['trial_days'] == null ? '' : '${p['trial_days']}');
    final po = TextEditingController(text: fmtInput(p['price_once'] as num?));
    var active = p['is_active'] == true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${p['title']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: pm, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: '${tr('Oyiga')} (${curName(p['currency'])})'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: py, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: '${tr('Yiliga')} (${curName(p['currency'])})'))),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: po,
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsFormatter()],
                decoration: InputDecoration(labelText: '${tr('Umrbod (bir martalik)')} (${curName(p['currency'])})', helperText: tr("Bo'sh — faqat oylik. To'liq to'lansa — tarif umrbod")),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: mo, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Obyektlar soni')))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: mu, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Xodimlar soni')))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: ai, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('AI (oyiga)')))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: td, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Sinov kunlari')))),
              ]),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => set(() => active = v), title: Text(tr('Saytda ko\'rinadi (faol)'))),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Saqlash'))),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    int? n(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
    try {
      await s.papi!.pSend('PUT', '/plans/${p['id']}', {
        'price_month': num.tryParse(pm.text.replaceAll(' ', '')) ?? 0, 'price_year': num.tryParse(py.text.replaceAll(' ', '')), 'max_objects': n(mo), 'max_users': n(mu),
        'ai_requests': n(ai), 'trial_days': n(td), 'is_active': active, 'price_once': num.tryParse(po.text.replaceAll(' ', '')),
      });
      HapticFeedback.mediumImpact();
      setState(() => _k = UniqueKey());
    } catch (e) {
      await s.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : '$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final cs = Theme.of(context).colorScheme;
    return FutureBody<dynamic>(
      key: _k,
      session: s,
      load: () => s.papi!.pGet('/plans'),
      builder: (context, raw, reload) {
        final items = ((raw as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
          children: [
            for (final p in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassRow(
                  margin: EdgeInsets.zero,
                  onTap: () => _edit(p),
                  child: Row(children: [
                    IconTile(icon: Icons.workspace_premium_rounded, color: p['is_active'] == true ? Brand.orange : cs.outline, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${money(p['price_month'] as num?)} ${curName(p['currency'])} / ${tr('oy')} · ${p['companies']} ${tr('kompaniya')}', style: TextStyle(color: cs.outline, fontSize: 12.5)),
                      ]),
                    ),
                    Icon(Icons.edit_rounded, color: cs.outline, size: 20),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}

/* ---------------- To'liq panel: veb-admin ilova ichida ---------------- */

Future<void> openWebAdmin(BuildContext context, Session s, String path, String title) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _WebAdmin(session: s, path: path, title: title)));

class _WebAdmin extends StatefulWidget {
  const _WebAdmin({required this.session, required this.path, required this.title});
  final Session session;
  final String path;
  final String title;

  @override
  State<_WebAdmin> createState() => _WebAdminState();
}

class _WebAdminState extends State<_WebAdmin> {
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
      final d = await widget.session.papi!.pSend('POST', '/web-link', {'path': widget.path});
      final url = '${(d as Map)['url']}';
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) setState(() => _error = tr("Sahifani ochib bo'lmadi. Internetni tekshiring."));
          },
        ));
      await c.loadRequest(Uri.parse(url));
      if (mounted) setState(() => _c = c);
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
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
              if (_progress < 100) LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100),
            ]),
    );
  }
}

/// Platforma egasi kirishi (login va parol) — kompaniya xodimlarinikidan alohida
class PlatformLoginScreen extends StatefulWidget {
  const PlatformLoginScreen({super.key, required this.session});
  final Session session;

  @override
  State<PlatformLoginScreen> createState() => _PlatformLoginScreenState();
}

class _PlatformLoginScreenState extends State<PlatformLoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false, _hide = true;
  String? _err;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _err = tr('Login va parolni kiriting.'));
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.session.platformSignIn(email: _email.text.trim(), password: _pass.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
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
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Reveal(child: Center(child: Container(width: 76, height: 76, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Brand.green, Color(0xFF16A05A)])), child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 40)))),
          const SizedBox(height: 16),
          const Center(child: Text('Platforma egalari uchun kirish', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
          const SizedBox(height: 6),
          Center(child: Text('Kompaniya xodimlari bu yerdan emas, o\'z kompaniyasi orqali kiradi.', textAlign: TextAlign.center, style: TextStyle(color: cs.outline))),
          const SizedBox(height: 24),
          Glass(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: InputDecoration(labelText: tr('Email yoki telefon'), prefixIcon: const Icon(Icons.alternate_email_rounded))),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: _hide,
                onSubmitted: (_) => _go(),
                decoration: InputDecoration(
                  labelText: tr('Parol'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded)),
                ),
              ),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700))),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _go,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Kirish'),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final email = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => PlatformForgotScreen(serverUrl: widget.session.serverUrl, email: _email.text.trim())));
                  if (email != null && mounted) {
                    setState(() {
                      _email.text = email;
                      _pass.clear();
                      _err = null;
                    });
                  }
                },
                child: const Text('Parolni unutdingizmi?'),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
