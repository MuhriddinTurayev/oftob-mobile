import 'rates.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import '../format.dart';
import '../session.dart';
import '../widgets.dart';
import '../l10n.dart';

num _n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);
num? _parse(String s) => num.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));

/// Oylik to'lov: foizsiz — qoldiq teng bo'linadi; foizli — annuitet (saytdagi bilan bir xil formula).
num monthlyPayment(num rest, int months, num ratePercent) {
  if (months <= 0) return rest;
  if (ratePercent <= 0) return rest / months;
  final r = ratePercent / 1200;
  return rest * r / (1 - math.pow(1 + r, -months));
}

/// Sotish / bron: xaridor, narx, boshlang'ich to'lov, muddat, foiz — saytdagi shakl bilan bir xil. Shartnoma serverning o'zida tuziladi.
class DealScreen extends StatefulWidget {
  const DealScreen({super.key, required this.session, required this.objectId, required this.apt, required this.onDone});

  final Session session;
  final String objectId;
  final Map<String, dynamic> apt;
  final VoidCallback onDone;

  @override
  State<DealScreen> createState() => _DealScreenState();
}

class _DealScreenState extends State<DealScreen> {
  late final bool _wasBooked = '${widget.apt['status']}' == 'booked';
  late final _name = TextEditingController(text: '${(widget.apt['buyer'] as Map?)?['name'] ?? ''}');
  late final _phone = TextEditingController(text: '${(widget.apt['buyer'] as Map?)?['phone'] ?? ''}');
  final _passport = TextEditingController();
  late final _price = TextEditingController(text: fmtInput(_n(widget.apt['price'])));
  final _down = TextEditingController();
  final _rate = TextEditingController();
  final _note = TextEditingController();
  Map<String, dynamic>? _terms;
  List<Map<String, dynamic>> _methods = const [];
  String? _loadError;
  String _mode = 'sold';
  int _months = 0;
  String _method = '';
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = widget.session.api!;
      final t = await api.salesTerms();
      List<Map<String, dynamic>> m = const [];
      try {
        m = await api.payMethods();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _terms = t;
        _methods = m;
        _loadError = null;
      });
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  List<Map<String, dynamic>> get _rates => ((_terms?['rates'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  bool get _canRate => _terms?['can_set_rate'] == true;
  bool get _canPrice => _terms?['can_set_price'] == true;
  num get _priceV => _canPrice ? (_parse(_price.text) ?? _n(widget.apt['price'])) : _n(widget.apt['price']);
  num get _paidBefore => _n(widget.apt['paid']);

  /// Tanlangan muddat uchun jadvaldagi foiz (yaqin kichik muddat) — saytdagi qoida
  num get _tableRate {
    num r = 0;
    for (final x in _rates) {
      if (_n(x['months']) <= _months) r = _n(x['rate']);
    }
    return r;
  }

  num get _rateV => _months == 0 ? 0 : (_canRate ? (_parse(_rate.text) ?? _tableRate) : _tableRate);
  String get _iso => '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  void _pickMonths(int m) {
    setState(() {
      _months = m;
      _rate.text = '$_tableRate';
    });
  }

  Future<void> _submit() async {
    final booking = _mode == 'booked';
    if (_name.text.trim().isEmpty) {
      _snack('Xaridor ismini kiriting');
      return;
    }
    final down = _parse(_down.text) ?? 0;
    if (!booking && down + _paidBefore > _priceV + 0.5) {
      _snack('Boshlang\'ich to\'lov narxdan katta');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await widget.session.api!.apartmentDeal(widget.objectId, '${widget.apt['id']}', {
        'status': _mode,
        'buyer_name': _name.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'buyer_phone': _phone.text.trim(),
        if (_passport.text.trim().isNotEmpty) 'passport': _passport.text.trim(),
        if (_canPrice) 'price': _priceV,
        if (!booking) 'months': _months,
        if (!booking && down > 0) 'down': down,
        if (!booking && _months > 0 && _canRate) 'rate': _rateV,
        'date': _iso,
        if (_method.isNotEmpty) 'method': _method,
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      widget.onDone();
      final queued = res['queued'] == true;
      final contract = res['contract'] == true;
      final warn = res['warning'];
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(queued ? Icons.cloud_off : Icons.check_circle, color: queued ? Colors.orange : Colors.green, size: 48),
          title: Text(queued ? 'Offline saqlandi' : (booking ? 'Bron qilindi' : 'Sotuv rasmiylashtirildi')),
          content: Text(queued ? "Internet yo'q — amal telefonda saqlandi va internet paydo bo'lganda avtomatik yuboriladi. Boshlang'ich to'lov kassaga va shartnoma o'sha payt tuziladi. Kvartira ro'yxatda hozirdan yangi holatda ko'rinadi." : [
            if (!booking && down > 0) 'Boshlang\'ich to\'lov kassaga o\'tkazildi.',
            if (!booking && contract) 'Shartnoma tuzildi — "Hujjatlar" bo\'limidan ochish mumkin.',
            if (booking) 'Bron muddati tugagach, to\'lov bo\'lmasa kvartira o\'zi bo\'shaydi.',
            if (warn != null) '$warn',
          ].join('\n\n')),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Yaxshi'))],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) {
        setState(() => _busy = false);
        _snack('$e');
      }
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = widget.apt;
    if (_terms == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Kvartira ${a['number']}')),
        body: _loadError != null ? ErrorView(message: _loadError!, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    final booking = _mode == 'booked';
    final bk = Map<String, dynamic>.from((_terms!['booking'] as Map?) ?? const {});
    final price = _priceV;
    final down = _parse(_down.text) ?? 0;
    final rest = math.max<num>(0, price - down - _paidBefore);
    final monthly = monthlyPayment(rest, _months, _rateV);
    final total = monthly * _months;
    final last = _date.add(Duration(days: (_months * 30.4).round()));
    return Scaffold(
      appBar: AppBar(title: Text(_wasBooked ? 'Kvartira ${a['number']} — sotishga o\'tkazish' : 'Kvartira ${a['number']}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Text('${roomsLabel(a['rooms'])} · ${area(a['area'] as num?)} m² · ${a['floor']}-qavat', style: TextStyle(color: cs.outline)),
          const SizedBox(height: 12),
          if (!_wasBooked)
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'sold', label: Text('Sotish'), icon: Icon(Icons.key)), ButtonSegment(value: 'booked', label: Text('Bron'), icon: Icon(Icons.bookmark_border))],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
          const SizedBox(height: 14),
          if (_canPrice)
            TextField(controller: _price, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Narx (so\'m)')), onChanged: (_) => setState(() {}))
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [const Expanded(child: Text('Narxi')), Text('${money(price)} so\'m', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))]),
            ),
          const SizedBox(height: 12),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Xaridor (F.I.Sh.)'))),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Telefon'))),
          if (!booking) ...[
            const SizedBox(height: 12),
            TextField(controller: _passport, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('Pasport (shartnoma uchun)'))),
            const SizedBox(height: 18),
            Text('To\'lov muddati', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              ChoiceChip(label: const Text('To\'liq to\'lov'), selected: _months == 0, onSelected: (_) => _pickMonths(0)),
              for (final r in _rates) ChoiceChip(label: Text('${r['months']} ${tr('oy')} · ${_n(r['rate'])}%'), selected: _months == _n(r['months']).toInt(), onSelected: (_) => _pickMonths(_n(r['months']).toInt())),
            ]),
            // foizlar jadvali: rahbar va buxgalter shu yerdan o'zgartiradi
            if (_canRate)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    await openRates(context, widget.session);
                    if (mounted) _load();
                  },
                  icon: const Icon(Icons.percent_rounded, size: 18),
                  label: const Text("Foizlarni o'zgartirish"),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _down,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsFormatter()],
              decoration: InputDecoration(labelText: tr('Boshlang\'ich to\'lov (so\'m)'), helperText: _wasBooked && _paidBefore > 0 ? 'Bron zadatogi ${money(_paidBefore)} so\'m allaqachon kiritilgan — u hisobga olinadi' : null),
              onChanged: (_) => setState(() {}),
            ),
            if (_months > 0) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _rate,
                enabled: _canRate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Yillik foiz (%)'), helperText: _canRate ? null : 'Foiz muddatga qarab jadvaldan olinadi'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ] else
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: cs.tertiaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
              child: Text(
                'Zadatok: ${_n(bk['amount']) > 0 ? '${money(_n(bk['amount']))} so\'m' : 'yo\'q'} · bron ${bk['days'] ?? 3} kun saqlanadi. Muddat ichida to\'lanmasa, kvartira o\'zi bo\'shaydi.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: cs.outlineVariant)),
            leading: const Icon(Icons.event),
            title: Text('Sana: ${formatDate(_iso)}'),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 60)), lastDate: DateTime.now().add(const Duration(days: 30)));
              if (d != null) setState(() => _date = d);
            },
          ),
          if (_methods.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final m in _methods) ChoiceChip(label: Text('${m['label']}'), selected: _method == '${m['value']}', onSelected: (v) => setState(() => _method = v ? '${m['value']}' : '')),
            ]),
          ],
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: InputDecoration(labelText: tr('Izoh (ixtiyoriy)'))),
          if (!booking && price > 0) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(18)),
              child: _months == 0
                  ? Text('To\'liq to\'lov: ${money(price)} so\'m${down > 0 ? '\nHozir: ${money(down)} · qoladi: ${money(rest)}' : ''}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onPrimaryContainer))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Oyiga ${money(monthly)} × $_months oy', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: cs.onPrimaryContainer)),
                      const SizedBox(height: 6),
                      Text('Boshlang\'ich: ${money(down + _paidBefore)} · qoldiq: ${money(rest)}', style: TextStyle(color: cs.onPrimaryContainer)),
                      Text('Oxirgi to\'lov: ${formatDate(_dateIso(last))}${_rateV > 0 ? ' · jami: ${money(down + _paidBefore + total)}' : ''}', style: TextStyle(color: cs.onPrimaryContainer)),
                    ]),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(booking ? 'Bron qilish' : 'Sotuvni rasmiylashtirish'),
          ),
        ),
      ),
    );
  }

  String _dateIso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
