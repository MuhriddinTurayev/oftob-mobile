import 'package:flutter/material.dart';

import '../format.dart';
import '../session.dart';
import '../widgets.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key, required this.session});

  final Session session;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final _search = TextEditingController();
  Key _key = UniqueKey();
  String _q = '';
  bool _low = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _apply() => setState(() {
        _q = _search.text.trim();
        _key = UniqueKey();
      });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _apply(),
            decoration: InputDecoration(
              hintText: 'Material qidirish',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _apply),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('Minimumdan past'),
              selected: _low,
              onSelected: (v) => setState(() {
                _low = v;
                _key = UniqueKey();
              }),
            ),
          ),
        ),
        Expanded(
          child: PagedList(
            key: _key,
            session: widget.session,
            emptyText: 'Materiallar topilmadi',
            fetch: (p) => widget.session.api!.stockItems(page: p, q: _q, low: _low),
            itemBuilder: (context, i) {
              final low = i['low'] == true;
              final wh = ((i['warehouses'] as List?) ?? const []).whereType<Map>().map((w) => '${w['name'] ?? ''}: ${money(w['qty'] as num?)}').join(' · ');
              return ListTile(
                title: Text('${i['name']}'),
                subtitle: Text([if ('${i['group'] ?? ''}'.isNotEmpty) '${i['group']}', if (wh.isNotEmpty) wh].join('\n')),
                isThreeLine: wh.isNotEmpty && '${i['group'] ?? ''}'.isNotEmpty,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${money(i['balance'] as num?)} ${i['unit'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w600, color: low ? Colors.red : null)),
                    if (low) const StatusChip('Kam', Colors.red),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
