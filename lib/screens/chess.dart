import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../format.dart';
import '../l10n.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'objects.dart';

/// Shaxmatka: podyezd × qavat setkasi. Har katakda — xonadon raqami va «xona · m²»;
/// rang — holat (oq: bo'sh, to'q sariq: bron, ko'k: sotilgan), pastki chiziq — to'langan ulush, qizil ramka — muddati o'tgan to'lov.
/// Katak bosilsa — xonadon kartochkasi (3D, bron/sotish, to'lovlar).
class ChessTab extends StatefulWidget {
  const ChessTab({super.key, required this.session});

  final Session session;

  @override
  State<ChessTab> createState() => _ChessTabState();
}

class _ChessTabState extends State<ChessTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _objects = const [];
  String? _object;
  List<Map<String, dynamic>> _apts = const [];
  int? _rooms; // null — hammasi, 0 — tijorat
  String? _status;
  String _q = '';

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final objs = await s.api!.objects();
      if (!mounted) return;
      _objects = objs;
      _object = objs.isEmpty ? null : '${objs.first['id']}';
      await _loadApts();
    } catch (e) {
      await s.handleError(e);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadApts({bool quiet = false}) async {
    final id = _object;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    if (!quiet) setState(() => _loading = true);
    try {
      final all = <Map<String, dynamic>>[];
      var page = 1;
      while (true) {
        final p = await s.api!.apartments(id, page: page, perPage: 200);
        all.addAll(p.items);
        if (!p.meta.hasMore || page >= 30) break;
        page++;
      }
      if (!mounted || id != _object) return;
      setState(() {
        _apts = all;
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

  String get _objectName => '${_objects.where((o) => '${o['id']}' == _object).firstOrNull?['name'] ?? ''}';

  Future<void> _open(Map<String, dynamic> a) async {
    HapticFeedback.selectionClick();
    var full = a;
    try {
      full = await s.api!.apartment(_object!, '${a['id']}');
    } catch (_) {
      // internet yo'q — ro'yxatdagi nusxa bilan ochiladi
    }
    if (!mounted) return;
    showApartmentSheet(context, s, _object!, _objectName, full, onChanged: () => _loadApts(quiet: true));
  }

  bool _match(Map a) {
    if (_rooms != null && (a['rooms'] as num?)?.toInt() != _rooms) return false;
    if (_status != null && a['status'] != _status) return false;
    if (_q.isNotEmpty) {
      final hay = '${a['number']} ${(a['buyer'] as Map?)?['name'] ?? ''} ${(a['buyer'] as Map?)?['phone'] ?? ''}'.toLowerCase();
      if (!hay.contains(_q.toLowerCase())) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_error != null && _apts.isEmpty) return ErrorView(message: _error!, onRetry: _init);
    final roomSet = <int>{for (final a in _apts) (a['rooms'] as num?)?.toInt() ?? 0}.toList()..sort();
    int count(String st) => _apts.where((a) => a['status'] == st).length;

    Widget chip(String t, bool on, VoidCallback f, {Color? dot}) => Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              if (dot != null) ...[Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: cs.outline.withValues(alpha: 0.4)))), const SizedBox(width: 6)],
              Text(t),
            ]),
            selected: on,
            showCheckmark: false,
            onSelected: (_) => f(),
          ),
        );

    final head = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_objects.length > 1)
          Wrap(children: [
            for (final o in _objects)
              chip('${o['name']}', _object == '${o['id']}', () {
                if (_object == '${o['id']}') return;
                setState(() {
                  _object = '${o['id']}';
                  _apts = const [];
                });
                _loadApts();
              }),
          ]),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          chip('Hammasi', _rooms == null, () => setState(() => _rooms = null)),
          for (final r in roomSet.where((r) => r > 0)) chip('$r-xonali', _rooms == r, () => setState(() => _rooms = _rooms == r ? null : r)),
          if (roomSet.contains(0)) chip('Tijorat', _rooms == 0, () => setState(() => _rooms = _rooms == 0 ? null : 0)),
          const SizedBox(width: 6),
          chip("${tr("Bo'sh")} ${count('free')}", _status == 'free', () => setState(() => _status = _status == 'free' ? null : 'free'), dot: Colors.white),
          chip('${tr('Bron')} ${count('booked')}', _status == 'booked', () => setState(() => _status = _status == 'booked' ? null : 'booked'), dot: Brand.orange),
          chip('${tr('Sotilgan')} ${count('sold')}', _status == 'sold', () => setState(() => _status = _status == 'sold' ? null : 'sold'), dot: Brand.blue),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: 260,
              child: TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(
                  hintText: tr('Xonadon №, xaridor yoki telefon'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );

    return RefreshIndicator(
      onRefresh: () => _loadApts(quiet: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: NavInset.listBottom(context) + 12),
        children: [
          head,
          if (_loading)
            const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()))
          else if (_apts.isEmpty)
            const Padding(padding: EdgeInsets.all(48), child: Center(child: Text("Xonadonlar yo'q")))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Glass(
                radius: 26,
                padding: EdgeInsets.all(MediaQuery.sizeOf(context).width >= 900 ? 18 : 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _board(cs),
                  const SizedBox(height: 14),
                  Text(tr("Xonadonni bosing — 3D da bino ichidagi joyi ko'rinadi, u yerdan sotish, bron qilish va to'lov qabul qilish mumkin. Pastki chiziq — qancha to'langani, qizil ramka — to'lov kechikkan."), style: TextStyle(color: cs.outline, fontSize: 12.5)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _board(ColorScheme cs) {
    // (blok, podyezd) bo'yicha guruhlash
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final a in _apts) {
      groups.putIfAbsent('${a['block'] ?? ''}\u0000${a['entrance'] ?? ''}', () => []).add(a);
    }
    final keys = groups.keys.toList()
      ..sort((x, y) {
        final a = x.split('\u0000'), b = y.split('\u0000');
        final c = a[0].compareTo(b[0]);
        if (c != 0) return c;
        return (int.tryParse(a[1]) ?? 0).compareTo(int.tryParse(b[1]) ?? 0);
      });
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final gap = wide ? 8.0 : 5.0, sp = wide ? 22.0 : 12.0;
    final cols = groups.values.map((l) {
      final per = <int, int>{};
      for (final a in l) {
        per.update((a['floor'] as num?)?.toInt() ?? 1, (v) => v + 1, ifAbsent: () => 1);
      }
      return per.values.fold<int>(1, (m, v) => v > m ? v : m);
    }).fold<int>(1, (m, v) => v > m ? v : m);
    return LayoutBuilder(builder: (context, bc) {
      var cw = 52.0;
      if (wide) {
        // podyezdlar bo'sh joyni to'ldiradi, lekin kataklar ixcham qoladi (60–74 px)
        final n = keys.length.clamp(1, 3);
        cw = ((((bc.maxWidth - sp * (n - 1)) / n) - 76) / cols - gap).clamp(60.0, 74.0).toDouble();
      }
      final ch = wide ? (cw * 0.76).clamp(46.0, 56.0).toDouble() : 42.0;
      return Wrap(spacing: sp, runSpacing: sp, children: [
        for (final k in keys) _entrance(cs, k.split('\u0000'), groups[k]!, cw, ch, gap),
      ]);
    });
  }

  Widget _entrance(ColorScheme cs, List<String> key, List<Map<String, dynamic>> list, double cw, double ch, double gap) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final byFloor = <int, List<Map<String, dynamic>>>{};
    for (final a in list) {
      byFloor.putIfAbsent((a['floor'] as num?)?.toInt() ?? 1, () => []).add(a);
    }
    int numOf(Map x) => int.tryParse('${x['number']}'.replaceAll(RegExp(r'\D'), '')) ?? 0;
    for (final f in byFloor.values) {
      f.sort((x, y) => numOf(x).compareTo(numOf(y)));
    }
    final floors = byFloor.keys.toList()..sort((a, b) => b.compareTo(a));
    final title = [if (key[0].isNotEmpty) key[0], if (key[1].isNotEmpty) '${tr('Podyezd')} ${key[1]}'].join(' · ');
    final free = list.where((a) => a['status'] == 'free').length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 8),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: dark ? 0.18 : 0.16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(title.isEmpty ? tr('Xonadonlar') : title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text("$free ${tr("bo'sh")}", style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 11.5)),
            ),
          ]),
        ),
        for (final f in floors)
          Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 24, child: Text('$f', textAlign: TextAlign.center, style: TextStyle(color: cs.outline, fontSize: 12, fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              for (final a in byFloor[f]!) Padding(padding: EdgeInsets.only(right: gap), child: _ChessCell(a: a, w: cw, h: ch, on: _match(a), onTap: () => _open(a))),
            ]),
          ),
      ]),
    );
  }
}

/// Bitta katak: holat rangi, to'langan ulush chizig'i, kechikkan to'lov ramkasi; ustiga kelinsa ko'tariladi.
class _ChessCell extends StatefulWidget {
  const _ChessCell({required this.a, required this.w, required this.h, required this.on, required this.onTap});

  final Map<String, dynamic> a;
  final double w;
  final double h;
  final bool on;
  final VoidCallback onTap;

  @override
  State<_ChessCell> createState() => _ChessCellState();
}

class _ChessCellState extends State<_ChessCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = widget.a;
    final st = '${a['status']}';
    final (g1, g2, border, fg) = switch (st) {
      'sold' => (dark ? const Color(0xFF284A94) : const Color(0xFFE6EFFF), dark ? const Color(0xFF1E3A78) : const Color(0xFFCADBFF), dark ? const Color(0xFF3F66C2) : const Color(0xFFA9C4FF), dark ? const Color(0xFFCFE0FF) : const Color(0xFF1D4FD8)),
      'booked' => (dark ? const Color(0xFF6B4516) : const Color(0xFFFFF0DC), dark ? const Color(0xFF5A3A12) : const Color(0xFFFFDDB8), dark ? const Color(0xFF9A6A2A) : const Color(0xFFFFC184), dark ? const Color(0xFFFFD9AC) : const Color(0xFFB45309)),
      'reserve' => (cs.outline.withValues(alpha: 0.16), cs.outline.withValues(alpha: 0.24), cs.outline.withValues(alpha: 0.3), cs.onSurface.withValues(alpha: 0.55)),
      _ => (dark ? Colors.white.withValues(alpha: 0.10) : Colors.white, dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF4F7FC), cs.outline.withValues(alpha: dark ? 0.3 : 0.26), cs.onSurface),
    };
    final rooms = (a['rooms'] as num?)?.toInt() ?? 0;
    final ar = (a['area'] as num?)?.round() ?? 0;
    final no = '${a['number']}';
    final sub = rooms > 0 ? '$rooms · $ar' : 'K · $ar';
    final owed = (a['owed'] as num?) ?? 0;
    final paid = (a['paid'] as num?) ?? 0;
    final ratio = owed > 0 ? (paid / owed).clamp(0, 1).toDouble() : 0.0;
    final overdue = ((a['overdue'] as num?) ?? 0) > 0;
    final price = (a['price'] as num?) ?? 0;
    final buyer = (a['buyer'] as Map?)?['name'];
    final tip = '${tr('Kv.')} $no · ${rooms > 0 ? '$rooms ${tr('xona')}' : tr('Tijorat')} · ${area(a['area'] as num?)} m²\n${money(price)} ${tr("so'm")} · ${aptStatus(st)}${buyer != null ? '\n$buyer' : ''}';
    final lift = _hover && widget.on;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: widget.on ? 1 : 0.2,
      child: Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: widget.on ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.on ? widget.onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOut,
              width: widget.w,
              height: widget.h,
              transform: Matrix4.translationValues(0, lift ? -2 : 0, 0),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [g1, g2]),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: overdue ? Colors.red.shade500 : (lift ? cs.primary : border), width: overdue || lift ? 1.8 : 1),
                boxShadow: lift ? [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 14, offset: const Offset(0, 6))] : null, // soya faqat ustiga kelganda (90+ katakda doim soya — qimmat)
              ),
              child: Stack(children: [
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(no, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: no.length > 3 ? 12 : 15, height: 1.1)),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(color: fg.withValues(alpha: 0.68), fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.1)),
                  ]),
                ),
                if (ratio > 0)
                  Positioned(
                    left: 7,
                    right: 7,
                    bottom: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Stack(children: [
                        Container(height: 3, color: fg.withValues(alpha: 0.16)),
                        FractionallySizedBox(widthFactor: ratio < 0.06 ? 0.06 : ratio, child: Container(height: 3, color: fg)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
