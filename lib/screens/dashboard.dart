import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as w show Text;
import 'package:url_launcher/url_launcher.dart';


import '../avatar.dart';
import '../format.dart';
import '../session.dart';
import '../widgets.dart';
import '../theme.dart';
import '../motion.dart';
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
      if (!mounted) return;
      if (_now.isNotEmpty) setState(() {});
      if (++_tick % 6 == 0) _load(); // har 3 daqiqada ma'lumot jimgina yangilanadi
    });
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_load);
    _clock?.cancel();
    super.dispose();
  }

  /// «Hozir ishda» qatori bosilganda: xodim kartochkasi (kelgan vaqti, ishlagan vaqt, joylashuv, oylik hisobi)
  void _openWorker(Map<String, dynamic> x) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WorkerNowSheet(
        session: s,
        x: x,
        onAttendance: () {
          Navigator.of(context).pop();
          widget.onOpen?.call('Davomat');
        },
      ),
    );
  }

  /// Bo'limlar ketma-ket yumshoq paydo bo'ladi
  List<Widget> _reveal(List<Widget> l) => [for (var i = 0; i < l.length; i++) Reveal(index: i, child: l[i])];

  int _tick = 0;

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
    if (_loading) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, NavInset.listBottom(context)),
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          Skeleton(height: 54, radius: 18),
          SizedBox(height: 16),
          Skeleton(height: 190, radius: 26),
          SizedBox(height: 14),
          Row(children: [Expanded(child: Skeleton(height: 150)), SizedBox(width: 10), Expanded(child: Skeleton(height: 150))]),
          SizedBox(height: 10),
          Skeleton(height: 120),
          SizedBox(height: 22),
          Skeleton(height: 24, width: 140, radius: 8),
          SizedBox(height: 12),
          Row(children: [Expanded(child: Skeleton(height: 100, radius: 20)), SizedBox(width: 10), Expanded(child: Skeleton(height: 100, radius: 20)), SizedBox(width: 10), Expanded(child: Skeleton(height: 100, radius: 20)), SizedBox(width: 10), Expanded(child: Skeleton(height: 100, radius: 20))]),
        ],
      );
    }
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
        padding: EdgeInsets.fromLTRB(16, 4, 16, NavInset.listBottom(context)),
        physics: const AlwaysScrollableScrollPhysics(),
        children: _reveal([
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
              _ObjectCards(_objs, onTap: () => widget.onOpen?.call('Obyektlar')),
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
            for (var i = 0; i < _now.take(8).length; i++)
              Reveal(index: i, child: GlassRow(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11), onTap: () => _openWorker(_now[i]), child: _WorkingRow(_now[i]))),
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
            for (var i = 0; i < _leads.length; i++) Reveal(index: i, child: GlassRow(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: _LeadRow(_leads[i]))),
          ],
          if (!searching && me.can('cash:read')) ...[
            const SizedBox(height: 22),
            _Section(title: 'Oxirgi operatsiyalar', onTap: () => widget.onOpen?.call('Kassa')),
            if (_ops.isEmpty) const _Empty("Operatsiya yo'q"),
            for (var i = 0; i < _ops.length; i++) Reveal(index: i, child: GlassRow(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: _OpRow(_ops[i]))),
          ],
        ]),
      ),
    );
  }
}

/// Obyektlar: bitta bo'lsa — butun qator, ikkita bo'lsa — yarim-yarim, ko'p bo'lsa — yonga surib ko'riladi
class _ObjectCards extends StatelessWidget {
  const _ObjectCards(this.objs, {this.onTap});

  final List<Map<String, dynamic>> objs;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, bc) {
      final n = objs.length;
      final w0 = bc.maxWidth;
      final cw = n == 1 ? w0 : (n == 2 ? (w0 - 10) / 2 : w0 * 0.74);
      final card = [for (final o in objs) SizedBox(width: cw, child: _ObjectCard(o, onTap: onTap))];
      if (n <= 2) return Row(children: [for (var i = 0; i < card.length; i++) ...[if (i > 0) const SizedBox(width: 10), card[i]]]);
      return SizedBox(height: 108, child: ListView.separated(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, itemCount: n, separatorBuilder: (_, _) => const SizedBox(width: 10), itemBuilder: (_, i) => card[i]));
    });
  }
}

class _ObjectCard extends StatelessWidget {
  const _ObjectCard(this.o, {this.onTap});

  final Map<String, dynamic> o;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = (o['apartments'] as Map?) ?? const {};
    final total = (a['total'] as num?)?.toDouble() ?? 0;
    final sold = (a['sold'] as num?)?.toInt() ?? 0;
    final free = (a['free'] as num?)?.toInt() ?? 0;
    final booked = (a['booked'] as num?)?.toInt() ?? 0;
    final frac = total == 0 ? 0.0 : sold / total;
    return Glass(
      radius: 22,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        SizedBox(
          width: 60,
          height: 60,
          child: CustomPaint(
            painter: _RingPainter(frac, cs.primary, cs.primary.withValues(alpha: 0.14)),
            child: Center(child: w.Text('${(frac * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: cs.primary))),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            w.Text('${o['name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.15)),
            const SizedBox(height: 5),
            Text('${tr('Sotilgan')} $sold · ${tr("Bo'sh")} $free · ${tr('Bron')} $booked', maxLines: 2, style: TextStyle(color: cs.outline, fontSize: 11.5, height: 1.25)),
          ]),
        ),
      ]),
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
    final place = [if ('${x['role'] ?? ''}'.isNotEmpty) '${x['role']}', if (x['site'] != null) '${x['site']}'].join(' · ');
    return Row(children: [
      Stack(clipBehavior: Clip.none, children: [
        IconTile(icon: office ? Icons.engineering_rounded : Icons.construction_rounded, color: office ? Brand.blue : Brand.teal, size: 42),
        Positioned(right: -2, bottom: -2, child: Container(width: 13, height: 13, decoration: BoxDecoration(color: Colors.green.shade500, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
      ]),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${x['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          if (place.isNotEmpty) Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12)),
          if (x['in'] != null) Text('${x['in']} ${tr('dan beri')}', style: TextStyle(color: cs.outline, fontSize: 12)),
        ]),
      ),
      const SizedBox(width: 8),
      if (dur != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Text(durationText(dur), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: cs.primary)),
        ),
    ]);
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
    final cs = Theme.of(context).colorScheme;
    final ink = context.ink;
    return HeroGlass(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const IconTile(icon: Icons.account_balance_wallet_rounded, color: Brand.green, size: 38),
          const SizedBox(width: 10),
          Text('Kassalarda jami', style: TextStyle(color: cs.outline, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: context.pill, borderRadius: BorderRadius.circular(20), border: Border.all(color: context.pillBorder)),
            child: Text('$desks ta kassa', style: TextStyle(color: ink, fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 14),
        CountUp(
          value: total ?? 0,
          builder: (context, v) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: w.Text.rich(TextSpan(children: [
              TextSpan(text: money(v), style: TextStyle(color: ink, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
              TextSpan(text: tr("  ${currency == 'UZS' ? "so'm" : currency}"), style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: 15, fontWeight: FontWeight.w700)),
            ])),
          ),
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(others.entries.map((e) => '${money(e.value)} ${e.key}').join('  ·  '), style: TextStyle(color: cs.outline, fontSize: 12.5)),
        ],
      ]),
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
        (int.tryParse(big) != null)
            ? CountUp(value: int.parse(big), builder: (_, v) => Text('$v', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.8, color: warn ? cs.error : cs.onSurface, height: 1)))
            : Text(big, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.8, color: warn ? cs.error : cs.onSurface, height: 1)),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: IconTile(icon: inc ? Icons.south_west_rounded : Icons.north_east_rounded, color: c, size: 38),
      title: Text('${o['category'] ?? (inc ? 'Kirim' : 'Chiqim')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      subtitle: Text('${formatDate('${o['date'] ?? ''}')}${(o['note'] ?? '').toString().isEmpty ? '' : ' · ${o['note']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      trailing: Text('${inc ? '+' : '−'}${money(amount)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: c)),
    );
  }
}

/// Hozir ishdagi xodim kartochkasi
class _WorkerNowSheet extends StatefulWidget {
  const _WorkerNowSheet({required this.session, required this.x, required this.onAttendance});

  final Session session;
  final Map<String, dynamic> x;
  final VoidCallback onAttendance;

  @override
  State<_WorkerNowSheet> createState() => _WorkerNowSheetState();
}

class _WorkerNowSheetState extends State<_WorkerNowSheet> {
  Map<String, dynamic>? _month; // oylik hisob (faqat ko'rishga ruxsati bo'lganlarga)
  bool _loading = false;
  String _cur = '';

  @override
  void initState() {
    super.initState();
    if (widget.x['office'] != true && widget.session.me!.can('crew:read')) {
      _loading = true;
      _loadMonth();
    }
  }

  Future<void> _loadMonth() async {
    try {
      final n = DateTime.now();
      final d = await widget.session.api!.crew(month: '${n.year}-${n.month.toString().padLeft(2, '0')}');
      final id = '${widget.x['id']}';
      for (final o in ((d['objects'] as List?) ?? const []).whereType<Map>()) {
        for (final w in ((o['workers'] as List?) ?? const []).whereType<Map>()) {
          if ('${w['id']}' == id) _month = Map<String, dynamic>.from((w['month'] as Map?) ?? const {});
        }
      }
      final c = '${d['currency'] ?? ''}'.trim();
      _cur = (c.isEmpty || c == 'UZS' || c.toLowerCase() == 'сум' || c.toLowerCase() == 'сўм') ? tr("so'm") : c;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Widget _kv(IconData icon, String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 19, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13))),
          Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final x = widget.x;
    final since = shiftMoment(x, 'in');
    final dur = since == null ? null : DateTime.now().difference(since);
    final office = x['office'] == true;
    final phone = '${x['phone'] ?? ''}'.trim();
    final lat = x['in_lat'] as num?, lng = x['in_lng'] as num?, dist = x['in_dist'] as num?;
    final where = lat == null ? tr('joylashuvsiz') : (dist == null ? tr('joylashuv bor') : (dist <= 300 ? tr('obyektda') : '${tr('obyektdan')} ${distLabel(dist)}'));
    final accrued = _month?['accrued'] as num?, paid = _month?['paid'] as num?, due = _month?['due'] as num?;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            UserAvatar(session: widget.session, name: '${x['name']}', size: 56, url: null, ring: false),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${x['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                Text([if ('${x['role'] ?? ''}'.isNotEmpty) '${x['role']}', if (x['site'] != null) '${x['site']}'].join(' · '), style: TextStyle(color: cs.outline, fontSize: 13)),
              ]),
            ),
            StatusChip(tr('Ishda'), Colors.green.shade700),
          ]),
          const SizedBox(height: 18),
          if (dur != null)
            HeroGlass(
              tint: Brand.teal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${tr('Keldi')} ${x['in'] ?? ''}', style: TextStyle(color: cs.outline, fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(durationText(dur), style: TextStyle(color: context.ink, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.4)),
                    Text(tr('ishlagan vaqt'), style: TextStyle(color: cs.outline, fontSize: 12)),
                  ]),
                ),
                const Icon(Icons.timer_rounded, color: Brand.teal, size: 34),
              ]),
            ),
          const SizedBox(height: 16),
          if (office) _kv(Icons.place_outlined, tr('Joylashuv'), where),
          if (x['week_days'] is num) _kv(Icons.calendar_month_outlined, tr('Shu hafta ish kuni'), '${x['week_days']}'),
          if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator(minHeight: 3)),
          if (accrued != null) ...[
            _kv(Icons.payments_outlined, tr("Oy bo'yicha hisoblangan"), '${money(accrued)} $_cur'),
            if (paid != null) _kv(Icons.check_circle_outline, tr("To'langan"), money(paid), color: Colors.green.shade700),
            if (due != null) _kv(Icons.pending_outlined, tr('Qoldi'), money(due), color: due > 0 ? cs.error : null),
          ],
          const SizedBox(height: 8),
          Row(children: [
            if (phone.isNotEmpty) ...[
              Expanded(child: FilledButton.icon(onPressed: () => launchUrl(Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}')), icon: const Icon(Icons.call_rounded, size: 19), label: Text(tr("Qo'ng'iroq")))),
              const SizedBox(width: 10),
            ],
            if (lat != null && lng != null) ...[
              Expanded(child: OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.map_outlined, size: 19), label: Text(tr('Xarita')))),
              const SizedBox(width: 10),
            ],
            Expanded(child: OutlinedButton.icon(onPressed: widget.onAttendance, icon: const Icon(Icons.how_to_reg_outlined, size: 19), label: Text(tr('Davomat')))),
          ]),
        ]),
      ),
    );
  }
}
