import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../desktop_web.dart';
import '../documents.dart';
import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../webcache.dart';
import '../widgets.dart';
import 'deal.dart';
import 'tour.dart';
import '../l10n.dart';

Color statusColor(String? s) => switch (s) {
      'free' => Brand.green,
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
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(12, 12, 12, NavInset.listBottom(context)),
          children: [
            DeskGrid(minColumn: 470, maxColumns: 3, gap: 12, children: [
          for (var i = 0; i < objects.length; i++)
          Builder(builder: (context) {
            final o = objects[i];
            final a = (o['apartments'] as Map?) ?? const {};
            final progress = ((o['progress'] as num?) ?? 0).toInt();
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(
                  context,
                  DeskRoute<void>(builder: (_) => ApartmentsScreen(session: session, object: o)),
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
                        StatusChip('Bo\'sh ${a['free'] ?? 0}', Brand.green),
                        StatusChip('Bron ${a['booked'] ?? 0}', Colors.orange),
                        StatusChip('Sotilgan ${a['sold'] ?? 0}', Colors.red),
                        StatusChip('Jami ${a['total'] ?? 0}', Colors.blueGrey),
                      ]),
                    ],
                  ),
                ),
              ),
            );
          }),
            ]),
          ],
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
                hintText: tr('Kvartira raqami yoki xaridor'),
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
                // to'lanishi kerak: bo'lib to'lash foiz bilan bo'lsa — jadval summasi (sayt bilan bir xil)
                final owed = (((a['owed'] as num?) ?? 0) > 0 ? a['owed'] as num : price);
                return GlassRow(onTap: () => showApartmentSheet(context, widget.session, _objectId, '${widget.object['name']}', a, onChanged: _reload), child: Row(children: [
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
                            ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: (paid / owed).clamp(0, 1).toDouble(), minHeight: 4)),
                          ],
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(money(price), style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        StatusChip(aptStatus(st), statusColor(st)),
                      ]),
                    ]));
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
  // kompyuter: pastdan chiqadigan varaq o'rniga ekran o'rtasidagi chiroyli oyna
  if (Platform.isWindows && MediaQuery.sizeOf(context).width >= 1120) {
    // keng oyna: chapda — 3D da bino ichidagi joyi (saytdagidek), o'ngda — xonadon kartochkasi
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (dc) {
        final sz = MediaQuery.sizeOf(dc);
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: (sz.width - 48).clamp(0, 1280).toDouble(),
            height: (sz.height - 48).clamp(0, 800).toDouble(),
            child: Row(children: [
              Expanded(flex: 11, child: _LocatePane(session: session, objectId: objectId, apartmentId: '${apt['id']}')),
              Container(width: 1, color: Theme.of(dc).colorScheme.outline.withValues(alpha: 0.2)),
              Expanded(
                flex: 8,
                child: Stack(children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: ApartmentSheet(session: session, objectId: objectId, objectName: objectName, apt: apt, onChanged: onChanged ?? () {}, desk: true),
                  ),
                  Positioned(top: 10, right: 10, child: IconButton.filledTonal(onPressed: () => Navigator.of(dc).pop(), icon: const Icon(Icons.close_rounded), tooltip: tr('Yopish'))),
                ]),
              ),
            ]),
          ),
        );
      },
    );
    return;
  }
  if (Platform.isWindows && MediaQuery.sizeOf(context).width >= 900) {
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (dc) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 760,
          // bo'sh xonadon — ixcham oyna; sotilgan/bron — to'lovlar jadvali uchun balandroq
          height: ('${apt['status']}' == 'free' ? 500.0 : 4000.0).clamp(0, MediaQuery.sizeOf(dc).height * 0.88).toDouble(),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: ApartmentSheet(session: session, objectId: objectId, objectName: objectName, apt: apt, onChanged: onChanged ?? () {}, desk: true),
            ),
            Positioned(top: 10, right: 10, child: IconButton.filledTonal(onPressed: () => Navigator.of(dc).pop(), icon: const Icon(Icons.close_rounded), tooltip: tr('Yopish'))),
          ]),
        ),
      ),
    );
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ApartmentSheet(session: session, objectId: objectId, objectName: objectName, apt: apt, onChanged: onChanged ?? () {}),
  );
}

/// Xonadon oynasining chap tomoni: «Uyda joyi» — bino 3D modelida xonadon belgilangan (saytdagi bilan bir xil sahifa; kesh orqali internetsiz ham ochiladi).
class _LocatePane extends StatefulWidget {
  const _LocatePane({required this.session, required this.objectId, required this.apartmentId});

  final Session session;
  final String objectId;
  final String apartmentId;

  @override
  State<_LocatePane> createState() => _LocatePaneState();
}

class _LocatePaneState extends State<_LocatePane> {
  String? _url;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await WebCache.viewUrl(widget.session, widget.objectId, 'locate', apartment: widget.apartmentId);
      if (mounted) setState(() => _url = u);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_url != null) return DesktopWeb(url: _url!);
    return ColoredBox(
      color: const Color(0xFF111418),
      child: Center(
        child: _error != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.apartment_rounded, size: 44, color: cs.outline),
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.outline))),
              ])
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class ApartmentSheet extends StatefulWidget {
  const ApartmentSheet({super.key, required this.session, required this.objectId, required this.objectName, required this.apt, required this.onChanged, this.desk = false});

  /// Kompyuter oynasi ichida (surib yuqoriga chiqariladigan varaq emas)
  final bool desk;

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
  late final _price = TextEditingController(text: fmtInput(widget.apt['price'] as num?));
  bool _busy = false;

  bool get _canWrite => widget.session.me!.can('sales:write');
  bool get _canSales => widget.session.me!.can('sales:read');

  /// Sotuvchi uchun: bitimni boshqa xodim rasmiylashtirgan — shartnoma va chekni u yoki buxgalter beradi (sayt qoidasi)
  bool get _foreign {
    final a = widget.apt;
    final me = widget.session.me!;
    final st = '${a['status']}';
    return me.role == 'manager' && widget.session.userId > 0 && (st == 'sold' || st == 'booked') && a['via_bot'] != true && (a['seller_id'] as num?)?.toInt() != widget.session.userId;
  }

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

  /// Sotish / bron — to'liq shakl (muddat, boshlang'ich to'lov, foiz, shartnoma) alohida ekranda
  Future<void> _openDeal() async {
    var done = false;
    await Navigator.of(context).push(DeskRoute<void>(
      builder: (_) => DealScreen(session: widget.session, objectId: widget.objectId, apt: widget.apt, onDone: () {
        done = true;
        widget.onChanged();
      }),
    ));
    if (done && mounted) Navigator.pop(context);
  }

  /// Shartnoma yoki chek PDF — telefondagi ko'rgichda ochiladi; share=true — ulashish (xaridorga yuborish)
  void _doc(String kind, {String? id, required String name, bool share = false}) {
    openDocument(context, widget.session, objectId: widget.objectId, apartmentId: '${widget.apt['id']}', kind: kind, id: id, fileName: name, share: share);
  }

  void _tour(String view, String title) {
    Navigator.of(context).push(DeskRoute<void>(
      full: true, // kompyuterda: yon panelda emas, butun ish maydonida
      builder: (_) => TourScreen(session: widget.session, objectId: widget.objectId, view: view, title: title, apartment: '${widget.apt['id']}'),
    ));
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// To'lov qabul qilish: summa (ko'pincha keyingi to'lov), sana, usul. Server kassaga o'tkazadi va chek yaratadi.
  Future<void> _pay() async {
    final a = widget.apt;
    final next = a['next'] as Map?;
    final debt = (a['debt'] as num?) ?? 0;
    final suggest = next != null ? math.min(debt, (next['amount'] as num)) : debt;
    final amount = TextEditingController(text: fmtInput(suggest));
    var date = DateTime.now();
    String method = '';
    List<Map<String, dynamic>> methods = const [];
    try {
      methods = await widget.session.api!.payMethods();
    } catch (_) {}
    if (!mounted) return;
    var queuedPay = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('To\'lov qabul qilish', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text('Kvartira ${a['number']} · ${(a['buyer'] as Map?)?['name'] ?? ''}', style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
              const SizedBox(height: 4),
              Text('Qarz: ${money(debt)} so\'m', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Summa (so\'m)'))),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(ctx).colorScheme.outlineVariant)),
                leading: const Icon(Icons.event),
                title: Text('Sana: ${formatDate(_iso(date))}'),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now());
                  if (d != null) set(() => date = d);
                },
              ),
              if (methods.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final m in methods)
                    ChoiceChip(
                      label: Text('${m['label']}'),
                      selected: method == '${m['value']}',
                      onSelected: (v) => set(() => method = v ? '${m['value']}' : ''),
                    ),
                ]),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                icon: const Icon(Icons.payments),
                label: const Text('To\'lovni qabul qilish'),
                onPressed: () async {
                  final v = num.tryParse(amount.text.replaceAll(RegExp(r'[^0-9.]'), ''));
                  if (v == null || v < 1) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Summani kiriting')));
                    return;
                  }
                  try {
                    final res = await widget.session.api!.apartmentPay(widget.objectId, '${a['id']}', amount: v, date: _iso(date), method: method);
                    queuedPay = res['queued'] == true;
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    await widget.session.handleError(e);
                    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      widget.onChanged();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(queuedPay ? "Offline saqlandi — internet paydo bo'lganda avtomatik yuboriladi" : "To'lov qabul qilindi va kassaga o'tkazildi")));
    }
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
    final owed = (((a['owed'] as num?) ?? 0) > 0 ? a['owed'] as num : price); // foiz bilan jami (sayt bilan bir xil)
    final payments = ((a['payments'] as List?) ?? const []).whereType<Map>().toList().reversed.toList();
    final phone = '${buyer?['phone'] ?? ''}'.trim();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: widget.desk ? 1 : 0.8,
      maxChildSize: widget.desk ? 1 : 0.95,
      minChildSize: widget.desk ? 1 : 0.45,
      builder: (ctx, ctl) => ListView(
        controller: ctl,
        padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + MediaQuery.of(context).viewInsets.bottom),
        children: [
          Row(children: [
            Expanded(child: Text('Kvartira ${a['number']}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
            if (a['pending'] == true) const Padding(padding: EdgeInsets.only(right: 6), child: StatusChip('Yuborilmagan', Colors.orange)),
            StatusChip(aptStatus(st), statusColor(st)),
            if (widget.desk) const SizedBox(width: 46), // yopish tugmasi uchun joy
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
                if (owed > price + 0.5)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('${tr("Bo'lib to'lash foizi bilan jami")}: ${money(owed)} so\'m', style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.8), fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: (paid / owed).clamp(0, 1).toDouble(), minHeight: 8)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('To\'langan ${money(paid)}', style: TextStyle(color: Brand.green, fontWeight: FontWeight.w700, fontSize: 13))),
                  Text('Qarz ${money(debt)}', style: TextStyle(color: debt > 0 ? cs.error : cs.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _tour('3d', 'Kvartira ${a['number']} — 3D / 360°'), icon: const Icon(Icons.view_in_ar_outlined), label: const Text('3D / 360°'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: () => _tour('locate', 'Uydagi joylashuvi'), icon: const Icon(Icons.apartment_outlined), label: const Text('Uyda joyi'))),
          ]),
          if (_canWrite && (st == 'booked' || st == 'sold') && debt > 0) ...[
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _busy ? null : _pay, icon: const Icon(Icons.payments), label: const Text('To\'lov qabul qilish')),
          ],
          if (_canSales && ((a['overdue'] as num?) ?? 0) > 0)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, color: cs.error),
                const SizedBox(width: 10),
                Expanded(child: Text('Muddati o\'tgan qarz: ${money(a['overdue'] as num?)} so\'m', style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w700))),
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
          if (_foreign) ...[
            const SizedBox(height: 16),
            GlassRow(
              margin: EdgeInsets.zero,
              tint: Colors.orange.withValues(alpha: 0.14),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: Colors.orange.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${tr('Bu bitimni boshqa xodim rasmiylashtirgan')}${'${a['seller'] ?? ''}'.isEmpty ? '' : ' (${a['seller']})'}. ${tr('Shartnoma va chekni u yoki buxgalter beradi.')}',
                    style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ]),
            ),
          ],
          if (_canWrite && !_foreign && st == 'sold') ...[
            const SizedBox(height: 16),
            Text('Hujjatlar', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => _doc('contract', name: 'Shartnoma-${a['number']}'), icon: const Icon(Icons.description_outlined), label: const Text('Shartnoma (PDF)'))),
              const SizedBox(width: 8),
              IconButton.outlined(tooltip: tr('Ulashish'), onPressed: () => _doc('contract', name: 'Shartnoma-${a['number']}', share: true), icon: const Icon(Icons.ios_share)),
            ]),
          ],
          if (_canSales && ((a['schedule'] as List?) ?? const []).isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('To\'lov grafigi', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            for (final r in ((a['schedule'] as List).whereType<Map>()))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(r['paid'] == true ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: r['paid'] == true ? Brand.green : cs.outline),
                  const SizedBox(width: 10),
                  Expanded(child: Text(formatDate('${r['date']}'), style: TextStyle(color: r['paid'] == true ? cs.outline : null, fontWeight: (a['next'] as Map?)?['date'] == r['date'] ? FontWeight.w800 : FontWeight.w500))),
                  Text(money(r['amount'] as num?), style: TextStyle(fontWeight: FontWeight.w700, color: r['paid'] == true ? cs.outline : null)),
                ]),
              ),
          ],
          if (_canSales && payments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('To\'lovlar (${payments.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            for (final p in payments.take(20))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 16, backgroundColor: Brand.green.withValues(alpha: 0.12), foregroundColor: Brand.green, child: const Icon(Icons.south_west, size: 16)),
                title: Text('+${money(p['amount'] as num?)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${formatDate('${p['date']}')}${p['method'] != null && '${p['method']}'.isNotEmpty ? ' · ${p['method']}' : ''}'),
                trailing: _canWrite && !_foreign
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: tr('Chek'), onPressed: () => _doc('receipt', id: '${p['id']}', name: 'Chek-${a['number']}-${p['id']}'), icon: const Icon(Icons.receipt_long_outlined)),
                        IconButton(tooltip: tr('Ulashish'), onPressed: () => _doc('receipt', id: '${p['id']}', name: 'Chek-${a['number']}-${p['id']}', share: true), icon: const Icon(Icons.ios_share, size: 20)),
                      ])
                    : null,
                onTap: _canWrite && !_foreign ? () => _doc('receipt', id: '${p['id']}', name: 'Chek-${a['number']}-${p['id']}') : null,
              ),
          ],
          if (_canWrite) ...[
            const Divider(height: 36),
            if (st == 'free' && a['can_sell'] == false)
              // obyekt hali sotuvga qo'yilmagan yoki narxi yo'q: sotish tugmasi yo'q, sababi aniq yoziladi (sayt qoidasi)
              GlassRow(
                margin: const EdgeInsets.only(bottom: 12),
                tint: Colors.orange.withValues(alpha: 0.14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.lock_clock_rounded, color: Colors.orange.shade700),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${a['sale_block'] ?? tr("Bu xonadonni hozircha sotib bo'lmaydi")}', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w700, fontSize: 13))),
                ]),
              ),
            if (st == 'free' && a['can_sell'] != false) ...[
              FilledButton.icon(onPressed: _busy ? null : _openDeal, icon: const Icon(Icons.key), label: const Text('Sotish / bron qilish')),
            ] else if (st == 'booked') ...[
              FilledButton(onPressed: _busy ? null : _openDeal, child: const Text('Sotishga o\'tkazish')),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _busy ? null : () => _change('free'), child: const Text('Bronni bekor qilish')),
            ] else if (st == 'sold')
              OutlinedButton(
                onPressed: _busy ? null : () => _change('free'),
                style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                child: const Text('Bo\'shatish'),
              ),
            if (st == 'free') ...[
              const SizedBox(height: 20),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: TextField(controller: _price, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Narx (so\'m)'), border: OutlineInputBorder()))),
                const SizedBox(width: 12),
                SizedBox(height: 56, child: FilledButton.tonal(onPressed: _busy ? null : _savePrice, child: const Text('Saqlash'))),
              ]),
            ],
          ],
        ],
      ),
    );
  }
}
