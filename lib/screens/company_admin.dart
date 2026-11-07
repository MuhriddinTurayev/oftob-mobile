import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../l10n.dart';
import '../session.dart';
import '../theme.dart';
import '../upload.dart';
import '../widgets.dart';
import 'funds.dart' show pickReceipt;

/* ============================================================================================
 * Rahbar va buxgalter uchun: tarif va to'lov, kompaniya sun'iy intellekti, jamoa va rollar.
 * Saytdagi «Тариф и оплата», «ИИ компании», «Пользователи и роли» bilan bir xil.
 * ========================================================================================== */

List<Map<String, dynamic>> _maps(Object? v) => ((v as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

String _cur(Object? c) {
  final v = '${c ?? ''}'.trim();
  return switch (v.toLowerCase()) { 'сум' || 'uzs' || "so'm" => tr("so'm"), _ => v };
}

String _m(Object? v, Object? c) => '${money(v as num?)} ${_cur(c)}';

void _snack(BuildContext context, String t) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(t)));

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

Widget _section(BuildContext context, String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(children: [
        Expanded(child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        ?trailing,
      ]),
    );

/// To'lov holati rangi va nomi
(String, Color) _claimSt(String s, ColorScheme cs) => switch (s) {
      'pending' => ('Tasdiq kutilmoqda', Colors.orange.shade700),
      'confirmed' => ('Tasdiqlandi', Colors.green.shade600),
      'rejected' => ('Tasdiqlanmadi', cs.error),
      _ => (s, cs.outline),
    };

/// Hisob progressi: to'langan (yashil) + tasdiq kutilayotgan (to'q sariq)
class InvoiceBar extends StatelessWidget {
  const InvoiceBar({super.key, required this.amount, required this.paid, this.pending = 0});
  final num amount;
  final num paid;
  final num pending;

  @override
  Widget build(BuildContext context) {
    final a = amount <= 0 ? 1 : amount;
    final p = (paid / a).clamp(0, 1).toDouble();
    final q = (pending / a).clamp(0, 1 - p).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 12,
        child: Row(children: [
          if (p > 0) Expanded(flex: (p * 1000).round(), child: Container(color: Colors.green.shade600)),
          if (q > 0) Expanded(flex: (q * 1000).round(), child: Container(color: Colors.orange.shade600)),
          if (1 - p - q > 0.0005) Expanded(flex: ((1 - p - q) * 1000).round(), child: Container(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.18))),
        ]),
      ),
    );
  }
}

/* ---------------------------------------- Tarif va to'lov ---------------------------------------- */

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, required this.session});
  final Session session;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  Key _k = UniqueKey();

  Session get s => widget.session;

  void _reload() => setState(() => _k = UniqueKey());

  Future<void> _order(Map<String, dynamic> p) async {
    final once = (p['price_once'] as num?) != null && (p['price_once'] as num) > 0;
    String period = '1';
    num price(String per) {
      if (per == 'once') return (p['price_once'] as num?) ?? 0;
      final m = int.parse(per);
      final y = (p['price_year'] as num?) ?? 0;
      return m == 12 && y > 0 ? y : ((p['price_month'] as num?) ?? 0) * m;
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(c).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['title']}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Qancha muddatga?', style: TextStyle(color: Theme.of(c).colorScheme.outline)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final per in ['1', '3', '6', '12'])
                ChoiceChip(label: Text('$per ${tr('oy')}'), selected: period == per, showCheckmark: false, onSelected: (_) => set(() => period = per)),
              if (once)
                ChoiceChip(
                  avatar: const Icon(Icons.all_inclusive_rounded, size: 18),
                  label: const Text('Umrbod (bir martalik)'),
                  selected: period == 'once',
                  showCheckmark: false,
                  onSelected: (_) => set(() => period = 'once'),
                ),
            ]),
            const SizedBox(height: 16),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const IconTile(icon: Icons.receipt_long_rounded, color: Brand.green, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(period == 'once' ? tr("Bir marta to'lanadi — tarif umrbod") : '$period ${tr('oy')}', style: TextStyle(color: Theme.of(c).colorScheme.outline, fontSize: 12.5)),
                    Text(_m(price(period), p['currency']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Text("Hisob yaratiladi. Uni bir yo'la yoki qismlab to'laysiz; har to'lovni platforma administratori tasdiqlaydi.", style: TextStyle(color: Theme.of(c).colorScheme.outline, fontSize: 12.5)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: const Text('Hisob yaratish'))),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await s.api!.aSend('POST', '/billing/order', {'plan_id': p['id'], 'kind': period == 'once' ? 'once' : 'month', 'months': period == 'once' ? null : int.parse(period)});
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, tr("Hisob yaratildi. Endi to'lovni yuboring."));
      _reload();
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    }
  }

  Future<void> _pay(Map<String, dynamic> inv, List<Map<String, dynamic>> methods) async {
    final amount = TextEditingController(text: fmtInput(inv['to_send'] as num?));
    final note = TextEditingController();
    String method = methods.isNotEmpty ? '${methods.first['id']}' : 'click';
    final now = DateTime.now();
    String date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    String? photo;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(c).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("To'lov qildim", style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              Text('${tr('Qolgan')}: ${_m(inv['to_send'], inv['currency'])}', style: TextStyle(color: Theme.of(c).colorScheme.outline)),
              const SizedBox(height: 12),
              TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Summa'), helperText: tr("Qismlab to'lash mumkin"))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final x in methods) ChoiceChip(label: Text('${x['name']}'), selected: method == x['id'], showCheckmark: false, onSelected: (_) => set(() => method = '${x['id']}')),
              ]),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(context: c, firstDate: DateTime(now.year - 1), lastDate: now.add(const Duration(days: 1)), initialDate: DateTime.tryParse(date) ?? now);
                  if (d != null) set(() => date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
                },
                icon: const Icon(Icons.event_rounded),
                label: Text("${tr("To'langan sana")}: ${formatDate(date)}"),
              ),
              const SizedBox(height: 10),
              GlassRow(
                margin: EdgeInsets.zero,
                onTap: () async {
                  final f = await pickReceipt(c);
                  if (f != null) set(() => photo = f.path);
                },
                child: Row(children: [
                  IconTile(icon: photo == null ? Icons.add_a_photo_rounded : Icons.check_circle_rounded, color: photo == null ? Brand.blue : Colors.green, size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: Text(photo == null ? tr('Chek yoki kvitansiya (rasm)') : tr('Chek tanlandi'), style: const TextStyle(fontWeight: FontWeight.w700))),
                  if (photo != null) IconButton(onPressed: () => set(() => photo = null), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: InputDecoration(labelText: tr('Izoh (ixtiyoriy)'), hintText: tr("masalan: Click orqali, to'lov raqami…"))),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(c, true),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Tasdiqlashga yuborish'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final sum = amount.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (sum.isEmpty) return _snack(context, tr('Summani kiriting'));
    try {
      await runUpload<dynamic>(context,
          title: tr("To'lov yuborilmoqda"),
          task: (p) => s.api!.aUpload('/billing/claim', {'amount': sum, 'method': method, 'paid_at': date, 'note': note.text.trim()}, file: photo, onProgress: p));
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, tr("To'lov administratorga yuborildi. Tasdiqlansa, xabar keladi."));
      _reload();
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
      load: () => s.api!.aGet('/billing'),
      builder: (context, raw, reload) {
        final d = Map<String, dynamic>.from(raw as Map);
        final inv = d['invoice'] is Map ? Map<String, dynamic>.from(d['invoice'] as Map) : null;
        final last = d['last_closed'] is Map ? Map<String, dynamic>.from(d['last_closed'] as Map) : null;
        final can = d['can_pay'] == true;
        final life = d['lifetime'] == true;
        final plans = _maps(d['plans']);
        final claims = _maps(d['claims']);
        final pays = _maps(d['payments']);
        final methods = _maps(d['methods']);
        final usage = (d['usage'] is Map) ? d['usage'] as Map : const {};
        final st = '${d['state']}';
        final stColor = switch (st) { 'active' => Colors.green.shade600, 'trial' => Brand.blue, 'expired' => Colors.orange.shade700, _ => cs.error };
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
          children: [
            HeroGlass(
              tint: stColor,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconTile(icon: life ? Icons.all_inclusive_rounded : Icons.workspace_premium_rounded, color: stColor, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Sizning tarifingiz', style: TextStyle(color: context.inkSoft, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      Text('${(d['plan'] as Map?)?['title'] ?? '—'}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: context.ink)),
                    ]),
                  ),
                  _Pill('${d['state_label'] ?? st}', stColor),
                ]),
                const SizedBox(height: 10),
                Text(
                  life
                      ? tr("To'liq to'langan — yopilgan. Tarif umrbod, uzaytirish shart emas.")
                      : st == 'expired' && d['until'] != null
                          ? "${tr('Muddati tugagan')}: ${formatDate('${d['until']}')} — ${tr("ishni davom ettirish uchun to'lang")}"
                          : d['until'] != null
                          ? '${tr('Amal qiladi')}: ${formatDate('${d['until']}')} · ${tr('qoldi')} ${d['days_left'] ?? 0} ${tr('kun')}'
                          : tr('Muddatsiz'),
                  style: TextStyle(color: context.inkSoft, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text('${tr('Obyektlar')}: ${usage['objects'] ?? 0}/${(usage['max_objects'] ?? 0) == 0 ? '∞' : usage['max_objects']} · ${tr('Xodimlar')}: ${usage['users'] ?? 0}/${(usage['max_users'] ?? 0) == 0 ? '∞' : usage['max_users']}',
                    style: TextStyle(color: context.inkSoft, fontSize: 12.5)),
              ]),
            ),
            if (inv != null) ...[
              _section(context, "To'lanadigan hisob"),
              Glass(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${inv['plan']} · ${inv['kind'] == 'once' ? tr('umrbod (bir martalik)') : '${inv['months']} ${tr('oy')}'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 12),
                  InvoiceBar(amount: (inv['amount'] as num?) ?? 0, paid: (inv['paid'] as num?) ?? 0, pending: (inv['pending'] as num?) ?? 0),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _kv(context, "To'landi", _m(inv['paid'], inv['currency']), Colors.green.shade600)),
                    Expanded(child: _kv(context, 'Qoldi', _m(inv['left'], inv['currency']), context.ink)),
                    Expanded(child: _kv(context, 'Jami', _m(inv['amount'], inv['currency']), context.inkSoft)),
                  ]),
                  if (((inv['pending'] as num?) ?? 0) > 0) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.hourglass_top_rounded, size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${tr('Tasdiq kutilmoqda')}: ${_m(inv['pending'], inv['currency'])}', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w700, fontSize: 12.5))),
                    ]),
                  ],
                  if (can && ((inv['to_send'] as num?) ?? 0) > 0) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _pay(inv, methods),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        icon: const Icon(Icons.payments_rounded),
                        label: const Text("To'lov qildim"),
                      ),
                    ),
                  ],
                ]),
              ),
            ] else if (last != null && !life) ...[
              const SizedBox(height: 12),
              GlassRow(
                margin: EdgeInsets.zero,
                tint: Colors.green.withValues(alpha: 0.12),
                child: Row(children: [
                  Icon(Icons.verified_rounded, color: Colors.green.shade600),
                  const SizedBox(width: 10),
                  Expanded(child: Text("${tr("Oxirgi hisob to'liq to'langan — yopilgan")}: ${last['plan']} · ${_m(last['amount'], last['currency'])}", style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
              ),
            ],
            _section(context, 'Tariflar'),
            for (final p in plans) _planCard(context, p, d, can, life),
            if (claims.isNotEmpty) _section(context, "Yuborilgan to'lovlar"),
            for (final c in claims)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassRow(
                  margin: EdgeInsets.zero,
                  child: Row(children: [
                    IconTile(icon: Icons.send_rounded, color: _claimSt('${c['status']}', cs).$2, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_m(c['amount'], c['currency']), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text([formatDate('${c['paid_at']}'), c['method_name'], c['by']].where((x) => x != null && '$x'.isNotEmpty).join(' · '), style: TextStyle(color: cs.outline, fontSize: 12.5)),
                        if (c['reject_reason'] != null) Text('${c['reject_reason']}', style: TextStyle(color: cs.error, fontSize: 12.5)),
                      ]),
                    ),
                    _Pill(tr(_claimSt('${c['status']}', cs).$1), _claimSt('${c['status']}', cs).$2),
                  ]),
                ),
              ),
            if (pays.isNotEmpty) _section(context, "To'lovlar tarixi"),
            for (final p in pays)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassRow(
                  margin: EdgeInsets.zero,
                  child: Row(children: [
                    const IconTile(icon: Icons.check_rounded, color: Colors.green, size: 38),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${formatDate('${p['paid_at']}')} · ${p['plan'] ?? ''} · ${(p['months'] ?? 0) == 0 ? tr('umrbod') : '${p['months']} ${tr('oy')}'}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text(_m(p['amount'], p['currency']), style: TextStyle(color: Colors.green.shade600, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _kv(BuildContext context, String k, String v, Color c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(color: context.inkSoft, fontSize: 12)),
        Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: c)),
      ]);

  Widget _planCard(BuildContext context, Map<String, dynamic> p, Map<String, dynamic> d, bool can, bool life) {
    final cs = Theme.of(context).colorScheme;
    final mine = (d['plan'] as Map?)?['id'] == p['id'];
    final once = (p['price_once'] as num?) ?? 0;
    final features = ((p['features'] as List?) ?? const []).map((e) => '$e').toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${p['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            if (mine) _Pill(tr('Sizning tarifingiz'), cs.primary) else if (p['featured'] == true) _Pill(tr('Mashhur'), Brand.orange),
          ]),
          const SizedBox(height: 6),
          Text('${_m(p['price_month'], p['currency'])} / ${tr('oy')}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          if (((p['price_year'] as num?) ?? 0) > 0) Text('${tr('yoki yiliga')} ${_m(p['price_year'], p['currency'])}', style: TextStyle(color: cs.outline, fontSize: 12.5)),
          if (once > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Icon(Icons.all_inclusive_rounded, size: 16, color: Brand.green),
                const SizedBox(width: 6),
                Text('${tr('Umrbod')}: ${_m(once, p['currency'])}', style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.green)),
              ]),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [
            Text('${tr('Obyektlar')}: ${(p['max_objects'] ?? 0) == 0 ? '∞' : p['max_objects']}', style: TextStyle(color: cs.outline, fontSize: 12.5)),
            Text('${tr('Xodimlar')}: ${(p['max_users'] ?? 0) == 0 ? '∞' : p['max_users']}', style: TextStyle(color: cs.outline, fontSize: 12.5)),
            Text('AI: ${p['ai'] == null ? '—' : ((p['ai'] as num) == 0 ? '∞' : '${p['ai']}/${tr('oy')}')}', style: TextStyle(color: cs.outline, fontSize: 12.5)),
          ]),
          for (final f in features.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.check_rounded, size: 16, color: Colors.green.shade600),
                const SizedBox(width: 6),
                Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
              ]),
            ),
          if (can && !(life && mine)) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: mine
                  ? FilledButton.tonal(onPressed: () => _order(p), child: const Text('Uzaytirish'))
                  : OutlinedButton(onPressed: () => _order(p), child: const Text('Tanlash')),
            ),
          ],
        ]),
      ),
    );
  }
}

/* ---------------------------------------- Sun'iy intellekt ---------------------------------------- */

class AiSetupScreen extends StatefulWidget {
  const AiSetupScreen({super.key, required this.session});
  final Session session;

  @override
  State<AiSetupScreen> createState() => _AiSetupScreenState();
}

class _AiSetupScreenState extends State<AiSetupScreen> {
  Key _k = UniqueKey();

  Session get s => widget.session;

  void _reload() => setState(() => _k = UniqueKey());

  Future<void> _addKey(Map<String, dynamic> d) async {
    final catalog = _maps(d['catalog']);
    var drv = catalog.isNotEmpty ? Map<String, dynamic>.from(catalog.first) : <String, dynamic>{};
    String purpose = 'both';
    final key = TextEditingController();
    final model = TextEditingController();
    final baseUrl = TextEditingController();
    bool canVoice(Map x) => ((x['can'] as List?) ?? const []).contains('voice');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final cs = Theme.of(c).colorScheme;
          if (!canVoice(drv)) purpose = 'chat';
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(c).bottom),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Kalit ulash', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('1. Xizmatni tanlang  2. Kalitni oling  3. Shu yerga qo\'ying — kalit darhol tekshiriladi.', style: TextStyle(color: cs.outline, fontSize: 12.5)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final x in catalog)
                    ChoiceChip(
                      label: Text('${x['name']}'.split(' (').first),
                      avatar: Icon(canVoice(x) ? Icons.graphic_eq_rounded : Icons.chat_bubble_outline_rounded, size: 16),
                      selected: drv['driver'] == x['driver'],
                      showCheckmark: false,
                      onSelected: (_) => set(() => drv = Map<String, dynamic>.from(x)),
                    ),
                ]),
                const SizedBox(height: 12),
                Glass(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.lightbulb_outline_rounded, color: Brand.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(canVoice(drv) ? tr('Chat va ovoz uchun') : tr('Faqat chat uchun (ovozni tushunmaydi)'), style: const TextStyle(fontWeight: FontWeight.w800))),
                    ]),
                    const SizedBox(height: 6),
                    Text('${drv['help'] ?? ''}', style: const TextStyle(fontSize: 13)),
                    if ('${drv['key_url'] ?? ''}'.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse('${drv['key_url']}'), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Kalitni olish'),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'chat', label: Text(tr('Chat')), icon: const Icon(Icons.chat_rounded, size: 18)),
                    ButtonSegment(value: 'voice', label: Text(tr('Ovoz')), icon: const Icon(Icons.mic_rounded, size: 18), enabled: canVoice(drv)),
                    ButtonSegment(value: 'both', label: Text(tr('Ikkalasi')), enabled: canVoice(drv)),
                  ],
                  selected: {purpose},
                  onSelectionChanged: (v) => set(() => purpose = v.first),
                ),
                const SizedBox(height: 12),
                TextField(controller: key, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: tr('API kalit'), prefixIcon: const Icon(Icons.key_rounded), hintText: 'sk-…')),
                const SizedBox(height: 10),
                TextField(controller: model, autocorrect: false, decoration: InputDecoration(labelText: tr('Model (ixtiyoriy)'), hintText: '${drv['model'] ?? ''}')),
                if (drv['driver'] == 'compatible') ...[
                  const SizedBox(height: 10),
                  TextField(controller: baseUrl, autocorrect: false, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: tr('API manzili'), hintText: 'https://…/v1')),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(c, true),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('Tekshirish va ulash'),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Kalit serverda shifrlangan holda saqlanadi.', style: TextStyle(color: cs.outline, fontSize: 12)),
              ]),
            ),
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    if (key.text.trim().length < 8) return _snack(context, tr('Kalitni to\'liq kiriting'));
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))));
    try {
      await s.api!.aSend('POST', '/ai/keys', {'driver': drv['driver'], 'purpose': purpose, 'api_key': key.text.trim(), 'model': model.text.trim(), 'base_url': baseUrl.text.trim().isEmpty ? null : baseUrl.text.trim()});
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, tr('Kalit tekshirildi va ulandi. Ilova, sayt va Telegram-bot shu kalit orqali ishlaydi.'));
      _reload();
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    }
  }

  Future<void> _request(Map<String, dynamic> d) async {
    var chat = true, voice = false;
    final limit = TextEditingController();
    final note = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(c).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Platforma AI'si uchun ariza", style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text("Administrator tasdiqlasa, AI ulanadi va oylik limit ajratiladi.", style: TextStyle(color: Theme.of(c).colorScheme.outline)),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: chat, onChanged: (v) => set(() => chat = v), title: Text(tr('Chat va javoblar'))),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: voice, onChanged: (v) => set(() => voice = v), title: Text(tr('Ovozli boshqaruv'))),
            TextField(controller: limit, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr("Oyiga taxminan nechta so'rov kerak"), hintText: '500')),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('Izoh (ixtiyoriy)'))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: const Text('Ariza yuborish'))),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await s.api!.aSend('POST', '/ai/request', {'chat': chat, 'voice': voice, 'wanted_limit': int.tryParse(limit.text.trim()), 'note': note.text.trim()});
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, tr("Ariza yuborildi. Javob bildirishnoma va Telegram orqali keladi."));
      _reload();
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
      load: () => s.api!.aGet('/ai/settings', {'probe': 1}),
      builder: (context, raw, reload) {
        final d = Map<String, dynamic>.from(raw as Map);
        final lim = (d['limits'] is Map) ? Map<String, dynamic>.from(d['limits'] as Map) : <String, dynamic>{};
        final keys = _maps(d['keys']);
        final req = d['request'] is Map ? Map<String, dynamic>.from(d['request'] as Map) : null;
        final src = '${d['source']}';
        final platform = '${d['platform']}';
        final srcColor = switch (src) { 'own' => Brand.purple, 'platform' => Brand.green, _ => cs.outline };
        final limit = (lim['limit'] as num?) ?? 0;
        final used = (lim['used'] as num?) ?? 0;
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
          children: [
            HeroGlass(
              tint: srcColor,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconTile(icon: Icons.auto_awesome_rounded, color: srcColor, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("Sun'iy intellekt", style: TextStyle(color: context.inkSoft, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      Text(switch (src) { 'own' => tr("O'z kalitingiz"), 'platform' => tr("Platforma AI'si"), _ => tr('Ulanmagan') }, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: context.ink)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                if (src == 'platform' && limit > 0) ...[
                  InvoiceBar(amount: limit, paid: used),
                  const SizedBox(height: 6),
                ],
                Text('${d['line'] ?? ''}', style: TextStyle(color: context.inkSoft, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  Text('${tr('Chat')}: ${lim['provider'] ?? '—'}', style: TextStyle(color: context.inkSoft, fontSize: 12.5)),
                  Text('${tr('Ovoz')}: ${lim['voice'] ?? '—'}', style: TextStyle(color: context.inkSoft, fontSize: 12.5)),
                  Text('${tr('Yangilanadi')}: ${formatDate('${lim['renews_at'] ?? ''}')}', style: TextStyle(color: context.inkSoft, fontSize: 12.5)),
                ]),
              ]),
            ),
            _section(context, "O'z kalitlaringiz", trailing: TextButton.icon(onPressed: () => _addKey(d), icon: const Icon(Icons.add_rounded), label: const Text('Ulash'))),
            if (keys.isEmpty)
              GlassRow(
                margin: EdgeInsets.zero,
                onTap: () => _addKey(d),
                child: Row(children: [
                  const IconTile(icon: Icons.key_rounded, color: Brand.purple, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(tr("O'z kalitingizni ulang — AI ilova, sayt va Telegram-botda platforma limitisiz ishlaydi. Chat: DeepSeek, ChatGPT, Claude, Gemini. Ovoz: Gemini, ChatGPT."),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
            for (final k in keys) _keyCard(context, k),
            _section(context, "Platforma AI'si"),
            Glass(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(platform == 'approved' ? Icons.verified_rounded : Icons.cloud_outlined, color: platform == 'approved' ? Colors.green.shade600 : cs.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      switch (platform) {
                        'approved' => tr("Platforma AI'si ulangan"),
                        'pending' => tr('Ariza administratorda'),
                        'rejected' => tr('Ariza rad etildi'),
                        _ => tr("O'z kalitingiz bo'lmasa — platforma AI'si uchun ariza bering"),
                      },
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ]),
                if (req != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      formatDate('${req['at']}'),
                      [if (req['chat'] == true) tr('chat'), if (req['voice'] == true) tr('ovoz')].join(', '),
                      if (req['wanted_limit'] != null) '${req['wanted_limit']} ${tr("so'rov/oy")}',
                      if (req['status'] == 'approved') '${tr('limit')}: ${req['limit'] == null ? tr("tarif bo'yicha") : (req['limit'] == 0 ? '∞' : req['limit'])}',
                    ].where((x) => x.isNotEmpty).join(' · '),
                    style: TextStyle(color: cs.outline, fontSize: 12.5),
                  ),
                  if (req['reply'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${req['reply']}', style: const TextStyle(fontSize: 13))),
                ],
                if (platform != 'approved' && req?['status'] != 'pending') ...[
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton.tonalIcon(onPressed: () => _request(d), icon: const Icon(Icons.send_rounded), label: const Text('Ariza berish'))),
                ],
              ]),
            ),
          ],
        );
      },
    );
  }

  Widget _keyCard(BuildContext context, Map<String, dynamic> k) {
    final cs = Theme.of(context).colorScheme;
    final l = k['limits'] is Map ? Map<String, dynamic>.from(k['limits'] as Map) : null;
    final st = '${l?['status'] ?? ''}';
    final c = switch (st) { 'ok' => Colors.green.shade600, 'limit' => Colors.orange.shade700, 'error' => cs.error, _ => cs.outline };
    final rows = _maps(l?['rows']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconTile(icon: k['purpose'] == 'chat' ? Icons.chat_rounded : Icons.graphic_eq_rounded, color: k['active'] == true ? Brand.purple : cs.outline, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${k['driver_name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${k['model']} · ${k['key']} · ${k['purpose_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12)),
              ]),
            ),
            Switch(
              value: k['active'] == true,
              onChanged: (v) async {
                try {
                  await widget.session.api!.aSend('PUT', '/ai/keys/${k['id']}', {'is_active': v});
                  _reload();
                } catch (e) {
                  await widget.session.handleError(e);
                  if (mounted) _snack(this.context, e is ApiException ? e.message : '$e');
                }
              },
            ),
          ]),
          if (l != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(st == 'ok' ? Icons.check_circle_rounded : Icons.error_rounded, size: 16, color: c),
              const SizedBox(width: 6),
              Expanded(child: Text('${l['message']}', style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13))),
            ]),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  Expanded(child: Text('${r['k']}', style: TextStyle(color: cs.outline, fontSize: 12.5))),
                  Text('${r['v']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ]),
              ),
            const SizedBox(height: 4),
            Text("${tr('Bugun')}: ${l['today'] ?? 0} · ${tr('Shu oy')}: ${l['month'] ?? 0} ${tr("so'rov")} · ${tr('tekshirildi')} ${l['at'] ?? ''}", style: TextStyle(color: cs.outline, fontSize: 12)),
            if (l['note'] != null) Text('${l['note']}', style: TextStyle(color: cs.outline, fontSize: 11.5)),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text("Kalitni o'chirish"),
                    content: Text('${k['driver_name']} · ${k['key']}'),
                    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text("O'chirish"))],
                  ),
                );
                if (ok != true) return;
                try {
                  await widget.session.api!.aSend('DELETE', '/ai/keys/${k['id']}');
                  _reload();
                } catch (e) {
                  await widget.session.handleError(e);
                }
              },
              icon: Icon(Icons.delete_outline_rounded, color: cs.error, size: 18),
              label: Text("O'chirish", style: TextStyle(color: cs.error)),
            ),
          ),
        ]),
      ),
    );
  }
}

/* ---------------------------------------- Jamoa va rollar ---------------------------------------- */

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, required this.session});
  final Session session;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  Key _k = UniqueKey();

  Session get s => widget.session;

  Future<void> _save(int id, Map<String, dynamic> body, {String? ok}) async {
    try {
      await s.api!.aSend('POST', '/team/$id', body);
      HapticFeedback.mediumImpact();
      if (mounted && ok != null) _snack(context, ok);
      setState(() => _k = UniqueKey());
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    }
  }

  Future<void> _toggle(Map<String, dynamic> u) async {
    final on = u['active'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(on ? tr('Kirishni bloklash') : tr('Kirishni yoqish')),
        content: Text(on ? tr('«:n» ilova, sayt va Telegram-botdan darhol chiqariladi.').replaceAll(':n', '${u['name']}') : '${u['name']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')),
          FilledButton(
            style: on ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(on ? tr('Bloklash') : tr('Yoqish')),
          ),
        ],
      ),
    );
    if (ok == true) await _save((u['id'] as num).toInt(), {'is_active': !on}, ok: on ? tr('Bloklandi') : tr('Kirish yoqildi'));
  }

  Future<void> _edit(Map<String, dynamic> u, List<Map<String, dynamic>> roles, List<Map<String, dynamic>> modules) async {
    String role = '${u['role']}';
    List<String> pagesOf(String r) {
      final x = roles.where((e) => e['id'] == r).firstOrNull;
      final p = x?['pages'];
      return p is List ? p.map((e) => '$e').toList() : modules.map((e) => '${e['id']}').toList();
    }

    var custom = u['modules'] is List;
    var mods = custom ? ((u['modules'] as List).map((e) => '$e').toSet()) : pagesOf(role).toSet();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (c, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('${u['name']}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              Text('${u['login'] ?? ''}', style: TextStyle(color: Theme.of(c).colorScheme.outline)),
              const SizedBox(height: 12),
              const Text('Rol', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in roles)
                  ChoiceChip(
                    label: Text('${r['name']}'),
                    selected: role == r['id'],
                    showCheckmark: false,
                    onSelected: (_) => set(() {
                      role = '${r['id']}';
                      if (!custom) mods = pagesOf(role).toSet();
                    }),
                  ),
              ]),
              if (role != 'admin') ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: custom,
                  onChanged: (v) => set(() {
                    custom = v;
                    if (!v) mods = pagesOf(role).toSet();
                  }),
                  title: Text(tr("Bo'limlarni cheklash")),
                  subtitle: Text(tr("Faqat belgilangan bo'limlarni ko'radi")),
                ),
                if (custom)
                  for (final m in modules)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: mods.contains(m['id']),
                      onChanged: (v) => set(() => v == true ? mods.add('${m['id']}') : mods.remove('${m['id']}')),
                      title: Text('${m['name']}'),
                    ),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: const Text('Saqlash')),
              const SizedBox(height: 6),
              Text("Rol o'zgarsa, xodim qayta kiradi — yangi huquqlar bilan.", textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).colorScheme.outline, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    await _save((u['id'] as num).toInt(), {'role': role, 'custom': custom && role != 'admin', 'modules': mods.toList()}, ok: tr('Saqlandi'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBody<dynamic>(
      key: _k,
      session: s,
      load: () => s.api!.aGet('/team'),
      builder: (context, raw, reload) {
        final d = Map<String, dynamic>.from(raw as Map);
        final users = _maps(d['users']);
        final roles = _maps(d['roles']);
        final modules = _maps(d['modules']);
        final canEdit = d['can_edit'] == true;
        final on = users.where((u) => u['active'] == true).toList();
        final off = users.where((u) => u['active'] != true).toList();
        Widget row(Map<String, dynamic> u) {
          final active = u['active'] == true;
          final self = u['self'] == true;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassRow(
              margin: EdgeInsets.zero,
              onTap: canEdit && !self ? () => _edit(u, roles, modules) : null,
              child: Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: (active ? cs.primary : cs.outline).withValues(alpha: 0.14),
                  child: Text('${u['name']}'.isEmpty ? '?' : '${u['name']}'[0].toUpperCase(), style: TextStyle(color: active ? cs.primary : cs.outline, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${u['name']}${self ? ' · ${tr('siz')}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: active ? null : cs.outline)),
                    Text(
                      [u['role_name'], if (u['modules'] is List) tr("bo'limlar cheklangan"), if (u['telegram'] == true) 'Telegram'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.outline, fontSize: 12.5),
                    ),
                  ]),
                ),
                if (!self && canEdit)
                  Switch(value: active, onChanged: (_) => _toggle(u), activeTrackColor: Colors.green.shade400)
                else if (!active)
                  _Pill(tr('Bloklangan'), cs.error),
              ]),
            ),
          );
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
          children: [
            GlassRow(
              margin: EdgeInsets.zero,
              child: Row(children: [
                const IconTile(icon: Icons.admin_panel_settings_rounded, color: Brand.blue, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text(tr("Kalitcha — kirishni bloklash/yoqish (ilova, sayt va bot darhol yopiladi). Xodimni bosing — rolni o'zgartirish va bo'limlarni cheklash."), style: const TextStyle(fontSize: 12.5))),
              ]),
            ),
            _section(context, '${tr('Faol')} (${on.length})'),
            for (final u in on) row(u),
            if (off.isNotEmpty) _section(context, '${tr('Bloklangan')} (${off.length})'),
            for (final u in off) row(u),
          ],
        );
      },
    );
  }
}
