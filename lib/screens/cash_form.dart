import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../l10n.dart';
import '../session.dart';
import '../theme.dart';

/// Kassa formasi uchun ma'lumot: kassalar, moddalar, obyektlar, ruxsatlar (GET /cash/form)
class CashFormData {
  CashFormData(Map d)
      : desks = [for (final x in (d['desks'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)],
        categories = [for (final x in (d['categories'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)],
        objects = [for (final x in (d['objects'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)],
        canAdd = d['can_add'] == true,
        isAdmin = d['is_admin'] == true;

  final List<Map<String, dynamic>> desks;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> objects;
  final bool canAdd;
  final bool isAdmin;

  static Future<CashFormData> load(Session s) async => CashFormData(await s.api!.aGet('/cash/form') as Map);
}

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Kirim/chiqim qo'shish yoki operatsiyani tuzatish. [op] berilsa — tahrirlash (kassa va tur o'zgarmaydi, o'chirish ham shu yerda).
/// true qaytsa — ro'yxat va qoldiqlar yangilanadi.
Future<bool> showCashOpForm(BuildContext context, Session s, CashFormData f, {Map<String, dynamic>? op, String type = 'in', int? deskId}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CashOpSheet(session: s, form: f, op: op, type: type, deskId: deskId),
  );
  return r == true;
}

class _CashOpSheet extends StatefulWidget {
  const _CashOpSheet({required this.session, required this.form, this.op, required this.type, this.deskId});
  final Session session;
  final CashFormData form;
  final Map<String, dynamic>? op;
  final String type;
  final int? deskId;

  @override
  State<_CashOpSheet> createState() => _CashOpSheetState();
}

class _CashOpSheetState extends State<_CashOpSheet> {
  Map<String, dynamic>? get op => widget.op;
  bool get editing => op != null;
  late String _type = editing ? '${op!['type']}' : widget.type;
  late int? _desk = editing ? (op!['desk_id'] as num?)?.toInt() : (widget.deskId ?? _firstDesk());
  late int? _cat = editing ? (op!['category_id'] as num?)?.toInt() : null;
  late String? _obj = editing ? (op!['object_id'] == null ? null : '${op!['object_id']}') : null;
  late String _date = editing ? '${op!['date']}' : _ymd(DateTime.now());
  late final _amount = TextEditingController(text: editing ? _amt((op!['amount'] as num?) ?? 0) : '');

  static String _amt(num a) => a == a.roundToDouble() ? groupDigits(a.round().toString()) : '${groupDigits(a.truncate().toString())}.${a.toStringAsFixed(2).split('.').last}';
  late final _note = TextEditingController(text: editing ? '${op!['note'] ?? ''}' : '');
  bool _busy = false;
  String? _err;

  int? _firstDesk() => widget.form.desks.isEmpty ? null : (widget.form.desks.first['id'] as num).toInt();

  Map<String, dynamic>? get _deskRow => widget.form.desks.where((d) => (d['id'] as num).toInt() == _desk).firstOrNull;

  List<Map<String, dynamic>> get _cats => widget.form.categories.where((c) => c['kind'] == _type).toList();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _sum => double.tryParse(_amount.text.replaceAll(' ', '').replaceAll(',', '.'));

  Future<void> _save() async {
    final sum = _sum;
    if (_desk == null) return setState(() => _err = tr('Kassani tanlang'));
    if (sum == null || sum <= 0) return setState(() => _err = tr('Summani kiriting'));
    setState(() {
      _busy = true;
      _err = null;
    });
    final body = <String, dynamic>{
      'amount': sum,
      'date': _date,
      'category_id': _cat,
      'object_id': _obj,
      'note': _note.text.trim(),
      if (!editing) ...{'desk_id': _desk, 'type': _type},
    };
    try {
      final d = editing ? await widget.session.api!.aSend('POST', '/cash/operations/${op!['id']}', body) : await widget.session.api!.aSend('POST', '/cash/operations', body);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final msg = d is Map ? '${d['message'] ?? ''}' : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.isNotEmpty ? msg : tr('Saqlandi'))));
      Navigator.pop(context, true);
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _err = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmCashDelete(context, op!);
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = await widget.session.api!.aSend('DELETE', '/cash/operations/${op!['id']}');
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final msg = d is Map ? '${d['message'] ?? ''}' : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.isNotEmpty ? msg : tr("O'chirildi"))));
      Navigator.pop(context, true);
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _err = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final income = _type == 'in';
    final color = income ? Colors.green : Colors.red;
    final cur = '${_deskRow?['currency'] ?? op?['currency'] ?? ''}';
    // tanlangan modda/obyekt ro'yxatda bo'lmasa (o'chirilgan yoki boshqa tur) — bo'sh qoldiramiz
    final catIds = _cats.map((c) => (c['id'] as num).toInt()).toSet();
    final cat = catIds.contains(_cat) ? _cat : null;
    final objIds = widget.form.objects.map((o) => '${o['id']}').toSet();
    final obj = objIds.contains(_obj) ? _obj : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom + MediaQuery.viewPaddingOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconTile(icon: income ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(editing ? tr('Operatsiyani tuzatish') : (income ? tr("Kirim qo'shish") : tr("Chiqim qo'shish")),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 14),
          if (!editing) ...[
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'in', icon: const Icon(Icons.south_west_rounded), label: Text(tr('Kirim'))),
                ButtonSegment(value: 'out', icon: const Icon(Icons.north_east_rounded), label: Text(tr('Chiqim'))),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() {
                _type = v.first;
                _cat = null;
              }),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(income ? tr('Qaysi kassaga') : tr('Qaysi kassadan'), style: TextStyle(color: cs.outline, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            Glass(
              radius: 18,
              shadow: false,
              onTap: () async {
                final v = await pickCashDesk(context, widget.form.desks, _desk, title: income ? tr('Qaysi kassaga') : tr('Qaysi kassadan'));
                if (v != null) setState(() => _desk = v);
              },
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
              child: _deskRow == null
                  ? Row(children: [Expanded(child: Text(tr('Kassani tanlang'), style: TextStyle(color: cs.outline))), const Icon(Icons.unfold_more_rounded)])
                  : Row(children: [
                      Expanded(child: DeskTile(_deskRow!)),
                      Icon(Icons.unfold_more_rounded, color: cs.outline),
                    ]),
            ),
          ] else
            Glass(
              radius: 14,
              blur: false,
              shadow: false,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(Icons.account_balance_wallet_rounded, color: cs.outline, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('${op!['desk'] ?? _deskRow?['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(income ? tr('Kirim') : tr('Chiqim'), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              ]),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: !editing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [ThousandsFormatter(decimal: true)],
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
            decoration: InputDecoration(labelText: tr('Summa'), suffixText: cur),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            key: ValueKey('cat$_type'),
            initialValue: cat,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Modda (ixtiyoriy)')),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(tr('— tanlanmagan —'), style: TextStyle(color: cs.outline))),
              for (final c in _cats) DropdownMenuItem<int?>(value: (c['id'] as num).toInt(), child: Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _cat = v),
          ),
          const SizedBox(height: 12),
          if (widget.form.objects.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              initialValue: obj,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Obyekt (ixtiyoriy)')),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(tr('Umumiy (obyektsiz)'), style: TextStyle(color: cs.outline))),
                for (final o in widget.form.objects) DropdownMenuItem<String?>(value: '${o['id']}', child: Text('${o['name']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _obj = v),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, firstDate: DateTime(now.year - 3), lastDate: now.add(const Duration(days: 1)), initialDate: DateTime.tryParse(_date) ?? now);
              if (d != null) setState(() => _date = _ymd(d));
            },
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.event_rounded),
            label: Text('${tr('Sana')}: ${formatDate(_date)}'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(labelText: tr('Izoh'), hintText: income ? tr("masalan: mijozdan avans, investordan qarz…") : tr('masalan: nimaga, kimga…')),
          ),
          if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_err!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700))),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded, color: Colors.white),
              label: Text(editing ? tr('Saqlash') : (income ? tr('Kirimni saqlash') : tr('Chiqimni saqlash'))),
            ),
          ),
          if (editing && op!['can_delete'] == true) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: cs.error),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text("Operatsiyani o'chirish"),
            ),
          ],
        ]),
      ),
    );
  }
}

Future<bool> confirmCashDelete(BuildContext context, Map<String, dynamic> op) async {
  final transfer = op['transfer_key'] != null;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(transfer ? tr("O'tkazmani o'chirish") : tr("Operatsiyani o'chirish")),
      content: Text(transfer ? tr("O'tkazma butunlay (ikkala operatsiya) o'chiriladi va kassalar qoldig'i qayta hisoblanadi.") : tr("Operatsiya o'chiriladi va kassa qoldig'i qayta hisoblanadi.")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')),
        FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error), child: const Text("O'chirish")),
      ],
    ),
  );
  return ok == true;
}


IconData deskIcon(Map d) => switch ('${d['kind']}') {
      'bank' => Icons.account_balance_rounded,
      'card' => Icons.credit_card_rounded,
      _ => d['object_id'] != null ? Icons.apartment_rounded : Icons.payments_rounded,
    };

Color deskColor(Map d) => switch ('${d['kind']}') {
      'bank' => const Color(0xFF6366F1),
      'card' => const Color(0xFF0EA5E9),
      _ => d['object_id'] != null ? const Color(0xFFF59E0B) : const Color(0xFF16A34A),
    };

/// Kassa qatori: turi belgisi, nomi va qoldig'i
class DeskTile extends StatelessWidget {
  const DeskTile(this.d, {super.key});

  final Map d;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bal = (d['balance'] as num?) ?? 0;
    return Row(children: [
      IconTile(icon: deskIcon(d), color: deskColor(d), size: 38),
      const SizedBox(width: 11),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${d['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          const SizedBox(height: 1),
          Text('${money(bal)} ${d['currency'] ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: bal < 0 ? cs.error : cs.outline)),
        ]),
      ),
    ]);
  }
}

/// Kassani tanlash varag'i: guruhlarga bo'lingan kartochkalar (kompaniya kassalari, obyekt kassalari, prorablar puli)
Future<int?> pickCashDesk(BuildContext context, List<Map<String, dynamic>> desks, int? current, {required String title}) {
  bool isForeman(Map d) => RegExp(r'^(Naqd|Karta)\s+—').hasMatch('${d['name']}');
  final groups = <String, List<Map<String, dynamic>>>{
    'Kompaniya kassalari': [for (final d in desks) if (d['object_id'] == null && !isForeman(d)) d],
    'Obyekt kassalari': [for (final d in desks) if (d['object_id'] != null) d],
    'Prorablar puli': [for (final d in desks) if (d['object_id'] == null && isForeman(d)) d],
  }..removeWhere((_, v) => v.isEmpty);
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.paddingOf(ctx).bottom),
          children: [
            Padding(padding: const EdgeInsets.only(left: 4, bottom: 10), child: Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
            for (final g in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                child: Text(tr(g.key).toUpperCase(), style: TextStyle(color: cs.outline, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              ),
              for (final d in g.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Glass(
                    radius: 18,
                    shadow: false,
                    blur: false,
                    tint: (d['id'] as num).toInt() == current ? cs.primary.withValues(alpha: 0.12) : null,
                    onTap: () => Navigator.of(ctx).pop((d['id'] as num).toInt()),
                    padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                    child: Row(children: [
                      Expanded(child: DeskTile(d)),
                      if ((d['id'] as num).toInt() == current) Icon(Icons.check_circle_rounded, color: cs.primary),
                    ]),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}
