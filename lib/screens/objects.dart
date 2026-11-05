import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../session.dart';
import '../widgets.dart';

Color statusColor(String? s) => switch (s) {
      'free' => Colors.green,
      'booked' => Colors.orange,
      'sold' => Colors.red,
      _ => Colors.blueGrey,
    };

class ObjectsScreen extends StatelessWidget {
  const ObjectsScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return FutureBody<List<Map<String, dynamic>>>(
      session: session,
      load: () => session.api!.objects(),
      builder: (context, objects, _) {
        if (objects.isEmpty) {
          return ListView(children: const [Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Obyektlar yo\'q')))]);
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: objects.length,
          itemBuilder: (context, i) {
            final o = objects[i];
            final a = (o['apartments'] as Map?) ?? const {};
            final progress = ((o['progress'] as num?) ?? 0).toInt();
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => ApartmentsScreen(session: session, object: o)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${o['name']}', style: Theme.of(context).textTheme.titleMedium),
                      if ('${o['address']}'.isNotEmpty) Text('${o['address']}', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: LinearProgressIndicator(value: progress / 100, minHeight: 8, borderRadius: BorderRadius.circular(4))),
                        const SizedBox(width: 12),
                        Text('$progress%'),
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        StatusChip('Bo\'sh ${a['free'] ?? 0}', Colors.green),
                        StatusChip('Bron ${a['booked'] ?? 0}', Colors.orange),
                        StatusChip('Sotilgan ${a['sold'] ?? 0}', Colors.red),
                        StatusChip('Jami ${a['total'] ?? 0}', Colors.blueGrey),
                      ]),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Obyektdagi xonadonlar: holat va xona soni bo'yicha filtr, raqam/xaridor bo'yicha qidiruv, xonadon kartasi.
class ApartmentsScreen extends StatefulWidget {
  const ApartmentsScreen({super.key, required this.session, required this.object});

  final Session session;
  final Map<String, dynamic> object;

  @override
  State<ApartmentsScreen> createState() => _ApartmentsScreenState();
}

class _ApartmentsScreenState extends State<ApartmentsScreen> {
  String? _status;
  int? _rooms;
  String _q = '';
  Key _listKey = UniqueKey();

  String get _objectId => '${widget.object['id']}';

  void _reload() => setState(() => _listKey = UniqueKey());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = widget.session.me!;
    final counts = (widget.object['apartments'] as Map?) ?? const {};
    return Scaffold(
      appBar: AppBar(title: Text('${widget.object['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Kvartira raqami yoki xaridor',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                for (final f in [(null, 'Hammasi', counts['total']), ('free', 'Bo\'sh', counts['free']), ('booked', 'Bron', counts['booked']), ('sold', 'Sotilgan', counts['sold'])])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${f.$2}${f.$3 != null ? ' ${f.$3}' : ''}'),
                      selected: _status == f.$1,
                      showCheckmark: false,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _status = f.$1;
                          _listKey = UniqueKey();
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                for (final r in const [null, 1, 2, 3, 4])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(r == null ? 'Barcha xonalar' : (r == 4 ? '4 xona' : '$r xona')),
                      selected: _rooms == r,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() {
                        _rooms = r;
                        _listKey = UniqueKey();
                      }),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PagedList(
              key: _listKey,
              session: widget.session,
              emptyText: 'Kvartiralar topilmadi',
              fetch: (p) => widget.session.api!.apartments(_objectId, status: _status, rooms: _rooms, page: p, perPage: 60),
              itemBuilder: (context, a) {
                final buyer = a['buyer'] as Map?;
                if (_q.isNotEmpty && !('${a['number']}'.toLowerCase().contains(_q) || '${buyer?['name'] ?? ''}'.toLowerCase().contains(_q))) return const SizedBox.shrink();
                final st = '${a['status']}';
                final price = (a['price'] as num?) ?? 0;
                final paid = (a['paid'] as num?) ?? 0;
                return InkWell(
                  onTap: () => showApartmentSheet(context, widget.session, _objectId, '${widget.object['name']}', a, onChanged: _reload),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Row(children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: statusColor(st).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                        child: Text('${a['number']}', style: TextStyle(fontWeight: FontWeight.w800, color: statusColor(st), fontSize: 15)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${roomsLabel(a['rooms'])} · ${area(a['area'] as num?)} m² · ${a['floor']}-qavat', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(buyer != null && '${buyer['name']}'.isNotEmpty ? '${buyer['name']}' : aptStatus(st), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 13)),
                          if (st != 'free' && price > 0) ...[
                            const SizedBox(height: 4),
                            ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: (paid / price).clamp(0, 1).toDouble(), minHeight: 4)),
                          ],
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(money(price), style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        StatusChip(aptStatus(st), statusColor(st)),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          ),
          if (!me.can('sales:read')) const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// Xonadon kartasi (pastdan chiqadigan varaq): narx, xaridor, to'lovlar, bron/sotuv/bo'shatish.
void showApartmentSheet(BuildContext context, Session session, String objectId, String objectName, Map<String, dynamic> apt, {VoidCallback? onChanged}) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ApartmentSheet(session: session, objectId: objectId, objectName: objectName, apt: apt, onChanged: onChanged ?? () {}),
  );
}

class ApartmentSheet extends StatefulWidget {
  const ApartmentSheet({super.key, required this.session, required this.objectId, required this.objectName, required this.apt, required this.onChanged});

  final Session session;
  final String objectId;
  final String objectName;
  final Map<String, dynamic> apt;
  final VoidCallback onChanged;

  @override
  State<ApartmentSheet> createState() => _ApartmentSheetState();
}

class _ApartmentSheetState extends State<ApartmentSheet> {
  late final _name = TextEditingController(text: '${(widget.apt['buyer'] as Map?)?['name'] ?? ''}');
  late final _phone = TextEditingController(text: '${(widget.apt['buyer'] as Map?)?['phone'] ?? ''}');
  late final _price = TextEditingController(text: money(widget.apt['price'] as num?).replaceAll(' ', ''));
  bool _busy = false;

  bool get _canWrite => widget.session.me!.can('sales:write');
  bool get _canSales => widget.session.me!.can('sales:read');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _patch(Map<String, dynamic> body, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await widget.session.api!.apartmentUpdate(widget.objectId, '${widget.apt['id']}', body);
      HapticFeedback.mediumImpact();
      widget.onChanged();
      if (!mounted) return;
      Navigator.pop(context);
      if (ok != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _change(String status) async {
    if ((status == 'booked' || status == 'sold') && _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Xaridor ismini kiriting')));
      return;
    }
    if (status == 'free') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${widget.apt['status']}' == 'booked' ? 'Bronni bekor qilish' : 'Bo\'shatish'),
          content: Text('Kvartira ${widget.apt['number']} bo\'sh holatga qaytariladi. Davom etasizmi?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Yo\'q')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ha')),
          ],
        ),
      );
      if (yes != true) return;
    }
    await _patch({
      'status': status,
      if (status != 'free') 'buyer_name': _name.text.trim(),
      if (status != 'free' && _phone.text.trim().isNotEmpty) 'buyer_phone': _phone.text.trim(),
      if (status == 'free') 'buyer_name': '',
    }, ok: switch (status) {
      'booked' => 'Bron qilindi',
      'sold' => 'Sotildi',
      _ => 'Bo\'shatildi',
    });
  }

  Future<void> _savePrice() async {
    final v = num.tryParse(_price.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Narxni to\'g\'ri kiriting')));
      return;
    }
    await _patch({'price': v}, ok: 'Narx saqlandi');
  }

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, color: color))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = widget.apt;
    final st = '${a['status']}';
    final buyer = a['buyer'] as Map?;
    final price = (a['price'] as num?) ?? 0;
    final paid = (a['paid'] as num?) ?? 0;
    final debt = (a['debt'] as num?) ?? 0;
    final payments = ((a['payments'] as List?) ?? const []).whereType<Map>().toList().reversed.toList();
    final phone = '${buyer?['phone'] ?? ''}'.trim();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      builder: (ctx, ctl) => ListView(
        controller: ctl,
        padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + MediaQuery.of(context).viewInsets.bottom),
        children: [
          Row(children: [
            Expanded(child: Text('Kvartira ${a['number']}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
            StatusChip(aptStatus(st), statusColor(st)),
          ]),
          Text('${widget.objectName} · ${a['floor']}-qavat · ${roomsLabel(a['rooms'])} · ${area(a['area'] as num?)} m²', style: TextStyle(color: cs.outline, fontSize: 13)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Narxi', style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.7), fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              Text('${money(price)} so\'m', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
              if (a['price_per_m2'] != null) Text('1 m² — ${money(a['price_per_m2'] as num?)} so\'m', style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.7), fontSize: 13)),
              if (_canSales && st != 'free' && price > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: (paid / price).clamp(0, 1).toDouble(), minHeight: 8)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('To\'langan ${money(paid)}', style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w700, fontSize: 13))),
                  Text('Qarz ${money(debt)}', style: TextStyle(color: debt > 0 ? cs.error : cs.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ],
            ]),
          ),
          if (_canSales && buyer != null && '${buyer['name']}'.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Xaridor', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            _kv('Ism', '${buyer['name']}'),
            if (a['plan'] != null && '${a['plan']}'.isNotEmpty) _kv('To\'lov shartlari', '${a['plan']}'),
            if (phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.call_outlined),
                  label: Text(phone),
                ),
              ),
          ],
          if (_canSales && payments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('To\'lovlar (${payments.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            for (final p in payments.take(20))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 16, backgroundColor: Colors.green.withValues(alpha: 0.12), foregroundColor: Colors.green.shade700, child: const Icon(Icons.south_west, size: 16)),
                title: Text('+${money(p['amount'] as num?)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${formatDate('${p['date']}')}${p['method'] != null && '${p['method']}'.isNotEmpty ? ' · ${p['method']}' : ''}'),
              ),
          ],
          if (_canWrite) ...[
            const Divider(height: 36),
            if (st == 'free') ...[
              TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Xaridor ismi', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _change('booked'), child: const Text('Bron qilish'))),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: _busy ? null : () => _change('sold'), child: const Text('Sotish'))),
              ]),
              const SizedBox(height: 20),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Narx (so\'m)', border: OutlineInputBorder()))),
                const SizedBox(width: 12),
                SizedBox(height: 56, child: FilledButton.tonal(onPressed: _busy ? null : _savePrice, child: const Text('Saqlash'))),
              ]),
            ] else if (st == 'booked') ...[
              FilledButton(onPressed: _busy ? null : () => _change('sold'), child: const Text('Sotishga o\'tkazish')),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _busy ? null : () => _change('free'), child: const Text('Bronni bekor qilish')),
            ] else if (st == 'sold')
              OutlinedButton(
                onPressed: _busy ? null : () => _change('free'),
                style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                child: const Text('Bo\'shatish'),
              ),
          ],
        ],
      ),
    );
  }
}
