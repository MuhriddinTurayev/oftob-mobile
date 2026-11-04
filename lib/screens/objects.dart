import 'package:flutter/material.dart';

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

class ApartmentsScreen extends StatefulWidget {
  const ApartmentsScreen({super.key, required this.session, required this.object});

  final Session session;
  final Map<String, dynamic> object;

  @override
  State<ApartmentsScreen> createState() => _ApartmentsScreenState();
}

class _ApartmentsScreenState extends State<ApartmentsScreen> {
  String? _status;
  Key _listKey = UniqueKey();

  String get _objectId => '${widget.object['id']}';

  void _setFilter(String? s) => setState(() {
        _status = s;
        _listKey = UniqueKey();
      });

  @override
  Widget build(BuildContext context) {
    final canWrite = widget.session.me!.can('sales:write');
    final canSales = widget.session.me!.can('sales:read');
    return Scaffold(
      appBar: AppBar(title: Text('${widget.object['name']}')),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final f in const [(null, 'Hammasi'), ('free', 'Bo\'sh'), ('booked', 'Bron'), ('sold', 'Sotilgan')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(f.$2), selected: _status == f.$1, onSelected: (_) => _setFilter(f.$1)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PagedList(
              key: _listKey,
              session: widget.session,
              emptyText: 'Kvartiralar topilmadi',
              fetch: (p) => widget.session.api!.apartments(_objectId, status: _status, page: p),
              itemBuilder: (context, a) {
                final buyer = a['buyer'] as Map?;
                return ListTile(
                  onTap: () => _open(context, a, canWrite, canSales),
                  leading: CircleAvatar(
                    backgroundColor: statusColor('${a['status']}').withValues(alpha: 0.15),
                    child: Text('${a['number']}', style: TextStyle(fontSize: 12, color: statusColor('${a['status']}'), fontWeight: FontWeight.bold)),
                  ),
                  title: Text('${a['rooms']} xona · ${area(a['area'] as num?)} m² · ${a['floor']}-qavat'),
                  subtitle: Text(buyer != null ? '${buyer['name']}' : aptStatus('${a['status']}')),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(money(a['price'] as num?), style: const TextStyle(fontWeight: FontWeight.w600)),
                      StatusChip(aptStatus('${a['status']}'), statusColor('${a['status']}')),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Map<String, dynamic> a, bool canWrite, bool canSales) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ApartmentSheet(
        session: widget.session,
        objectId: _objectId,
        apt: a,
        canWrite: canWrite,
        canSales: canSales,
        onChanged: () => setState(() => _listKey = UniqueKey()),
      ),
    );
  }
}

class _ApartmentSheet extends StatefulWidget {
  const _ApartmentSheet({required this.session, required this.objectId, required this.apt, required this.canWrite, required this.canSales, required this.onChanged});

  final Session session;
  final String objectId;
  final Map<String, dynamic> apt;
  final bool canWrite;
  final bool canSales;
  final VoidCallback onChanged;

  @override
  State<_ApartmentSheet> createState() => _ApartmentSheetState();
}

class _ApartmentSheetState extends State<_ApartmentSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _change(String status) async {
    if ((status == 'booked' || status == 'sold') && _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Xaridor ismini kiriting')));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.session.api!.apartmentUpdate(widget.objectId, '${widget.apt['id']}', {
        'status': status,
        if (status != 'free') 'buyer_name': _name.text.trim(),
        if (status != 'free' && _phone.text.trim().isNotEmpty) 'buyer_phone': _phone.text.trim(),
        if (status == 'free') 'buyer_name': '',
      });
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.apt;
    final buyer = a['buyer'] as Map?;
    final status = '${a['status']}';
    final lines = <(String, String)>[
      ('Holati', aptStatus(status)),
      ('Qavat / xona', '${a['floor']}-qavat · ${a['rooms']} xona'),
      ('Maydon', '${area(a['area'] as num?)} m²'),
      ('Narx', money(a['price'] as num?)),
      if (a['price_per_m2'] != null) ('1 m² narxi', money(a['price_per_m2'] as num?)),
      if (widget.canSales && buyer != null) ('Xaridor', '${buyer['name']} ${buyer['phone'] ?? ''}'),
      if (widget.canSales && a['paid'] != null && status != 'free') ('To\'langan', money(a['paid'] as num?)),
      if (widget.canSales && a['debt'] != null && status != 'free') ('Qarz', money(a['debt'] as num?)),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kvartira ${a['number']}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [SizedBox(width: 120, child: Text(l.$1, style: TextStyle(color: Theme.of(context).colorScheme.outline))), Expanded(child: Text(l.$2))]),
              ),
            if (widget.canWrite) ...[
              const Divider(height: 32),
              if (status == 'free') ...[
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Xaridor ismi', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _change('booked'), child: const Text('Bron qilish'))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton(onPressed: _busy ? null : () => _change('sold'), child: const Text('Sotish'))),
                ]),
              ] else if (status == 'booked' || status == 'sold')
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(onPressed: _busy ? null : () => _change('free'), child: Text(status == 'booked' ? 'Bronni bekor qilish' : 'Bo\'shatish')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
