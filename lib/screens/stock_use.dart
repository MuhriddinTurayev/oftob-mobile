import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as w show Text;

import '../api.dart';
import '../format.dart';
import '../keyboard.dart';
import '../l10n.dart';
import '../session.dart';
import '../theme.dart';

String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Ombordan sarflash oynasini ochadi.
/// Saytdagi «Ombordan sarfladim» bilan bir xil: prorab faqat o'z obyekti omboridagi materialni o'z obyektiga sarflaydi;
/// boshqa rollar — ruxsat etilgan istalgan ombordan, obyekt tanlanadi (ixtiyoriy).
/// Natija: null — bekor qilindi, 'sent' — yuborildi, 'queued' — internet yo'q, navbatga qo'yildi.
Future<String?> showStockUse(BuildContext context, Session session, {Map<String, dynamic>? item}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _StockUseSheet(session: session, item: item),
  );
}

class _StockUseSheet extends StatefulWidget {
  const _StockUseSheet({required this.session, this.item});

  final Session session;
  final Map<String, dynamic>? item;

  @override
  State<_StockUseSheet> createState() => _StockUseSheetState();
}

class _StockUseSheetState extends State<_StockUseSheet> {
  final _qty = TextEditingController();
  final _note = TextEditingController();
  final _search = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _whs = const []; // sarflash mumkin bo'lgan omborlar
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _objects = const [];
  Map<String, dynamic>? _item;
  int? _wh;
  String? _object;
  DateTime _date = DateTime.now();

  bool get _foreman => widget.session.me?.role == 'foreman';
  ApiClient get _api => widget.session.api!;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _qty.dispose();
    _note.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final whs = await _api.stockWarehouses();
      // prorab — faqat o'z obyektining ombori (markaziy ombordan olish — omborchi orqali)
      _whs = whs.where((x) => x['is_active'] != false && (!_foreman || '${x['object_id'] ?? ''}'.isNotEmpty)).toList();
      if (!_foreman) {
        try {
          _objects = await _api.objects();
        } catch (_) {}
      }
      if (_item == null) {
        await _find('');
      } else {
        _pickDefaultWarehouse();
      }
    } on ApiException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Materialning sarflash mumkin bo'lgan omborlardagi qoldig'i
  List<Map<String, dynamic>> _stockOf(Map<String, dynamic> it) {
    final ids = {for (final x in _whs) x['id']};
    return ((it['warehouses'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).where((x) => ids.contains(x['id']) && ((x['qty'] as num?) ?? 0) > 0).toList();
  }

  Future<void> _find(String q) async {
    try {
      final p = await _api.stockItems(q: q.trim().isEmpty ? null : q.trim());
      final rows = p.items.where((i) => _stockOf(i).isNotEmpty).toList();
      if (mounted) setState(() => _items = rows);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _pickDefaultWarehouse() {
    final st = _item == null ? const <Map<String, dynamic>>[] : _stockOf(_item!);
    _wh = st.length == 1 ? st.first['id'] as int? : (st.any((x) => x['id'] == _wh) ? _wh : null);
    _syncObject();
  }

  void _syncObject() {
    if (_foreman) return;
    final w = _whs.where((x) => x['id'] == _wh).firstOrNull;
    final o = '${w?['object_id'] ?? ''}';
    if (o.isNotEmpty) _object = o;
  }

  num get _left {
    if (_item == null || _wh == null) return 0;
    return (_stockOf(_item!).where((x) => x['id'] == _wh).firstOrNull?['qty'] as num?) ?? 0;
  }

  num? get _qtyVal => num.tryParse(_qty.text.trim().replaceAll(',', '.').replaceAll(' ', ''));

  Future<void> _save() async {
    final q = _qtyVal;
    if (_item == null || _wh == null) {
      setState(() => _error = tr('Material va omborni tanlang'));
      return;
    }
    if (q == null || q <= 0) {
      setState(() => _error = tr('Miqdorni kiriting'));
      return;
    }
    if (q > _left + 0.0005) {
      setState(() => _error = '${tr('Omborda faqat')} ${area(_left)} ${_item!['unit'] ?? ''}');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final queued = await _api.stockUse(
        item: _item!['id'] as int,
        warehouse: _wh!,
        qty: q,
        object: _foreman ? null : _object,
        note: _note.text.trim(),
        date: ymd(_date),
        label: '${tr('Ombordan sarflash')}: ${_item!['name']} −${area(q)} ${_item!['unit'] ?? ''}',
      );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(queued ? 'queued' : 'sent');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.isNetwork ? tr("Internet yo'q") : e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
        child: _loading
            ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Row(children: [
                    const IconTile(icon: Icons.outbox_rounded, color: Colors.deepOrange, size: 40),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Ombordan sarflash', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    _foreman ? "Material o'z obyektingizga sarflanadi, ombordagi qoldiq kamayadi. Rahbar va buxgalter ko'radi." : 'Material ombordan chiqadi va tanlangan obyektga yoziladi.',
                    style: TextStyle(color: cs.outline, fontSize: 13),
                  ),
                ),
                Flexible(
                  child: _item == null ? _itemPicker(cs) : _form(cs),
                ),
              ]),
      ),
    );
  }

  /* -------- 1-qadam: material tanlash -------- */

  Widget _itemPicker(ColorScheme cs) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () => _find(v));
          },
          onSubmitted: _find,
          decoration: InputDecoration(
            hintText: tr('Material qidirish'),
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: w.Text(_error!, style: TextStyle(color: cs.error))),
      Flexible(
        child: _items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(28),
                child: Text(_foreman ? "Obyektingiz omborida material yo'q. Material olib kelsangiz — «Pul» bo'limida xarid hisobotini topshiring." : "Omborlarda material yo'q", textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
              )
            : ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final it = _items[i];
                  final st = _stockOf(it);
                  final sum = st.fold<num>(0, (a, x) => a + ((x['qty'] as num?) ?? 0));
                  return GlassRow(
                    margin: const EdgeInsets.only(bottom: 8),
                    onTap: () => setState(() {
                      _item = it;
                      _error = null;
                      _pickDefaultWarehouse();
                    }),
                    child: Row(children: [
                      CircleAvatar(backgroundColor: cs.primary.withValues(alpha: 0.12), foregroundColor: cs.primary, child: const Icon(Icons.inventory_2_outlined, size: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          w.Text('${it['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          w.Text(st.map((x) => '${x['name'] ?? ''}').join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      w.Text('${area(sum)} ${it['unit'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  /* -------- 2-qadam: qancha, qayerdan, nimaga -------- */

  Widget _form(ColorScheme cs) {
    final it = _item!;
    final st = _stockOf(it);
    final unit = '${it['unit'] ?? ''}';
    final q = _qtyVal;
    final over = q != null && _wh != null && q > _left + 0.0005;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.paddingOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // tanlangan material
        Glass(
          radius: 16,
          shadow: false,
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(children: [
            Icon(Icons.inventory_2_outlined, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(child: w.Text('${it['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            if (widget.item == null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _item = null;
                          _wh = null;
                          _error = null;
                        }),
                child: const Text("O'zgartirish"),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        Text('Qaysi ombordan', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (st.isEmpty)
          Text(_foreman ? "Obyektingiz omborida bu material yo'q" : "Bu material omborlarda yo'q", style: TextStyle(color: cs.error))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in st)
              ChoiceChip(
                showCheckmark: false,
                selected: _wh == x['id'],
                label: w.Text('${x['name'] ?? ''} · ${area(x['qty'] as num?)} $unit'),
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                          _wh = x['id'] as int?;
                          _syncObject();
                        }),
              ),
          ]),
        const SizedBox(height: 14),
        TextField(
          controller: _qty,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
            labelText: tr('Qancha sarflandi'),
            suffixText: unit,
            helperText: _wh == null ? null : '${tr('Omborda')}: ${area(_left)} $unit',
            errorText: over ? '${tr('Omborda faqat')} ${area(_left)} $unit' : null,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          enabled: !_busy,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Nimaga ishlatildi'), hintText: tr('Masalan: poydevor quyish, 2-seksiya'), counterText: ''),
        ),
        if (!_foreman && _objects.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _objects.any((o) => '${o['id']}' == _object) ? _object : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Obyekt')),
            items: [for (final o in _objects) DropdownMenuItem(value: '${o['id']}', child: w.Text('${o['name']}', overflow: TextOverflow.ellipsis))],
            onChanged: _busy ? null : (v) => setState(() => _object = v),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            avatar: const Icon(Icons.event_outlined, size: 18),
            label: w.Text(_isToday ? tr('Bugun') : formatDate(ymd(_date))),
            onPressed: _busy
                ? null
                : () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 60)), lastDate: now, initialDate: _date);
                    if (d != null) setState(() => _date = d);
                  },
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: w.Text(_error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        KeyboardLift(
          child: FilledButton.icon(
            onPressed: _busy || st.isEmpty || over ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Icon(Icons.check_rounded),
            label: const Text('Sarflash'),
          ),
        ),
      ]),
    );
  }

  bool get _isToday {
    final n = DateTime.now();
    return _date.year == n.year && _date.month == n.month && _date.day == n.day;
  }
}
