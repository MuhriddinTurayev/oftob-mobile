import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../l10n.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'map_picker.dart';

/* ============================================================================================
 * Ish vaqti va joylashuv (rahbar, buxgalter, prorab — o'z obyekti) va maosh tafsiloti:
 * KPI, kechikish va qo'lda ushlab qolish (rahbar, buxgalter). Saytdagi «Рабочее время и геолокация»,
 * «KPI, премии и удержания» bilan bir xil.
 * ========================================================================================== */

List<Map<String, dynamic>> _maps(Object? v) => ((v as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

String _cur(Object? c) {
  final v = '${c ?? ''}'.trim();
  return switch (v.toLowerCase()) { 'сум' || 'uzs' || "so'm" => tr("so'm"), _ => v };
}

const _months = ['Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'];

String formatMonth(DateTime m) => '${tr(_months[m.month - 1])} ${m.year}';

void _snack(BuildContext context, String t) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(t)));

Widget _title(BuildContext context, String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(children: [Expanded(child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))), ?trailing]),
    );

/* ---------------------------------------- Ish vaqti va joylashuv ---------------------------------------- */

class WorkScreen extends StatefulWidget {
  const WorkScreen({super.key, required this.session});
  final Session session;

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> {
  Key _k = UniqueKey();

  Session get s => widget.session;

  void _reload() => setState(() => _k = UniqueKey());

  Future<void> _editRules(Map<String, dynamic> d) async {
    final r = Map<String, dynamic>.from(d['rules'] as Map);
    var start = '${r['start']}', end = '${r['end']}';
    var mode = '${r['late_mode']}';
    var geoReq = r['geo_required'] == true;
    final roles = ((r['geo_roles'] as List?) ?? const []).map((e) => '$e').toSet();
    final grace = TextEditingController(text: '${r['grace'] ?? 10}');
    final fixed = TextEditingController(text: fmtInput(r['late_fixed'] as num?));
    final canRoles = d['can_edit_geo_roles'] == true;
    final modes = _maps(d['late_modes']);
    Future<String?> pick(BuildContext c, String cur) async {
      final p = cur.split(':');
      final t = await showTimePicker(context: c, initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 9, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0));
      return t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(c).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ish vaqti', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final v = await pick(c, start);
                      if (v != null) set(() => start = v);
                    },
                    icon: const Icon(Icons.login_rounded),
                    label: Text('${tr('Boshlanadi')}: $start'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final v = await pick(c, end);
                      if (v != null) set(() => end = v);
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: Text('${tr('Tugaydi')}: $end'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(controller: grace, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Necha daqiqagacha kechikish hisoblanmaydi'))),
              const SizedBox(height: 12),
              const Text('Kechikkanda', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final m in modes) ChoiceChip(label: Text('${m['name']}'), selected: mode == m['id'], showCheckmark: false, onSelected: (_) => set(() => mode = '${m['id']}')),
              ]),
              const SizedBox(height: 8),
              if (mode == 'fixed') TextField(controller: fixed, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Har kechikish uchun summa'))),
              Text("Soatbay: oylik 3 000 000 → 26 kun × 8 soat → soatiga 14 423; 30 daqiqa kechiksa — 7 212 ushlanadi. Faqat oylik va kunlik stavkadagilardan ushlanadi.",
                  style: TextStyle(color: Theme.of(c).colorScheme.outline, fontSize: 12)),
              if (canRoles) ...[
                const SizedBox(height: 14),
                const Text('Geolokatsiya', style: TextStyle(fontWeight: FontWeight.w800)),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: geoReq, onChanged: (v) => set(() => geoReq = v), title: Text(tr("«Keldim» faqat obyektda (hamma xodim va ishchilar)"))),
                Text('Obyektni xaritada kim belgilaydi (rahbar — doim):', style: TextStyle(color: Theme.of(c).colorScheme.outline, fontSize: 12.5)),
                CheckboxListTile(contentPadding: EdgeInsets.zero, value: roles.contains('foreman'), onChanged: (v) => set(() => v == true ? roles.add('foreman') : roles.remove('foreman')), title: Text(tr("Prorab — faqat o'z obyekti"))),
                CheckboxListTile(contentPadding: EdgeInsets.zero, value: roles.contains('accountant'), onChanged: (v) => set(() => v == true ? roles.add('accountant') : roles.remove('accountant')), title: Text(tr('Buxgalter'))),
              ],
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: const Text('Saqlash'))),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await s.api!.aSend('POST', '/work/rules', {
        'start': start, 'end': end, 'grace': int.tryParse(grace.text.trim()) ?? 10, 'late_mode': mode,
        'late_fixed': num.tryParse(fixed.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0, 'geo_roles': roles.toList(), 'geo_required': geoReq,
      });
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, tr('Saqlandi'));
      _reload();
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    }
  }

  Future<void> _setSite(Map<String, dynamic> o) async {
    final site = o['site'] is Map ? Map<String, dynamic>.from(o['site'] as Map) : null;
    final picked = await Navigator.of(context).push<PickedSite>(MaterialPageRoute(
      builder: (_) => MapPickerScreen(title: '${o['name']}', lat: (site?['lat'] as num?)?.toDouble(), lng: (site?['lng'] as num?)?.toDouble(), radius: ((site?['radius'] as num?) ?? 150).toInt()),
    ));
    if (picked == null || !mounted) return;
    try {
      await s.api!.aSend('POST', '/work/sites/${o['id']}', {'lat': picked.lat, 'lng': picked.lng, 'radius': picked.radius});
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, tr('Obyekt joylashuvi saqlandi'));
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
      load: () => s.api!.aGet('/work'),
      builder: (context, raw, reload) {
        final d = Map<String, dynamic>.from(raw as Map);
        final r = Map<String, dynamic>.from(d['rules'] as Map);
        final sites = _maps(d['sites']);
        final mode = '${r['late_mode']}';
        final modeName = _maps(d['late_modes']).where((m) => m['id'] == mode).map((m) => '${m['name']}').firstOrNull ?? mode;
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
          children: [
            HeroGlass(
              tint: Brand.teal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const IconTile(icon: Icons.schedule_rounded, color: Brand.teal, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Ish vaqti', style: TextStyle(color: context.inkSoft, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      Text('${r['start']} – ${r['end']}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: context.ink)),
                    ]),
                  ),
                  if (d['can_edit_rules'] == true) IconButton.filledTonal(onPressed: () => _editRules(d), icon: const Icon(Icons.edit_rounded)),
                ]),
                const SizedBox(height: 8),
                Text('${tr('Kechikish')}: ${r['grace']} ${tr('daqiqagacha hisoblanmaydi')} · $modeName${mode == 'fixed' ? ' (${money(r['late_fixed'] as num?)})' : ''}',
                    style: TextStyle(color: context.inkSoft, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(r['geo_required'] == true ? tr("«Keldim» faqat obyektda belgilanadi") : tr("«Keldim» joylashuvsiz ham qabul qilinadi"), style: TextStyle(color: context.inkSoft, fontSize: 12.5)),
              ]),
            ),
            _title(context, 'Obyektlar joylashuvi'),
            if (sites.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr("Obyekt yo'q"))),
            for (final o in sites)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassRow(
                  margin: EdgeInsets.zero,
                  onTap: o['can_set'] == true ? () => _setSite(o) : null,
                  child: Row(children: [
                    IconTile(icon: o['site'] != null ? Icons.location_on_rounded : Icons.location_off_rounded, color: o['site'] != null ? Colors.green : Colors.orange, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${o['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          o['site'] != null
                              ? '${tr('belgilangan')} · ${tr('radius')} ${(o['site'] as Map)['radius']} m'
                              : (o['can_set'] == true ? tr('belgilanmagan — bosing va belgilang') : tr('belgilanmagan')),
                          style: TextStyle(color: o['site'] != null ? cs.outline : Colors.orange.shade800, fontSize: 12.5),
                        ),
                      ]),
                    ),
                    if (o['site'] != null)
                      IconButton(
                        onPressed: () => launchUrl(Uri.parse('https://maps.google.com/?q=${(o['site'] as Map)['lat']},${(o['site'] as Map)['lng']}'), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.map_rounded),
                      ),
                    if (o['can_set'] == true) Icon(Icons.chevron_right_rounded, color: cs.outline),
                  ]),
                ),
              ),
            const SizedBox(height: 6),
            Text("Prorab faqat o'z obyektini belgilaydi; buxgalterga rahbar ruxsat beradi. Rahbar ruxsatni olib tashlasa — belgilay olmaydi.", style: TextStyle(color: cs.outline, fontSize: 12)),
          ],
        );
      },
    );
  }
}

/* ---------------------------------------- Maosh: KPI va ushlab qolish ---------------------------------------- */

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key, required this.session});
  final Session session;

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  Key _k = UniqueKey();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Session get s => widget.session;

  String get _m => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  void _reload() => setState(() => _k = UniqueKey());

  Future<void> _open(Map<String, dynamic> st, String objectId, Map<String, dynamic> d) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StaffSheet(session: s, st: st, objectId: objectId, data: d, month: _m),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBody<dynamic>(
      key: ValueKey('$_k|$_m'),
      session: s,
      load: () => s.api!.aGet('/work/staff', {'month': _m}),
      builder: (context, raw, reload) {
        final d = Map<String, dynamic>.from(raw as Map);
        final objs = _maps(d['objects']);
        final cur = _cur(d['currency']);
        num tot(String k) => objs.fold<num>(0, (a, o) => a + _maps(o['staff']).fold<num>(0, (b, x) => b + ((x[k] as num?) ?? 0)));
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
          children: [
            Row(children: [
              IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left_rounded)),
              Expanded(child: Center(child: Text(formatMonth(_month), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))),
              IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right_rounded)),
            ]),
            HeroGlass(
              child: Row(children: [
                Expanded(child: _stat(context, 'Hisoblangan', '${money(tot('sum'))} $cur', context.ink)),
                Expanded(child: _stat(context, 'KPI bonus', '+${money(tot('bonus'))}', Colors.green.shade700)),
                Expanded(child: _stat(context, 'Ushlab qolindi', '−${money(tot('deduct'))}', cs.error)),
              ]),
            ),
            for (final o in objs) ...[
              _title(context, '${o['name']}'),
              if (_maps(o['staff']).isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr("Xodim yo'q"), style: TextStyle(color: cs.outline))),
              for (final x in _maps(o['staff']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassRow(
                    margin: EdgeInsets.zero,
                    onTap: () => _open(x, '${o['id']}', d),
                    child: Row(children: [
                      CircleAvatar(radius: 19, backgroundColor: cs.primary.withValues(alpha: 0.12), child: Text('${x['name']}'.isEmpty ? '?' : '${x['name']}'[0].toUpperCase(), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${x['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(
                            [
                              '${(x['pay'] as Map?)?['type_name'] ?? ''}',
                              '${x['days']} ${tr('kun')}',
                              if (((x['late'] as Map?)?['count'] ?? 0) > 0) '${tr('kechikdi')} ${(x['late'] as Map)['count']}',
                              if (_maps(x['kpis']).isNotEmpty) 'KPI ${_maps(x['kpis']).where((k) => k['reached'] == true).length}/${_maps(x['kpis']).length}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.outline, fontSize: 12.5),
                          ),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(money(x['sum'] as num?), style: const TextStyle(fontWeight: FontWeight.w900)),
                        if (((x['deduct'] as num?) ?? 0) > 0) Text('−${money(x['deduct'] as num?)}', style: TextStyle(color: cs.error, fontSize: 12, fontWeight: FontWeight.w700)),
                        if (((x['bonus'] as num?) ?? 0) > 0) Text('+${money(x['bonus'] as num?)}', style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ]),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _stat(BuildContext context, String k, String v, Color c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(color: context.inkSoft, fontSize: 12)),
        Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: c, fontSize: 15)),
      ]);
}

/// Xodim: maosh tafsiloti, KPI ro'yxati (qo'shish/olib tashlash), ushlab qolishlar (qo'shish/bekor qilish)
class _StaffSheet extends StatefulWidget {
  const _StaffSheet({required this.session, required this.st, required this.objectId, required this.data, required this.month});
  final Session session;
  final Map<String, dynamic> st;
  final String objectId;
  final Map<String, dynamic> data;
  final String month;

  @override
  State<_StaffSheet> createState() => _StaffSheetState();
}

class _StaffSheetState extends State<_StaffSheet> {
  late List<Map<String, dynamic>> _defs = _maps(widget.st['kpi_defs']);
  bool _changed = false, _busy = false;

  Session get s => widget.session;

  Future<void> _saveKpis() async {
    setState(() => _busy = true);
    try {
      await s.api!.aSend('POST', '/work/kpi', {'object': widget.objectId, 'staff': widget.st['id'], 'kpis': _defs});
      _changed = true;
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, tr('KPI saqlandi'));
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addKpi() async {
    final metrics = _maps(widget.data['metrics']);
    String metric = metrics.isNotEmpty ? '${metrics.first['id']}' : 'days';
    String mode = 'fixed';
    final plan = TextEditingController();
    final bonus = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text("KPI qo'shish"),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: metric,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr("Ko'rsatkich")),
                items: [for (final m in metrics) DropdownMenuItem(value: '${m['id']}', child: Text('${m['name']}', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => set(() => metric = v ?? metric),
              ),
              const SizedBox(height: 8),
              TextField(controller: plan, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "${tr('Oylik reja')} (${metrics.where((m) => m['id'] == metric).map((m) => m['unit']).firstOrNull ?? ''})")),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [ButtonSegment(value: 'fixed', label: Text(tr('Summa'))), ButtonSegment(value: 'percent', label: Text(tr('% hisoblangandan')))],
                selected: {mode},
                onSelectionChanged: (v) => set(() => mode = v.first),
              ),
              const SizedBox(height: 8),
              TextField(controller: bonus, keyboardType: TextInputType.number, inputFormatters: mode == 'fixed' ? const [ThousandsFormatter()] : null, decoration: InputDecoration(labelText: tr('Bonus'))),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text("Qo'shish"))],
        ),
      ),
    );
    final p = num.tryParse(plan.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    final b = num.tryParse(bonus.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    if (ok != true || p == null || p <= 0) return;
    setState(() {
      _defs = [..._defs.where((k) => k['metric'] != metric), {'metric': metric, 'plan': p, 'mode': mode, 'bonus': b}];
    });
    await _saveKpis();
  }

  Future<void> _addFine() async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ushlab qolish'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amount, autofocus: true, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Summa'))),
          const SizedBox(height: 8),
          TextField(controller: reason, decoration: InputDecoration(labelText: tr('Sabab'), hintText: tr('masalan: ish joyini tark etdi'))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ushlab qolish'))],
      ),
    );
    final a = num.tryParse(amount.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (ok != true || a == null || a <= 0 || reason.text.trim().isEmpty) return;
    final now = DateTime.now();
    final month = widget.month;
    final date = '$month-${(now.toString().startsWith(month) ? now.day : 1).toString().padLeft(2, '0')}';
    try {
      await s.api!.aSend('POST', '/work/fine', {'object': widget.objectId, 'staff': widget.st['id'], 'amount': a, 'reason': reason.text.trim(), 'date': date});
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      await s.handleError(e);
      if (mounted) _snack(context, e is ApiException ? e.message : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final x = widget.st;
    final cur = _cur(widget.data['currency']);
    final late = Map<String, dynamic>.from((x['late'] as Map?) ?? const {});
    final fines = _maps((x['fines'] as Map?)?['list']);
    final kpis = _maps(x['kpis']);
    final can = widget.data['can_kpi'] == true;
    final metrics = {for (final m in _maps(widget.data['metrics'])) '${m['id']}': m};
    Widget kv(String k, String v, {Color? c, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(color: cs.outline))),
            Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: c)),
          ]),
        );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) Navigator.pop(context, _changed);
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (c, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text('${x['name']}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            Text('${x['role']} · ${(x['pay'] as Map?)?['type_name'] ?? ''} · ${money((x['pay'] as Map?)?['rate'] as num?)} $cur', style: TextStyle(color: cs.outline)),
            const SizedBox(height: 12),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                kv(tr('Ish kunlari / soat'), '${x['days']} · ${x['hours']}'),
                kv(tr('Asos (ishlagani)'), '${money(x['base'] as num?)} $cur'),
                kv(tr('KPI bonus'), '+${money(x['bonus'] as num?)} $cur', c: Colors.green.shade700),
                if (((late['count'] as num?) ?? 0) > 0) kv('${tr('Kechikish')} (${late['count']} ${tr('marta')}, ${late['minutes']} ${tr('daq')})', '−${money(late['sum'] as num?)} $cur', c: cs.error),
                if (fines.isNotEmpty) kv(tr("Qo'lda ushlab qolish"), '−${money((x['fines'] as Map?)?['sum'] as num?)} $cur', c: cs.error),
                const Divider(),
                kv(tr('Hisoblangan'), '${money(x['sum'] as num?)} $cur', bold: true),
                kv(tr("Berildi"), '${money(x['paid'] as num?)} $cur', c: Colors.green.shade700),
                kv(tr('Qoldi'), '${money(x['due'] as num?)} $cur', c: ((x['due'] as num?) ?? 0) > 0 ? cs.error : null, bold: true),
              ]),
            ),
            if ((late['days'] is Map) && (late['days'] as Map).isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in (late['days'] as Map).entries) Chip(visualDensity: VisualDensity.compact, label: Text('${formatDate('${e.key}')}: +${e.value} ${tr('daq')}')),
              ]),
            ],
            _title(context, 'KPI', trailing: can ? TextButton.icon(onPressed: _busy ? null : _addKpi, icon: const Icon(Icons.add_rounded), label: const Text("Qo'shish")) : null),
            if (_defs.isEmpty) Text(tr('KPI qo\'yilmagan'), style: TextStyle(color: cs.outline)),
            for (final k in _defs)
              Builder(builder: (_) {
                final res = kpis.where((r) => r['metric'] == k['metric']).firstOrNull;
                final pct = ((res?['pct'] as num?) ?? 0).toDouble();
                final reached = res?['reached'] == true;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassRow(
                    margin: EdgeInsets.zero,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${metrics[k['metric']]?['name'] ?? k['metric']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                        if (can)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _defs = _defs.where((d) => d['metric'] != k['metric']).toList());
                                    await _saveKpis();
                                  },
                            icon: Icon(Icons.close_rounded, size: 18, color: cs.error),
                          ),
                      ]),
                      Text(
                        '${tr('Fakt')}: ${res?['fact'] ?? 0} / ${k['plan']} ${metrics[k['metric']]?['unit'] ?? ''} · ${tr('bonus')} ${k['mode'] == 'percent' ? '${k['bonus']}%' : money(k['bonus'] as num?)}${reached ? ' · +${money(res?['bonus'] as num?)}' : ''}',
                        style: TextStyle(color: cs.outline, fontSize: 12.5),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: LinearProgressIndicator(value: (pct / 100).clamp(0, 1), minHeight: 7, color: reached ? Colors.green : Brand.blue, backgroundColor: cs.outline.withValues(alpha: 0.15)),
                      ),
                    ]),
                  ),
                );
              }),
            _title(context, 'Ushlab qolishlar', trailing: widget.data['can_fine'] == true ? TextButton.icon(onPressed: _addFine, icon: const Icon(Icons.remove_rounded), label: const Text('Ushlab qolish')) : null),
            if (fines.isEmpty) Text(tr("Qo'lda ushlab qolish yo'q"), style: TextStyle(color: cs.outline)),
            for (final f in fines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassRow(
                  margin: EdgeInsets.zero,
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('−${money(f['amount'] as num?)} $cur', style: TextStyle(fontWeight: FontWeight.w800, color: cs.error)),
                        Text('${f['reason']} · ${formatDate('${f['date']}')} · ${f['by']}', style: TextStyle(color: cs.outline, fontSize: 12.5)),
                      ]),
                    ),
                    if (widget.data['can_fine'] == true)
                      IconButton(
                        onPressed: () async {
                          try {
                            await s.api!.aSend('DELETE', '/work/fine/${widget.objectId}/${f['id']}');
                            if (context.mounted) Navigator.pop(context, true);
                          } catch (e) {
                            await s.handleError(e);
                          }
                        },
                        icon: Icon(Icons.undo_rounded, color: cs.outline),
                        tooltip: tr('Bekor qilish'),
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
