import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../session.dart';
import '../widgets.dart';

const _months = ['Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'];

const _payTypes = {
  'hour': 'Soatbay',
  'day': 'Kunlik',
  'month': 'Oylik (maosh)',
  'sqm': 'm² uchun',
  'm3': 'm³ uchun',
  'piece': 'Dona uchun',
};

/// Xodimlar: obyektlar bo'yicha ro'yxat, oy uchun hisoblangan / to'langan / qolgan ish haqi, xodim kartasi, yangi xodim qabul qilish.
/// Hisob veb-dasturdagi «Mening xodimlarim» bilan bir xil (server hisoblaydi). To'lov qilish bu ekranda yo'q (pul operatsiyasi — saytda).
class CrewScreen extends StatefulWidget {
  const CrewScreen({super.key, required this.session});

  final Session session;

  @override
  State<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends State<CrewScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String? _object;
  String _q = '';

  Session get s => widget.session;
  String get _monthStr => '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}';
  bool get _isCurrent => _month.year == DateTime.now().year && _month.month == DateTime.now().month;
  bool get _money => _data?['money'] == true;
  String get _cur {
    final c = '${_data?['currency'] ?? ''}'.trim();
    return const {'', 'uzs', 'сум', 'сўм', 'sum', 'som'}.contains(c.toLowerCase()) ? 'so\'m' : c;
  }

  List<Map<String, dynamic>> get _objects => ((_data?['objects'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = _data == null;
        _error = null;
      });
    }
    try {
      final d = await s.api!.crew(month: _monthStr);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      await s.handleError(e);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _shift(int d) {
    final n = DateTime(_month.year, _month.month + d);
    if (n.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) return;
    HapticFeedback.selectionClick();
    setState(() {
      _month = n;
      _data = null;
    });
    _load();
  }

  Future<void> _hire() async {
    final objs = _objects;
    if (objs.isEmpty) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HireSheet(session: s, objects: objs, initial: _object ?? '${objs.first['id']}'),
    );
    if (ok == true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Xodim qo\'shildi')));
      _load(quiet: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canEdit = _data?['can_edit'] == true;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canEdit ? FloatingActionButton.extended(onPressed: _hire, icon: const Icon(Icons.person_add_alt_1), label: const Text('Xodim qo\'shish')) : null,
      body: Column(children: [
        _monthBar(cs),
        Expanded(child: _body(cs)),
      ]),
    );
  }

  Widget _monthBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(children: [
        IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12)),
            child: Text('${_months[_month.month - 1]} ${_month.year}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        IconButton(onPressed: _isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }

  Widget _body(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) return ErrorView(message: _error!, onRetry: _load);
    final sum = Map<String, dynamic>.from((_data?['summary'] as Map?) ?? const {});
    final objs = _objects.where((o) => _object == null || o['id'] == _object).toList();
    final tiles = <Widget>[];
    for (final o in objs) {
      final workers = ((o['workers'] as List?) ?? const []).whereType<Map>().where((w) {
        if (_q.isEmpty) return true;
        return '${w['name']} ${w['role']} ${w['phone']}'.toLowerCase().contains(_q.toLowerCase());
      }).toList();
      if (workers.isEmpty) continue;
      tiles.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Row(children: [
          Expanded(child: Text('${o['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          Text('${workers.length} kishi', style: TextStyle(color: cs.outline, fontWeight: FontWeight.w600)),
        ]),
      ));
      for (final w in workers) {
        tiles.add(_WorkerRow(w: w, money: _money, cur: _cur, onTap: () => _open(w, '${o['name']}')));
      }
    }
    return RefreshIndicator(
      onRefresh: () => _load(quiet: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          if (_money)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(18)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Oy bo\'yicha hisob · ${sum['workers'] ?? 0} xodim', style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.75), fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _Sum('Hisoblangan', sum['accrued'], _cur, cs.onPrimaryContainer),
                    _Sum('To\'langan', sum['paid'], _cur, Colors.green.shade800),
                    _Sum('Qoldi', sum['due'], _cur, ((sum['due'] as num?) ?? 0) > 0 ? cs.error : cs.onPrimaryContainer),
                  ]),
                ]),
              ),
            ),
          if (_objects.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip('Hamma obyektlar', _object == null, () => setState(() => _object = null)),
                  for (final o in _objects) _chip('${o['name']}', _object == o['id'], () => setState(() => _object = '${o['id']}')),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(
                hintText: 'Qidirish: ism, lavozim, telefon',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (tiles.isEmpty) const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Xodim yo\'q'))),
          ...tiles,
        ],
      ),
    );
  }

  Widget _chip(String t, bool on, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(t), selected: on, onSelected: (_) => f(), showCheckmark: false),
      );

  void _open(Map w, String object) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _WorkerSheet(w: w, object: object, money: _money, cur: _cur, month: '${_months[_month.month - 1]} ${_month.year}'),
    );
  }
}

class _Sum extends StatelessWidget {
  const _Sum(this.label, this.v, this.cur, this.color);

  final String label;
  final dynamic v;
  final String cur;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(money(v as num?), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color))),
      ]),
    );
  }
}

class _WorkerRow extends StatelessWidget {
  const _WorkerRow({required this.w, required this.money, required this.cur, required this.onTap});

  final Map w;
  final bool money;
  final String cur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = '${w['name']}';
    final pay = Map<String, dynamic>.from((w['pay'] as Map?) ?? const {});
    final month = Map<String, dynamic>.from((w['month'] as Map?) ?? const {});
    final rate = pay['rate'] as num?;
    final sub = [
      if ('${w['role']}'.isNotEmpty) '${w['role']}',
      if (money && rate != null && rate > 0) '${_fmtMoney(rate)} / ${pay['unit'] ?? ''}',
    ].join(' · ');
    final due = month['due'] as num?;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          CircleAvatar(radius: 20, backgroundColor: cs.primaryContainer, foregroundColor: cs.onPrimaryContainer, child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
            ]),
          ),
          if (money)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmtMoney(month['accrued'] as num?), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              Text(due != null && due > 0 ? 'qoldi ${_fmtMoney(due)}' : (((month['accrued'] as num?) ?? 0) > 0 ? 'to\'langan' : ''), style: TextStyle(color: due != null && due > 0 ? cs.error : Colors.green.shade700, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ]),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right, color: cs.outline, size: 20),
        ]),
      ),
    );
  }
}

String _fmtMoney(num? v) => money(v);

class _WorkerSheet extends StatelessWidget {
  const _WorkerSheet({required this.w, required this.object, required this.money, required this.cur, required this.month});

  final Map w;
  final String object;
  final bool money;
  final String cur;
  final String month;

  Widget _kv(BuildContext context, String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
          Text(v, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pay = Map<String, dynamic>.from((w['pay'] as Map?) ?? const {});
    final m = Map<String, dynamic>.from((w['month'] as Map?) ?? const {});
    final work = ((w['work'] as List?) ?? const []).whereType<Map>().toList();
    final phone = '${w['phone'] ?? ''}'.trim();
    final due = (m['due'] as num?) ?? 0;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, ctl) => ListView(
        controller: ctl,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Row(children: [
            CircleAvatar(radius: 26, backgroundColor: cs.primary, foregroundColor: cs.onPrimary, child: Text('${w['name']}'.isEmpty ? '?' : '${w['name']}'[0].toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${w['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                Text([if ('${w['role']}'.isNotEmpty) '${w['role']}', object].join(' · '), style: TextStyle(color: cs.outline, fontSize: 13)),
              ]),
            ),
          ]),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.call_outlined),
              label: Text(phone),
            ),
          ],
          const SizedBox(height: 18),
          Text('Ish haqi shartlari', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          _kv(context, 'Turi', '${pay['type_name'] ?? ''}'),
          if (money && pay['rate'] != null) _kv(context, 'Stavka', '${_fmtMoney(pay['rate'] as num?)} $cur / ${pay['unit'] ?? ''}'),
          const SizedBox(height: 12),
          Text(month, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          _kv(context, 'Ish kunlari', '${m['days'] ?? 0}'),
          _kv(context, 'Soat', area((m['hours'] as num?) ?? 0)),
          if (money) ...[
            _kv(context, 'Hisoblangan', '${_fmtMoney(m['accrued'] as num?)} $cur'),
            _kv(context, 'To\'langan', '${_fmtMoney(m['paid'] as num?)} $cur', color: Colors.green.shade700),
            _kv(context, 'Qoldi', '${_fmtMoney(due)} $cur', color: due > 0 ? cs.error : null),
          ],
          if (work.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Bajarilgan ish hajmi', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            for (final x in work)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${area((x['qty'] as num?) ?? 0)} ${pay['unit'] ?? ''}'),
                subtitle: Text('${x['note'] ?? ''}'.isEmpty ? formatDate('${x['date']}') : '${formatDate('${x['date']}')} · ${x['note']}'),
              ),
          ],
          const SizedBox(height: 12),
          Text('To\'lov va ish hajmini yozish — saytda ("To\'liq sayt versiyasi").', style: TextStyle(color: cs.outline, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HireSheet extends StatefulWidget {
  const _HireSheet({required this.session, required this.objects, required this.initial});

  final Session session;
  final List<Map<String, dynamic>> objects;
  final String initial;

  @override
  State<_HireSheet> createState() => _HireSheetState();
}

class _HireSheetState extends State<_HireSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _rate = TextEditingController();
  final _role = TextEditingController();
  late String _object = widget.initial;
  String _pay = 'hour';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _rate.dispose();
    _role.dispose();
    super.dispose();
  }

  List<String> get _roles {
    final o = widget.objects.firstWhere((e) => e['id'] == _object, orElse: () => const {});
    return ((o['positions'] as List?) ?? const []).whereType<Map>().map((e) => '${e['name']}').toList();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _role.text.trim().isEmpty) {
      setState(() => _error = 'Ism va lavozimni kiriting.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api!.crewHire(
        object: _object,
        name: _name.text.trim(),
        role: _role.text.trim(),
        phone: _phone.text.trim(),
        pay: _pay,
        rate: num.tryParse(_rate.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    InputDecoration dec(String l) => InputDecoration(labelText: l, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none));
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Yangi xodim', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (widget.objects.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _object,
              decoration: dec('Obyekt'),
              items: [for (final o in widget.objects) DropdownMenuItem(value: '${o['id']}', child: Text('${o['name']}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _object = v ?? _object),
            ),
            const SizedBox(height: 12),
          ],
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: dec('Ism familiya')),
          const SizedBox(height: 12),
          TextField(controller: _role, decoration: dec('Lavozim (masalan: Betonchi)')),
          if (_roles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 0, children: [for (final r in _roles) ActionChip(label: Text(r), onPressed: () => setState(() => _role.text = r))]),
            ),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: dec('Telefon (ixtiyoriy)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _pay,
            decoration: dec('Ish haqi turi'),
            items: [for (final e in _payTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _pay = v ?? _pay),
          ),
          const SizedBox(height: 12),
          TextField(controller: _rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dec('Stavka')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Qo\'shish', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
