import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import '../l10n.dart';

enum _Kind { foreman, sales }

enum _Period { today, week, month, custom }

/// Hisobotlar: prorab hisoboti (pul, xaridlar, yoqilg'i, ish haqi, ish hajmi, ombordan sarf) va sotuvchi hisoboti
/// (sotuv, bron, to'lovlar, muddati o'tgan qarzlar, smena). Hisob veb-dasturdagi hisobotlar bilan bir xil — server hisoblaydi.
/// Kim nimani ko'ra olishi serverda rol bo'yicha hal qilinadi (prorab — faqat o'ziniki, rahbar/buxgalter — hammasini).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.session});

  final Session session;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<Map<String, dynamic>> _foremen = const [];
  List<Map<String, dynamic>> _sellers = const [];
  _Kind? _kind;
  int? _foremanId;
  int? _sellerId;
  _Period _period = _Period.today;
  DateTimeRange? _range;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _peopleLoaded = false;

  Session get s => widget.session;

  String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  (String, String) get _dates {
    final now = DateTime.now();
    switch (_period) {
      case _Period.today:
        return (_d(now), _d(now));
      case _Period.week:
        return (_d(now.subtract(const Duration(days: 6))), _d(now));
      case _Period.month:
        return (_d(DateTime(now.year, now.month, 1)), _d(now));
      case _Period.custom:
        final r = _range ?? DateTimeRange(start: now, end: now);
        return (_d(r.start), _d(r.end));
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  List<Map<String, dynamic>> _list(dynamic v) => ((v as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<void> _init() async {
    try {
      final p = await s.api!.reportPeople();
      _foremen = _list(p['foremen']);
      _sellers = _list(p['sellers']);
      _peopleLoaded = true;
      if (_foremen.isNotEmpty) {
        _kind = _Kind.foreman;
        _foremanId = (_foremen.first['id'] as num).toInt();
      } else if (_sellers.isNotEmpty) {
        _kind = _Kind.sales;
      }
      if (_sellers.isNotEmpty) _sellerId = (_sellers.first['id'] as num).toInt();
      if (_kind == null) {
        setState(() => _loading = false);
        return;
      }
      await _load();
    } catch (e) {
      await s.handleError(e);
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final (from, to) = _dates;
    try {
      final d = _kind == _Kind.foreman ? await s.api!.reportForeman(user: _foremanId, from: from, to: to) : await s.api!.reportSales(user: _sellerId, from: from, to: to);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
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

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now(), initialDateRange: _range);
    if (r == null) return;
    setState(() {
      _range = r;
      _period = _Period.custom;
    });
    _load();
  }

  bool _busy = false;

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 5)));
  }

  String _periodText() {
    final (from, to) = _dates;
    return from == to ? formatDate(from) : '${formatDate(from)} – ${formatDate(to)}';
  }

  Future<bool> _confirm(String title, String body, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok))],
      ),
    );
    return r == true;
  }

  /// Prorab: hisobotni direktor va buxgalterga topshirish
  Future<void> _submitForeman() async {
    if (_busy) return;
    final ok = await _confirm(tr('Hisobotni topshirish'), '${_periodText()} — ${tr('hisobot direktor va buxgalterga yuboriladi.')}', tr('Topshirish'));
    if (!ok) return;
    setState(() => _busy = true);
    final (from, to) = _dates;
    try {
      final r = await s.api!.reportForemanSend(from: from, to: to, idemKey: 'rep-${DateTime.now().microsecondsSinceEpoch}');
      HapticFeedback.mediumImpact();
      _snack('${r['message'] ?? tr('Hisobot topshirildi')}');
      await _load();
    } catch (e) {
      await s.handleError(e);
      _snack(e is ApiException && e.isNetwork ? tr("Internet yo'q — hisobot topshirish uchun internet kerak") : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Buxgalter: tanlangan prorab hisobotini direktorga yuborish
  Future<void> _forwardToBoss(String name) async {
    if (_busy) return;
    final ok = await _confirm(tr('Direktorga yuborish'), '$name · ${_periodText()}', tr('Yuborish'));
    if (!ok) return;
    setState(() => _busy = true);
    final (from, to) = _dates;
    try {
      final r = await s.api!.reportForemanSend(user: _foremanId, from: from, to: to, idemKey: 'fwd-${DateTime.now().microsecondsSinceEpoch}');
      HapticFeedback.mediumImpact();
      _snack('${r['message'] ?? tr('Yuborildi')}');
    } catch (e) {
      await s.handleError(e);
      _snack(e is ApiException && e.isNetwork ? tr("Internet yo'q — hisobot topshirish uchun internet kerak") : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sotuvchi: kunlik hisobotni izoh bilan topshirish (davrning oxirgi kuni uchun)
  Future<void> _submitSales() async {
    if (_busy) return;
    final date = _dates.$2;
    final note = TextEditingController(text: '${_data?['note'] ?? ''}');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Kunlik hisobotni topshirish', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('${formatDate(date)} · ${tr('direktor va buxgalter ko\'radi')}', style: TextStyle(color: Theme.of(c).colorScheme.outline)),
          const SizedBox(height: 14),
          TextField(controller: note, minLines: 3, maxLines: 6, maxLength: 2000, decoration: InputDecoration(labelText: tr('Izoh (ixtiyoriy)'), hintText: tr('Bugun nima qildingiz, mijozlar, muammolar…'))),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.send_rounded, size: 20), label: const Text('Topshirish'))),
        ]),
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await s.api!.reportSalesSubmit(date: date, note: note.text.trim(), idemKey: 'srep-${DateTime.now().microsecondsSinceEpoch}');
      HapticFeedback.mediumImpact();
      _snack('${r['message'] ?? tr('Hisobot topshirildi')}');
      await _load();
    } catch (e) {
      await s.handleError(e);
      _snack(e is ApiException && e.isNetwork ? tr("Internet yo'q — hisobot topshirish uchun internet kerak") : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Rahbar so'ragan kunni ochish
  void _openDay(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return;
    setState(() {
      _range = DateTimeRange(start: d, end: d);
      _period = _Period.custom;
    });
    _load();
  }

  /// Hisobot ustidagi «topshirish» kartasi: kim nima qila oladi — aniq yozilgan
  List<Widget> _actionCard(Map<String, dynamic> d, ColorScheme cs, {required bool sales}) {
    final asks = _list(d['asks']);
    final canSubmit = d['can_submit'] == true;
    final canForward = d['can_forward'] == true;
    final sentAt = '${(sales ? d['submitted'] : d['sent_at']) ?? ''}';
    final sent = sentAt.isNotEmpty;
    final who = '${((sales ? d['seller'] : d['foreman']) as Map?)?['name'] ?? ''}';
    final out = <Widget>[];
    for (final a in asks) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassRow(
          tint: Colors.orange.withValues(alpha: 0.16),
          onTap: () => _openDay('${a['date']}'),
          child: Row(children: [
            const IconTile(icon: Icons.campaign_rounded, color: Colors.orange, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tr('Rahbar hisobot so\'radi')}: ${formatDate('${a['date']}')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${'${a['by']}'.isEmpty ? '' : '${a['by']} · '}${tr('ochish uchun bosing')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.outline),
          ]),
        ),
      ));
    }
    // holat qatori: topshirilgan / hali topshirilmagan
    final status = Row(children: [
      Icon(sent ? Icons.check_circle_rounded : Icons.schedule_rounded, size: 18, color: sent ? Colors.green.shade600 : Colors.orange.shade700),
      const SizedBox(width: 6),
      Expanded(
        child: Text(sent ? '${tr('Topshirilgan')}: $sentAt' : tr('Hali topshirilmagan'),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: sent ? Colors.green.shade600 : Colors.orange.shade700)),
      ),
    ]);
    if (canSubmit) {
      out.add(HeroGlass(
        tint: sent ? Colors.green : Brand.blue,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconTile(icon: Icons.outgoing_mail, color: sent ? Colors.green : Brand.blue, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sales ? tr('Kunlik hisobot') : tr('Hisobotni topshirish'), style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900)),
                Text(sales ? '${formatDate(_dates.$2)} · ${tr('direktor va buxgalterga')}' : '${_periodText()} · ${tr('direktor va buxgalterga')}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          status,
          const SizedBox(height: 6),
          Text(sales ? tr("Topshirgach: direktor va buxgalter ilovada xabar oladi, Telegram'da esa PDF hisobot.") : tr("Topshirgach: direktor va buxgalter ilovada xabar oladi, Telegram'da esa PDF hisobot. Rahbar so'ragan kunlar yopiladi."),
              style: TextStyle(color: cs.outline, fontSize: 12.5)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : (sales ? _submitSales : _submitForeman),
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(sent ? Icons.refresh_rounded : Icons.send_rounded, size: 20),
              label: Text(_busy ? tr('Yuborilmoqda…') : (sent ? tr('Qayta topshirish') : (sales ? tr('Hisobotni topshirish') : tr('Direktor va buxgalterga topshirish')))),
            ),
          ),
        ]),
      ));
    } else {
      // rahbar / buxgalter / kassir: kim topshirdi — ko'rinib turadi; buxgalter direktorga yubora oladi
      out.add(GlassRow(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          status,
          if (canForward) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _forwardToBoss(who),
                icon: const Icon(Icons.forward_to_inbox_rounded, size: 20),
                label: Text(_busy ? tr('Yuborilmoqda…') : tr('Direktorga yuborish')),
              ),
            ),
          ],
        ]),
      ));
    }
    out.add(const SizedBox(height: 12));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_error != null && !_peopleLoaded) return ErrorView(message: _error!, onRetry: _init);
    if (_peopleLoaded && _kind == null) return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Sizning rolingiz uchun hisobot yo\'q.', textAlign: TextAlign.center)));
    final people = _kind == _Kind.foreman ? _foremen : _sellers;
    final selected = _kind == _Kind.foreman ? _foremanId : _sellerId;
    return Column(children: [
      if (_foremen.isNotEmpty && _sellers.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_Kind>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: _Kind.foreman, label: Text('Prorab')), ButtonSegment(value: _Kind.sales, label: Text('Sotuvchi'))],
              selected: {_kind!},
              onSelectionChanged: (v) {
                setState(() {
                  _kind = v.first;
                  _data = null;
                });
                _load();
              },
            ),
          ),
        ),
      if (people.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: DropdownButtonFormField<int>(
            key: ValueKey(_kind),
            initialValue: selected,
            isDense: true,
            decoration: InputDecoration(filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none), prefixIcon: const Icon(Icons.person_outline)),
            items: [for (final x in people) DropdownMenuItem(value: (x['id'] as num).toInt(), child: Text('${x['name']}'))],
            onChanged: (v) {
              setState(() {
                if (_kind == _Kind.foreman) {
                  _foremanId = v;
                } else {
                  _sellerId = v;
                }
              });
              _load();
            },
          ),
        ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final p in [(_Period.today, 'Bugun'), (_Period.week, '7 kun'), (_Period.month, 'Shu oy')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(p.$2),
                  selected: _period == p.$1,
                  showCheckmark: false,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _period = p.$1);
                    _load();
                  },
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.date_range, size: 18),
              label: Text(_period == _Period.custom ? '${formatDate(_dates.$1)} – ${formatDate(_dates.$2)}' : 'Davr tanlash'),
              backgroundColor: _period == _Period.custom ? cs.secondaryContainer : null,
              onPressed: _pickRange,
            ),
          ],
        ),
      ),
      Expanded(child: _body(cs)),
    ]);
  }

  Widget _body(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 40 + NavInset.of(context)),
        children: _kind == _Kind.foreman ? _foremanView(d, cs) : _salesView(d, cs),
      ),
    );
  }

  /* ---------------- prorab hisoboti ---------------- */

  List<Widget> _foremanView(Map<String, dynamic> d, ColorScheme cs) {
    final m = _map(d['money']);
    final purchases = _list(d['purchases']);
    final fuel = _list(d['fuel']);
    final salaries = _list(d['salaries']);
    final workers = _list(d['workers']);
    final work = _list(d['work']);
    final used = _list(d['used']);
    final noReceipt = (d['no_receipt'] as num?)?.toInt() ?? 0;
    return [
      ..._actionCard(d, cs, sales: false),
      _Hero(title: '${(d['foreman'] as Map?)?['name'] ?? ''}', sub: '${formatDate('${d['from']}')} – ${formatDate('${d['to']}')}', rows: [
        _Pair('Boshida', m['opening']),
        _Pair('Berilgan', m['received'], color: Colors.green.shade700),
        _Pair('Qaytarilgan', m['returned']),
        _Pair('Sarflangan', m['spent'], color: cs.error),
        _Pair('Oxirida (qoldiq)', m['closing'], bold: true),
      ]),
      if (noReceipt > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GlassRow(
            margin: EdgeInsets.zero,
            tint: Colors.orange.withValues(alpha: 0.16),
            child: Row(children: [Icon(Icons.receipt_long_outlined, color: Colors.orange.shade700), const SizedBox(width: 10), Expanded(child: Text('${tr('Cheksiz xaridlar')}: $noReceipt', style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w700)))]),
          ),
        ),
      _Block('Xaridlar', purchases.isEmpty ? null : money(d['purchases_sum'] as num?), [
        for (final p in purchases)
          _Line('${p['vendor']}'.isEmpty ? (('${p['what']}').isEmpty ? 'Xarid' : '${p['what']}') : '${p['vendor']}', '${formatDate('${p['date']}')}${p['receipt'] == true ? '' : ' · chek yo\'q'}${p['checked'] == true ? ' · tekshirilgan' : ''}', money(p['amount'] as num?), warn: p['receipt'] != true),
      ]),
      _Block('Yoqilg\'i', fuel.isEmpty ? null : '${area(d['fuel_liters'] as num?)} l · ${money(d['fuel_sum'] as num?)}', [
        for (final f in fuel) _Line('${f['vehicle']}', formatDate('${f['date']}'), '${area(f['liters'] as num?)} l'),
      ]),
      _Block('Ish haqi (to\'langan)', salaries.isEmpty ? null : money(d['salaries_sum'] as num?), [
        for (final x in salaries) _Line('${x['worker']}', formatDate('${x['date']}'), money(x['amount'] as num?)),
      ]),
      _Block('Xodimlar holati (${d['month']})', null, [
        for (final w in workers)
          _Line('${w['name']}', '${w['role']} · ${area(w['qty'] as num?)} ${w['unit']}', 'qoldi ${money(w['due'] as num?)}', warn: ((w['due'] as num?) ?? 0) > 0, sub2: 'hisoblangan ${money(w['accrued'] as num?)} · to\'langan ${money(w['paid'] as num?)}'),
      ]),
      _Block('Bajarilgan ish hajmi', null, [
        for (final w in work) _Line('${w['worker']}', '${formatDate('${w['date']}')}${'${w['note']}'.isEmpty ? '' : ' · ${w['note']}'}', '${area(w['qty'] as num?)} ${w['unit']}'),
      ]),
      _Block('Ombordan sarflangan', used.isEmpty ? null : money(d['used_sum'] as num?), [
        for (final u in used) _Line('${u['item']}', '${formatDate('${u['date']}')}${'${u['note']}'.isEmpty ? '' : ' · ${u['note']}'}', '${area(u['qty'] as num?)} ${u['unit']}'),
      ]),
    ];
  }

  /* ---------------- sotuvchi hisoboti ---------------- */

  Widget _deal(Map<String, dynamic> x, {bool late = false}) => _Line(
        'kv. ${x['number']} · ${'${x['buyer']}'.isEmpty ? 'Xaridor' : x['buyer']}',
        '${x['object']}${late ? ' · ${x['late_days']} kun kechikkan' : ''}',
        late ? money(x['overdue'] as num?) : money(x['price'] as num?),
        warn: late,
        sub2: late ? null : 'to\'langan ${money(x['paid'] as num?)} · qoldi ${money(x['left'] as num?)}',
      ).build(context);

  List<Widget> _salesView(Map<String, dynamic> d, ColorScheme cs) {
    final k = _map(d['kpi']);
    final ways = _map(d['ways']);
    final sold = _list(d['sold']);
    final booked = _list(d['booked']);
    final late = _list(d['late']);
    final pays = _list(d['payments']);
    final shifts = _list(d['shifts']);
    return [
      ..._actionCard(d, cs, sales: true),
      _Hero(title: '${(d['seller'] as Map?)?['name'] ?? ''}', sub: '${formatDate('${d['from']}')} – ${formatDate('${d['to']}')}', rows: [
        _Pair('Davr ichida tushum', k['collectedPeriod'], color: Colors.green.shade700, bold: true),
        _Pair('Sotilgan (${k['soldN'] ?? 0} ta)', k['soldSum']),
        _Pair('Bron (${k['bookedN'] ?? 0} ta), birinchi to\'lov', k['bookedSum']),
        _Pair('Muddati o\'tgan (${k['overdueN'] ?? 0} ta)', k['overdueSum'], color: ((k['overdueN'] as num?) ?? 0) > 0 ? cs.error : null),
        _Pair('Umumiy qarz (${k['deals'] ?? 0} bitim)', k['debt']),
      ]),
      _Block('To\'lov usullari', null, [for (final e in ways.entries) _Line(e.key, '', money(e.value as num?))]),
      _BlockW('Muddati o\'tgan qarzlar', late.isEmpty ? null : '${late.length} ta', [for (final x in late) _deal(x, late: true)]),
      _BlockW('Sotilgan kvartiralar', sold.isEmpty ? null : '${sold.length} ta', [for (final x in sold) _deal(x)]),
      _BlockW('Bron qilinganlar', booked.isEmpty ? null : '${booked.length} ta', [for (final x in booked) _deal(x)]),
      _Block('To\'lovlar', pays.isEmpty ? null : '${pays.length} ta', [
        for (final p in pays) _Line('${'${p['buyer']}'.isEmpty ? 'Xaridor' : p['buyer']} · kv. ${p['number']}', '${formatDate('${p['date']}')}${'${p['way']}'.isEmpty ? '' : ' · ${p['way']}'}', '+${money(p['amount'] as num?)}'),
      ]),
      _Block('Ish vaqti (smena)', null, [for (final x in shifts) _Line(formatDate('${x['date']}'), '', '${x['in'] ?? '—'} – ${x['out'] ?? '—'}')]),
      if ('${d['note'] ?? ''}'.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: GlassRow(margin: EdgeInsets.zero, padding: const EdgeInsets.all(14), child: Row(children: [Icon(Icons.notes_rounded, color: cs.outline), const SizedBox(width: 10), Expanded(child: Text('${d['note']}'))])),
        ),
    ];
  }
}

class _Pair {
  const _Pair(this.label, this.value, {this.color, this.bold = false});
  final String label;
  final dynamic value;
  final Color? color;
  final bool bold;
}

class _Hero extends StatelessWidget {
  const _Hero({required this.title, required this.sub, required this.rows});

  final String title;
  final String sub;
  final List<_Pair> rows;

  @override
  Widget build(BuildContext context) {
    return HeroGlass(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.ink)),
        Text(sub, style: TextStyle(color: context.inkSoft, fontSize: 13)),
        const SizedBox(height: 10),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(r.label, style: TextStyle(color: context.inkSoft, fontWeight: r.bold ? FontWeight.w700 : FontWeight.w500))),
              Text(money(r.value as num?), style: TextStyle(fontWeight: r.bold ? FontWeight.w800 : FontWeight.w700, fontSize: r.bold ? 17 : 15, color: r.color ?? context.ink)),
            ]),
          ),
      ]),
    );
  }
}

/// Bo'lim: sarlavha + (ixtiyoriy) jami + qatorlar. Qator bo'lmasa — ko'rsatilmaydi.
class _Block extends StatelessWidget {
  const _Block(this.title, this.total, this.lines);

  final String title;
  final String? total;
  final List<_Line> lines;

  @override
  Widget build(BuildContext context) {
    // bir bo'limdagi barcha kartalar bir xil balandlikda
    final h = lines.any((l) => l.sub2 != null) ? 84.0 : (lines.any((l) => l.sub.isNotEmpty) ? 66.0 : 54.0);
    return _BlockW(title, total, [for (final l in lines) l.card(context, h)]);
  }
}

class _BlockW extends StatelessWidget {
  const _BlockW(this.title, this.total, this.children);

  final String title;
  final String? total;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            if (total != null) Text(total!, style: TextStyle(color: cs.outline, fontWeight: FontWeight.w700)),
          ]),
        ),
        ...children,
      ]),
    );
  }
}

/// Bitta qator — alohida shaffof karta, oralig'ida bo'sh joy, balandligi bo'lim ichida bir xil.
class _Line {
  const _Line(this.title, this.sub, this.value, {this.warn = false, this.sub2});

  final String title;
  final String sub;
  final String value;
  final bool warn;
  final String? sub2;

  Widget build(BuildContext context) => card(context, sub2 != null ? 84 : 66);

  Widget card(BuildContext context, double height) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: height,
        child: GlassRow(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: warn ? Colors.orange.shade700 : cs.outline, fontSize: 12.5)),
                if (sub2 != null) Text(sub2!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 12),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: warn ? cs.error : null)),
          ]),
        ),
      ),
    );
  }
}
