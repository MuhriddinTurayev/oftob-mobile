import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../session.dart';
import '../widgets.dart';
import '../theme.dart';
import '../l10n.dart';

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
  final _selected = <String>{}; // "obyekt|xodim"
  bool _busy = false;

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

  Future<void> _openMap(num lat, num lng) =>
      launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'), mode: LaunchMode.externalApplication);

  /// «Men ishga keldim» bosgan prorablar va ofis xodimlari: kelgan/ketgan vaqt va joylashuv (xaritada ochiladi).
  Widget _officeBlock(ColorScheme cs) {
    final came = _office.where((o) => o['status'] != 'none').length;
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
          for (final o in _office) _officeRow(o, cs),
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
      'working' => ('Ishda', Colors.teal),
      'left' => ('Ketdi', Colors.blueGrey),
      _ => ('Kelmadi', cs.error),
    };
    final since = shiftMoment(o, 'in');
    final until = st == 'working' ? DateTime.now() : shiftMoment(o, 'out');
    final worked = (st == 'none' || since == null || until == null) ? '' : durationText(until.difference(since));
    final times = st == 'none' ? '' : '${o['in'] ?? ''}${o['out'] != null ? ' – ${o['out']}' : ''}${st == 'working' ? ' · ${tr('dan beri')}' : ''}${worked.isEmpty ? '' : ' · $worked'}';
    final where = st == 'none' ? '' : (lat == null ? 'joylashuvsiz' : (dist == null ? 'joylashuv bor' : (dist <= 300 ? 'obyektda' : 'obyektdan ${distLabel(dist)}')));
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
        if (lat != null && lng != null) IconButton(tooltip: tr('Xaritada ochish'), visualDensity: VisualDensity.compact, onPressed: () => _openMap(lat, lng), icon: Icon(Icons.map_outlined, color: cs.primary)),
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
    setState(() => _busy = true);
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
    setState(() => _busy = false);
    final msg = queued ? "Offline saqlandi ($done) — internet paydo bo'lganda yuboriladi" : '${act == 'in' ? 'Smenaga qo\'yildi' : 'Smenadan olindi'}: $done${skipped > 0 ? ' · o\'tkazib yuborildi: $skipped' : ''}${errors.isNotEmpty ? '\n${errors.join('; ')}' : ''}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _load(quiet: true);
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
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(children: [
          Expanded(child: Text('${site['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text('${site['came']}/${site['total']}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ]),
      ));
      // ishchilar holati bo'yicha alohida guruhlarda: Ishda, Ketgan, Kelmagan (prorablar bloki kabi)
      final groups = <(String, Color, List<Map>)>[
        ('Ishda', Colors.teal, ws.where((w) => w['status'] == 'working' || w['status'] == 'forgot').toList()),
        ('Ketgan', Colors.blueGrey, ws.where((w) => w['status'] == 'left').toList()),
        ('Kelmagan', cs.error, ws.where((w) => w['status'] == 'absent').toList()),
      ];
      for (final g in groups) {
        if (g.$3.isEmpty) continue;
        final tiles = <Widget>[];
        for (final w in g.$3) {
          tiles.add(_WorkerTile(
          flat: true,
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
        ));
        }
        rows.add(Padding(
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
              for (var k = 0; k < tiles.length; k++) ...[
                if (k > 0) Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
                tiles[k],
              ],
            ]),
          ),
        ));
      }
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
              _Stat('Keldi', '${sum['came'] ?? 0}', _filter == _Filter.came, () => setState(() => _filter = _Filter.came), Colors.green.shade700),
              _Stat('Ishda', '${sum['working'] ?? 0}', _filter == _Filter.working, () => setState(() => _filter = _Filter.working), Colors.teal),
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
  const _WorkerTile({required this.w, required this.selected, required this.selecting, required this.canMark, required this.busy, required this.onToggle, required this.onLong, required this.onAction, this.live = false, this.flat = false});

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
      'working' => ('Ishda', Colors.teal),
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
    final (whereIcon, whereText, whereWarn) = st == 'absent'
        ? (null, '', false)
        : w['manual'] == true
            ? (Icons.edit_location_alt_outlined, by.isEmpty ? tr("Qo'lda belgilangan") : '${tr('Belgiladi')}: $by', false)
            : w['off_site'] == true || w['on_site'] == false
                ? (Icons.wrong_location_outlined, tr('Obyektdan tashqarida'), true)
                : w['on_site'] == true
                    ? (Icons.place_rounded, tr('Obyektda (telefon orqali)'), false)
                    : (Icons.phone_iphone_rounded, tr('Telefon orqali'), false);
    final row = Row(children: [
          selected
              ? CircleAvatar(radius: 20, backgroundColor: cs.primary, child: Icon(Icons.check, color: cs.onPrimary))
              : CircleAvatar(radius: 20, backgroundColor: color.withValues(alpha: 0.14), foregroundColor: color, child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
              if (whereIcon != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Icon(whereIcon, size: 14, color: whereWarn ? Colors.orange.shade700 : cs.primary),
                    const SizedBox(width: 4),
                    Expanded(child: Text(whereText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: whereWarn ? Colors.orange.shade700 : cs.outline, fontSize: 12, fontWeight: FontWeight.w600))),
                  ]),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          if (canMark && !selecting && (st == 'absent' || st == 'working' || st == 'forgot'))
            SizedBox(
              height: 34,
              child: FilledButton.tonal(
                onPressed: busy ? null : () => onAction(st == 'absent' ? 'in' : 'out'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14), visualDensity: VisualDensity.compact),
                child: Text(st == 'absent' ? 'Keldi' : 'Ketdi'),
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
          onTap: selecting ? onToggle : null,
          onLongPress: onLong,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(color: selected ? cs.primaryContainer.withValues(alpha: 0.6) : Colors.transparent, borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
            child: row,
          ),
        ),
      );
    }
    return GlassRow(
      onTap: selecting ? onToggle : null,
      onLongPress: onLong,
      tint: selected ? cs.primaryContainer.withValues(alpha: 0.75) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: row,
    );
  }
}
