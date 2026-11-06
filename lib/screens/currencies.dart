import 'package:flutter/material.dart' hide Text;

import '../format.dart';
import '../l10n.dart';
import '../session.dart';
import '../widgets.dart';

/// Valyutalar: prorab xaridni shu valyutalarda kiritadi (summa kurs bo'yicha kompaniya valyutasiga o'tadi).
/// Qo'shimcha valyutalarni faqat rahbar yoqadi/o'chiradi; boshqalar kurslarni ko'radi.
class CurrenciesScreen extends StatefulWidget {
  const CurrenciesScreen({super.key, required this.session});

  final Session session;

  @override
  State<CurrenciesScreen> createState() => _CurrenciesScreenState();
}

class _CurrenciesScreenState extends State<CurrenciesScreen> {
  Key _key = UniqueKey();
  bool _busy = false;

  Future<void> _toggle(List<Map<String, dynamic>> items, String code, bool on) async {
    final extras = <String>[
      for (final i in items)
        if (i['enabled'] == true && i['base'] != true && i['code'] != 'USD' && i['code'] != code) '${i['code']}',
      if (on) code,
    ];
    setState(() => _busy = true);
    try {
      final queued = await widget.session.api!.currenciesSave(extras);
      if (queued && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Offline saqlandi — internet paydo bo'lganda yuboriladi")));
      if (mounted) setState(() => _key = UniqueKey());
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBody<Map<String, dynamic>>(
      key: _key,
      session: widget.session,
      load: () => widget.session.api!.currencies(),
      builder: (context, d, reload) {
        final items = ((d['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        final canManage = d['can_manage'] == true;
        final base = items.firstWhere((e) => e['base'] == true, orElse: () => const {'code': ''});
        final baseCode = '${base['code']}';
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(16)),
              child: Text("Prorab xaridni shu valyutalarda kiritishi mumkin: summa kurs bo'yicha kompaniya valyutasiga o'tadi. Kassa, shartnoma va hisobotlar kompaniya valyutasi va dollarda qoladi.", style: TextStyle(color: cs.onPrimaryContainer)),
            ),
            const SizedBox(height: 12),
            if (!canManage) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text("Valyutalarni faqat rahbar yoqadi.", style: TextStyle(color: cs.outline, fontSize: 13))),
            for (final i in items)
              Card(
                child: ListTile(
                  title: Text('${i['code']}  ·  ${i['sign']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: i['base'] == true
                      ? const Text('Kompaniya valyutasi')
                      : Text('1 ${i['code']} = ${money(i['rate'] as num?)} $baseCode'),
                  trailing: i['base'] == true || i['code'] == 'USD'
                      ? const StatusChip('Doim mavjud', Colors.green)
                      : Switch(value: i['enabled'] == true, onChanged: canManage && !_busy ? (v) => _toggle(items, '${i['code']}', v) : null),
                ),
              ),
          ],
        );
      },
    );
  }
}
