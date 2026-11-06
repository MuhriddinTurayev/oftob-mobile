import 'package:flutter/material.dart' hide Text;


import '../format.dart';
import '../session.dart';
import '../widgets.dart';
import '../theme.dart';
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
              Expanded(child: const Text('Kassalar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              IconButton(onPressed: _refreshAll, icon: const Icon(Icons.refresh)),
            ]),
          ),
          if (_deskError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_deskError!, style: TextStyle(color: cs.error))),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final d in _desks)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Glass(
                      radius: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${d['name']}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.outline)),
                          const SizedBox(height: 4),
                          Text('${money(d['balance'] as num?)} ${d['currency'] ?? ''}', style: TextStyle(color: cs.primary, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: const Text('So\'nggi operatsiyalar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
        ],
      ),
      itemBuilder: (context, o) {
        final income = o['type'] == 'in';
        final color = income ? Colors.green : Colors.red;
        final title = '${o['category'] ?? (income ? 'Kirim' : 'Chiqim')}';
        final note = '${o['note'] ?? ''}'.trim();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Glass(
            radius: 18,
            blur: false,
            shadow: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              IconTile(icon: income ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text([formatDate('${o['date']}'), if (note.isNotEmpty) note].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12)),
                ]),
              ),
              const SizedBox(width: 8),
              Text('${income ? '+' : '−'}${money(o['amount'] as num?)} ${o['currency'] ?? ''}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13.5)),
            ]),
          ),
        );
      },
    );
  }
}
