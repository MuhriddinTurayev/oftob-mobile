import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'objects.dart';
import '../l10n.dart';

const _months = ['Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'];

enum _Tab { payments, debtors }

/// Sotuv: xaridorlardan tushgan to'lovlar (oy bo'yicha) va qarzdorlar (sotilgan xonadonlar bo'yicha qolgan qarz).
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, required this.session});

  final Session session;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  _Tab _tab = _Tab.payments;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pays = const [];
  num _sum = 0;
  List<Map<String, dynamic>> _debtors = const [];
  num? _debtTotal; // server jami (sayt bilan bir xil)
  num _debtOverdue = 0;
  Map<String, String> _objectNames = {};
  bool _debtorsLoaded = false;

  Session get s => widget.session;
  bool get _isCurrent => _month.year == DateTime.now().year && _month.month == DateTime.now().month;
  String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
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
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<_Tab>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: _Tab.payments, label: Text('To\'lovlar')), ButtonSegment(value: _Tab.debtors, label: Text('Qarzdorlar'))],
            selected: {_tab},
            onSelectionChanged: (v) {
              setState(() => _tab = v.first);
              if (_tab == _Tab.payments || !_debtorsLoaded) _load();
            },
          ),
        ),
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
      Expanded(child: _body(cs)),
    ]);
  }

  Widget _body(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    return _tab == _Tab.payments ? _paymentsView(cs) : _debtorsView(cs);
  }

  Widget _paymentsView(ColorScheme cs) {
    final rows = <Widget>[];
    String? last;
    for (final p in _pays) {
      final date = '${p['date']}';
      if (date != last) {
        last = date;
        rows.add(Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text(formatDate(date), style: TextStyle(color: cs.outline, fontWeight: FontWeight.w700, fontSize: 13))));
      }
      final buyer = Map<String, dynamic>.from((p['buyer'] as Map?) ?? const {});
      rows.add(GlassRow(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: CircleAvatar(backgroundColor: Colors.green.withValues(alpha: 0.12), foregroundColor: Colors.green.shade700, child: const Icon(Icons.south_west, size: 18)),
        title: Text('${buyer['name'] ?? ''}'.isEmpty ? 'Xaridor' : '${buyer['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('kv. ${p['apartment_number']} · ${_objectNames['${p['object_id']}'] ?? ''}${p['method'] != null && '${p['method']}'.isNotEmpty ? ' · ${p['method']}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text('+${money(p['amount'] as num?)}', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade700)),
      )));
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
          for (final a in _debtors)
            GlassRow(onTap: () => _openDebtor(a), child: Row(children: [
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
        ],
      ),
    );
  }
}
