import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../l10n.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import '../screens/company_admin.dart' show InvoiceBar;
import 'platform_home.dart' show curName, openCompany;

/* Platforma administratori: kompaniyalar to'lovlarini tasdiqlash, sun'iy intellekt (kalitlar, real limitlar, arizalar), kirish kodi */

List<Map<String, dynamic>> _maps(Object? v) => ((v as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

String _m(Object? v, Object? c) => '${money(v as num?)} ${curName(c)}';

void _snack(BuildContext context, String t) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(t)));

Future<void> openPlatformPage(BuildContext context, String title, Widget body) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(backgroundColor: Colors.transparent, appBar: AppBar(title: Text(title)), body: body)));

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
      );
}

/* ---------------------------------------- To'lovlarni tasdiqlash ---------------------------------------- */

class ClaimsScreen extends StatefulWidget {
  const ClaimsScreen({super.key, required this.session});
  final Session session;

  @override
  State<ClaimsScreen> createState() => _ClaimsScreenState();
}

class _ClaimsScreenState extends State<ClaimsScreen> {
  String _st = 'pending';
  Key _k = UniqueKey();

  Session get s => widget.session;

  Future<void> _confirm(Map<String, dynamic> c) async {
    final amount = TextEditingController(text: fmtInput(c['amount'] as num?));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("To'lovni tasdiqlash", style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          Text('${c['company']}', style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
          const SizedBox(height: 12),
          TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Haqiqatda tushgan summa'))),
          const SizedBox(height: 8),
          Text("Hisob to'liq yopilsa, tarif avtomatik qo'llanadi (oylar qo'shiladi yoki umrbod bo'ladi).", style: TextStyle(color: Theme.of(ctx).colorScheme.outline, fontSize: 12.5)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), icon: const Icon(Icons.check_rounded), label: const Text('Tasdiqlash'))),
        ]),
      ),
    );
    if (ok != true) return;
    try {
      await s.papi!.pSend('POST', '/billing/claims/${c['id']}/confirm', {'amount': num.tryParse(amount.text.replaceAll(RegExp(r'[^0-9.]'), ''))});
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, tr("To'lov tasdiqlandi"));
      setState(() => _k = UniqueKey());
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    }
  }

  Future<void> _reject(Map<String, dynamic> c) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rad etish'),
        content: TextField(controller: reason, autofocus: true, decoration: InputDecoration(labelText: tr('Sabab'), hintText: tr("masalan: to'lov tushmadi"))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor qilish')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rad etish'))],
      ),
    );
    if (ok != true || reason.text.trim().isEmpty) return;
    try {
      await s.papi!.pSend('POST', '/billing/claims/${c['id']}/reject', {'reason': reason.text.trim()});
      if (mounted) _snack(context, tr('Rad etildi, kompaniyaga sabab yuborildi'));
      setState(() => _k = UniqueKey());
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    }
  }

  void _receipt(Map<String, dynamic> c) {
    final api = s.papi!;
    final url = api.fileUrl('/platform/billing/claims/${c['id']}/receipt');
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(tr('Chek'))),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(url, headers: api.authHeaders, errorBuilder: (_, _, _) => Padding(padding: const EdgeInsets.all(24), child: Text(tr("Chekni ochib bo'lmadi (PDF bo'lishi mumkin — saytda oching)"), style: const TextStyle(color: Colors.white)))),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBody<dynamic>(
      key: ValueKey('$_k|$_st'),
      session: s,
      load: () => s.papi!.pGet('/billing/claims', {'status': _st}),
      builder: (context, raw, reload) {
        final d = Map<String, dynamic>.from(raw as Map);
        final items = _maps(d['items']);
        final counts = d['counts'] is Map ? d['counts'] as Map : const {};
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
          children: [
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final (id, t) in [('pending', 'Kutilmoqda'), ('confirmed', 'Tasdiqlangan'), ('rejected', 'Rad etilgan'), ('all', 'Hammasi')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text('${tr(t)}${id == 'all' ? '' : ' ${counts[id] ?? 0}'}'), selected: _st == id, showCheckmark: false, onSelected: (_) => setState(() => _st = id)),
                  ),
              ]),
            ),
            const SizedBox(height: 6),
            if (items.isEmpty) Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(_st == 'pending' ? tr("Tasdiq kutayotgan to'lov yo'q") : tr("To'lov yo'q")))),
            for (final c in items) _card(context, c, cs),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> c, ColorScheme cs) {
    final inv = c['invoice'] is Map ? Map<String, dynamic>.from(c['invoice'] as Map) : null;
    final st = '${c['status']}';
    final (stText, stColor) = switch (st) {
      'pending' => ('Kutilmoqda', Colors.orange.shade700),
      'confirmed' => ('Tasdiqlangan', Colors.green.shade600),
      _ => ('Rad etilgan', cs.error),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => openCompany(context, s, (c['company_id'] as num).toInt()),
                child: Text('${c['company']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),
            _Pill(tr(stText), stColor),
          ]),
          const SizedBox(height: 4),
          Text(_m(c['amount'], c['currency']), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: context.ink)),
          Text([formatDate('${c['paid_at']}'), c['method_name'], c['by']].where((x) => x != null && '$x'.isNotEmpty).join(' · '), style: TextStyle(color: cs.outline, fontSize: 12.5)),
          if (c['note'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${c['note']}', style: const TextStyle(fontSize: 13))),
          if (c['reject_reason'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${c['reject_reason']}', style: TextStyle(color: cs.error, fontSize: 13))),
          if (inv != null) ...[
            const SizedBox(height: 10),
            Text("${tr('Hisob')}: ${inv['plan']} · ${inv['kind'] == 'once' ? tr('umrbod') : '${inv['months']} ${tr('oy')}'} — ${_m(inv['paid'], inv['currency'])} / ${_m(inv['amount'], inv['currency'])}",
                style: TextStyle(color: context.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            InvoiceBar(amount: (inv['amount'] as num?) ?? 0, paid: (inv['paid'] as num?) ?? 0, pending: st == 'pending' ? ((c['amount'] as num?) ?? 0) : 0),
          ],
          const SizedBox(height: 10),
          Row(children: [
            if (c['receipt'] == true) OutlinedButton.icon(onPressed: () => _receipt(c), icon: const Icon(Icons.receipt_long_rounded, size: 18), label: const Text('Chek')),
            const Spacer(),
            if (st == 'pending') ...[
              IconButton.outlined(onPressed: () => _reject(c), icon: Icon(Icons.close_rounded, color: cs.error), tooltip: tr('Rad etish')),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: () => _confirm(c), icon: const Icon(Icons.check_rounded), label: const Text('Tasdiqlash')),
            ],
          ]),
        ]),
      ),
    );
  }
}

/* ---------------------------------------- Sun'iy intellekt (platforma) ---------------------------------------- */

class PlatformAiScreen extends StatefulWidget {
  const PlatformAiScreen({super.key, required this.session});
  final Session session;

  @override
  State<PlatformAiScreen> createState() => _PlatformAiScreenState();
}

class _PlatformAiScreenState extends State<PlatformAiScreen> {
  Key _k = UniqueKey();
  bool _refresh = false;

  Session get s => widget.session;

  Future<void> _decide(Map<String, dynamic> r, List<Map<String, dynamic>> providers, bool approve) async {
    final limit = TextEditingController(text: '${r['wanted_limit'] ?? 500}');
    final reply = TextEditingController();
    int? provider;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(c).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(approve ? tr("AI'ni ulash") : tr('Arizani rad etish'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            Text('${r['company']}', style: TextStyle(color: Theme.of(c).colorScheme.outline)),
            const SizedBox(height: 12),
            if (approve) ...[
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final v in [100, 300, 500, 1000, 3000, 0])
                  ChoiceChip(label: Text(v == 0 ? tr('Cheklovsiz') : '$v'), selected: limit.text == '$v', showCheckmark: false, onSelected: (_) => set(() => limit.text = '$v')),
              ]),
              const SizedBox(height: 8),
              TextField(controller: limit, keyboardType: TextInputType.number, onChanged: (_) => set(() {}), decoration: InputDecoration(labelText: tr("Oylik limit (so'rov), 0 — cheklovsiz"))),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: provider,
                decoration: InputDecoration(labelText: tr('Ulanish')),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(tr("Platforma bo'yicha standart"))),
                  for (final p in providers.where((p) => p['active'] == true)) DropdownMenuItem<int?>(value: (p['id'] as num).toInt(), child: Text('${p['name']}')),
                ],
                onChanged: (v) => set(() => provider = v),
              ),
              const SizedBox(height: 10),
            ],
            TextField(controller: reply, decoration: InputDecoration(labelText: approve ? tr('Izoh (ixtiyoriy)') : tr('Sabab'))),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: approve ? null : Theme.of(c).colorScheme.error),
                child: Text(approve ? tr('Ulash') : tr('Rad etish')),
              ),
            ),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await s.papi!.pSend('POST', '/ai/requests/${r['id']}', {'approve': approve, 'limit': approve ? int.tryParse(limit.text.trim()) : null, 'provider_id': provider, 'reply': reply.text.trim()});
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, approve ? tr('AI ulandi') : tr('Ariza rad etildi'));
      setState(() => _k = UniqueKey());
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBody<dynamic>(
      key: _k,
      session: s,
      load: () async {
        final r = await s.papi!.pGet('/ai', {'refresh': _refresh ? 1 : null});
        _refresh = false;
        return r;
      },
      builder: (context, raw, reload) {
        final d = Map<String, dynamic>.from(raw as Map);
        final providers = _maps(d['providers']);
        final reqs = _maps(d['requests']);
        final comps = _maps(d['companies']);
        final pending = reqs.where((r) => r['status'] == 'pending').toList();
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
          children: [
            if (pending.isNotEmpty) ...[
              _title(context, "Kompaniyalar arizalari (${pending.length})"),
              for (final r in pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Glass(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r['company']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                      Text(
                        [r['by'], [if (r['chat'] == true) tr('chat'), if (r['voice'] == true) tr('ovoz')].join(', '), if (r['wanted_limit'] != null) "${r['wanted_limit']} ${tr("so'rov/oy")}"]
                            .where((x) => x != null && '$x'.isNotEmpty)
                            .join(' · '),
                        style: TextStyle(color: cs.outline, fontSize: 12.5),
                      ),
                      if (r['note'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['note']}')),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Spacer(),
                        IconButton.outlined(onPressed: () => _decide(r, providers, false), icon: Icon(Icons.close_rounded, color: cs.error)),
                        const SizedBox(width: 8),
                        FilledButton.icon(onPressed: () => _decide(r, providers, true), icon: const Icon(Icons.check_rounded), label: const Text('Ulash')),
                      ]),
                    ]),
                  ),
                ),
            ],
            _title(context, 'Ulanishlar va real limitlar',
                trailing: TextButton.icon(
                  onPressed: () => setState(() {
                    _refresh = true;
                    _k = UniqueKey();
                  }),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Yangilash'),
                )),
            if (providers.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr("Ulanish yo'q. «To'liq panel → AI ulanishlari» dan kalit qo'shing."))),
            for (final p in providers) _provider(context, p, cs),
            if (comps.isNotEmpty) _title(context, 'Kompaniyalar limiti', trailing: Text('${tr('yangilanadi')} ${formatDate('${d['renews_at']}')}', style: TextStyle(color: cs.outline, fontSize: 12))),
            for (final c in comps)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassRow(
                  margin: EdgeInsets.zero,
                  onTap: () => openCompany(context, s, (c['id'] as num).toInt()),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                      _Pill(c['source'] == 'own' ? tr("o'z kaliti") : (c['source'] == 'platform' ? tr('platforma') : '—'), c['source'] == 'own' ? Brand.purple : Brand.green),
                    ]),
                    const SizedBox(height: 6),
                    if (c['source'] == 'platform' && ((c['limit'] as num?) ?? 0) > 0) ...[
                      InvoiceBar(amount: (c['limit'] as num?) ?? 0, paid: (c['used'] as num?) ?? 0),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      c['source'] == 'own'
                          ? "${tr('Shu oy')}: ${c['all_used']} ${tr("so'rov")} · ${c['provider'] ?? ''}"
                          : "${tr('Ishlatildi')}: ${c['used']} / ${((c['limit'] as num?) ?? 0) == 0 ? '∞' : c['limit']} · ${tr('qoldi')}: ${c['left'] ?? '∞'}",
                      style: TextStyle(color: cs.outline, fontSize: 12.5),
                    ),
                  ]),
                ),
              ),
            if (reqs.length > pending.length) _title(context, 'Arizalar tarixi'),
            for (final r in reqs.where((r) => r['status'] != 'pending'))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassRow(
                  margin: EdgeInsets.zero,
                  child: Row(children: [
                    Expanded(child: Text('${r['company']} · ${formatDate('${r['at']}')}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    _Pill(r['status'] == 'approved' ? tr('Ulangan') : tr('Rad etilgan'), r['status'] == 'approved' ? Colors.green.shade600 : cs.error),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _title(BuildContext context, String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Row(children: [Expanded(child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))), ?trailing]),
      );

  Widget _provider(BuildContext context, Map<String, dynamic> p, ColorScheme cs) {
    final l = p['limits'] is Map ? Map<String, dynamic>.from(p['limits'] as Map) : null;
    final st = '${l?['status'] ?? ''}';
    final c = switch (st) { 'ok' => Colors.green.shade600, 'limit' => Colors.orange.shade700, 'error' => cs.error, _ => cs.outline };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconTile(icon: p['voice'] == true ? Icons.graphic_eq_rounded : Icons.chat_rounded, color: p['active'] == true ? Brand.purple : cs.outline, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (p['default'] == true) ...[const SizedBox(width: 6), _Pill(tr('asosiy'), cs.primary)],
                ]),
                Text('${p['model']} · ${p['key']}${p['voice'] == true ? ' · ${tr('ovoz')}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12)),
              ]),
            ),
            if (p['active'] != true) _Pill(tr("o'chirilgan"), cs.outline),
          ]),
          if (l != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(st == 'ok' ? Icons.check_circle_rounded : Icons.error_rounded, size: 16, color: c),
              const SizedBox(width: 6),
              Expanded(child: Text('${l['message']}', style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13))),
            ]),
            for (final r in _maps(l['rows']))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  Expanded(child: Text('${r['k']}', style: TextStyle(color: cs.outline, fontSize: 12.5))),
                  Text('${r['v']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ]),
              ),
            const SizedBox(height: 4),
            Text("${tr('Bugun')}: ${l['today'] ?? 0} (${tr('xato')} ${l['today_err'] ?? 0}) · ${tr('Shu oy')}: ${l['month'] ?? 0} · ${tr('tokenlar')}: ${money(l['tokens'] as num?)} · ${tr('tekshirildi')} ${l['at'] ?? ''}",
                style: TextStyle(color: cs.outline, fontSize: 12)),
            if (l['note'] != null) Text('${l['note']}', style: TextStyle(color: cs.outline, fontSize: 11.5)),
          ],
        ]),
      ),
    );
  }
}

/* ---------------------------------------- Kirish kodi ---------------------------------------- */

Future<void> changeGateCode(BuildContext context, Session s) async {
  final code = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.pin_rounded, size: 32),
      title: const Text('Kirish kodi'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Ilovada «korxona kodi» o'rniga shu kod yozilsa — platforma administratori kirish oynasi ochiladi.", style: TextStyle(color: Theme.of(c).colorScheme.outline, fontSize: 13)),
        const SizedBox(height: 12),
        TextField(
          controller: code,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))],
          decoration: InputDecoration(labelText: tr('Yangi kod (kamida 4 belgi)')),
        ),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Saqlash'))],
    ),
  );
  if (ok != true || !context.mounted) return;
  if (code.text.trim().length < 4) return _snack(context, tr('Kod kamida 4 belgi bo\'lsin'));
  try {
    await s.papi!.pSend('POST', '/gate-code', {'code': code.text.trim()});
    HapticFeedback.mediumImpact();
    if (context.mounted) _snack(context, tr("Kirish kodi o'zgartirildi"));
  } catch (e) {
    await s.handleError(e);
    if (context.mounted) _snack(context, e is ApiException ? e.message : '$e');
  }
}
