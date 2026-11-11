import 'dart:io' show Platform;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../l10n.dart';
import '../motion.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'deal.dart';
import 'lead_sources.dart';
import 'leads.dart';
import 'objects.dart';

Color _hex(String? h, [Color fallback = const Color(0xFF64748B)]) {
  final v = (h ?? '').replaceFirst('#', '');
  if (v.length != 6) return fallback;
  return Color(int.parse('FF$v', radix: 16));
}

({IconData icon, Color color, String name}) _ch(String? ch) {
  switch ((ch ?? '').toLowerCase()) {
    case 'instagram':
      return (icon: Icons.camera_alt_outlined, color: const Color(0xFFD6249F), name: 'Instagram');
    case 'facebook':
    case 'messenger':
      return (icon: Icons.thumb_up_alt_outlined, color: const Color(0xFF1877F2), name: 'Facebook');
    case 'whatsapp':
      return (icon: Icons.chat_outlined, color: const Color(0xFF25D366), name: 'WhatsApp');
    case 'telegram':
      return (icon: Icons.send_outlined, color: const Color(0xFF229ED9), name: 'Telegram');
    case 'site':
    case 'form':
      return (icon: Icons.language, color: const Color(0xFF2F6FDE), name: 'Sayt');
    case 'manual':
      return (icon: Icons.edit_note_rounded, color: Brand.orange, name: 'Qo\'lda');
    default:
      return (icon: Icons.inbox_outlined, color: Colors.blueGrey, name: 'Boshqa');
  }
}

String _fd(String? d) => (d == null || d.isEmpty) ? '' : formatDate(d);

/// Lidlar: saytdagi kabi voronka — bosqichlar, ularning soni, har lid uchun «javob berdi / kelish kuni va soati / tanlagan xonadon».
/// Lidni bossangiz — tahrirlash oynasi; u yerdan to'g'ri xonadon va xaridor ismi bilan sotuvga o'tiladi. Eski serverda — oddiy ro'yxat.
class LeadBoardScreen extends StatefulWidget {
  const LeadBoardScreen({super.key, required this.session});

  final Session session;

  @override
  State<LeadBoardScreen> createState() => _LeadBoardScreenState();
}

class _LeadBoardScreenState extends State<LeadBoardScreen> {
  bool _loading = true;
  bool _oldServer = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _meta = const {};
  String? _stage;
  String _q = '';

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = _items.isEmpty);
    try {
      final r = await s.api!.leadBoard();
      if (!mounted) return;
      if (r == null) {
        setState(() {
          _oldServer = true;
          _loading = false;
        });
        return;
      }
      setState(() {
        _items = r.items;
        _meta = r.meta;
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

  List<Map<String, dynamic>> get _stages => ((_meta['stages'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  Map<String, dynamic> _stageOf(String? k) => _stages.firstWhere((x) => x['key'] == k, orElse: () => {'key': k, 'name': k, 'color': '#64748b'});

  bool _passes(Map l) {
    if (_stage != null && '${l['status']}' != _stage) return false;
    if (_q.isEmpty) return true;
    final t = '${l['name']} ${l['phone']} ${l['note']} ${l['src']} ${l['apartment_number']}'.toLowerCase();
    return t.contains(_q.toLowerCase());
  }

  Future<void> _add() async {
    final created = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => LeadForm(session: s));
    if (created == true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr("Ariza qo'shildi"))));
      _load(quiet: true);
    }
  }

  Future<void> _open(Map<String, dynamic> l) async {
    HapticFeedback.selectionClick();
    final changed = await presentSheet<bool>(context, LeadDetail(session: s, lead: l, meta: _meta));
    if (changed == true) _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_oldServer) return LeadsScreen(session: s);
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return ErrorView(message: _error!, onRetry: _load);
    final canWrite = s.me!.can('leads:write');
    final counts = Map<String, dynamic>.from((_meta['counts'] as Map?) ?? const {});
    final shown = _items.where(_passes).toList();
    final newN = _items.where((l) => l['unread'] == true || l['status'] == 'new').length;

    Widget chip(String label, bool on, VoidCallback f, {Color? dot}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              if (dot != null) ...[Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 6)],
              Text(label),
            ]),
            selected: on,
            showCheckmark: false,
            onSelected: (_) {
              HapticFeedback.selectionClick();
              f();
            },
          ),
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canWrite ? GlassFab(onPressed: _add, icon: Icons.add, label: 'Ariza') : null,
      body: RefreshIndicator(
        onRefresh: () => _load(quiet: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: NavInset.listBottom(context) + 70),
          children: [
            if (s.me!.role == 'admin' || s.me!.role == 'manager')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: GlassRow(
                  margin: EdgeInsets.zero,
                  onTap: () => Navigator.push(context, DeskRoute(builder: (_) => LeadSourcesScreen(session: s))),
                  child: Row(children: [
                    const IconTile(icon: Icons.hub_rounded, color: Brand.blue, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Lid manbalari', style: TextStyle(fontWeight: FontWeight.w800)),
                        Text('Sayt, Instagram, Facebook, WhatsApp, Telegram — ulash', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: cs.outline),
                  ]),
                ),
              ),
            if (newN > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: HeroGlass(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  radius: 20,
                  child: Row(children: [
                    Icon(Icons.mark_email_unread_rounded, color: cs.onPrimaryContainer),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${tr('Yangi, javob kutyapti')}: $newN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cs.onPrimaryContainer))),
                  ]),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(
                  hintText: tr('Qidirish: ism, telefon, izoh'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), children: [
                chip('${tr('Hammasi')} ${_items.length}', _stage == null, () => setState(() => _stage = null)),
                for (final st in _stages)
                  chip('${st['name']} ${counts['${st['key']}'] ?? 0}', _stage == st['key'], () => setState(() => _stage = _stage == st['key'] ? null : '${st['key']}'), dot: _hex('${st['color']}')),
              ]),
            ),
            if (shown.isEmpty) const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Arizalar topilmadi'))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: DeskGrid(minColumn: 470, maxColumns: 2, gap: 12, children: [for (var i = 0; i < shown.length; i++) Reveal(index: i.clamp(0, 9), child: _card(context, shown[i]))]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> l) {
    final cs = Theme.of(context).colorScheme;
    final ch = _ch('${l['channel']}');
    final st = _stageOf('${l['status']}');
    final stc = _hex('${st['color']}');
    final name = '${l['name']}'.trim();
    final phone = '${l['phone']}'.trim();
    final info = [
      if ('${l['src']}'.isNotEmpty) '${l['src']}',
      if ('${l['rooms']}'.isNotEmpty) '${l['rooms']} ${tr('xona')}',
      if (l['budget'] != null) '${tr('byudjet')} ${money(l['budget'] as num?)}',
      if (_meta['team'] != null && '${l['manager']}'.isNotEmpty) '${l['manager']}',
    ].join(' · ');
    final visit = '${l['visit_date'] ?? ''}'.isNotEmpty;
    final reach = '${l['reach']}';
    final reachName = ((_meta['reach'] as List?) ?? const []).whereType<Map>().firstWhere((x) => x['key'] == reach, orElse: () => const {})['name'];
    Widget pill(String t, Color c, {IconData? icon}) => Container(
          margin: const EdgeInsets.only(top: 6, right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
            Flexible(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12))),
          ]),
        );
    return GlassRow(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      onTap: () => _open(l),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(clipBehavior: Clip.none, children: [
          CircleAvatar(radius: 22, backgroundColor: ch.color.withValues(alpha: 0.14), foregroundColor: ch.color, child: Icon(ch.icon, size: 22)),
          if (l['unread'] == true) Positioned(right: -1, top: -1, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)))),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name.isNotEmpty ? name : (phone.isNotEmpty ? phone : 'Nomsiz ariza'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
              const SizedBox(width: 6),
              StatusChip('${st['name']}', stc),
            ]),
            if (name.isNotEmpty && phone.isNotEmpty) Text(phone, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13)),
            if (info.isNotEmpty) Text(info, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
            Wrap(children: [
              if ('${l['apartment_number']}'.isNotEmpty) pill('${tr('Xonadon')} №${l['apartment_number']}', Brand.purple, icon: Icons.apartment_rounded),
              if (visit) pill('${tr('Keladi')}: ${_fd('${l['visit_date']}')}${'${l['visit_time'] ?? ''}'.isNotEmpty ? ' · ${l['visit_time']}' : ''}', Brand.blue, icon: Icons.event_available_rounded),
              if (reachName != null) pill('$reachName', reach == 'answered' ? Brand.teal : (reach == 'noanswer' ? cs.error : Brand.orange), icon: Icons.phone_in_talk_rounded),
            ]),
            if ('${l['note']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${l['note']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            if (!visit && '${l['next_date'] ?? ''}'.isNotEmpty && ['new', 'contact', 'meet', 'shown', 'booked'].contains('${l['status']}'))
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('${_fd('${l['next_date']}')} · ${l['next_text']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12))),
          ]),
        ),
      ]),
    );
  }
}

/// Keng oynada (kompyuter) — o'rtadagi oyna; telefonda — pastdan chiqadigan varaq
Future<T?> presentSheet<T>(BuildContext context, Widget child) {
  if (Platform.isWindows && MediaQuery.sizeOf(context).width >= 900) {
    return showDialog<T>(
      context: context,
      useRootNavigator: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (dc) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 700, maxHeight: MediaQuery.sizeOf(dc).height * 0.92), child: child),
      ),
    );
  }
  return showModalBottomSheet<T>(context: context, isScrollControlled: true, showDragHandle: true, useSafeArea: true, builder: (_) => child);
}

/// Lid kartochkasi: aloqa natijasi, kelish kuni va soati, bosqich, javobgar, xonadon, sotuvga o'tish
class LeadDetail extends StatefulWidget {
  const LeadDetail({super.key, required this.session, required this.lead, required this.meta});

  final Session session;
  final Map<String, dynamic> lead;
  final Map<String, dynamic> meta;

  @override
  State<LeadDetail> createState() => _LeadDetailState();
}

class _LeadDetailState extends State<LeadDetail> {
  late final _name = TextEditingController(text: '${widget.lead['name']}');
  late final _phone = TextEditingController(text: '${widget.lead['phone']}');
  late final _next = TextEditingController(text: '${widget.lead['next_text'] ?? ''}');
  late final _note = TextEditingController(text: '${widget.lead['note'] ?? ''}');
  final _log = TextEditingController();
  late String _status = '${widget.lead['status']}';
  late String _reach = '${widget.lead['reach'] ?? ''}';
  late String? _visitDate = '${widget.lead['visit_date'] ?? ''}'.isEmpty ? null : '${widget.lead['visit_date']}';
  late String? _visitTime = '${widget.lead['visit_time'] ?? ''}'.isEmpty ? null : '${widget.lead['visit_time']}';
  late String? _nextDate = '${widget.lead['next_date'] ?? ''}'.isEmpty ? null : '${widget.lead['next_date']}';
  late String _manager = '${widget.lead['manager'] ?? ''}';
  late String _apt = '${widget.lead['apartment_id'] ?? ''}';
  late String _aptNum = '${widget.lead['apartment_number'] ?? ''}';
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _log2 = const [];

  Session get s => widget.session;
  bool get _canWrite => s.me!.can('leads:write');
  String get _oid => '${widget.lead['object_id']}';
  String get _id => '${widget.lead['id']}';

  @override
  void initState() {
    super.initState();
    _log2 = ((widget.lead['log'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _next, _note, _log]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _stages => ((widget.meta['stages'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  List<Map<String, dynamic>> get _reachOpts => ((widget.meta['reach'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  List<String> get _team => ((widget.meta['team'] as List?) ?? const []).map((e) => '$e').toList();

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool visit}) async {
    final cur = DateTime.tryParse((visit ? _visitDate : _nextDate) ?? '') ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: cur.isBefore(DateTime.now().subtract(const Duration(days: 1))) ? DateTime.now() : cur, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 730)));
    if (d == null) return;
    setState(() {
      if (visit) {
        _visitDate = _iso(d);
        if (_status == 'new' || _status == 'contact') _status = 'meet'; // kelish vaqti belgilandi — «Uchrashuv belgilandi»
      } else {
        _nextDate = _iso(d);
      }
    });
  }

  Future<void> _pickTime() async {
    final parts = (_visitTime ?? '10:00').split(':');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 10, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0), builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!));
    if (t == null) return;
    setState(() => _visitTime = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  }

  void _quickDay(int add) {
    setState(() {
      _visitDate = _iso(DateTime.now().add(Duration(days: add)));
      if (_status == 'new' || _status == 'contact') _status = 'meet';
    });
  }

  /// Faqat o'zgargan maydonlar
  Map<String, dynamic> _diff() {
    final l = widget.lead;
    final b = <String, dynamic>{};
    void put(String k, String now, String was) {
      if (now != was) b[k] = now;
    }

    put('name', _name.text.trim(), '${l['name']}');
    put('phone', _phone.text.trim(), '${l['phone']}');
    put('status', _status, '${l['status']}');
    put('reach', _reach, '${l['reach'] ?? ''}');
    put('visitDate', _visitDate ?? '', '${l['visit_date'] ?? ''}');
    put('visitTime', _visitTime ?? '', '${l['visit_time'] ?? ''}');
    put('nextDate', _nextDate ?? '', '${l['next_date'] ?? ''}');
    put('nextText', _next.text.trim(), '${l['next_text'] ?? ''}');
    put('manager', _manager, '${l['manager'] ?? ''}');
    put('note', _note.text.trim(), '${l['note'] ?? ''}');
    put('apt', _apt, '${l['apartment_id'] ?? ''}');
    put('aptNum', _aptNum, '${l['apartment_number'] ?? ''}');
    if (_log.text.trim().isNotEmpty) b['log'] = _log.text.trim();
    if (b['name'] == '') b.remove('name');
    return b;
  }

  Future<bool> _save({bool close = true}) async {
    final b = _diff();
    if (b.isEmpty) {
      if (close && mounted) Navigator.pop(context, false);
      return true;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await s.api!.leadBoardUpdate(_oid, _id, b);
      if (!mounted) return true;
      widget.lead
        ..clear()
        ..addAll(r);
      if (close) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context, true);
      } else {
        setState(() {
          _busy = false;
          _log.clear();
          _log2 = ((r['log'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
      return false;
    }
  }

  /// Bo'sh xonadonlardan tanlash (lidning xonasiga mos)
  Future<void> _pickApt() async {
    final rooms = int.tryParse('${widget.lead['rooms'] ?? ''}');
    final picked = await showDialog<Map<String, dynamic>>(context: context, useRootNavigator: false, builder: (_) => _AptPicker(session: s, objectId: _oid, rooms: rooms));
    if (picked == null) return;
    setState(() {
      _apt = '${picked['id']}';
      _aptNum = '${picked['number']}';
    });
  }

  /// Sotuvga o'tish: tanlangan xonadon ochiladi, ism va telefon avtomatik yoziladi
  Future<void> _toSale() async {
    if (_apt.isEmpty) {
      await _pickApt();
      if (_apt.isEmpty) return;
    }
    if (!await _save(close: false)) return;
    Map<String, dynamic> apt;
    try {
      apt = await s.api!.apartment(_oid, _apt);
    } catch (e) {
      await s.handleError(e);
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
      return;
    }
    if (!mounted) return;
    final name = _name.text.trim(), phone = _phone.text.trim();
    final objName = '${widget.lead['object']}';
    if ('${apt['status']}' == 'free') {
      await Navigator.of(context).push(DeskRoute<void>(builder: (_) => DealScreen(session: s, objectId: _oid, apt: apt, prefillName: name, prefillPhone: phone, onDone: () {})));
      // sotuv/bron bajarilgan bo'lsa — lid bosqichi o'zi yangilanadi
      try {
        final after = await s.api!.apartment(_oid, _apt);
        final st = '${after['status']}';
        if (st == 'sold' || st == 'booked') {
          final r = await s.api!.leadBoardUpdate(_oid, _id, {'status': st == 'sold' ? 'deal' : 'booked'});
          widget.lead
            ..clear()
            ..addAll(r);
          if (mounted) Navigator.pop(context, true);
        }
      } catch (_) {}
    } else {
      showApartmentSheet(context, s, _oid, objName, apt, onChanged: () {});
    }
  }

  Widget _sec(String t) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 8), child: Text(tr(t), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Theme.of(context).colorScheme.outline, letterSpacing: 0.2)));

  InputDecoration _dec(String l) => InputDecoration(labelText: tr(l), filled: true, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ch = _ch('${widget.lead['channel']}');
    final phone = _phone.text.trim();
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final user = '${widget.lead['igUser'] ?? ''}';
    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Row(children: [
        Expanded(child: FilledButton.icon(onPressed: _busy ? null : () => _save(), icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Icon(Icons.check_rounded), label: Text(tr('Saqlash')))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton.tonalIcon(onPressed: _busy ? null : _toSale, icon: const Icon(Icons.key_rounded), label: Text(_apt.isNotEmpty ? '${tr('Sotuvga')} · №$_aptNum' : tr("Sotuvga o'tkazish")))),
      ]),
    );
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Row(children: [
            CircleAvatar(radius: 24, backgroundColor: ch.color.withValues(alpha: 0.14), foregroundColor: ch.color, child: Icon(ch.icon, size: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Lid'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                Text([ch.name, if ('${widget.lead['object']}'.isNotEmpty) '${widget.lead['object']}', _fd('${widget.lead['created']}')].where((e) => e.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
              ]),
            ),
            if (Platform.isWindows) IconButton.filledTonal(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close_rounded)),
      ]),
    );
    final body = <Widget>[
          const SizedBox(height: 8),
          TextField(controller: _name, enabled: _canWrite, textCapitalization: TextCapitalization.words, decoration: _dec('Ism familiyasi')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _phone, enabled: _canWrite, keyboardType: TextInputType.phone, onChanged: (_) => setState(() {}), decoration: _dec('Telefon'))),
            if (phone.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton.filled(tooltip: tr("Qo'ng'iroq"), onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')), mode: LaunchMode.externalApplication), icon: const Icon(Icons.call)),
            ],
            if (digits.length >= 9) ...[
              const SizedBox(width: 6),
              IconButton.filledTonal(tooltip: 'WhatsApp', onPressed: () => launchUrl(Uri.parse('https://wa.me/${digits.length == 9 ? '998$digits' : digits}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.chat)),
            ],
            if (user.isNotEmpty) ...[
              const SizedBox(width: 6),
              IconButton.filledTonal(tooltip: 'Telegram', onPressed: () => launchUrl(Uri.parse('https://t.me/${user.replaceFirst('@', '')}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.send_outlined)),
            ],
          ]),
          _sec('BOSQICH'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final st in _stages)
              ChoiceChip(
                avatar: Container(width: 10, height: 10, decoration: BoxDecoration(color: _hex('${st['color']}'), shape: BoxShape.circle)),
                label: Text('${st['name']}'),
                selected: _status == st['key'],
                showCheckmark: false,
                onSelected: _canWrite ? (_) => setState(() => _status = '${st['key']}') : null,
              ),
          ]),
          _sec('MIJOZ BILAN ALOQA'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in _reachOpts)
              ChoiceChip(
                avatar: Icon(r['key'] == 'answered' ? Icons.check_circle_outline : (r['key'] == 'noanswer' ? Icons.phone_missed_outlined : Icons.phone_callback_outlined), size: 18),
                label: Text('${r['name']}'),
                selected: _reach == r['key'],
                showCheckmark: false,
                onSelected: _canWrite
                    ? (v) => setState(() {
                          _reach = v ? '${r['key']}' : '';
                          if (v && _status == 'new') _status = 'contact'; // aloqa bo'ldi — «Bog'lanildi»
                        })
                    : null,
              ),
          ]),
          _sec('QACHON KELA OLADI'),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ActionChip(label: Text(tr('Bugun')), onPressed: _canWrite ? () => _quickDay(0) : null),
            ActionChip(label: Text(tr('Ertaga')), onPressed: _canWrite ? () => _quickDay(1) : null),
            OutlinedButton.icon(onPressed: _canWrite ? () => _pickDate(visit: true) : null, icon: const Icon(Icons.event_rounded, size: 18), label: Text(_visitDate == null ? tr('Kun tanlash') : _fd(_visitDate))),
            OutlinedButton.icon(onPressed: _canWrite ? _pickTime : null, icon: const Icon(Icons.schedule_rounded, size: 18), label: Text(_visitTime ?? tr('Soat')) ),
            if (_visitDate != null || _visitTime != null) IconButton(tooltip: tr('Tozalash'), onPressed: _canWrite ? () => setState(() {
                  _visitDate = null;
                  _visitTime = null;
                }) : null, icon: const Icon(Icons.close_rounded)),
          ]),
          _sec('XONADON'),
          if (_apt.isNotEmpty)
            GlassRow(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(children: [
                const IconTile(icon: Icons.apartment_rounded, color: Brand.purple, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text('${tr('Tanlagan xonadon')}: №$_aptNum', style: const TextStyle(fontWeight: FontWeight.w800))),
                if (_canWrite) TextButton(onPressed: _pickApt, child: Text(tr("O'zgartirish"))),
              ]),
            )
          else
            OutlinedButton.icon(onPressed: _canWrite ? _pickApt : null, icon: const Icon(Icons.add_home_work_outlined), label: Text(tr('Xonadon tanlash'))),
          _sec('KEYINGI QADAM VA JAVOBGAR'),
          if (_team.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _team.contains(_manager) ? _manager : '',
              isExpanded: true,
              decoration: _dec('Javobgar'),
              items: [DropdownMenuItem(value: '', child: Text(tr('—'))), for (final t in _team) DropdownMenuItem(value: t, child: Text(t))],
              onChanged: _canWrite ? (v) => setState(() => _manager = v ?? '') : null,
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _next, enabled: _canWrite, decoration: _dec('Keyingi qadam'))),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _canWrite ? () => _pickDate(visit: false) : null, icon: const Icon(Icons.event_note_rounded, size: 18), label: Text(_nextDate == null ? tr('Sana') : _fd(_nextDate))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _note, enabled: _canWrite, minLines: 1, maxLines: 3, decoration: _dec('Izoh')),
          const SizedBox(height: 10),
          TextField(controller: _log, enabled: _canWrite, decoration: _dec("Suhbatni yozib qo'yish…")),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: cs.error))),
          if (_log2.isNotEmpty) ...[
            _sec('TARIX'),
            for (final e in _log2.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 82, child: Text(_fd('${e['date']}'), style: TextStyle(color: cs.outline, fontSize: 12))),
                  Expanded(child: Text('${e['text']}', style: const TextStyle(fontSize: 13))),
                ]),
              ),
          ],
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body))),
        if (_canWrite) footer,
      ]),
    );
  }
}

/// Bo'sh xonadonlar ro'yxati (lidning xonasiga mos, qidirish bilan)
class _AptPicker extends StatefulWidget {
  const _AptPicker({required this.session, required this.objectId, this.rooms});

  final Session session;
  final String objectId;
  final int? rooms;

  @override
  State<_AptPicker> createState() => _AptPickerState();
}

class _AptPickerState extends State<_AptPicker> {
  List<Map<String, dynamic>> _all = const [];
  bool _loading = true;
  String _q = '';
  int? _rooms;

  @override
  void initState() {
    super.initState();
    _rooms = widget.rooms;
    _load();
  }

  Future<void> _load() async {
    try {
      final out = <Map<String, dynamic>>[];
      var page = 1;
      while (true) {
        final p = await widget.session.api!.apartments(widget.objectId, status: 'free', page: page, perPage: 200);
        out.addAll(p.items);
        if (!p.meta.hasMore || page >= 5) break;
        page++;
      }
      if (mounted) setState(() {
            _all = out;
            _loading = false;
          });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = _all.where((a) => (_rooms == null || (a['rooms'] as num?)?.toInt() == _rooms) && (_q.isEmpty || '${a['number']}'.toLowerCase().contains(_q.toLowerCase()))).toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr("Bo'sh xonadonni tanlang"), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            TextField(onChanged: (v) => setState(() => _q = v.trim()), decoration: InputDecoration(hintText: tr('Xonadon raqami'), prefixIcon: const Icon(Icons.search), isDense: true, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(tr('Hammasi')), selected: _rooms == null, showCheckmark: false, onSelected: (_) => setState(() => _rooms = null))),
                for (final r in ({for (final a in _all) (a['rooms'] as num?)?.toInt() ?? 0}.toList()..sort()))
                  Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(r == 0 ? tr('Tijorat') : '$r ${tr('xona')}'), selected: _rooms == r, showCheckmark: false, onSelected: (_) => setState(() => _rooms = r))),
              ]),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: _loading
                  ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                  : shown.isEmpty
                      ? const Padding(padding: EdgeInsets.all(36), child: Center(child: Text("Bo'sh xonadon topilmadi")))
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: shown.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: cs.outline.withValues(alpha: 0.15)),
                          itemBuilder: (_, i) {
                            final a = shown[i];
                            return ListTile(
                              dense: true,
                              leading: Container(width: 44, height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Text('${a['number']}', style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary))),
                              title: Text('${roomsLabel(a['rooms'])} · ${area(a['area'] as num?)} m² · ${a['floor']}-${tr('qavat')}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              trailing: Text(money(a['price'] as num?), style: const TextStyle(fontWeight: FontWeight.w800)),
                              onTap: () => Navigator.pop(context, a),
                            );
                          },
                        ),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor qilish')))),
          ]),
        ),
      ),
    );
  }
}
