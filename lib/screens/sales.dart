import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chess.dart';
import 'objects.dart';
import 'sales_deals.dart';
import '../l10n.dart';

const _months = ['Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'];

enum _Tab { chess, deals, payments, debtors }

/// Sotuv: xaridorlardan tushgan to'lovlar (oy bo'yicha) va qarzdorlar (sotilgan xonadonlar bo'yicha qolgan qarz).
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, required this.session});

  final Session session;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  late _Tab _tab = _team ? _Tab.deals : _Tab.chess;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _pays = const [];
  num _sum = 0;
  List<Map<String, dynamic>> _debtors = const [];
  num? _debtTotal; // server jami (sayt bilan bir xil)
  num _debtOverdue = 0;
  Map<String, String> _objectNames = {};
  bool _debtorsLoaded = false;

  Session get s => widget.session;

  /// Rahbar/buxgalter/kuzatuvchi — barcha sotuvchilar bo'yicha; sotuvchi — faqat o'z sotuvlari
  bool get _team => const {'admin', 'accountant', 'viewer'}.contains(s.me?.role);
  bool get _isCurrent => _month.year == DateTime.now().year && _month.month == DateTime.now().month;
  String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final objs = await s.api!.objects();
      _objectNames = {for (final o in objs) '${o['id']}': '${o['name']}'};
      if (_tab == _Tab.payments) {
        final r = await s.api!.salesPayments(from: _d(_month), to: _d(DateTime(_month.year, _month.month + 1, 0)));
        _pays = r.items;
        _sum = r.sum;
      } else {
        final srv = await s.api!.salesDebtors();
        if (srv != null) {
          _debtors = [for (final x in srv.items) {...x, 'id': x['apartment_id'], '_object': '${x['object'] ?? _objectNames['${x['object_id']}'] ?? ''}'}];
          _debtTotal = srv.total;
          _debtOverdue = srv.overdue;
          _debtorsLoaded = true;
          if (mounted) setState(() => _loading = false);
          return;
        }
        _debtTotal = null;
        final out = <Map<String, dynamic>>[];
        for (final o in objs) {
          var page = 1;
          while (true) {
            final p = await s.api!.apartments('${o['id']}', status: 'sold', page: page, perPage: 100);
            for (final a in p.items) {
              if (((a['debt'] as num?) ?? 0) > 0) out.add({...a, '_object': '${o['name']}'});
            }
            if (!p.meta.hasMore || page >= 10) break;
            page++;
          }
        }
        out.sort((x, y) => ((y['debt'] as num?) ?? 0).compareTo((x['debt'] as num?) ?? 0));
        _debtors = out;
        _debtorsLoaded = true;
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      await s.handleError(e);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _shift(int d) {
    final n = DateTime(_month.year, _month.month + d);
    if (n.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) return;
    HapticFeedback.selectionClick();
    setState(() => _month = n);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: LayoutBuilder(builder: (context, bc) {
          final tabs = <(_Tab, String)>[
            (_Tab.chess, 'Shaxmatka'),
            (_Tab.deals, _team ? 'Sotuvchilar' : 'Sotuvlarim'),
            (_Tab.payments, "To'lovlar"),
            (_Tab.debtors, 'Qarzdorlar'),
          ];
          void pick(_Tab t) {
            HapticFeedback.selectionClick();
            setState(() => _tab = t);
            if (t == _Tab.payments || (t == _Tab.debtors && !_debtorsLoaded)) _load();
          }

          // telefon (tor ekran): 4 ta tab sig'maydi — surib o'tkaziladigan chiplar; kompyuter/planshet: bitta segment qatori
          if (bc.maxWidth < 560) {
            return SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final t in tabs)
                  Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(t.$2), selected: _tab == t.$1, showCheckmark: false, onSelected: (_) => pick(t.$1))),
              ]),
            );
          }
          return SizedBox(
            width: double.infinity,
            child: SegmentedButton<_Tab>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [for (final t in tabs) ButtonSegment(value: t.$1, label: Text(t.$2))],
              selected: {_tab},
              onSelectionChanged: (v) => pick(v.first),
            ),
          );
        }),
      ),
      if (_tab == _Tab.payments)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(children: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12)),
                child: Text('${_months[_month.month - 1]} ${_month.year}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            IconButton(onPressed: _isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
          ]),
        ),
      Expanded(
        child: switch (_tab) {
          _Tab.chess => ChessTab(session: s),
          _Tab.deals => _team ? SellersView(session: s) : DealsView(session: s),
          _ => _body(cs),
        },
      ),
    ]);
  }

  Widget _body(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    return _tab == _Tab.payments ? _paymentsView(cs) : _debtorsView(cs);
  }

  Widget _paymentsView(ColorScheme cs) {
    // kunlar bo'yicha guruh: sana sarlavhasi + (kompyuterda 2 ustun) to'lov kartochkalari
    final rows = <Widget>[];
    final days = <String, List<Map<String, dynamic>>>{};
    for (final p in _pays) {
      days.putIfAbsent('${p['date']}', () => []).add(p);
    }
    for (final e in days.entries) {
      rows.add(Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text(formatDate(e.key), style: TextStyle(color: cs.outline, fontWeight: FontWeight.w800, fontSize: 13))));
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DeskGrid(minColumn: 460, gap: 12, children: [
          for (final p in e.value)
            GlassRow(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              onTap: () => _openPayment(p),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: Brand.blue.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.south_west_rounded, size: 19, color: Brand.blue)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${(p['buyer'] as Map?)?['name'] ?? ''}'.isEmpty ? 'Xaridor' : '${(p['buyer'] as Map)['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('kv. ${p['apartment_number']} · ${_objectNames['${p['object_id']}'] ?? ''}${p['method'] != null && '${p['method']}'.isNotEmpty ? ' · ${p['method']}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                  ]),
                ),
                Text('+${money(p['amount'] as num?)}', style: const TextStyle(fontWeight: FontWeight.w900, color: Brand.blue, fontSize: 15)),
              ]),
            ),
        ]),
      ));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: NavInset.listBottom(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: HeroGlass(
              padding: const EdgeInsets.all(16),
              radius: 22,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Oy davomida tushgan · ${_pays.length} ta to\'lov', style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.75), fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('${money(_sum)} so\'m', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer))),
              ]),
            ),
          ),
          if (_pays.isEmpty) const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Bu oyda to\'lov yo\'q'))),
          ...rows,
        ],
      ),
    );
  }

  /// To'lanishi kerak: jadval summasi (foiz bilan), bo'lmasa narx
  num _owed(Map a) {
    final o = (a['owed'] as num?) ?? (a['price'] as num?) ?? 0;
    return o <= 0 ? 1 : o;
  }

  /// To'lov qatori: xonadon kartochkasi ochiladi
  Future<void> _openPayment(Map<String, dynamic> p) async {
    try {
      final full = await s.api!.apartment('${p['object_id']}', '${p['apartment_id']}');
      if (!mounted) return;
      showApartmentSheet(context, s, '${p['object_id']}', _objectNames['${p['object_id']}'] ?? '', full, onChanged: _load);
    } catch (e) {
      await s.handleError(e);
    }
  }
  /// Qarzdor qatori: to'liq kvartira ma'lumoti serverdan olinadi, keyin kartochka ochiladi
  Future<void> _openDebtor(Map<String, dynamic> a) async {
    var full = a;
    if (_debtTotal != null) {
      try {
        full = await s.api!.apartment('${a['object_id']}', '${a['apartment_id'] ?? a['id']}');
      } catch (e) {
        await s.handleError(e);
      }
    }
    if (!mounted) return;
    showApartmentSheet(context, s, '${a['object_id']}', '${a['_object']}', full, onChanged: _load);
  }

  Widget _debtorsView(ColorScheme cs) {
    final total = _debtTotal ?? _debtors.fold<num>(0, (a, b) => a + ((b['debt'] as num?) ?? 0));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: NavInset.listBottom(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Xaridorlarning umumiy qarzi · ${_debtors.length} ta kvartira', style: TextStyle(color: cs.onErrorContainer.withValues(alpha: 0.8), fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('${money(total)} so\'m', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cs.onErrorContainer))),
                if (_debtTotal != null && _debtOverdue > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${tr("shundan muddati o'tgan")}: ${money(_debtOverdue)} so\'m', style: TextStyle(color: cs.error, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
              ]),
            ),
          ),
          if (_debtors.isEmpty) const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Qarzdor yo\'q'))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DeskGrid(minColumn: 460, gap: 12, children: [
          for (final a in _debtors)
            GlassRow(margin: const EdgeInsets.only(bottom: 2), onTap: () => _openDebtor(a), child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: cs.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                    child: Text('${a['number']}', style: TextStyle(fontWeight: FontWeight.w800, color: cs.error)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${(a['buyer'] as Map?)?['name'] ?? 'Xaridor'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${a['_object']} · ${roomsLabel(a['rooms'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: (((a['paid'] as num?) ?? 0) / _owed(a)).clamp(0, 1).toDouble(), minHeight: 4)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(money(a['debt'] as num?), style: TextStyle(fontWeight: FontWeight.w800, color: cs.error)),
                    Text('qarz', style: TextStyle(color: cs.outline, fontSize: 11.5)),
                  ]),
                ])),
            ]),
          ),
        ],
      ),
    );
  }
}
