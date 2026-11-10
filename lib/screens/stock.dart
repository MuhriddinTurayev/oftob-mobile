import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import '../l10n.dart';
import 'stock_use.dart';

enum _Tab { balance, moves }

/// Ombor: materiallar qoldig'i (qidiruv, minimumdan past) va harakatlar (kirim, chiqim, ko'chirish, tuzatish).
/// «Ombordan sarflash» — ilovada ham (prorab: o'z obyekti omboridan); kirim — xarid hisoboti orqali, ko'chirish/tuzatish — saytda.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key, required this.session});

  final Session session;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  _Tab _tab = _Tab.balance;
  final _search = TextEditingController();
  Key _key = UniqueKey();
  String _q = '';
  bool _low = false;
  String? _type;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _canUse => widget.session.me?.can('stock:write') == true;

  Future<void> _use([Map<String, dynamic>? item]) async {
    final r = await showStockUse(context, widget.session, item: item);
    if (r == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r == 'queued' ? tr("Offline saqlandi — internet paydo bo'lganda yuboriladi") : tr('Ombordan sarflandi — qoldiq kamaydi'))));
    setState(() => _key = UniqueKey());
  }

  void _apply() => setState(() {
        _q = _search.text.trim();
        _key = UniqueKey();
      });

  static String _moveName(String t) => switch (t) {
        'in' => 'Kirim',
        'out' => 'Chiqim',
        'transfer' => 'Ko\'chirish',
        'adjust' => 'Tuzatish',
        _ => t,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      if (_canUse)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: FilledButton.icon(
            onPressed: () => _use(),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.outbox_rounded),
            label: const Text('Ombordan sarflash'),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<_Tab>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: _Tab.balance, label: Text('Qoldiq')), ButtonSegment(value: _Tab.moves, label: Text('Harakatlar'))],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() {
              _tab = v.first;
              _key = UniqueKey();
            }),
          ),
        ),
      ),
      if (_tab == _Tab.balance) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _apply(),
            decoration: InputDecoration(
              hintText: tr('Material qidirish'),
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _apply),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: FilterChip(
              avatar: Icon(Icons.warning_amber_rounded, size: 18, color: _low ? null : Colors.red.shade400),
              label: const Text('Minimumdan past'),
              selected: _low,
              showCheckmark: false,
              onSelected: (v) => setState(() {
                _low = v;
                _key = UniqueKey();
              }),
            ),
          ),
        ),
      ] else
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              for (final f in const [(null, 'Hammasi'), ('in', 'Kirim'), ('out', 'Chiqim'), ('transfer', 'Ko\'chirish'), ('adjust', 'Tuzatish')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.$2),
                    selected: _type == f.$1,
                    showCheckmark: false,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _type = f.$1;
                        _key = UniqueKey();
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      Expanded(
        child: _tab == _Tab.balance
            ? PagedList(
                key: _key,
                session: widget.session,
                emptyText: 'Materiallar topilmadi',
                fetch: (p) => widget.session.api!.stockItems(page: p, q: _q, low: _low),
                itemBuilder: (context, i) {
                  final low = i['low'] == true;
                  final whs = ((i['warehouses'] as List?) ?? const []).whereType<Map>().toList();
                  return GlassRow(onTap: () => _itemSheet(i), child: Row(children: [
                        CircleAvatar(backgroundColor: (low ? Colors.red : cs.primary).withValues(alpha: 0.12), foregroundColor: low ? Colors.red : cs.primary, child: Icon(low ? Icons.warning_amber_rounded : Icons.inventory_2_outlined, size: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${i['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text([if ('${i['group'] ?? ''}'.isNotEmpty) '${i['group']}', if (whs.isNotEmpty) '${whs.length} ta omborda'].join(' · '), style: TextStyle(color: cs.outline, fontSize: 12.5)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${area(i['balance'] as num?)} ${i['unit'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w800, color: low ? Colors.red : null)),
                          if (low) const StatusChip('Kam', Colors.red),
                        ]),
                      ]));
                },
              )
            : PagedList(
                key: _key,
                session: widget.session,
                emptyText: 'Harakat yo\'q',
                fetch: (p) => widget.session.api!.stockMoves(page: p, type: _type),
                itemBuilder: (context, m) {
                  final qty = (m['qty'] as num?) ?? 0;
                  final inc = qty >= 0;
                  final item = Map<String, dynamic>.from((m['item'] as Map?) ?? const {});
                  final wh = Map<String, dynamic>.from((m['warehouse'] as Map?) ?? const {});
                  return GlassRow(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: CircleAvatar(
                      backgroundColor: (inc ? Brand.green : cs.error).withValues(alpha: 0.12),
                      foregroundColor: inc ? Brand.green : cs.error,
                      child: Icon(inc ? Icons.south_west : Icons.north_east, size: 20),
                    ),
                    title: Text('${item['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${_moveName('${m['type']}')} · ${formatDate('${m['date']}')} · ${wh['name'] ?? ''}${'${m['note'] ?? ''}'.isEmpty ? '' : '\n${m['note']}'}', maxLines: 3, overflow: TextOverflow.ellipsis),
                    isThreeLine: '${m['note'] ?? ''}'.isNotEmpty,
                    trailing: Text('${inc ? '+' : ''}${area(qty)} ${item['unit'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w800, color: inc ? Brand.green : cs.error)),
                  ));
                },
              ),
      ),
    ]);
  }

  void _itemSheet(Map<String, dynamic> i) {
    final cs = Theme.of(context).colorScheme;
    final whs = ((i['warehouses'] as List?) ?? const []).whereType<Map>().toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${i['name']}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          if ('${i['group'] ?? ''}'.isNotEmpty) Text('${i['group']}', style: TextStyle(color: cs.outline)),
          const SizedBox(height: 14),
          _row('Jami qoldiq', '${area(i['balance'] as num?)} ${i['unit'] ?? ''}', color: i['low'] == true ? Colors.red : null),
          if ((i['min_qty'] as num?) != null && (i['min_qty'] as num) > 0) _row('Minimum', '${area(i['min_qty'] as num?)} ${i['unit'] ?? ''}'),
          if ((i['price'] as num?) != null && (i['price'] as num) > 0) _row('Narxi', '${money(i['price'] as num?)} so\'m'),
          if ('${i['sku'] ?? ''}'.isNotEmpty) _row('Artikul', '${i['sku']}'),
          if (whs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Omborlar bo\'yicha', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            for (final w in whs) _row('${w['name'] ?? ''}', '${area(w['qty'] as num?)} ${i['unit'] ?? ''}'),
          ],
          if (_canUse && ((i['balance'] as num?) ?? 0) > 0) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _use(i);
                },
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: const Icon(Icons.outbox_rounded),
                label: const Text('Sarflash'),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
          Text(v, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}
