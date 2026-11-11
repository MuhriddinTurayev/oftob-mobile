import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import '../l10n.dart';

/// Bo'lib to'lash foizlari (muddat → yillik foiz) va bron sharti (zadatok, kun). Sotishda tanlangan muddat o'z foizini oladi.
/// O'zgartirish — faqat rahbar va buxgalter; boshqalar faqat ko'radi. Saytdagi «Проценты» bilan bir xil.
class RatesScreen extends StatefulWidget {
  const RatesScreen({super.key, required this.session});

  final Session session;

  @override
  State<RatesScreen> createState() => _RatesScreenState();
}

/// Sotish oynasidan ochish uchun (o'z sarlavhasi bilan)
Future<void> openRates(BuildContext context, Session session) => Navigator.of(context).push(DeskRoute<void>(
      builder: (_) => Scaffold(backgroundColor: Colors.transparent, appBar: AppBar(title: const Text("Bo'lib to'lash foizlari")), body: RatesScreen(session: session)),
    ));

class _Row {
  _Row(num months, num rate)
      : m = TextEditingController(text: months > 0 ? '${months.toInt()}' : ''),
        r = TextEditingController(text: rate > 0 ? (rate == rate.roundToDouble() ? '${rate.toInt()}' : '$rate') : (months > 0 ? '0' : ''));
  final TextEditingController m;
  final TextEditingController r;
}

class _RatesScreenState extends State<RatesScreen> {
  final _rows = <_Row>[];
  final _bkAmount = TextEditingController();
  final _bkDays = TextEditingController();
  bool _loading = true, _busy = false, _can = false;
  String? _error;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final x in _rows) {
      x.m.dispose();
      x.r.dispose();
    }
    _bkAmount.dispose();
    _bkDays.dispose();
    super.dispose();
  }

  num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  void _fill(Map<String, dynamic> t) {
    _rows.clear();
    for (final x in ((t['rates'] as List?) ?? const []).whereType<Map>()) {
      _rows.add(_Row(_n(x['months']), _n(x['rate'])));
    }
    if (_rows.isEmpty) _rows.add(_Row(12, 0));
    final bk = (t['booking'] as Map?) ?? const {};
    _bkAmount.text = fmtInput(_n(bk['amount']));
    _bkDays.text = '${_n(bk['days']).toInt()}';
    _can = t['can_set_rate'] == true;
  }

  Future<void> _load() async {
    try {
      final t = await s.api!.salesTerms();
      if (!mounted) return;
      setState(() {
        _fill(t);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      await s.handleError(e);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _save() async {
    final rates = <Map<String, num>>[];
    for (final x in _rows) {
      final m = int.tryParse(x.m.text.trim());
      final r = num.tryParse(x.r.text.trim().replaceAll(',', '.'));
      if (m == null && x.m.text.trim().isEmpty) continue;
      if (m == null || m < 1 || m > 360 || r == null || r < 0 || r > 100) {
        _snack(tr("Muddat 1–360 oy, foiz 0–100 bo'lsin"));
        return;
      }
      rates.add({'months': m, 'rate': r});
    }
    setState(() => _busy = true);
    try {
      final t = await s.api!.salesTermsSave(
        rates: rates,
        bookingAmount: num.tryParse(_bkAmount.text.replaceAll(' ', '')) ?? 0,
        bookingDays: int.tryParse(_bkDays.text.trim()) ?? 3,
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _fill(t));
      _snack(tr('Saqlandi — endi sotishda shu foizlar ishlatiladi'));
    } catch (e) {
      await s.handleError(e);
      _snack(e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = ErrorView(message: _error!, onRetry: _load);
    } else {
      body = ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
        children: [
          GlassRow(
            margin: EdgeInsets.zero,
            tint: cs.primary.withValues(alpha: 0.10),
            child: Text(
              _can
                  ? "Har bir muddat uchun yillik foiz. Sotishda muddat tanlansa, foiz shu jadvaldan olinadi (yaqin kichik muddat). Sotuvchilar foizni o'zgartira olmaydi."
                  : "Foizlarni faqat rahbar va buxgalter o'zgartiradi. Sotishda muddat tanlansa, foiz shu jadvaldan olinadi.",
              style: TextStyle(fontSize: 13, color: context.inkSoft),
            ),
          ),
          const SizedBox(height: 14),
          Text("Bo'lib to'lash foizlari", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (var i = 0; i < _rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassRow(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _rows[i].m,
                      enabled: _can,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: tr('Muddat (oy)'), isDense: true, border: InputBorder.none),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _rows[i].r,
                      enabled: _can,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tr('Yillik foiz (%)'), suffixText: '%', isDense: true, border: InputBorder.none),
                    ),
                  ),
                  if (_can)
                    IconButton(
                      tooltip: tr("O'chirish"),
                      onPressed: () => setState(() => _rows.removeAt(i)),
                      icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                    ),
                ]),
              ),
            ),
          if (_can)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => setState(() => _rows.add(_Row(0, 0))), icon: const Icon(Icons.add_rounded), label: const Text("Muddat qo'shish")),
            ),
          const SizedBox(height: 14),
          Text('Bron sharti', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          GlassRow(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _bkAmount,
                  enabled: _can,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsFormatter()],
                  decoration: InputDecoration(labelText: tr("Zadatok (so'm)"), isDense: true, border: InputBorder.none),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _bkDays,
                  enabled: _can,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: tr('Necha kun'), isDense: true, border: InputBorder.none),
                ),
              ),
            ]),
          ),
          if (_can) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
                label: const Text('Saqlash'),
              ),
            ),
          ],
        ],
      );
    }
    return body;
  }
}
