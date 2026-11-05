import 'package:flutter/material.dart' hide Text;


import '../format.dart';
import '../session.dart';
import '../widgets.dart';
import '../l10n.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key, required this.session});

  final Session session;

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  Key _key = UniqueKey();
  List<Map<String, dynamic>> _desks = const [];
  String? _deskError;

  @override
  void initState() {
    super.initState();
    _loadDesks();
  }

  Future<void> _loadDesks() async {
    try {
      final d = await widget.session.api!.cashDesks();
      if (mounted) setState(() => _desks = d);
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _deskError = '$e');
    }
  }

  Future<void> _refreshAll() async {
    setState(() => _key = UniqueKey());
    await _loadDesks();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PagedList(
      key: _key,
      session: widget.session,
      emptyText: 'Operatsiyalar yo\'q',
      fetch: (p) => widget.session.api!.cashOps(page: p),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Expanded(child: Text('Kassalar', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(onPressed: _refreshAll, icon: const Icon(Icons.refresh)),
            ]),
          ),
          if (_deskError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_deskError!, style: TextStyle(color: cs.error))),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final d in _desks)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('${money(d['balance'] as num?)} ${d['currency'] ?? ''}', style: TextStyle(color: cs.primary, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('So\'nggi operatsiyalar', style: Theme.of(context).textTheme.titleMedium)),
        ],
      ),
      itemBuilder: (context, o) {
        final income = o['type'] == 'in';
        final color = income ? Colors.green : Colors.red;
        final title = '${o['category'] ?? (income ? 'Kirim' : 'Chiqim')}';
        final note = '${o['note'] ?? ''}'.trim();
        return ListTile(
          leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(income ? Icons.south_west : Icons.north_east, color: color, size: 20)),
          title: Text(title),
          subtitle: Text([formatDate('${o['date']}'), if (note.isNotEmpty) note].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text('${income ? '+' : '−'}${money(o['amount'] as num?)} ${o['currency'] ?? ''}', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        );
      },
    );
  }
}
