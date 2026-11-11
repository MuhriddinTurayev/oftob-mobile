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
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: _board(cs)),
          if (!_loading && _apts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Text(tr("Xonadon pastidagi chiziq — qancha to'langani. Qizil ramka — to'lov kechikkan. Bron qilish, sotish yoki to'lov qabul qilish uchun xonadonni bosing."), style: TextStyle(color: cs.outline, fontSize: 12.5)),
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
    final gap = wide ? 7.0 : 5.0, sp = wide ? 44.0 : 24.0;
    // katak o'lchami: keng oynada podyezdlar bo'sh joyni to'ldiradi (62–92 px), telefonda — ixcham
    final cols = groups.values.map((l) {
      final per = <int, int>{};
      for (final a in l) {
        per.update((a['floor'] as num?)?.toInt() ?? 1, (v) => v + 1, ifAbsent: () => 1);
      }
      return per.values.fold<int>(1, (m, v) => v > m ? v : m);
    }).fold<int>(1, (m, v) => v > m ? v : m);
    return LayoutBuilder(builder: (context, bc) {
      var cw = wide ? 62.0 : 54.0;
      if (wide) {
        final n = keys.length.clamp(1, 3);
        cw = ((((bc.maxWidth - sp * (n - 1)) / n) - 30) / cols - gap).clamp(62.0, 92.0).toDouble();
      }
      final ch = wide ? (cw * 0.77).clamp(48.0, 70.0).toDouble() : 44.0;
      return Wrap(spacing: sp, runSpacing: 28, children: [
        for (final k in keys) _entrance(cs, k.split('\u0000'), groups[k]!, cw, ch, gap),
      ]);
    });
  }

  Widget _entrance(ColorScheme cs, List<String> key, List<Map<String, dynamic>> list, double cw, double ch, double gap) {
    final byFloor = <int, List<Map<String, dynamic>>>{};
    for (final a in list) {
      byFloor.putIfAbsent((a['floor'] as num?)?.toInt() ?? 1, () => []).add(a);
    }
    for (final f in byFloor.values) {
      f.sort((x, y) => (int.tryParse('${x['number']}'.replaceAll(RegExp(r'\D'), '')) ?? 0).compareTo(int.tryParse('${y['number']}'.replaceAll(RegExp(r'\D'), '')) ?? 0));
    }
    final floors = byFloor.keys.toList()..sort((a, b) => b.compareTo(a));
    final title = [if (key[0].isNotEmpty) key[0], if (key[1].isNotEmpty) '${tr('Podyezd')} ${key[1]}'].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (title.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10, left: 2), child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: cs.onSurface.withValues(alpha: 0.8)))),
      for (final f in floors)
        Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 22, child: Text('$f', textAlign: TextAlign.center, style: TextStyle(color: cs.outline, fontSize: 12, fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            for (final a in byFloor[f]!)
              Padding(padding: EdgeInsets.only(right: gap), child: _cell(cs, a, cw, ch)),
          ]),
        ),
    ]);
  }

  Widget _cell(ColorScheme cs, Map<String, dynamic> a, double w, double h) {
    final st = '${a['status']}';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = switch (st) {
      'sold' => (dark ? const Color(0xFF1E3A78) : const Color(0xFFD3E2FF), dark ? const Color(0xFFBFD6FF) : const Color(0xFF1D4FD8)),
      'booked' => (dark ? const Color(0xFF5A3A12) : const Color(0xFFFFE6C8), dark ? const Color(0xFFFFD2A1) : const Color(0xFFB45309)),
      'reserve' => (cs.outline.withValues(alpha: 0.16), cs.onSurface.withValues(alpha: 0.6)),
      _ => (dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.92), cs.onSurface),
    };
    final rooms = (a['rooms'] as num?)?.toInt() ?? 0;
    final ar = (a['area'] as num?)?.round() ?? 0;
    final no = '${a['number']}';
    final sub = rooms > 0 ? '$rooms·$ar' : 'K·$ar';
    final owed = (a['owed'] as num?) ?? 0;
    final paid = (a['paid'] as num?) ?? 0;
    final ratio = owed > 0 ? (paid / owed).clamp(0, 1).toDouble() : 0.0;
    final overdue = ((a['overdue'] as num?) ?? 0) > 0;
    final on = _match(a);
    final price = (a['price'] as num?) ?? 0;
    final tip = '${tr('Kv.')} $no · ${rooms > 0 ? '$rooms ${tr('xona')}' : tr('Tijorat')} · ${area(a['area'] as num?)} m²\n${money(price)} ${tr("so'm")} · ${aptStatus(st)}${(a['buyer'] as Map?)?['name'] != null ? '\n${(a['buyer'] as Map)['name']}' : ''}';
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: on ? 1 : 0.22,
      child: Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 350),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: on ? () => _open(a) : null,
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: overdue ? Colors.red.shade600 : (st == 'free' ? cs.outline.withValues(alpha: 0.28) : Colors.transparent), width: overdue ? 2 : 1),
              ),
              child: Stack(children: [
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(no, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: no.length > 3 ? 12 : (w > 75 ? 17 : 14.5), height: 1.1)),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: w > 75 ? 11.5 : 10.5, fontWeight: FontWeight.w600, height: 1.1)),
                  ]),
                ),
                if (ratio > 0)
                  Positioned(left: 6, right: 6, bottom: 3, child: ClipRRect(borderRadius: BorderRadius.circular(2), child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: ratio, child: Container(height: 3, color: Brand.blue))))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
