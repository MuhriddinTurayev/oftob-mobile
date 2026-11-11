import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/widgets.dart' as w show Text;

import 'package:flutter/services.dart';

import '../assistant.dart' show AiBubble;
import '../format.dart';
import '../pulse.dart';
import '../session.dart';
import '../widgets.dart';
import '../theme.dart';
import '../l10n.dart';
import 'checkin_map.dart';
import 'tg_link.dart';

/// Davomat: kim ishga keldi, kim ishda, kim ketdi, kim kelmadi — obyektlar bo'yicha.
/// Hisob veb-dasturdagi "Kim ishga keldi" bilan bir xil (server hisoblaydi). Prorab faqat o'z ishchilarini ko'radi.
/// Belgilash huquqi bor bo'lsa (rahbar/prorab, faqat bugun): qatordagi tugma yoki uzoq bosib ko'plab tanlash.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.session});

  final Session session;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

enum _Filter { all, came, working, absent }

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  _Filter _filter = _Filter.all;
  String? _object; // null — hamma obyektlar
  String _q = '';

  /// Ixcham ko'rinish: obyektlar yig'iq (sarlavhada sonlar), uzun guruhlar dastlab 5 ta bilan
  final Set<String> _openSites = {};
  final Set<String> _openGroups = {};
  bool _officeAll = false;
  static const _peek = 5;

  /// Qidiruv yoki filtr bor — hammasi ochiq ko'rinadi
  bool get _focused => _q.isNotEmpty || _filter != _Filter.all || _object != null;
  final _selected = <String>{}; // "obyekt|xodim"
  bool _busy = false;

  /// Hozirgina belgilanganlar ("obyekt|xodim" → in/out): qator bir necha soniya yashil/kulrang yonib turadi
  final Map<String, String> _flash = {};
  Timer? _flashT;

  /// Hozir yuborilayotganlar — o'sha qator tugmasida aylanuvchi belgi
  final Set<String> _pending = {};

  /// Har bir qatorning kaliti — belgilangandan keyin «Ko'rish» shu qatorga olib boradi
  final Map<String, GlobalKey> _keys = {};

  @override
  void dispose() {
    Pulse.attendance.removeListener(_onPulse);
    Pulse.shift.removeListener(_onPulse);
    _flashT?.cancel();
    super.dispose();
  }

  String _nameOf(String site, String id) {
    for (final x in _sites) {
      if ('${x['id']}' != site) continue;
      for (final w in ((x['workers'] as List?) ?? const []).whereType<Map>()) {
        if ('${w['id']}' == id) return '${w['name']}';
      }
    }
    return '';
  }

  /// Belgilangan qatorga ekranni olib borish
  void _reveal(String k) {
    final c = _keys[k]?.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic, alignment: 0.3);
  }

  Session get s => widget.session;
  bool get _isToday {
    final n = DateTime.now();
    return _date.year == n.year && _date.month == n.month && _date.day == n.day;
  }

  String get _dateStr => '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
    Pulse.attendance.addListener(_onPulse);
    Pulse.shift.addListener(_onPulse);
  }

  void _onPulse() {
    if (mounted && _isToday && !_busy) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = _data == null;
        _error = null;
      });
    }
    try {
      final d = await s.api!.attendance(date: _dateStr);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
        _error = null;
        _selected.clear();
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

  void _shift(int days) {
    final n = _date.add(Duration(days: days));
    if (n.isAfter(DateTime.now())) return;
    HapticFeedback.selectionClick();
    setState(() {
      _date = n;
      _data = null;
    });
    _load();
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2024), lastDate: DateTime.now());
    if (p == null) return;
    setState(() {
      _date = p;
      _data = null;
    });
    _load();
  }

  List<Map<String, dynamic>> get _sites => ((_data?['sites'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  bool get _canMark => _data?['can_mark'] == true;

  List<Map<String, dynamic>> get _office => ((_data?['office'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  /// «Men ishga keldim» bosgan prorablar va ofis xodimlari: kelgan/ketgan vaqt va joylashuv (xaritada ochiladi).
  /// Kengligi yetarli bo'lsa qatorlar 2–3 ustunda (kompyuter), aks holda bitta ro'yxat (ajratgichlar bilan)
  Widget _cols(List<Widget> items, ColorScheme cs) => LayoutBuilder(builder: (context, bc) {
        final cols = ((bc.maxWidth + 28) / (380 + 28)).floor().clamp(1, 3);
        if (cols == 1) {
          return Column(children: [
            for (var k = 0; k < items.length; k++) ...[
              if (k > 0) Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
              items[k],
            ],
          ]);
        }
        final w = (bc.maxWidth - 28 * (cols - 1)) / cols;
        return Wrap(spacing: 28, children: [for (final i in items) SizedBox(width: w, child: i)]);
      });

  Widget _officeBlock(ColorScheme cs) {    final came = _office.where((o) => o['status'] != 'none').length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Glass(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Prorablar va ofis xodimlari', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            Text('$came/${_office.length}', style: TextStyle(color: cs.outline, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          ...() {
            // avval kelganlar, keyin kelmaganlar; ko'p bo'lsa — dastlab bir qismi
            final list = [..._office]..sort((a, b) => (a['status'] == 'none' ? 1 : 0) - (b['status'] == 'none' ? 1 : 0));
            final all = _officeAll || _focused || list.length <= _peek + 1;
            final shown = all ? list : list.take(_peek).toList();
            return [
              _cols([for (final o in shown) _officeRow(o, cs)], cs),
              if (!all) _moreButton(list.length - shown.length, cs, () => setState(() => _officeAll = true)),
            ];
          }(),
        ]),
      ),
    );
  }

  Widget _officeRow(Map<String, dynamic> o, ColorScheme cs) {
    final st = '${o['status']}';
    final lat = o['in_lat'] as num?;
    final lng = o['in_lng'] as num?;
    final dist = o['in_dist'] as num?;
    final (label, color) = switch (st) {
      'working' => ('Ishda', Brand.teal),
      'left' => ('Ketdi', Colors.blueGrey),
      _ => ('Kelmadi', cs.error),
    };
    final since = shiftMoment(o, 'in');
    final until = st == 'working' ? DateTime.now() : shiftMoment(o, 'out');
    final worked = (st == 'none' || since == null || until == null) ? '' : durationText(until.difference(since));
    final times = st == 'none' ? '' : '${o['in'] ?? ''}${o['out'] != null ? ' – ${o['out']}' : ''}${st == 'working' ? ' · ${tr('dan beri')}' : ''}${worked.isEmpty ? '' : ' · $worked'}';
    final where = st == 'none'
        ? ''
        : (lat == null ? tr('joylashuvsiz') : (dist == null ? tr('joylashuv bor') : (dist <= 300 ? '${tr('obyektda')} · ${distLabel(dist)}' : tr('Obyektdan :d uzoqda').replaceAll(':d', distLabel(dist)))));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        CircleAvatar(radius: 18, backgroundColor: color.withValues(alpha: 0.14), foregroundColor: color, child: Text('${o['name']}'.isEmpty ? '?' : '${o['name']}'[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${o['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text([if ('${o['role']}'.isNotEmpty) '${o['role']}', if (times.isNotEmpty) times, if (where.isNotEmpty) where].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: (lat == null && st != 'none') ? Colors.orange.shade800 : cs.outline, fontSize: 12.5)),
          ]),
        ),
        if (lat != null && lng != null)
          IconButton(
            tooltip: tr('Xaritada ochish'),
            visualDensity: VisualDensity.compact,
            onPressed: () => showCheckinMap(context,
                name: '${o['name']}', points: [CheckPoint.from(o, 'in', tr('Keldi')), CheckPoint.from(o, 'out', tr('Ketdi'))].whereType<CheckPoint>().toList()),
            icon: Icon(Icons.map_outlined, color: cs.primary),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ]),
    );
  }

  bool _passes(Map w) {
    final st = '${w['status']}';
    switch (_filter) {
      case _Filter.all:
        break;
      case _Filter.came:
        if (st == 'absent') return false;
      case _Filter.working:
        if (st != 'working') return false;
      case _Filter.absent:
        if (st != 'absent') return false;
    }
    if (_q.isNotEmpty) {
      final t = '${w['name']} ${w['role']} ${w['phone']}'.toLowerCase();
      if (!t.contains(_q.toLowerCase())) return false;
    }
    return true;
  }

  Future<void> _mark(String act, Map<String, List<String>> byObject) async {
    if (_busy) return;
    final keys = [for (final e in byObject.entries) for (final id in e.value) '${e.key}|$id'];
    final names = [for (final k in keys) _nameOf(k.substring(0, k.indexOf('|')), k.substring(k.indexOf('|') + 1))].where((x) => x.isNotEmpty).toList();
    setState(() {
      _busy = true;
      _pending
        ..clear()
        ..addAll(keys);
    });
    var done = 0, skipped = 0;
    var queued = false;
    final errors = <String>{};
    try {
      for (final e in byObject.entries) {
        final r = await s.api!.attendanceMark(act, e.key, e.value);
        if (r['queued'] == true) queued = true;
        done += (r['done'] as num?)?.toInt() ?? 0;
        skipped += (r['skipped'] as num?)?.toInt() ?? 0;
        errors.addAll(((r['errors'] as List?) ?? const []).map((x) => '$x'));
      }
      HapticFeedback.mediumImpact();
    } catch (e) {
      await s.handleError(e);
      errors.add('$e');
    }
    if (!mounted) return;
    await _load(quiet: true);
    if (!mounted) return;
    final ok = errors.isEmpty && (done > 0 || queued);
    setState(() {
      _busy = false;
      _pending.clear();
      if (ok) {
        _selected.clear();
        _flash
          ..clear()
          ..addEntries(keys.map((k) => MapEntry(k, act)));
      }
    });
    _flashT?.cancel();
    _flashT = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(_flash.clear);
    });
    // aniq xabar: kim, nima bo'ldi, qaysi guruhga o'tdi + «Ko'rish» (qatorga olib boradi)
    final who = names.isEmpty ? '' : (names.length == 1 ? names.first : '${names.first} ${tr('va yana')} ${names.length - 1}');
    final title = act == 'in' ? tr('ishga keldi') : tr('ishdan ketdi');
    final group = act == 'in' ? tr('«Ishda» ro\'yxatiga o\'tdi') : tr('«Ketgan» ro\'yxatiga o\'tdi');
    final color = act == 'in' ? Brand.green : const Color(0xFF475569);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: w.Text(errors.isNotEmpty ? errors.join('; ') : tr("Hech kim belgilanmadi"))));
      return;
    }
    AiBubble.tuck(const Duration(milliseconds: 5400)); // AI tugmasi xabarni yopmasin
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Row(children: [
        Icon(act == 'in' ? Icons.login_rounded : Icons.logout_rounded, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            w.Text('$who — $title', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            w.Text(queued ? tr("Offline saqlandi — internet paydo bo'lganda yuboriladi") : (skipped > 0 ? '$group · ${tr("o'tkazib yuborildi")}: $skipped' : group),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
          ]),
        ),
      ]),
      action: keys.isEmpty ? null : SnackBarAction(label: tr("Ko'rish"), textColor: Colors.white, onPressed: () => _reveal(keys.first)),
    ));
  }

  Map<String, List<String>> _selectedByObject() {
    final m = <String, List<String>>{};
    for (final k in _selected) {
      final i = k.indexOf('|');
      m.putIfAbsent(k.substring(0, i), () => []).add(k.substring(i + 1));
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(children: [
      Column(children: [
        _dateBar(cs),
        Expanded(child: _body(cs)),
      ]),
      if (_selected.isNotEmpty) Positioned(left: 12, right: 12, bottom: 12, child: _selectionBar(cs)),
    ]);
  }

  Widget _moreButton(int n, ColorScheme cs, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${tr('Yana')} $n ${tr('ta')}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
              Icon(Icons.expand_more_rounded, color: cs.primary, size: 20),
            ]),
          ),
        ),
      );

  Widget _dateBar(ColorScheme cs) {
    final label = _isToday ? 'Bugun · ${formatDate(_dateStr)}' : formatDate(_dateStr);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(children: [
        IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pickDate,
            child: Glass(
              radius: 14,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.calendar_today_outlined, size: 16),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
        IconButton(onPressed: _isToday ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }

  Widget _body(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) return ErrorView(message: _error!, onRetry: _load);
    final sum = Map<String, dynamic>.from((_data?['summary'] as Map?) ?? const {});
    final sites = _sites.where((x) => _object == null || x['id'] == _object).toList();
    final rows = <Widget>[];
    for (final site in sites) {
      final ws = ((site['workers'] as List?) ?? const []).whereType<Map>().where(_passes).toList();
      if (ws.isEmpty) continue;
      final sid = '${site['id']}';
      final nWork = ws.where((w) => w['status'] == 'working' || w['status'] == 'forgot').length;
      final nLeft = ws.where((w) => w['status'] == 'left').length;
      final nAbs = ws.where((w) => w['status'] == 'absent').length;
      // bitta obyekt, qidiruv/filtr bo'lsa — ochiq; aks holda foydalanuvchi bosib ochadi
      final open = _focused || sites.length == 1 || _openSites.contains(sid);
      Widget pill(String t, int n, Color c) => n == 0
          ? const SizedBox.shrink()
          : Container(
              margin: const EdgeInsets.only(right: 6, top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text('${tr(t)} $n', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
            );
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Glass(
          radius: 20,
          onTap: _focused || sites.length == 1 ? null : () => setState(() => open ? _openSites.remove(sid) : _openSites.add(sid)),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${site['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                Wrap(children: [pill('Ishda', nWork, Brand.teal), pill('Ketgan', nLeft, Colors.blueGrey), pill('Kelmagan', nAbs, cs.error)]),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text('${site['came']}/${site['total']}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
            if (!_focused && sites.length > 1) Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: cs.outline),
          ]),
        ),
      ));
      if (!open) continue;
      // ishchilar holati bo'yicha alohida guruhlarda: Ishda, Ketgan, Kelmagan (prorablar bloki kabi)
      final groups = <(String, Color, List<Map>)>[
        ('Ishda', Brand.teal, ws.where((w) => w['status'] == 'working' || w['status'] == 'forgot').toList()),
        ('Ketgan', Colors.blueGrey, ws.where((w) => w['status'] == 'left').toList()),
        ('Kelmagan', cs.error, ws.where((w) => w['status'] == 'absent').toList()),
      ];
      final cards = <Widget>[]; // kompyuterda guruhlar yonma-yon (Ishda | Ketgan | Kelmagan)
      for (final g in groups) {
        if (g.$3.isEmpty) continue;
        final gk = '$sid|${g.$1}';
        final all = _focused || _openGroups.contains(gk) || g.$3.length <= _peek + 1;
        final list = all ? g.$3 : g.$3.take(_peek).toList();
        final tiles = <Widget>[];
        for (final w in list) {
          final key = '${site['id']}|${w['id']}';
          tiles.add(KeyedSubtree(
            key: _keys.putIfAbsent(key, GlobalKey.new),
            child: _WorkerTile(
          flat: true,
          flash: _flash[key],
          pending: _pending.contains(key),
          w: w,
          selected: _selected.contains('${site['id']}|${w['id']}'),
          selecting: _selected.isNotEmpty,
          canMark: _canMark,
          busy: _busy,
          onToggle: () => setState(() {
            final k = '${site['id']}|${w['id']}';
            if (!_selected.remove(k)) _selected.add(k);
          }),
          onLong: _canMark
              ? () {
                  HapticFeedback.mediumImpact();
                  setState(() => _selected.add('${site['id']}|${w['id']}'));
                }
              : null,
          onAction: (act) => _mark(act, {'${site['id']}': ['${w['id']}']}),
          live: _isToday,
          dense: w['status'] == 'absent',
          site: site['site'] as Map?,
          // ishchini bosish — Telegram-botga ulash kodi
          onInfo: w['tg_code'] != null
              ? () => showTelegramLink(context, s,
                      objectId: '${site['id']}', staffId: '${w['id']}', name: '${w['name']}', code: '${w['tg_code']}', linked: w['tg_linked'] == true, bot: '${_data?['bot'] ?? ''}')
                  .then((_) => _load(quiet: true))
              : null,
        )));
        }
        cards.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Glass(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: g.$2, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(g.$1, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: g.$2))),
                Text('${g.$3.length}', style: TextStyle(color: g.$2, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 4),
              _cols(tiles, cs),
              if (!all) _moreButton(g.$3.length - list.length, cs, () => setState(() => _openGroups.add(gk))),
            ]),
          ),
        ));
      }
      if (cards.isNotEmpty) rows.addAll(cards);
    }
    return RefreshIndicator(
      onRefresh: () => _load(quiet: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: NavInset.listBottom(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(children: [
              _Stat('Jami', '${sum['staff'] ?? 0}', _filter == _Filter.all, () => setState(() => _filter = _Filter.all), cs.primary),
              _Stat('Keldi', '${sum['came'] ?? 0}', _filter == _Filter.came, () => setState(() => _filter = _Filter.came), Brand.green),
              _Stat('Ishda', '${sum['working'] ?? 0}', _filter == _Filter.working, () => setState(() => _filter = _Filter.working), Brand.teal),
              _Stat('Kelmadi', '${sum['absent'] ?? 0}', _filter == _Filter.absent, () => setState(() => _filter = _Filter.absent), cs.error),
            ]),
          ),
          if (_sites.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip('Hamma obyektlar', _object == null, () => setState(() => _object = null)),
                  for (final x in _sites) _chip('${x['name']}', _object == x['id'], () => setState(() => _object = '${x['id']}')),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(
                hintText: tr('Qidirish: ism, lavozim, telefon'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_office.isNotEmpty) _officeBlock(cs),
          if (_canMark && _selected.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Ko\'p odamni belgilash uchun qatorni uzoq bosing.', style: TextStyle(color: cs.outline, fontSize: 12)),
            ),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Ma\'lumot yo\'q'))),
          ...rows,
        ],
      ),
    );
  }

  Widget _chip(String t, bool on, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(t), selected: on, onSelected: (_) => f(), showCheckmark: false),
      );

  Widget _selectionBar(ColorScheme cs) {
    return Glass(
      radius: 22,
      blur: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
          Text('${_selected.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const Spacer(),
          FilledButton.tonal(onPressed: _busy ? null : () => _mark('out', _selectedByObject()), child: const Text('Ketdi')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : () => _mark('in', _selectedByObject()), child: const Text('Keldi')),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.on, this.onTap, this.color);

  final String label;
  final String value;
  final bool on;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Glass(
          radius: 16,
          onTap: onTap,
          tint: on ? color.withValues(alpha: 0.16) : null,
          shadow: on,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: color, height: 1.1)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11.5, color: on ? color : cs.outline, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _WorkerTile extends StatelessWidget {
  const _WorkerTile({required this.w, required this.selected, required this.selecting, required this.canMark, required this.busy, required this.onToggle, required this.onLong, required this.onAction, this.live = false, this.flat = false, this.onInfo, this.site, this.flash, this.pending = false, this.dense = false});

  /// Ixcham qator (kelmaganlar ro'yxati): kichikroq avatar va bo'shliq
  final bool dense;

  /// Hozirgina belgilangan: 'in' — yashil, 'out' — kulrang yonadi
  final String? flash;

  /// Shu qator yuborilmoqda
  final bool pending;

  /// Obyekt joylashuvi (xaritada doira): {lat, lng, radius}
  final Map? site;

  /// Bosilganda (tanlash rejimi bo'lmasa): Telegram-botga ulash kodi
  final VoidCallback? onInfo;

  /// Guruh kartasi ichida: alohida shisha fonsiz qator
  final bool flat;

  final Map w;
  final bool selected;
  final bool selecting;
  final bool canMark;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback? onLong;
  final void Function(String act) onAction;
  final bool live;

  /// Ishlagan vaqt: «8 soat 12 daq». Ishdagi xodim uchun (bugun) — kelgan vaqtidan hozirgacha
  String _worked(String st) {
    var h = ((w['hours'] as num?) ?? 0).toDouble();
    if (h <= 0 && live && st == 'working') {
      final ts = DateTime.tryParse('${w['in_ts'] ?? ''}');
      if (ts != null) {
        final d = DateTime.now().difference(ts);
        if (!d.isNegative) h = d.inMinutes / 60;
      }
    }
    if (h <= 0 && live && st == 'working') {
      final p = '${w['in'] ?? ''}'.split(':');
      final hh = p.length > 1 ? int.tryParse(p[0]) : null, mm = p.length > 1 ? int.tryParse(p[1]) : null;
      if (hh != null && mm != null) {
        final n = DateTime.now();
        final d = n.difference(DateTime(n.year, n.month, n.day, hh, mm));
        if (!d.isNegative) h = d.inMinutes / 60;
      }
    }
    if (h <= 0) return '';
    final total = (h * 60).round();
    return total >= 60 ? '${total ~/ 60} ${tr('soat')} ${total % 60} ${tr('daq')}' : '$total ${tr('daq')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = '${w['status']}';
    final (label, color) = switch (st) {
      'working' => ('Ishda', Brand.teal),
      'left' => ('Ketdi', Colors.blueGrey),
      'forgot' => ('Chiqmagan', Colors.orange.shade800),
      _ => ('Kelmadi', cs.error),
    };
    final name = '${w['name']}';
    final times = [if (w['in'] != null) '${w['in']}', if (w['out'] != null) '${w['out']}'].join(' – ');
    final wk = _worked(st);
    final sub = [
      if ('${w['role']}'.isNotEmpty) '${w['role']}',
      if (times.isNotEmpty) times,
      if (wk.isNotEmpty) wk,
    ].join(' · ');
    // qayerda / kim belgiladi: telefon orqali o'zi (obyektda yoki tashqarida) yoki prorab qo'lda
    final by = '${w['marked_by'] ?? ''}';
    // «Keldim»/«Ketdim» bosilgan joy (Telegram-bot, shaxsiy havola yoki ilova) — bosilsa xaritada ko'rinadi
    final pts = [CheckPoint.from(w, 'in', tr('Keldi')), CheckPoint.from(w, 'out', tr('Ketdi'))].whereType<CheckPoint>().toList();
    final dist = w['in_dist'] as num?;
    final far = dist == null ? '' : ' · ${distLabel(dist)}';
    final (whereIcon, whereText, whereWarn) = st == 'absent'
        ? (null, '', false)
        : w['manual'] == true
            ? (Icons.edit_location_alt_outlined, by.isEmpty ? tr("Qo'lda belgilangan") : '${tr('Belgiladi')}: $by', false)
            : w['off_site'] == true || w['on_site'] == false
                ? (Icons.wrong_location_outlined, dist == null ? tr('Obyektdan tashqarida') : tr('Obyektdan :d uzoqda').replaceAll(':d', distLabel(dist)), true)
                : w['on_site'] == true
                    ? (Icons.place_rounded, '${tr('Obyektda (telefon orqali)')}$far', false)
                    : pts.isNotEmpty
                        ? (Icons.place_outlined, '${tr('Joylashuv bor')}$far', false)
                        : (Icons.phone_iphone_rounded, tr('Telefon orqali'), false);
    final tgOn = w['tg_linked'] == true;
    // tor telefon (≤360dp): ism 2 qatorda, «xaritada» — faqat belgi, tugma ixcham
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final avatar = selected
        ? CircleAvatar(radius: dense ? 16 : 20, backgroundColor: cs.primary, child: Icon(Icons.check, color: cs.onPrimary, size: dense ? 18 : 24))
        : CircleAvatar(
            radius: dense ? 16 : 20,
            backgroundColor: color.withValues(alpha: 0.14),
            foregroundColor: color,
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: dense ? 13 : 15)));
    final row = Row(children: [
          // Telegram holati — avatar burchagidagi kichik nishon (alohida belgi qatorni siqmaydi)
          if (w['tg_code'] != null && !selecting)
            Tooltip(
              message: tgOn ? tr('Telegram ulangan') : tr('Telegram ulanmagan — bosing, kod chiqadi'),
              child: SizedBox(
                width: dense ? 34 : 42,
                height: dense ? 34 : 42,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(child: Align(alignment: Alignment.topLeft, child: avatar)),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: dense ? 15 : 19,
                      height: dense ? 15 : 19,
                      decoration: BoxDecoration(
                        color: tgOn ? const Color(0xFF229ED9) : cs.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 2),
                      ),
                      child: Icon(Icons.send_rounded, size: dense ? 7.5 : 9.5, color: tgOn ? Colors.white : cs.outline),
                    ),
                  ),
                ]),
              ),
            )
          else
            avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: narrow ? 2 : 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.2)),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
              if (whereIcon != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: pts.isEmpty || selecting ? null : () => showCheckinMap(context, name: name, points: pts, site: site),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Icon(whereIcon, size: 14, color: whereWarn ? Colors.orange.shade700 : cs.primary),
                      const SizedBox(width: 4),
                      Flexible(child: Text(whereText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: whereWarn ? Colors.orange.shade700 : cs.outline, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2))),
                      if (pts.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: narrow ? const EdgeInsets.all(3) : const EdgeInsets.fromLTRB(5, 2, 7, 2),
                          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.map_rounded, size: 13, color: cs.primary),
                            if (!narrow) ...[
                              const SizedBox(width: 3),
                              Text(tr('xaritada'), style: TextStyle(color: cs.primary, fontSize: 11.5, fontWeight: FontWeight.w800, height: 1.2)),
                            ],
                          ]),
                        ),
                      ],
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          if (flash != null)
            // hozirgina belgilandi — tugma o'rniga aniq belgi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: flash == 'in' ? Brand.green : const Color(0xFF475569), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(flash == 'in' ? 'Keldi' : 'Ketdi', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ]),
            )
          else if (canMark && !selecting && (st == 'absent' || st == 'working' || st == 'forgot'))
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: busy ? null : () => onAction(st == 'absent' ? 'in' : 'out'),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: narrow ? 9 : 14),
                  visualDensity: VisualDensity.compact,
                  textStyle: TextStyle(fontSize: narrow ? 13 : 14, fontWeight: FontWeight.w700),
                  backgroundColor: st == 'absent' ? Brand.green : const Color(0xFF64748B),
                ),
                child: pending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(st == 'absent' ? Icons.login_rounded : Icons.logout_rounded, size: narrow ? 15 : 16),
                        SizedBox(width: narrow ? 4 : 5),
                        Text(st == 'absent' ? 'Keldi' : 'Ketdi'),
                      ]),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
        ]);
    if (flat) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: selecting ? onToggle : onInfo,
          onLongPress: onLong,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            decoration: BoxDecoration(
              color: selected
                  ? cs.primaryContainer.withValues(alpha: 0.6)
                  : flash == 'in'
                      ? Brand.green.withValues(alpha: 0.14)
                      : flash == 'out'
                          ? const Color(0xFF475569).withValues(alpha: 0.12)
                          : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: flash == null ? null : Border.all(color: (flash == 'in' ? Brand.green : const Color(0xFF475569)).withValues(alpha: 0.5), width: 1.4),
            ),
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: dense ? 5 : 9),
            child: row,
          ),
        ),
      );
    }
    return GlassRow(
      onTap: selecting ? onToggle : onInfo,
      onLongPress: onLong,
      tint: selected ? cs.primaryContainer.withValues(alpha: 0.75) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: row,
    );
  }
}
