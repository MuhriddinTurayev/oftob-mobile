import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/widgets.dart' as w show Text;


import '../format.dart';
import '../session.dart';
import '../widgets.dart';
import '../theme.dart';
import 'shift_card.dart';
import '../l10n.dart';

/// Bosh ekran: rahbar uchun bir qarashda — kassa, sotuv, vazifalar, yangi lidlar, oxirgi operatsiyalar.
/// Faqat kalit (rol) ruxsat bergan bo'limlar ko'rsatiladi; har biri alohida yuklanadi — biri xato bersa, qolganlari ishlayveradi.
/// «Xizmatlar» tugmasi: bo'lim nomi (tab nomi), belgisi va rangi
class DashSection {
  const DashSection(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session, this.onOpen, this.sections = const [], this.onProfile, this.refresh});

  final Session session;
  final List<DashSection> sections;
  final VoidCallback? onProfile;

  /// Qiymati o'zgarsa — ma'lumot jim yangilanadi (tabga qaytganda, ilova ochilganda)
  final ValueNotifier<int>? refresh;

  /// Bo'limga o'tish (pastki tab nomi bilan)
  final void Function(String tab)? onOpen;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;

  Map<String, num> _cash = {}; // valyuta → jami qoldiq
  int _desks = 0;
  int _apts = 0, _sold = 0, _booked = 0, _free = 0;
  int _open = 0, _overdue = 0;
  int _attStaff = 0, _attWorking = 0, _attCame = 0, _attAbsent = 0;
  int _leadsTotal = 0;
  List<Map<String, dynamic>> _leads = const [];
  List<Map<String, dynamic>> _ops = const [];
  List<Map<String, dynamic>> _objs = const [];
  List<Map<String, dynamic>> _now = const []; // hozir ishda: prorablar/ofis va ishchilar
  Timer? _clock;
  String _q = '';

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
    widget.refresh?.addListener(_load);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _now.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_load);
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final me = s.me!;
    final api = s.api!;
    var failed = 0, tried = 0;
    Future<void> part(bool allowed, Future<void> Function() f) async {
      if (!allowed) return;
      tried++;
      try {
        await f();
      } catch (e) {
        failed++;
        await s.handleError(e);
        _error = '$e';
      }
    }

    await Future.wait([
      part(me.can('cash:read'), () async {
        final d = await api.cashDesks();
        final m = <String, num>{};
        var n = 0;
        for (final x in d) {
          if (x['is_active'] == false) continue;
          n++;
          final cur = '${x['currency'] ?? ''}';
          m[cur] = (m[cur] ?? 0) + ((x['balance'] as num?) ?? 0);
        }
        final ops = await api.cashOps();
        if (!mounted) return;
        _cash = m;
        _desks = n;
        _ops = ops.items.take(6).toList();
      }),
      part(me.can('objects:read'), () async {
        final o = await api.objects();
        _objs = o;
        var t = 0, sold = 0, b = 0, f = 0;
        for (final x in o) {
          final a = (x['apartments'] as Map?) ?? const {};
          t += (a['total'] as num?)?.toInt() ?? 0;
          sold += (a['sold'] as num?)?.toInt() ?? 0;
          b += (a['booked'] as num?)?.toInt() ?? 0;
          f += (a['free'] as num?)?.toInt() ?? 0;
        }
        _apts = t;
        _sold = sold;
        _booked = b;
        _free = f;
      }),
      part(me.can('attendance:read'), () async {
        final a = await api.attendance();
        final sum = Map<String, dynamic>.from((a['summary'] as Map?) ?? const {});
        _attStaff = (sum['staff'] as num?)?.toInt() ?? 0;
        _attWorking = (sum['working'] as num?)?.toInt() ?? 0;
        _attCame = (sum['came'] as num?)?.toInt() ?? 0;
        _attAbsent = (sum['absent'] as num?)?.toInt() ?? math.max(0, _attStaff - _attCame);
        final now = <Map<String, dynamic>>[];
        for (final o in ((a['office'] as List?) ?? const []).whereType<Map>()) {
          if (o['status'] == 'working') now.add({...Map<String, dynamic>.from(o), 'office': true});
        }
        for (final site in ((a['sites'] as List?) ?? const []).whereType<Map>()) {
          for (final w in ((site['workers'] as List?) ?? const []).whereType<Map>()) {
            if (w['status'] == 'working') now.add({...Map<String, dynamic>.from(w), 'site': '${site['name']}'});
          }
        }
        _now = now;
      }),
      part(me.can('tasks:read'), () async {
        final p = await api.tasks();
        final today = DateTime.now().toIso8601String().substring(0, 10);
        var open = 0, over = 0;
        for (final x in p.items) {
          if (x['status'] == 'done') continue;
          open++;
          final due = x['due_date'] as String?;
          if (due != null && due.compareTo(today) < 0) over++;
        }
        _open = open;
        _overdue = over;
      }),
      part(me.can('leads:read'), () async {
        final l = await api.leads();
        _leadsTotal = l.meta.total;
        _leads = l.items.take(3).toList();
      }),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = tried > 0 && failed == tried ? _error : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = s.me!;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _cash.isEmpty && _apts == 0 && _open == 0 && _leads.isEmpty) return ErrorView(message: _error!, onRetry: _load);

    final cur = _cash.keys.isEmpty ? '' : (_cash.containsKey('UZS') ? 'UZS' : _cash.keys.first);
    final q = _q.trim().toLowerCase();
    final services = widget.sections.where((x) => q.isEmpty || tr(x.label).toLowerCase().contains(q) || x.label.toLowerCase().contains(q)).toList();
    final searching = q.isNotEmpty;

    final stats = <Widget>[
      if (me.can('objects:read'))
        _Stat(icon: Icons.apartment_rounded, color: Brand.blue, title: 'Sotuv', big: '$_sold', sub: "$_apts xonadondan · bron $_booked · bo'sh $_free", progress: _apts == 0 ? 0 : _sold / _apts, onTap: () => widget.onOpen?.call('Obyektlar')),
      if (me.can('tasks:read'))
        _Stat(icon: Icons.checklist_rounded, color: _overdue > 0 ? cs.error : Brand.purple, title: 'Vazifalar', big: '$_open', sub: _overdue > 0 ? "ochiq · $_overdue ta muddati o'tgan" : 'ochiq vazifa', warn: _overdue > 0, onTap: () => widget.onOpen?.call('Vazifalar')),
      if (me.can('attendance:read'))
        _Stat(icon: Icons.how_to_reg_rounded, color: Brand.teal, title: 'Bugun ishda', big: '$_attWorking', sub: '$_attCame keldi · $_attAbsent kelmadi · $_attStaff xodim', progress: _attStaff == 0 ? 0 : _attCame / _attStaff, onTap: () => widget.onOpen?.call('Davomat')),
      if (me.can('leads:read'))
        _Stat(icon: Icons.people_alt_rounded, color: Brand.pink, title: 'Lidlar', big: '$_leadsTotal', sub: 'jami so\'rovlar', onTap: () => widget.onOpen?.call('Lidlar')),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // qidiruv: xizmatlar ro'yxatini filtrlaydi
          Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Icon(Icons.search_rounded, color: cs.outline),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(hintText: tr("Bo'lim qidirish…"), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (!searching) ...[
            if (me.can('objects:read') && _objs.isNotEmpty) ...[
              SizedBox(
                height: 98,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: _objs.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => _ObjectRing(_objs[i], onTap: () => widget.onOpen?.call('Obyektlar')),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (me.can('shift:write')) ...[ShiftCard(session: s), const SizedBox(height: 14)],
            if (me.can('cash:read')) ...[
              _CashCard(
                total: _cash[cur],
                currency: cur,
                others: {for (final e in _cash.entries) if (e.key != cur) e.key: e.value},
                desks: _desks,
                onTap: () => widget.onOpen?.call('Kassa'),
              ),
              const SizedBox(height: 14),
            ],
            if (stats.isNotEmpty) ...[
              for (var i = 0; i < stats.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: stats[i]),
                      if (i + 1 < stats.length) ...[const SizedBox(width: 10), Expanded(child: stats[i + 1])],
                    ]),
                  ),
                ),
              const SizedBox(height: 6),
            ],
          ],
          if (!searching && me.can('attendance:read') && _now.isNotEmpty) ...[
            _Section(title: 'Hozir ishda', trailing: '${_now.length} kishi', onTap: () => widget.onOpen?.call('Davomat')),
            Glass(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [for (final x in _now.take(8)) _WorkingRow(x)]),
            ),
            if (_now.length > 8) Padding(padding: const EdgeInsets.only(top: 6, left: 6), child: Text('+${_now.length - 8} ${tr('kishi yana')}', style: TextStyle(color: cs.outline, fontSize: 12.5))),
            const SizedBox(height: 18),
          ],
          if (services.isNotEmpty) ...[
            _Section(title: 'Xizmatlar'),
            LayoutBuilder(
              builder: (context, bc) {
                final tw = (bc.maxWidth - 30) / 4;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [for (final x in services) SizedBox(width: tw, height: tw * 1.08, child: _ServiceTile(x, onTap: () => widget.onOpen?.call(x.label)))],
                );
              },
            ),
          ] else if (searching)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text("Hech narsa topilmadi"))),
          if (!searching && me.can('leads:read')) ...[
            const SizedBox(height: 22),
            _Section(title: 'Yangi lidlar', trailing: '$_leadsTotal ta', onTap: () => widget.onOpen?.call('Lidlar')),
            if (_leads.isEmpty) const _Empty("Hozircha lid yo'q"),
            if (_leads.isNotEmpty) Glass(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: [for (final l in _leads) _LeadRow(l)])),
          ],
          if (!searching && me.can('cash:read')) ...[
            const SizedBox(height: 22),
            _Section(title: 'Oxirgi operatsiyalar', onTap: () => widget.onOpen?.call('Kassa')),
            if (_ops.isEmpty) const _Empty("Operatsiya yo'q"),
            if (_ops.isNotEmpty) Glass(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: [for (final o in _ops) _OpRow(o)])),
          ],
        ],
      ),
    );
  }
}

/// Obyekt: sotilgan ulushi aylana ko'rsatkichda (HEMIS «story» doiralari kabi)
class _ObjectRing extends StatelessWidget {
  const _ObjectRing(this.o, {this.onTap});

  final Map<String, dynamic> o;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = (o['apartments'] as Map?) ?? const {};
    final total = (a['total'] as num?)?.toDouble() ?? 0;
    final sold = (a['sold'] as num?)?.toDouble() ?? 0;
    final frac = total == 0 ? 0.0 : sold / total;
    final name = '${o['name'] ?? ''}';
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 74,
        child: Column(children: [
          SizedBox(
            width: 66,
            height: 66,
            child: CustomPaint(
              painter: _RingPainter(frac, cs.primary, cs.primary.withValues(alpha: 0.14)),
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Glass(
                  radius: 30,
                  blur: false,
                  shadow: false,
                  child: Center(child: w.Text('${(frac * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: cs.primary))),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          w.Text(name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurface, height: 1.15)),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac, this.color, this.track);

  final double frac;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = track;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(startAngle: -math.pi / 2, endAngle: math.pi * 1.5, colors: [Brand.amber, color, color], stops: const [0, 0.4, 1], transform: const GradientRotation(-math.pi / 2)).createShader(r);
    if (frac > 0) canvas.drawArc(r, -math.pi / 2, math.pi * 2 * frac.clamp(0.0, 1.0), false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.frac != frac || old.color != color;
}

/// Hozir ishda: kim, qachondan beri, necha soat (prorab/ofis «Ishga keldim» bosganlar ham shu yerda)
class _WorkingRow extends StatelessWidget {
  const _WorkingRow(this.x);

  final Map<String, dynamic> x;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final since = shiftMoment(x, 'in');
    final dur = since == null ? null : DateTime.now().difference(since);
    final office = x['office'] == true;
    final name = '${x['name']}';
    return ListTile(
      dense: true,
      leading: Stack(clipBehavior: Clip.none, children: [
        IconTile(icon: office ? Icons.engineering_rounded : Icons.construction_rounded, color: office ? Brand.blue : Brand.teal, size: 38),
        Positioned(right: -2, bottom: -2, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.green.shade500, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
      ]),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
      subtitle: Text([if ('${x['role'] ?? ''}'.isNotEmpty) '${x['role']}', if (x['site'] != null) '${x['site']}', if (x['in'] != null) '${x['in']} ${tr('dan beri')}'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12)),
      trailing: dur == null ? null : Text(durationText(dur), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: cs.primary)),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile(this.x, {this.onTap});

  final DashSection x;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 20,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconTile(icon: x.icon, color: x.color, size: 42),
        const SizedBox(height: 7),
        w.Text(tr(x.label), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.15)),
      ]),
    );
  }
}

class _CashCard extends StatelessWidget {
  const _CashCard({required this.total, required this.currency, required this.others, required this.desks, this.onTap});

  final num? total;
  final String currency;
  final Map<String, num> others;
  final int desks;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B7A3B), Color(0xFF0E9A55), Color(0xFF0F8F8A)]),
          boxShadow: [BoxShadow(color: Brand.green.withValues(alpha: 0.32), blurRadius: 26, offset: const Offset(0, 12))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(children: [
            // shisha yaltiroqligi
            Positioned(right: -40, top: -50, child: Container(width: 180, height: 180, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10)))),
            Positioned(right: 30, bottom: -70, child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.amber.withValues(alpha: 0.16)))),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(11)),
                    child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text('Kassalarda jami', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                    child: Text('$desks ta kassa', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: w.Text.rich(TextSpan(children: [
                    TextSpan(text: money(total ?? 0), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                    TextSpan(text: tr("  ${currency == 'UZS' ? "so'm" : currency}"), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15, fontWeight: FontWeight.w700)),
                  ])),
                ),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(others.entries.map((e) => '${money(e.value)} ${e.key}').join('  ·  '), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.color, required this.title, required this.big, required this.sub, this.progress, this.warn = false, this.onTap});

  final IconData icon;
  final Color color;
  final String title;
  final String big;
  final String sub;
  final double? progress;
  final bool warn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Glass(
      radius: 22,
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconTile(icon: icon, color: color, size: 30),
          const SizedBox(width: 8),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontWeight: FontWeight.w700, fontSize: 12.5))),
        ]),
        const SizedBox(height: 8),
        Text(big, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.8, color: warn ? cs.error : cs.onSurface, height: 1)),
        if (progress != null) ...[
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress, minHeight: 5, color: color, backgroundColor: color.withValues(alpha: 0.14))),
        ],
        const SizedBox(height: 7),
        Text(sub, style: TextStyle(color: cs.outline, fontSize: 11.5, height: 1.25)),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.trailing, this.onTap});

  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
          const Spacer(),
          if (trailing != null) Text(trailing!, style: TextStyle(color: cs.outline, fontSize: 13)),
          if (onTap != null) Icon(Icons.chevron_right, color: cs.outline, size: 20),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Glass(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.outline))));
}

class _LeadRow extends StatelessWidget {
  const _LeadRow(this.l);
  final Map<String, dynamic> l;

  @override
  Widget build(BuildContext context) {
    final name = '${l['name'] ?? l['phone'] ?? 'Lid'}';
    return ListTile(
      dense: true,
      leading: IconTile(icon: Icons.person_rounded, color: Brand.pink, size: 38),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      subtitle: Text('${l['source'] ?? ''}${l['rooms'] != null ? ' · ${l['rooms']} xona' : ''} · ${formatDate('${l['created_at'] ?? ''}')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _OpRow extends StatelessWidget {
  const _OpRow(this.o);
  final Map<String, dynamic> o;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inc = o['type'] == 'in';
    final amount = (o['amount'] as num?) ?? 0;
    final c = inc ? Colors.green.shade700 : cs.error;
    return ListTile(
      dense: true,
      leading: IconTile(icon: inc ? Icons.south_west_rounded : Icons.north_east_rounded, color: c, size: 38),
      title: Text('${o['category'] ?? (inc ? 'Kirim' : 'Chiqim')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      subtitle: Text('${formatDate('${o['date'] ?? ''}')}${(o['note'] ?? '').toString().isEmpty ? '' : ' · ${o['note']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      trailing: Text('${inc ? '+' : '−'}${money(amount)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: c)),
    );
  }
}
