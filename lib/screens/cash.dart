import 'package:flutter/material.dart' hide Text;


import '../api.dart';
import '../format.dart';
import '../session.dart';
import '../widgets.dart';
import '../theme.dart';
import '../l10n.dart';
import 'cash_form.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key, required this.session});

  final Session session;

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  final _list = GlobalKey<PagedListState>();
  List<Map<String, dynamic>> _desks = const [];
  String? _deskError;
  CashFormData? _form; // kirim/chiqim qo'shish uchun: kassalar, moddalar, ruxsat
  final _page = PageController(viewportFraction: 0.86);
  int _at = 0; // 0 — hamma kassalar, keyin har bir kassa
  int? get _deskId => _at == 0 || _at > _desks.length ? null : (_desks[_at - 1]['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _loadDesks();
    _loadForm();
  }

  Future<void> _loadForm() async {
    try {
      final f = await CashFormData.load(widget.session);
      if (mounted) setState(() => _form = f);
    } catch (_) {/* ruxsat yo'q yoki oflayn — qo'shish tugmasi chiqmaydi */}
  }

  Future<void> _add() async {
    final f = _form;
    if (f == null) return;
    if (await showCashOpForm(context, widget.session, f, deskId: _deskId)) await _refreshAll();
  }

  /// Operatsiyani bosish: tuzatish (oddiy kirim/chiqim) yoki o'chirish (o'tkazma va boshqalar)
  Future<void> _open(Map<String, dynamic> o) async {
    final f = _form;
    if (o['can_edit'] == true && f != null) {
      if (await showCashOpForm(context, widget.session, f, op: o)) await _refreshAll();
    } else if (o['can_delete'] == true) {
      if (!await confirmCashDelete(context, o) || !mounted) return;
      try {
        await widget.session.api!.aSend('DELETE', '/cash/operations/${o['id']}');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr("O'chirildi"))));
        await _refreshAll();
      } catch (e) {
        await widget.session.handleError(e);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : '$e')));
      }
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _loadDesks() async {
    try {
      final d = await widget.session.api!.cashDesks();
      if (mounted) setState(() => _desks = d.where((x) => x['is_active'] != false).toList());
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _deskError = '$e');
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadDesks(), _loadForm(), if (_list.currentState != null) _list.currentState!.reload()]);
  }

  static const _palette = [
    [Color(0xFF0B7A3B), Color(0xFF14A05A)],
    [Color(0xFF2F6FDE), Color(0xFF5B8DEF)],
    [Color(0xFF7B5CE0), Color(0xFF9C84F0)],
    [Color(0xFFE0457B), Color(0xFFF07A9E)],
    [Color(0xFF14A39A), Color(0xFF3CC6BC)],
    [Color(0xFFF27A1A), Color(0xFFF5A04E)],
  ];

  /// Jami: valyuta bo'yicha yig'indi
  Map<String, num> get _totals {
    final m = <String, num>{};
    for (final d in _desks) {
      final c = '${d['currency'] ?? ''}';
      m[c] = (m[c] ?? 0) + ((d['balance'] as num?) ?? 0);
    }
    return m;
  }

  Widget _card({required List<Color> g, required IconData icon, required String title, required String sub, required List<String> amounts, required bool on}) {
    return AnimatedScale(
      scale: on ? 1 : 0.94,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
          boxShadow: on ? [BoxShadow(color: g.first.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 8))] : null,
        ),
        child: Stack(children: [
          Positioned(right: -30, top: -40, child: Container(width: 120, height: 120, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10)))),
          Positioned(right: 30, bottom: -50, child: Container(width: 90, height: 90, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
            ]),
            const Spacer(),
            for (final a in amounts.take(2))
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(a, style: TextStyle(color: Colors.white, fontSize: amounts.length > 1 ? 21 : 26, fontWeight: FontWeight.w900, letterSpacing: -0.4))),
            const SizedBox(height: 4),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
          ),
        ]),
      ),
    );
  }

  IconData _icon(String? kind) => switch (kind) {
        'bank' || 'card' => Icons.credit_card_rounded,
        'cash' => Icons.payments_rounded,
        _ => Icons.account_balance_wallet_rounded,
      };

  Widget _carousel() {
    final pages = <Widget>[
      _card(
        g: const [Color(0xFF10201A), Color(0xFF2B4A3C)],
        icon: Icons.account_balance_rounded,
        title: tr('Hamma kassalar'),
        sub: '${_desks.length} ${tr('ta kassa')} · ${tr('chapga suring')}',
        amounts: [for (final e in _totals.entries) '${money(e.value)} ${e.key}'],
        on: _at == 0,
      ),
      for (var i = 0; i < _desks.length; i++)
        _card(
          g: _palette[i % _palette.length],
          icon: _icon('${_desks[i]['kind']}'),
          title: '${_desks[i]['name']}',
          sub: tr('Bosing: shu kassa operatsiyalari'),
          amounts: ['${money(_desks[i]['balance'] as num?)} ${_desks[i]['currency'] ?? ''}'],
          on: _at == i + 1,
        ),
    ];
    final n = pages.length;
    return Column(children: [
      SizedBox(
        height: 150,
        child: PageView.builder(
          controller: _page,
          itemCount: n,
          onPageChanged: (i) {
            setState(() => _at = i);
            // ro'yxat tanlangan kassa bo'yicha qayta yuklanadi (karusel joyida qoladi)
            WidgetsBinding.instance.addPostFrameCallback((_) => _list.currentState?.reload());
          },
          itemBuilder: (_, i) => pages[i],
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < n; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _at ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: i == _at ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline.withValues(alpha: 0.35)),
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deskName = _deskId == null ? null : '${_desks[_at - 1]['name']}';
    // karusel ro'yxatdan TASHQARIDA: ro'yxat qayta yuklanganda u qayta qurilmaydi va boshiga qaytib ketmaydi
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(children: [
            Expanded(child: const Text('Kassalar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            if (_form?.canAdd == true)
              FilledButton.icon(
                onPressed: _add,
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Kirim / chiqim'),
              ),
            IconButton(onPressed: _refreshAll, icon: const Icon(Icons.refresh)),
          ]),
        ),
        if (_deskError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_deskError!, style: TextStyle(color: cs.error))),
        if (_desks.isNotEmpty) _carousel(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(deskName == null ? tr("So'nggi operatsiyalar") : '${tr("So'nggi operatsiyalar")} · $deskName', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ),
      ],
    );
    return Column(children: [
      head,
      Expanded(child: PagedList(
      key: _list,
      session: widget.session,
      emptyText: "Operatsiyalar yo'q",
      fetch: (p) => widget.session.api!.cashOps(page: p, desk: _deskId),
      itemBuilder: (context, o) {
        final income = o['type'] == 'in';
        final color = income ? Colors.green : Colors.red;
        final title = '${o['category'] ?? (income ? 'Kirim' : 'Chiqim')}';
        final note = '${o['note'] ?? ''}'.trim();
        final tappable = (o['can_edit'] == true && _form != null) || o['can_delete'] == true;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: GestureDetector(
            onTap: tappable ? () => _open(o) : null,
            behavior: HitTestBehavior.opaque,
            child: Glass(
            radius: 18,
            blur: false,
            shadow: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              IconTile(icon: income ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text([formatDate('${o['date']}'), if (_deskId == null && o['desk'] != null) '${o['desk']}', if (note.isNotEmpty) note].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${income ? '+' : '−'}${money(o['amount'] as num?)} ${o['currency'] ?? ''}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13.5)),
                if (tappable) Padding(padding: const EdgeInsets.only(top: 2), child: Icon(o['can_edit'] == true ? Icons.edit_rounded : Icons.delete_outline_rounded, size: 15, color: cs.outline)),
              ]),
            ]),
          ),
          ),
        );
      },
    )),
    ]);
  }
}
