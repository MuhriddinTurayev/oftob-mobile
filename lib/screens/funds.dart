import 'dart:io';

import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../format.dart';
import '../offline.dart';
import '../session.dart';
import '../upload.dart';
import '../widgets.dart';
import '../theme.dart';
import '../motion.dart';
import '../l10n.dart';

num _n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);
String _cur(Object? c) => '$c'.trim().toLowerCase() == 'сум' ? "so'm" : '${c ?? ''}';
String _kind(Object? k) => k == 'card' ? 'Karta' : 'Naqd';
List<Map<String, dynamic>> _list(Object? v) => (v is List ? v : const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

/// Kameradan yoki galereyadan chek surati
Future<XFile?> pickReceipt(BuildContext context) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Kamera bilan suratga olish'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galereyadan tanlash'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (src == null) return null;
  try {
    return await ImagePicker().pickImage(source: src, maxWidth: 1700, imageQuality: 78);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Suratni ochib bo\'lmadi. Ilovaga kamera/galereya ruxsatini bering.')));
    return null;
  }
}

/// Mahsulot suratlari: kameradan bitta yoki galereyadan bir nechta (ko'pi bilan [max])
Future<List<XFile>> pickGoods(BuildContext context, {int max = 8}) async {
  if (max <= 0) return const [];
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Kamera bilan suratga olish'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galereyadan tanlash'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (src == null) return const [];
  try {
    if (src == ImageSource.camera) {
      final f = await ImagePicker().pickImage(source: src, maxWidth: 1700, imageQuality: 78);
      return f == null ? const [] : [f];
    }
    final l = await ImagePicker().pickMultiImage(maxWidth: 1700, imageQuality: 78);
    return l.take(max).toList();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Suratni ochib bo\'lmadi. Ilovaga kamera/galereya ruxsatini bering.')));
    return const [];
  }
}

/// Formadagi bitta mahsulot surati: tanlanishi bilan serverga yuklanadi
class _GoodsPic {
  _GoodsPic(this.file);
  final XFile file;
  String? upId;
  bool uploading = true;
  String? error;
}

/// Hisobotdagi mahsulot suratlari (serverdan): kichik rasmlar qatori, bosilsa katta ko'rinadi
class GoodsStrip extends StatelessWidget {
  const GoodsStrip({super.key, required this.api, required this.op, required this.count});
  final ApiClient api;
  final int op;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _GoodsView(api: api, op: op, count: count, start: i))),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 92, height: 92, child: _GoodsPicNet(api: api, op: op, i: i, fit: BoxFit.cover))),
        ),
      ),
    );
  }
}

class _GoodsPicNet extends StatelessWidget {
  const _GoodsPicNet({required this.api, required this.op, required this.i, this.fit});
  final ApiClient api;
  final int op;
  final int i;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>?>(
      future: api.goodsBytes(op, i),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
        final b = snap.data;
        if (b == null) return Container(color: Colors.black12, child: const Icon(Icons.broken_image_outlined, color: Colors.grey));
        return Image.memory(Uint8List.fromList(b), fit: fit ?? BoxFit.contain, width: double.infinity, height: double.infinity);
      },
    );
  }
}

class _GoodsView extends StatelessWidget {
  const _GoodsView({required this.api, required this.op, required this.count, required this.start});
  final ApiClient api;
  final int op;
  final int count;
  final int start;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Mahsulot surati')),
      body: PageView.builder(
        controller: PageController(initialPage: start),
        itemCount: count,
        itemBuilder: (_, i) => InteractiveViewer(maxScale: 6, child: Center(child: _GoodsPicNet(api: api, op: op, i: i))),
      ),
    );
  }
}

/// Prorab puli: prorab uchun — o'z balansi, pul so'rash, xarid hisoboti (chek bilan); rahbar/buxgalter uchun — barcha prorablar.
class FundsScreen extends StatefulWidget {
  const FundsScreen({super.key, required this.session});

  final Session session;

  @override
  State<FundsScreen> createState() => _FundsScreenState();
}

class _FundsScreenState extends State<FundsScreen> {
  Key _key = UniqueKey();
  int? _user;
  String? _status;
  int _lastPending = Offline.pending.value;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    Offline.pending.addListener(_onQueue);
  }

  @override
  void dispose() {
    Offline.pending.removeListener(_onQueue);
    super.dispose();
  }

  /// Navbat bo'shaganda (offline xaridlar yuborilganda) ma'lumot yangilanadi
  void _onQueue() {
    final n = Offline.pending.value;
    if (n < _lastPending && mounted) _reload();
    _lastPending = n;
  }

  void _reload() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) {
    return FutureBody<Map<String, dynamic>>(
      key: _key,
      session: s,
      load: () => s.api!.funds(user: _user, status: _status),
      builder: (context, d, reload) {
        final cur = _cur(d['currency']);
        return d['mode'] == 'holder' ? _holder(context, d, cur) : _boss(context, d, cur);
      },
    );
  }

  /* ================= prorab ================= */

  Widget _holder(BuildContext context, Map<String, dynamic> d, String cur) {
    final cs = Theme.of(context).colorScheme;
    final me = Map<String, dynamic>.from(d['me'] as Map);
    final reqs = _list(d['requests']);
    final ops = _list(d['ops']);
    final noRc = _n(me['no_receipt']).toInt();
    // yuborilmagan (offline) xaridlar balansdan ayirib ko'rsatiladi
    final pendCash = Offline.pendingSpend('cash'), pendCard = Offline.pendingSpend('card');
    me['cash'] = _n(me['cash']) - pendCash;
    me['card'] = _n(me['card']) - pendCard;
    me['total'] = _n(me['total']) - pendCash - pendCard;
    final pend = Offline.ops.where((o) => o.kind == 'spend' || o.kind == 'request').toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
      children: [
        HeroGlass(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Mening pullarim', style: TextStyle(color: cs.outline, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            CountUp(value: _n(me['total']), builder: (_, v) => Text('${money(v)} $cur', style: TextStyle(color: context.ink, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8))),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 8, children: [
              _chipStat('Naqd', money(_n(me['cash']))),
              _chipStat('Karta', money(_n(me['card']))),
              _chipStat('Shu oy sarfladim', money(_n(me['month']))),
            ]),
          ]),
        ),
        if (noRc > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Shu oy $noRc ta xarid cheksiz topshirilgan — iloji bo\'lsa chekni keyinroq qo\'shing.', style: TextStyle(color: Colors.orange.shade800, fontSize: 13)),
          ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PurchaseScreen(session: s, data: d)));
                if (ok == true) _reload();
              },
              icon: const Icon(Icons.receipt_long),
              label: const Text('Xarid hisoboti'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _requestSheet(context, d),
              icon: const Icon(Icons.request_quote_outlined),
              label: const Text('Pul so\'rash'),
            ),
          ),
        ]),
        if (pend.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _Title('Yuborilmagan (offline)'),
          for (final o in pend)
            Card(
              child: ListTile(
                leading: Icon(o.kind == 'spend' ? Icons.receipt_long : Icons.request_quote_outlined, color: Colors.orange.shade800),
                title: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(o.state == 'failed' ? (o.error ?? '') : 'Internet paydo bo\'lganda yuboriladi${o.file != null ? ' · chek surati bor' : ''}'),
                trailing: o.state == 'failed' ? const StatusChip('Xato', Colors.red) : const StatusChip('Navbatda', Colors.orange),
              ),
            ),
        ],
        if (reqs.isNotEmpty) ...[
          const SizedBox(height: 22),
          const _Title('So\'rovlarim'),
          for (var i = 0; i < reqs.length; i++) Reveal(index: i.clamp(0, 9), child: _requestTile(context, reqs[i], cur, mine: true)),
        ],
        const SizedBox(height: 22),
        const _Title('Berilgan va sarflangan pul'),
        if (ops.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Hali operatsiya yo\'q'))),
        for (var i = 0; i < ops.length; i++) Reveal(index: i.clamp(0, 9), child: _opTile(context, ops[i], cur, boss: false)),
      ],
    );
  }

  Widget _chipStat(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: context.pill, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pillBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ', style: TextStyle(color: context.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(color: context.ink, fontSize: 13.5, fontWeight: FontWeight.w900)),
        ]),
      );

  Widget _requestTile(BuildContext context, Map<String, dynamic> r, String cur, {required bool mine, bool manage = false}) {
    final st = '${r['status']}';
    final (label, color) = switch (st) {
      'new' => ('Javob kutilmoqda', Colors.orange.shade800),
      'issued' => ('Berildi', Colors.green.shade700),
      _ => ('Rad etildi', Colors.red.shade700),
    };
    final obj = '${r['object'] ?? ''}';
    final cs = Theme.of(context).colorScheme;
    // har bir qator o'z balandligini saqlaydi: kartalar bir xil o'lchamda bo'ladi (matn yo'q bo'lsa ham bo'sh joy qoladi)
    Widget line(String t, {TextStyle? style}) => SizedBox(height: 19, child: Align(alignment: Alignment.centerLeft, child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)));
    final note = '${r['note'] ?? ''}';
    final reply = '${r['reply'] ?? ''}';
    return GlassRow(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 30,
            child: Row(children: [
              Expanded(child: Text(mine ? '${money(_n(r['amount']))} $cur · ${_kind(r['kind'])}' : '${r['name']} — ${money(_n(r['amount']))} $cur', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              StatusChip(label, color),
            ]),
          ),
          line(mine ? obj : '${_kind(r['kind'])}${obj.isEmpty ? '' : ' · $obj'}'),
          line(note),
          line(reply.isEmpty ? '' : 'Javob: $reply', style: TextStyle(color: Colors.red.shade700)),
          line(formatDate('${r['created_at']}'), style: TextStyle(color: cs.outline, fontSize: 12)),
          if (mine && st == 'new')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  try {
                    final queued = await s.api!.fundsAct('f_cancel', '/funds/request/${r['id']}/cancel', {}, label: "So'rovni qaytarib olish", refId: '${r['id']}');
                    if (queued) _toast("Offline saqlandi — internet paydo bo'lganda yuboriladi");
                    _reload();
                  } catch (e) {
                    _toast('$e');
                  }
                },
                child: const Text('Qaytarib olish'),
              ),
            ),
          if (manage && st == 'new')
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _declineDialog(r), child: const Text('Rad etish'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: () => _issueSheet(context, _lastData!, holder: r['user_id'] as int?, amount: _n(r['amount']), kind: '${r['kind']}'), child: const Text('Pul berish'))),
            ]),
      ]),
    );
  }

  Map<String, dynamic>? _lastData;

  Future<void> _declineDialog(Map<String, dynamic> r) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('So\'rovni rad etish'),
        content: TextField(controller: c, decoration: InputDecoration(labelText: tr('Sabab (ixtiyoriy)'))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rad etish'))],
      ),
    );
    if (ok != true) return;
    try {
      final queued = await s.api!.fundsAct('f_decline', '/funds/request/${r['id']}/decline', {'reply': c.text.trim()}, label: "So'rovni rad etish — ${r['name'] ?? ''}", refId: '${r['id']}');
      if (queued) _toast("Offline saqlandi — internet paydo bo'lganda yuboriladi");
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Widget _opTile(BuildContext context, Map<String, dynamic> o, String cur, {required bool boss}) {
    final cs = Theme.of(context).colorScheme;
    final fund = '${o['fund']}';
    final spend = fund == 'spend';
    final isIn = '${o['type']}' == 'in';
    final color = spend ? Colors.red.shade700 : Colors.green.shade700;
    final st = o['status'];
    final (stLabel, stColor) = switch (st) {
      'checked' => ('Tekshirildi', Colors.green.shade700),
      'rejected' => ('Qaytarildi', Colors.red.shade700),
      'pending' => ('Tekshirilmagan', Colors.orange.shade800),
      _ => ('', Colors.grey),
    };
    final title = spend ? ('${o['note'] ?? ''}'.isEmpty ? 'Xarid' : '${o['note']}') : (fund == 'return' ? 'Qaytarilgan pul' : 'Pul berildi');
    final who = boss && o['holder'] is Map ? '${(o['holder'] as Map)['name']} · ' : '';
    // hamma kartalar bir xil balandlikda (chekli xaridlar ham, oddiy kirimlar ham): sarlavha va tavsif bir qatorda, belgilar alohida qatorda
    return GlassRow(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => _opSheet(context, o, cur, boss: boss),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: SizedBox(
        height: 74,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          IconTile(icon: spend ? Icons.shopping_cart_outlined : (isIn ? Icons.south_west_rounded : Icons.north_east_rounded), color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text('$who${formatDate('${o['date']}')}${'${o['object'] ?? ''}'.isNotEmpty ? ' · ${o['object']}' : ''} · ${_kind(o['kind'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
              if (spend)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    height: 24,
                    child: ListView(scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(), children: [
                      StatusChip(stLabel, stColor),
                      const SizedBox(width: 6),
                      if (o['pending'] == true) ...[const StatusChip('Yuborilmagan', Colors.orange), const SizedBox(width: 6)],
                      if (o['has_receipt'] == true) StatusChip('Chek bor', Colors.blueGrey) else StatusChip("Chek yo'q", Colors.deepOrange),
                      if (((o['photos'] as num?) ?? 0) > 0) StatusChip('${tr('Mahsulot surati')}: ${o['photos']}', Colors.teal),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          Text('${spend ? '−' : (isIn ? '+' : '−')}${money(_n(o['amount']))}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)),
        ]),
      ),
    );
  }

  Future<void> _opSheet(BuildContext context, Map<String, dynamic> o, String cur, {required bool boss}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _OpSheet(session: s, op: o, cur: cur, boss: boss),
    );
    if (changed == true) _reload();
  }

  Future<void> _requestSheet(BuildContext context, Map<String, dynamic> d) async {
    final projects = _list(d['projects']);
    final amount = TextEditingController();
    final note = TextEditingController();
    var kind = 'cash';
    String? object = projects.length == 1 ? '${projects.first['id']}' : null;
    var queuedReq = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Pul so\'rash', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('So\'rov buxgalter va rahbarga Telegram orqali ham boradi.'),
              const SizedBox(height: 14),
              TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Summa'))),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'cash', label: Text('Naqd')), ButtonSegment(value: 'card', label: Text('Kartaga'))],
                selected: {kind},
                onSelectionChanged: (v) => set(() => kind = v.first),
              ),
              if (projects.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: object,
                  decoration: InputDecoration(labelText: tr('Qaysi obyekt uchun')),
                  items: [for (final p in projects) DropdownMenuItem(value: '${p['id']}', child: Text('${p['name']}'))],
                  onChanged: (v) => set(() => object = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(controller: note, decoration: InputDecoration(labelText: tr('Nimaga kerak (masalan: sement, armatura)')), maxLines: 2),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final a = num.tryParse(amount.text.replaceAll(' ', ''));
                  if (a == null || a < 1) return;
                  try {
                    queuedReq = await s.api!.fundsRequest(amount: a, kind: kind, object: object, note: note.text);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
                child: const Text('Yuborish'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) {
      _toast(queuedReq ? "Offline saqlandi — internet paydo bo'lganda yuboriladi" : "So'rov yuborildi");
      _reload();
    }
  }

  /* ================= rahbar / buxgalter ================= */

  Widget _boss(BuildContext context, Map<String, dynamic> d, String cur) {
    _lastData = d;
    final cs = Theme.of(context).colorScheme;
    final holders = _list(d['holders']);
    final reqs = _list(d['requests']);
    final ops = _list(d['ops']);
    final manage = d['can_manage'] == true;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
      children: [
        HeroGlass(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Prorablar qo\'lidagi pul', style: TextStyle(color: cs.outline, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                CountUp(value: _n(d['total']), builder: (_, v) => Text('${money(v)} $cur', style: TextStyle(color: context.ink, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6))),
              ]),
            ),
            if (manage) FilledButton(onPressed: () => _issueSheet(context, d), child: const Text('Pul berish')),
          ]),
        ),
        if (reqs.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Title('Pul so\'rovlari (${reqs.length})'),
          for (var i = 0; i < reqs.length; i++) Reveal(index: i.clamp(0, 9), child: _requestTile(context, reqs[i], cur, mine: false, manage: manage)),
        ],
        const SizedBox(height: 20),
        const _Title('Prorablar'),
        for (final h in holders)
          Card(
            color: _user == h['user_id'] ? cs.primaryContainer : null,
            child: ListTile(
              onTap: () {
                _user = _user == h['user_id'] ? null : h['user_id'] as int;
                _reload();
              },
              title: Text('${h['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Naqd ${money(_n(h['cash']))} · Karta ${money(_n(h['card']))}\nShu oy sarflagan: ${money(_n(h['month']))}${_n(h['no_receipt']) > 0 ? ' · cheksiz: ${h['no_receipt']}' : ''}'),
              isThreeLine: true,
              trailing: Text(money(_n(h['total'])), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.primary)),
            ),
          ),
        const SizedBox(height: 16),
        const _Title('Operatsiyalar'),
        Wrap(spacing: 8, children: [
          for (final f in const [(null, 'Hammasi'), ('pending', 'Tekshirilmagan'), ('norc', 'Cheksiz')])
            ChoiceChip(
              label: Text(f.$2),
              selected: _status == f.$1,
              onSelected: (_) {
                _status = f.$1;
                _reload();
              },
            ),
        ]),
        const SizedBox(height: 8),
        if (ops.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Operatsiya topilmadi'))),
        for (var i = 0; i < ops.length; i++) Reveal(index: i.clamp(0, 9), child: _opTile(context, ops[i], cur, boss: true)),
      ],
    );
  }

  Future<void> _issueSheet(BuildContext context, Map<String, dynamic> d, {int? holder, num? amount, String? kind}) async {
    final holders = _list(d['holders']);
    final sources = _list(d['sources']);
    final amountC = TextEditingController(text: amount != null ? fmtInput(amount) : '');
    final noteC = TextEditingController();
    int? who = holder ?? (holders.length == 1 ? holders.first['user_id'] as int : null);
    var k = kind ?? 'cash';
    int? from = sources.isNotEmpty ? sources.first['id'] as int : null;
    var queuedIssue = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Prorabga pul berish', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: who,
                decoration: InputDecoration(labelText: tr('Prorab')),
                items: [for (final h in holders) DropdownMenuItem(value: h['user_id'] as int, child: Text('${h['name']}'))],
                onChanged: (v) => set(() => who = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: from,
                decoration: InputDecoration(labelText: tr('Qaysi kassadan')),
                items: [for (final x in sources) DropdownMenuItem(value: x['id'] as int, child: Text('${x['name']}', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => set(() => from = v),
              ),
              const SizedBox(height: 12),
              TextField(controller: amountC, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Summa'))),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'cash', label: Text('Naqd')), ButtonSegment(value: 'card', label: Text('Kartaga'))],
                selected: {k},
                onSelectionChanged: (v) => set(() => k = v.first),
              ),
              const SizedBox(height: 12),
              TextField(controller: noteC, decoration: InputDecoration(labelText: tr('Izoh (ixtiyoriy)'))),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final a = num.tryParse(amountC.text.replaceAll(' ', ''));
                  if (who == null || from == null || a == null || a < 1) return;
                  try {
                    final name = holders.where((h) => h['user_id'] == who).map((h) => '${h['name']}').firstOrNull ?? '';
                    queuedIssue = await s.api!.fundsAct('f_issue', '/funds/issue', {'user_id': who, 'kind': k, 'from_desk': from, 'amount': a, if (noteC.text.trim().isNotEmpty) 'note': noteC.text.trim()}, label: 'Pul berish — $name ${a.round()}');
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
                child: const Text('Berish'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) {
      _toast(queuedIssue ? "Offline saqlandi — internet paydo bo'lganda beriladi (kassa qoldig'i o'sha payt tekshiriladi)" : 'Pul berildi');
      _reload();
    }
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)));
}

/// Operatsiya tafsiloti: chek surati, nima sotib olingan va qayerga qo'yilgan, tekshirish
class _OpSheet extends StatefulWidget {
  const _OpSheet({required this.session, required this.op, required this.cur, required this.boss});

  final Session session;
  final Map<String, dynamic> op;
  final String cur;
  final bool boss;

  @override
  State<_OpSheet> createState() => _OpSheetState();
}

class _OpSheetState extends State<_OpSheet> {
  bool _busy = false;
  final _up = UploadTracker();
  bool _adding = false; // chek yuklanmoqda (tugma ichida foiz)

  @override
  void dispose() {
    _up.dispose();
    super.dispose();
  }

  Map<String, dynamic> get o => widget.op;

  // mahsulot suratlari soni (keyin qo'shilsa — shu oynada yangilanadi)
  late int _photos = (o['photos'] as num?)?.toInt() ?? 0;
  bool _addingGoods = false;

  Future<void> _addGoods() async {
    final files = await pickGoods(context, max: 8 - _photos);
    if (files.isEmpty || !mounted) return;
    setState(() => _addingGoods = true);
    try {
      final n = await widget.session.api!.fundsAddPhotos(o['id'] as int, [for (final f in files) f.path]);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _photos = n);
      o['photos'] = n;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Mahsulot surati qo\'shildi — rahbar va buxgalter ko\'radi'))));
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : '$e')));
    } finally {
      if (mounted) setState(() => _addingGoods = false);
    }
  }

  Future<void> _run(Future<Object?> Function() fn) async {
    setState(() => _busy = true);
    try {
      final res = await fn();
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        if (res == true) messenger.showSnackBar(const SnackBar(content: Text("Offline saqlandi — internet paydo bo'lganda yuboriladi")));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _reject() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hisobotni qaytarish'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Pul prorabga qaytadi, materiallar ombordan chiqariladi.'),
          const SizedBox(height: 10),
          TextField(controller: c, decoration: InputDecoration(labelText: tr('Sabab'))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Qaytarish'))],
      ),
    );
    if (ok != true || c.text.trim().isEmpty) return;
    await _run(() => widget.session.api!.fundsAct('f_reject', '/funds/${o['id']}/reject', {'reason': c.text.trim()}, label: 'Hisobotni qaytarish #${o['id']}', refId: '${o['id']}'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final api = widget.session.api!;
    final spend = o['fund'] == 'spend';
    final items = (o['items'] is List ? o['items'] as List : const []).whereType<Map>().toList();
    final st = o['status'];
    final canManage = widget.boss && spend && widget.session.me!.can('funds:write') && ['admin', 'accountant', 'cashier'].contains(widget.session.me!.role);
    final mine = !widget.boss && spend && st == 'pending';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${money(_n(o['amount']))} ${widget.cur}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text([
            formatDate('${o['date']}'),
            if (o['holder'] is Map) '${(o['holder'] as Map)['name']}',
            if ('${o['object'] ?? ''}'.isNotEmpty) '${o['object']}',
            _kind(o['kind']),
          ].join(' · '), style: TextStyle(color: cs.outline)),
          if ('${o['note'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${o['note']}', style: const TextStyle(fontSize: 16))),
          if ('${o['vendor'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Qayerdan: ${o['vendor']}')),
          if (st == 'rejected') Padding(padding: const EdgeInsets.only(top: 10), child: Text('Qaytarilgan: ${o['reject_reason']}', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Omborga kirgan materiallar', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('• ${it['name']}: ${_n(it['qty'])} ${it['unit'] ?? ''} × ${money(_n(it['price']))} = ${money(_n(it['qty']) * _n(it['price']))}${'${it['warehouse'] ?? ''}'.isNotEmpty ? '\n   → ${it['warehouse']}' : ''}'),
              ),
          ],
          if (spend) ...[
            const SizedBox(height: 14),
            if (o['has_receipt'] == true)
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ReceiptView(api: api, id: o['id'] as int))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _ReceiptPic(api: api, id: o['id'] as int, height: 220, fit: BoxFit.cover),
                ),
              )
            else
              Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: const Text('Chek surati yo\'q')),
            if (_photos > 0) ...[
              const SizedBox(height: 14),
              Text('${tr('Mahsulot suratlari')} · $_photos', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              GoodsStrip(key: ValueKey('gs$_photos'), api: api, op: o['id'] as int, count: _photos),
            ],
          ],
          const SizedBox(height: 16),
          if (mine && o['has_receipt'] != true)
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final f = await pickReceipt(context);
                      if (f == null) return;
                      setState(() => _adding = true);
                      _up.start();
                      await _run(() async {
                        try {
                          await api.fundsAddReceipt(o['id'] as int, f.path, onProgress: _up.onBytes);
                          _up.finish();
                        } finally {
                          _up.stop();
                          if (mounted) setState(() => _adding = false);
                        }
                        return null;
                      });
                    },
              icon: _adding ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Icon(Icons.add_a_photo),
              label: _adding
                  ? ValueListenableBuilder<double>(valueListenable: _up.progress, builder: (_, p, _) => Text('${tr('Chek yuklanmoqda')}… ${(p * 100).round()}%'))
                  : const Text('Chek qo\'shish'),
            ),
          if (mine && _photos < 8) ...[
            if (o['has_receipt'] != true) const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy || _addingGoods ? null : _addGoods,
              icon: _addingGoods ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_addingGoods ? '${tr('Yuklanmoqda')}…' : tr('Mahsulot suratini qo\'shish')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
            const SizedBox(height: 8),
          ],
          if (canManage && st != 'rejected') ...[
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(() => api.fundsAct('f_check', '/funds/${o['id']}/check', {'checked': st != 'checked'}, label: st == 'checked' ? 'Tekshiruv belgisini olish #${o['id']}' : 'Tekshirildi #${o['id']}', refId: '${o['id']}')),
              icon: Icon(st == 'checked' ? Icons.undo : Icons.check_circle),
              label: Text(st == 'checked' ? 'Tekshirilgan belgisini olish' : 'Tekshirildi'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _reject,
              icon: const Icon(Icons.keyboard_return),
              label: const Text('Hisobotni qaytarish'),
              style: OutlinedButton.styleFrom(foregroundColor: cs.error, minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ReceiptView extends StatelessWidget {
  const _ReceiptView({required this.api, required this.id});

  final ApiClient api;
  final int id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Chek')),
      body: InteractiveViewer(maxScale: 6, child: Center(child: _ReceiptPic(api: api, id: id))),
    );
  }
}

/// Chek surati: serverdan (shaxsiy kalit bilan) yoki telefondagi saqlangan nusxadan
class _ReceiptPic extends StatelessWidget {
  const _ReceiptPic({required this.api, required this.id, this.height, this.fit});

  final ApiClient api;
  final int id;
  final double? height;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>?>(
      future: api.receiptBytes(id),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return SizedBox(height: height ?? 160, child: const Center(child: CircularProgressIndicator()));
        final b = snap.data;
        if (b == null) return const Padding(padding: EdgeInsets.all(20), child: Text("Chek suratini yuklab bo'lmadi (offline'da faqat oldin ko'rilganlari bor)", style: TextStyle(color: Colors.grey)));
        return Image.memory(Uint8List.fromList(b), height: height, width: double.infinity, fit: fit ?? BoxFit.contain);
      },
    );
  }
}

/// Xarid hisoboti: nima, qayerdan, qancha, chek surati; materiallar — omborga kiritiladi
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key, required this.session, required this.data});

  final Session session;
  final Map<String, dynamic> data;

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _Line {
  final name = TextEditingController();
  final qty = TextEditingController();
  final price = TextEditingController();
  String unit = '';
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  late final List<Map<String, dynamic>> _projects = _list(widget.data['projects']);
  late final List<Map<String, dynamic>> _warehouses = _list(widget.data['warehouses']);
  late final List<Map<String, dynamic>> _units = _list(widget.data['units']);
  final _what = TextEditingController();
  final _vendor = TextEditingController();
  final _amount = TextEditingController();
  final _lines = <_Line>[];
  late final List<Map<String, dynamic>> _currencies = _list(widget.data['currencies']);
  late String _curCode = '${widget.data['base_currency'] ?? ''}';
  String _kindV = 'cash';
  String? _object;
  int? _wh;
  XFile? _photo;
  bool _noReceipt = false;
  bool _busy = false;
  String? _formErr; // xato sababi yuborish tugmasi ustida doimiy ko'rinadi
  DateTime _date = DateTime.now();

  // chek surati tanlanishi bilan serverga yuklanadi; tugagach «yuborish» tugmasi faollashadi
  final _up = UploadTracker();
  String? _upId; // serverdagi yuklama raqami
  bool _uploading = false;
  bool _upOffline = false; // internet yo'q: rasm telefonda saqlanadi, hisobot bilan keyin ketadi
  String? _upErr;
  int _upGen = 0; // eski yuklama javobi yangi rasmni bosib ketmasin

  // mahsulot suratlari (olib kelingan narsa): har biri tanlanishi bilan yuklanadi
  final _goods = <_GoodsPic>[];
  bool get _goodsBusy => _goods.any((g) => g.uploading);

  Future<void> _addGoodsPics() async {
    final files = await pickGoods(context, max: 8 - _goods.length);
    if (files.isEmpty || !mounted) return;
    final add = [for (final f in files) _GoodsPic(f)];
    setState(() {
      _goods.addAll(add);
      _formErr = null;
    });
    for (final g in add) {
      _uploadGoods(g);
    }
  }

  Future<void> _uploadGoods(_GoodsPic g) async {
    setState(() {
      g.uploading = true;
      g.error = null;
    });
    try {
      final id = await widget.session.api!.fundsReceiptUpload(g.file.path);
      if (!mounted) return;
      setState(() {
        g.upId = id;
        g.uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        g.uploading = false;
        g.error = e is ApiException && e.isNetwork ? tr("Internet yo'q — hisobotdan keyin qo'shing") : (e is ApiException ? e.message : '$e');
      });
    }
  }

  @override
  void dispose() {
    _up.dispose();
    super.dispose();
  }

  Future<void> _setPhoto(XFile? f) async {
    final gen = ++_upGen;
    setState(() {
      _photo = f;
      _upId = null;
      _upErr = null;
      _upOffline = false;
      _uploading = f != null;
      _formErr = null;
    });
    if (f == null) {
      _up.stop();
      return;
    }
    _up.start();
    try {
      final id = await widget.session.api!.fundsReceiptUpload(f.path, onProgress: _up.onBytes);
      if (!mounted || gen != _upGen) return;
      _up.finish();
      HapticFeedback.lightImpact();
      setState(() {
        _upId = id;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted || gen != _upGen) return;
      _up.stop();
      final net = e is ApiException && e.isNetwork;
      setState(() {
        _uploading = false;
        _upOffline = net && Offline.enabled; // internet yo'q — hisobot bilan birga keyin yuboriladi
        _upErr = _upOffline ? null : (e is ApiException ? e.message : '$e');
      });
    }
  }

  /// Chek tayyormi: yuklangan, yoki internet yo'q (telefonda saqlanadi), yoki chek kerak emas
  bool get _receiptReady => _noReceipt || (_photo != null && (_upId != null || _upOffline));

  @override
  void initState() {
    super.initState();
    if (_projects.isNotEmpty) _object = '${_projects.first['id']}';
    final me = Map<String, dynamic>.from(widget.data['me'] as Map);
    if (_n(me['cash']) <= 0 && _n(me['card']) > 0) _kindV = 'card';
    _syncWh();
  }

  void _syncWh() {
    final w = _warehouses.where((e) => '${e['object_id']}' == _object).toList();
    _wh = w.isNotEmpty ? w.first['id'] as int : (_warehouses.isNotEmpty ? _warehouses.first['id'] as int : null);
  }

  /// Taxminiy summa kompaniya valyutasida (yuborilmagan xarid balansdan ayirib ko'rsatilishi uchun)
  num _estimate(bool hasLines, num? amount) {
    final v = hasLines && _linesTotal > 0 ? _linesTotal : (amount ?? 0);
    final rate = _n(_currencies.firstWhere((c) => '${c['code']}' == _curCode, orElse: () => const {'rate': 1})['rate']);
    return v * (_curCode == '${widget.data['base_currency'] ?? ''}' ? 1 : (rate > 0 ? rate : 1));
  }

  String get _iso => '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  num get _linesTotal => _lines.fold<num>(0, (a, l) => a + (num.tryParse(l.qty.text.replaceAll(',', '.')) ?? 0) * (num.tryParse(l.price.text.replaceAll(' ', '')) ?? 0));

  Future<void> _submit() async {
    final s = widget.session;
    final named = _lines.where((l) => l.name.text.trim().isNotEmpty).toList();
    final hasLines = named.isNotEmpty;
    final amount = num.tryParse(_amount.text.replaceAll(' ', ''));
    String? err;
    if (_object == null) {
      err = 'Obyektni tanlang';
    } else if (!hasLines && (amount == null || amount < 1) ) {
      err = 'Summani yozing yoki materiallarni kiriting';
    } else if (!hasLines && _what.text.trim().isEmpty) {
      err = 'Nima sotib olinganini yozing';
    } else if (hasLines && _wh == null) {
      err = 'Materiallar uchun ombor tanlang';
    } else if (hasLines && named.any((l) => (num.tryParse(l.qty.text.replaceAll(',', '.')) ?? 0) <= 0)) {
      err = 'Har bir material uchun miqdorni yozing';
    } else if (_photo != null && !_noReceipt && _uploading) {
      err = 'Chek hali yuklanmoqda — biroz kuting';
    } else if (_photo != null && !_noReceipt && !_receiptReady) {
      err = 'Chek yuklanmadi — qayta urinib ko\'ring';
    } else if (_photo == null && !_noReceipt) {
      err = 'Chek suratini qo\'shing yoki "Chek yo\'q" ni belgilang';
    } else if (_goodsBusy) {
      err = 'Mahsulot suratlari hali yuklanmoqda — biroz kuting';
    }
    if (err != null) {
      HapticFeedback.heavyImpact();
      setState(() => _formErr = err);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() {
      _busy = true;
      _formErr = null;
    });
    try {
      final res = await s.api!.fundsSpend(
        kind: _kindV,
        object: _object!,
        date: _iso,
        what: _what.text,
        vendor: _vendor.text,
        amount: hasLines && _linesTotal > 0 ? null : amount,
        warehouse: _wh,
        lines: [
          for (final l in named) {'name': l.name.text.trim(), 'qty': l.qty.text.replaceAll(',', '.'), 'unit': l.unit, 'price': l.price.text.replaceAll(' ', '')},
        ],
        receiptPath: _noReceipt ? null : _photo?.path,
        noReceipt: _noReceipt,
        currency: _curCode == '${widget.data['base_currency'] ?? ''}' ? null : _curCode,
        estimate: _estimate(hasLines, amount),
        receiptUpload: _noReceipt ? null : _upId,
        photoUploads: [for (final g in _goods) if (g.upId != null) g.upId!],
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final queued = res['queued'] == true;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(queued ? Icons.cloud_off : Icons.check_circle, color: queued ? Colors.orange : Colors.green, size: 48),
          title: Text(queued ? 'Offline saqlandi' : 'Hisobot yuborildi'),
          content: Text(queued ? "Internet yo'q — hisobot va chek surati telefonda saqlandi. Internet paydo bo'lganda avtomatik yuboriladi va rahbar bilan buxgalterga xabar boradi. Balansdan hozirdan ayirib ko'rsatiladi." : 'Xarid hisobotingiz rahbar va buxgalterga yuborildi. Pul balansingizdan yechildi.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Yaxshi'))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      await s.handleError(e);
      if (mounted) {
        final m = e is ApiException ? e.message : '$e';
        setState(() {
          _busy = false;
          _formErr = m;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = Map<String, dynamic>.from(widget.data['me'] as Map);
    final baseLabel = _cur(widget.data['currency']);
    final foreign = _curCode.isNotEmpty && _curCode != '${widget.data['base_currency'] ?? ''}';
    final cur = foreign ? _curCode : baseLabel;
    final rate = _n(_currencies.firstWhere((c) => '${c['code']}' == _curCode, orElse: () => const {'rate': 1})['rate']);
    final foreignTotal = (_lines.isEmpty || _linesTotal <= 0) ? (num.tryParse(_amount.text.replaceAll(' ', '')) ?? 0) : _linesTotal;
    return Scaffold(
      appBar: AppBar(title: const Text('Xarid hisoboti')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Text('Qo\'limdagi pul: naqd ${money(_n(me['cash']))}, karta ${money(_n(me['card']))} $cur', style: TextStyle(color: cs.outline)),
          const SizedBox(height: 14),
          if (_projects.length > 1)
            DropdownButtonFormField<String>(
              initialValue: _object,
              decoration: InputDecoration(labelText: tr('Qaysi obyekt')),
              items: [for (final p in _projects) DropdownMenuItem(value: '${p['id']}', child: Text('${p['name']}'))],
              onChanged: (v) => setState(() {
                _object = v;
                _syncWh();
              }),
            )
          else if (_projects.length == 1)
            Text('Obyekt: ${_projects.first['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'cash', label: Text('Naqd puldan')), ButtonSegment(value: 'card', label: Text('Kartadan'))],
            selected: {_kindV},
            onSelectionChanged: (v) => setState(() => _kindV = v.first),
          ),
          if (_currencies.length > 1) ...[
            const SizedBox(height: 14),
            Text('Xarid valyutasi', style: TextStyle(color: cs.outline, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final c in _currencies) ChoiceChip(label: Text('${c['code']}'), selected: _curCode == '${c['code']}', onSelected: (_) => setState(() => _curCode = '${c['code']}')),
            ]),
          ],
          const SizedBox(height: 12),
          TextField(controller: _what, decoration: InputDecoration(labelText: tr('Nima sotib olindi'))),
          const SizedBox(height: 12),
          TextField(controller: _vendor, decoration: InputDecoration(labelText: tr('Qayerdan (bozor, do\'kon nomi)'))),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: cs.outlineVariant)),
            leading: const Icon(Icons.event),
            title: Text('Sana: ${formatDate(_iso)}'),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 60)), lastDate: DateTime.now());
              if (d != null) setState(() => _date = d);
            },
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Text('Omborga kiradigan materiallar', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            TextButton.icon(
              onPressed: () => setState(() => _lines.add(_Line()..unit = _units.isNotEmpty ? '${_units.first['value']}' : '')),
              icon: const Icon(Icons.add),
              label: const Text('Qo\'shish'),
            ),
          ]),
          if (_lines.isEmpty) Text('Material olgan bo\'lsangiz qo\'shing — u omborga avtomatik kiradi. Aks holda faqat summani yozing.', style: TextStyle(color: cs.outline, fontSize: 13)),
          for (var i = 0; i < _lines.length; i++) _lineCard(i),
          if (_lines.isNotEmpty && _warehouses.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _wh,
              decoration: InputDecoration(labelText: tr('Qaysi omborga')),
              items: [for (final w in _warehouses) DropdownMenuItem(value: w['id'] as int, child: Text('${w['name']}'))],
              onChanged: (v) => setState(() => _wh = v),
            ),
          ],
          const SizedBox(height: 14),
          if (_lines.isEmpty || _linesTotal <= 0)
            TextField(controller: _amount, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Jami summa ($cur)')), onChanged: (_) => setState(() {}))
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
              child: Text('Jami: ${money(_linesTotal)} $cur (miqdor × narx)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          if (foreign)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('≈ ${money(foreignTotal * rate)} $baseLabel · joriy kurs: 1 $_curCode = ${money(rate)} $baseLabel — balansdan shu kurs bo\'yicha yechiladi', style: TextStyle(color: cs.outline, fontSize: 13)),
            ),
          const SizedBox(height: 20),
          Text('Chek surati', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (_photo != null && !_noReceipt)
            _ReceiptPreview(
              file: _photo!,
              tracker: _up,
              uploading: _uploading,
              done: _upId != null,
              offline: _upOffline,
              error: _upErr,
              onRemove: () => _setPhoto(null),
              onRetry: () => _setPhoto(_photo),
              onReplace: () async {
                final f = await pickReceipt(context);
                if (f != null) _setPhoto(f);
              },
            )
          else
            OutlinedButton.icon(
              onPressed: _noReceipt
                  ? null
                  : () async {
                      final f = await pickReceipt(context);
                      if (f != null) _setPhoto(f);
                    },
              icon: const Icon(Icons.photo_camera),
              label: const Text('Chekni suratga olish'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Chek yo\'q (bozor)'),
            value: _noReceipt,
            onChanged: (v) => setState(() => _noReceipt = v),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text('Mahsulot suratlari', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Text('${_goods.length}/8', style: TextStyle(color: cs.outline, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text('Olib kelgan narsangizni suratga oling — rahbar chek bilan birga ko\'radi (ixtiyoriy).', style: TextStyle(color: cs.outline, fontSize: 13)),
          const SizedBox(height: 8),
          if (_goods.isNotEmpty)
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _goods.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final g = _goods[i];
                  return Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(g.file.path), width: 96, height: 96, fit: BoxFit.cover)),
                    if (g.uploading)
                      Positioned.fill(child: Container(decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12)), child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))))),
                    if (g.error != null)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () => _uploadGoods(g),
                          child: Container(
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.refresh_rounded, color: Colors.white),
                          ),
                        ),
                      ),
                    if (g.upId != null) const Positioned(left: 4, bottom: 4, child: Icon(Icons.check_circle, color: Colors.lightGreenAccent, size: 20)),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _goods.removeAt(i)),
                        child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), padding: const EdgeInsets.all(3), child: const Icon(Icons.close, color: Colors.white, size: 16)),
                      ),
                    ),
                  ]);
                },
              ),
            ),
          if (_goods.any((g) => g.error != null))
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(_goods.firstWhere((g) => g.error != null).error!, style: TextStyle(color: cs.error, fontSize: 12.5))),
          if (_goods.length < 8)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: _addGoodsPics,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Mahsulotni suratga olish'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_formErr != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(color: cs.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.error.withValues(alpha: 0.4))),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, color: cs.error, size: 19),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_formErr!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700, fontSize: 13))),
                  ]),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ValueListenableBuilder<double>(
                valueListenable: _up.progress,
                builder: (context, p, _) {
                  final waiting = !_noReceipt && _photo != null && _uploading;
                  return FilledButton(
                    onPressed: (_busy || waiting || (!_noReceipt && _photo != null && !_receiptReady)) ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : waiting
                            ? Text('${tr('Chek yuklanmoqda')}… ${(p * 100).round()}%')
                            : const Text('Rahbar va buxgalterga yuborish'),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _lineCard(int i) {
    final l = _lines[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(child: TextField(controller: l.name, decoration: InputDecoration(labelText: tr('Material nomi')))),
            IconButton(onPressed: () => setState(() => _lines.removeAt(i)), icon: const Icon(Icons.delete_outline)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: l.qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Miqdor')), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: DropdownButtonFormField<String>(
                initialValue: _units.any((u) => '${u['value']}' == l.unit) ? l.unit : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Birlik')),
                items: [for (final u in _units) DropdownMenuItem(value: '${u['value']}', child: Text('${u['label']}'))],
                onChanged: (v) => setState(() => l.unit = v ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: l.price, keyboardType: TextInputType.number, inputFormatters: const [ThousandsFormatter()], decoration: InputDecoration(labelText: tr('Narxi (1 birlik)')), onChanged: (_) => setState(() {}))),
          ]),
        ]),
      ),
    );
  }
}


/// Chek surati: tanlangach yumshoq chiqadi, ustida yuklanish foizi; tugagach «Yuklandi» belgisi.
class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({required this.file, required this.tracker, required this.uploading, required this.done, required this.offline, required this.error, required this.onRemove, required this.onRetry, required this.onReplace});

  final XFile file;
  final UploadTracker tracker;
  final bool uploading;
  final bool done;
  final bool offline;
  final String? error;
  final VoidCallback onRemove;
  final VoidCallback onRetry;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 190,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(fit: StackFit.expand, children: [
          Image.file(
            File(file.path),
            fit: BoxFit.cover,
            cacheWidth: 900,
            frameBuilder: (context, child, frame, sync) => AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 300), child: child),
          ),
          // yuklanayotganda: qora parda va o'rtada foiz
          AnimatedOpacity(
            opacity: uploading || error != null ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !(uploading || error != null),
              child: ColoredBox(
                color: const Color(0x8C000000),
                child: Center(
                  child: error != null
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 30),
                          const SizedBox(height: 6),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(error!, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Qayta urinish')),
                        ])
                      : ValueListenableBuilder<double>(
                          valueListenable: tracker.progress,
                          builder: (context, p, _) => TweenAnimationBuilder<double>(
                            tween: Tween(end: p),
                            duration: const Duration(milliseconds: 260),
                            builder: (context, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                              SizedBox(
                                width: 70,
                                height: 70,
                                child: Stack(alignment: Alignment.center, children: [
                                  SizedBox.expand(child: CircularProgressIndicator(value: v, strokeWidth: 6, strokeCap: StrokeCap.round, color: Colors.white, backgroundColor: Colors.white24)),
                                  Text('${(v * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                                ]),
                              ),
                              const SizedBox(height: 8),
                              const Text('Chek yuklanmoqda', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                ),
              ),
            ),
          ),
          // holat belgisi: yuklandi / internet yo'q
          Positioned(
            left: 10,
            bottom: 10,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
              child: done
                  ? _badge(Icons.check_circle_rounded, 'Yuklandi', Colors.green.shade600, key: 'ok')
                  : offline
                      ? _badge(Icons.cloud_off_rounded, "Internet yo'q — telefonda saqlanadi", Colors.orange.shade700, key: 'off')
                      : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Row(children: [
              IconButton.filledTonal(onPressed: uploading ? null : onReplace, icon: const Icon(Icons.photo_camera_rounded), tooltip: tr('Boshqa rasm')),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: onRemove, icon: const Icon(Icons.close), style: IconButton.styleFrom(backgroundColor: cs.error)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _badge(IconData i, String t, Color c, {required String key}) => Container(
        key: ValueKey(key),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
      );
}
