import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../format.dart';
import '../l10n.dart';
import '../motion.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'objects.dart';

enum _P { today, week, month, all }

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

(String, String) _range(_P p) {
  final n = DateTime.now();
  return switch (p) {
    _P.today => (_ymd(n), _ymd(n)),
    _P.week => (_ymd(n.subtract(const Duration(days: 6))), _ymd(n)),
    _P.month => (_ymd(DateTime(n.year, n.month, 1)), _ymd(n)),
    _P.all => ('2000-01-01', _ymd(n)),
  };
}

/// Server valyutasi rus yozuvida kelsa («сум») — o'zbekcha belgi
String _curOf(Object? c) {
  final v = '$c'.trim();
  return v.isEmpty || v == 'null' || v.toLowerCase() == 'сум' || v.toLowerCase() == 'uzs' ? "so'm" : v;
}

String _pName(_P p) => switch (p) { _P.today => 'Bugun', _P.week => '7 kun', _P.month => 'Shu oy', _P.all => 'Hammasi' };

Widget _periodBar(_P cur, ValueChanged<_P> on) => SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          for (final p in _P.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(_pName(p)), selected: cur == p, showCheckmark: false, onSelected: (_) {
                HapticFeedback.selectionClick();
                on(p);
              }),
            ),
        ],
      ),
    );

/// Katta raqamli ko'rsatkich kartochkasi (sotuv summasi + ikkilamchi ko'rsatkichlar)
Widget _hero(BuildContext context, {required String title, required num sum, required String cur, required List<(String, String, Color?)> chips}) {
  final cs = Theme.of(context).colorScheme;
  return HeroGlass(
    padding: const EdgeInsets.all(18),
    radius: 24,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.75), fontWeight: FontWeight.w700, fontSize: 13)),
      const SizedBox(height: 6),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('${money(sum)} $cur', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: cs.onPrimaryContainer, letterSpacing: -0.6))),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 8, children: [
        for (final c in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: context.pill, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pillBorder)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${tr(c.$1)}: ', style: TextStyle(color: context.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(c.$2, style: TextStyle(color: c.$3 ?? context.ink, fontSize: 13.5, fontWeight: FontWeight.w900)),
            ]),
          ),
      ]),
    ]),
  );
}

/// Sotuvlar: sotuvchi — faqat o'zinikini; rahbar/buxgalter — [sellerId] bo'yicha bitta sotuvchiniki (yoki hammasi).
/// Har bitim: xonadon, xaridor, narx, qancha to'langan; ustiga bosilsa — xonadon kartochkasi.
class DealsView extends StatefulWidget {
  const DealsView({super.key, required this.session, this.sellerId, this.initial});

  final Session session;
  final String? sellerId;
  final int? initial;

  @override
  State<DealsView> createState() => _DealsViewState();
}

class _DealsViewState extends State<DealsView> {
  late _P _p = widget.initial != null ? _P.values[widget.initial!] : _P.month;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _meta = const {};

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final (from, to) = _range(_p);
      final r = await s.api!.salesDeals(from: from, to: to, seller: widget.sellerId);
      if (!mounted) return;
      setState(() {
        _items = r.items;
        _meta = r.meta;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      await s.handleError(e);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> a) async {
    HapticFeedback.selectionClick();
    var full = a;
    try {
      full = await s.api!.apartment('${a['object_id']}', '${a['apartment_id']}');
    } catch (_) {}
    if (!mounted) return;
    showApartmentSheet(context, s, '${a['object_id']}', '${a['object']}', full, onChanged: () => _load(quiet: true));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = _curOf(_meta['currency']);
    final body = _error != null && _items.isEmpty
        ? ErrorView(message: _error!, onRetry: _load)
        : RefreshIndicator(
            onRefresh: () => _load(quiet: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: NavInset.listBottom(context) + 12),
              children: [
                _periodBar(_p, (p) {
                  setState(() => _p = p);
                  _load();
                }),
                if (_loading)
                  const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()))
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: _hero(context,
                        title: 'Sotilgan summa',
                        sum: (_meta['sold_sum'] as num?) ?? 0,
                        cur: cur,
                        chips: [
                          ('Sotilgan', '${_meta['sold'] ?? 0} ${tr('ta')}', null),
                          if (((_meta['booked'] as num?) ?? 0) > 0) ('Bron', '${_meta['booked']} ${tr('ta')} · ${money((_meta['booked_sum'] as num?) ?? 0)}', Brand.orange),
                          ("Qabul qilingan to'lov", money((_meta['collected'] as num?) ?? 0), Brand.blue),
                          if (((_meta['overdue'] as num?) ?? 0) > 0) ("Muddati o'tgan", money((_meta['overdue'] as num?) ?? 0), cs.error),
                        ]),
                  ),
                  if (_items.isEmpty) const Padding(padding: EdgeInsets.all(48), child: Center(child: Text("Bu davrda sotuv yo'q"))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: DeskGrid(minColumn: 460, gap: 12, children: [for (var i = 0; i < _items.length; i++) Reveal(index: i.clamp(0, 9), child: _tile(context, _items[i], cur))]),
                  ),
                ],
              ],
            ),
          );
    return body;
  }

  Widget _tile(BuildContext context, Map<String, dynamic> a, String cur) {
    final cs = Theme.of(context).colorScheme;
    final price = (a['price'] as num?) ?? 0;
    final owed = ((a['owed'] as num?) ?? 0) > 0 ? a['owed'] as num : price;
    final paid = (a['paid'] as num?) ?? 0;
    final ratio = owed > 0 ? (paid / owed).clamp(0, 1).toDouble() : 0.0;
    final st = '${a['status']}';
    final buyer = '${(a['buyer'] as Map?)?['name'] ?? ''}';
    final overdue = ((a['overdue'] as num?) ?? 0) > 0;
    final stc = st == 'sold' ? Brand.blue : (st == 'booked' ? Brand.orange : statusColor(st));
    return GlassRow(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      onTap: () => _open(a),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: stc.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: Text('${a['number']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: stc, fontSize: '${a['number']}'.length > 3 ? 12 : 15)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(buyer.isEmpty ? '—' : buyer, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text([
                '${roomsLabel(a['rooms'])}',
                '${a['object']}',
                if (a['sale_date'] != null) formatDate('${a['sale_date']}'),
                if (a['seller'] != null && widget.sellerId == null && _meta['seller_scope'] != true) '${a['seller']}',
              ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${money(price)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
            const SizedBox(height: 4),
            StatusChip(aptStatus(st), stc),
          ]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: ratio, minHeight: 6, backgroundColor: cs.outline.withValues(alpha: 0.15), color: overdue ? cs.error : Brand.blue),
            ),
          ),
          const SizedBox(width: 10),
          Text("${tr("To'langan")} ${money(paid)}", style: TextStyle(color: cs.outline, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}

/// Rahbar va buxgalter uchun: har bir sotuvchi nechta kvartira va qancha summaga sotgani (eng ko'p sotgan yuqorida).
class SellersView extends StatefulWidget {
  const SellersView({super.key, required this.session});

  final Session session;

  @override
  State<SellersView> createState() => _SellersViewState();
}

class _SellersViewState extends State<SellersView> {
  _P _p = _P.month;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  Map<String, dynamic> _meta = const {};

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final (from, to) = _range(_p);
      final r = await s.api!.salesTeam(from: from, to: to);
      if (!mounted) return;
      setState(() {
        _rows = r.items;
        _meta = r.meta;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      await s.handleError(e);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _openSeller(Map<String, dynamic> r) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(DeskRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('${r['name']}')),
        body: DealsView(session: s, sellerId: '${r['id']}', initial: _p.index),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_error != null && _rows.isEmpty) return ErrorView(message: _error!, onRetry: _load);
    final cur = _curOf(_meta['currency']);
    final total = Map<String, dynamic>.from((_meta['total'] as Map?) ?? const {});
    final top = _rows.fold<num>(0, (m, r) => ((r['period'] as Map?)?['sold_sum'] as num? ?? 0) > m ? (r['period'] as Map)['sold_sum'] as num : m);
    return RefreshIndicator(
      onRefresh: () => _load(quiet: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: NavInset.listBottom(context) + 12),
        children: [
          _periodBar(_p, (p) {
            setState(() => _p = p);
            _load();
          }),
          if (_loading)
            const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()))
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: _hero(context, title: 'Kompaniya bo\'yicha sotilgan', sum: (total['sold_sum'] as num?) ?? 0, cur: cur, chips: [
                ('Sotilgan', '${total['sold'] ?? 0} ${tr('ta')}', null),
                if (((total['booked'] as num?) ?? 0) > 0) ('Bron', '${total['booked']} ${tr('ta')} · ${money((total['booked_sum'] as num?) ?? 0)}', Brand.orange),
                ('Sotuvchilar', '${_rows.where((r) => (((r['period'] as Map?)?['sold'] as num?) ?? 0) + (((r['period'] as Map?)?['booked'] as num?) ?? 0) > 0).length}', null),
                ("Qabul qilingan to'lov", money((total['collected'] as num?) ?? 0), Brand.blue),
                if (((total['overdue'] as num?) ?? 0) > 0) ("Muddati o'tgan", money((total['overdue'] as num?) ?? 0), cs.error),
              ]),
            ),
            if (_rows.isEmpty) const Padding(padding: EdgeInsets.all(48), child: Center(child: Text("Sotuvchilar yo'q"))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: DeskGrid(minColumn: 460, gap: 12, children: [for (var i = 0; i < _rows.length; i++) Reveal(index: i.clamp(0, 9), child: _card(context, _rows[i], i, top, cur))]),
            ),
            if (((_meta['no_seller'] as num?) ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text("${tr("Sotuvchisi ko'rsatilmagan bitimlar")}: ${_meta['no_seller']}", style: TextStyle(color: cs.outline, fontSize: 12.5)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> r, int rank, num top, String cur) {
    final cs = Theme.of(context).colorScheme;
    final p = Map<String, dynamic>.from((r['period'] as Map?) ?? const {});
    final td = Map<String, dynamic>.from((r['today'] as Map?) ?? const {});
    final sum = (p['sold_sum'] as num?) ?? 0;
    final name = '${r['name']}';
    final medal = sum > 0 && rank < 3 ? [const Color(0xFFF5B301), const Color(0xFF9AA7B8), const Color(0xFFC98A52)][rank] : null;
    return GlassRow(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      onTap: () => _openSeller(r),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            CircleAvatar(radius: 24, backgroundColor: cs.primary.withValues(alpha: 0.14), foregroundColor: cs.primary, child: Text(name.isEmpty ? '?' : name.trim()[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
            if (medal != null)
              Positioned(right: -4, bottom: -4, child: Container(width: 20, height: 20, alignment: Alignment.center, decoration: BoxDecoration(color: medal, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)), child: Text('${rank + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)))),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text('${r['role'] ?? ''}', style: TextStyle(color: cs.outline, fontSize: 12.5)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${money(sum)} $cur', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text('${p['sold'] ?? 0} ${tr('ta kvartira')}${((p['booked'] as num?) ?? 0) > 0 ? ' · ${p['booked']} ${tr('ta bron')}' : ''}', style: TextStyle(color: cs.outline, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: cs.outline),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: top > 0 ? (sum / top).clamp(0, 1).toDouble() : 0, minHeight: 6, backgroundColor: cs.outline.withValues(alpha: 0.15), color: medal ?? Brand.blue),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _mini(context, "Qabul qilingan to'lov", money((p['collected'] as num?) ?? 0), Brand.blue),
          if (((td['sold'] as num?) ?? 0) > 0) _mini(context, 'Bugun', '${td['sold']} ${tr('ta')} · ${money(td['sold_sum'] as num?)}', Brand.teal),
          if (((p['booked_sum'] as num?) ?? 0) > 0) _mini(context, 'Bron', money(p['booked_sum'] as num?), Brand.orange),
          if (((p['overdue'] as num?) ?? 0) > 0) _mini(context, "Muddati o'tgan", money(p['overdue'] as num?), cs.error),
        ]),
      ]),
    );
  }

  Widget _mini(BuildContext context, String l, String v, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text('${tr(l)}: $v', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
      );
}

/// Sotuvchining bosh sahifasi uchun: shu oydagi o'z sotuvlari (nechta, qancha summaga, qancha to'lov) — bosilsa «Sotuv» ochiladi.
class SalesGlance extends StatefulWidget {
  const SalesGlance({super.key, required this.session, this.onTap});

  final Session session;
  final VoidCallback? onTap;

  @override
  State<SalesGlance> createState() => _SalesGlanceState();
}

class _SalesGlanceState extends State<SalesGlance> {
  Map<String, dynamic>? _m;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (from, to) = _range(_P.month);
      final r = await widget.session.api!.salesDeals(from: from, to: to);
      if (mounted) setState(() => _m = r.meta);
    } catch (_) {
      // internet yo'q — karta yashirin qoladi
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    if (m == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: widget.onTap,
      child: _hero(context, title: 'Shu oy — mening sotuvlarim', sum: (m['sold_sum'] as num?) ?? 0, cur: _curOf(m['currency']), chips: [
        ('Sotilgan', '${m['sold'] ?? 0} ${tr('ta')}', null),
        if (((m['booked'] as num?) ?? 0) > 0) ('Bron', '${m['booked']} ${tr('ta')}', Brand.orange),
        ("Qabul qilingan to'lov", money((m['collected'] as num?) ?? 0), Brand.blue),
        if (((m['overdue'] as num?) ?? 0) > 0) ("Muddati o'tgan", money((m['overdue'] as num?) ?? 0), cs.error),
      ]),
    );
  }
}