import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as w show Text;

import '../api.dart';
import '../assistant.dart';
import '../format.dart';
import '../location.dart';
import '../session.dart';
import '../theme.dart';
import '../l10n.dart';

/// «Men ishga keldim» kartasi: bosilganda joylashuv olinadi va smena boshlanadi. Ish davomida jonli taymer (nechchi soat ishladi),
/// keyin «Ketdim» (va xato yopilsa «Qaytdim»). Ish kuni tugagach — bugun ishlagan umumiy vaqt.
/// Rahbar-admin bu tugmani ko'rmaydi — uning o'rniga davomat sahifasida hammaning kelishi va joyi chiqadi.
class ShiftCard extends StatefulWidget {
  const ShiftCard({super.key, required this.session});

  final Session session;

  @override
  State<ShiftCard> createState() => _ShiftCardState();
}

class _ShiftCardState extends State<ShiftCard> {
  Map<String, dynamic>? _st;
  bool _busy = false;
  String? _error;
  Timer? _tick;
  final ValueNotifier<int> _sec = ValueNotifier(0);

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
    AppNav.shift.addListener(_onVoice);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && '${_st?['status']}' == 'working') _sec.value++; // faqat taymer yozuvi qayta chiziladi, butun karta emas
    });
  }

  @override
  void dispose() {
    AppNav.shift.removeListener(_onVoice);
    _tick?.cancel();
    _sec.dispose();
    super.dispose();
  }

  /// Ovozli buyruq («Ishga keldim» / «Ketdim») — tasdiqlangandan keyin shu yerda bajariladi
  void _onVoice() {
    final v = AppNav.shift.value;
    if (v == null) return;
    AppNav.shift.value = null;
    final st = '${_st?['status'] ?? 'none'}';
    if (v == 'start' && (st == 'none' || st == '')) _act('start');
    if (v == 'end' && st == 'working') _act('end');
  }

  Future<void> _load() async {
    try {
      final d = await s.api!.shift();
      if (mounted) {
        setState(() {
          _st = d;
          _error = null;
        });
      }
    } catch (e) {
      await s.handleError(e);
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    }
  }

  /// Kelgan / ketgan vaqt: serverning aniq vaqti (`in_ts`/`out_ts`), bo'lmasa «HH:MM» bugungi sana bilan
  DateTime? _when(String key) {
    final ts = DateTime.tryParse('${_st?['${key}_ts'] ?? ''}');
    if (ts != null) return ts.toLocal();
    final hm = '${_st?[key] ?? ''}'.split(':');
    if (hm.length < 2) return null;
    final h = int.tryParse(hm[0]), m = int.tryParse(hm[1]);
    if (h == null || m == null) return null;
    final n = DateTime.now();
    var d = DateTime(n.year, n.month, n.day, h, m);
    if (d.isAfter(n.add(const Duration(minutes: 2)))) d = d.subtract(const Duration(days: 1));
    return d;
  }

  Duration? get _worked {
    final a = _when('in');
    if (a == null) return null;
    final end = '${_st?['status']}' == 'left' ? (_when('out') ?? DateTime.now()) : DateTime.now();
    final d = end.difference(a);
    return d.isNegative ? Duration.zero : d;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// «8 soat 12 daq»
  String _human(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '$h ${tr('soat')} $m ${tr('daq')}' : '$m ${tr('daq')}';
  }

  Future<void> _act(String act) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    Fix? fix;
    if (act != 'reopen') {
      final r = await currentFix(real: act == 'start');
      fix = r.fix;
      // «Keldim» telefonda faqat obyektda (joylashuvsiz qabul qilinmaydi). Kompyuterda GPS yo'q — joylashuv topilmasa, tasdiqlab joylashuvsiz belgilanadi.
      if (fix == null && act == 'start' && !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        // «Keldim» faqat obyektda: joylashuvsiz qabul qilinmaydi
        if (mounted) {
          setState(() {
            _error = "${r.error ?? ''} ${tr("«Keldim» faqat obyektda belgilanadi.")}".trim();
            _busy = false;
          });
        }
        return;
      }
      if (fix == null) {
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Joylashuv olinmadi'),
            content: Text('${r.error}\n\nJoylashuvsiz belgilansinmi? Rahbar "joylashuvsiz" deb ko\'radi.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor qilish')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Baribir belgilash')),
            ],
          ),
        );
        if (go != true) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }
    }
    try {
      final d = await s.api!.shiftAct(act, lat: fix?.lat, lng: fix?.lng, acc: fix?.acc, mocked: fix?.mocked ?? false);
      if (!mounted) return;
      final queued = d['queued'] == true;
      setState(() {
        _st = d;
        _busy = false;
      });
      final dist = (act == 'start' ? d['in_dist'] : d['out_dist']) as num?;
      final where = fix == null
          ? 'joylashuvsiz'
          : dist == null
              ? 'joylashuv saqlandi'
              : (dist <= 300 ? 'obyektda' : 'obyektdan ${distLabel(dist)} uzoqda');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(queued ? "Offline saqlandi (vaqt va joylashuv bilan) — internet paydo bo'lganda yuboriladi" : switch (act) {
        'start' => 'Ish kuni boshlandi · $where',
        'end' => 'Ish kuni tugadi · $where',
        _ => 'Ish kuni qayta ochildi',
      })));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  Widget _pill(String label, String value, Color ink) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: context.pill, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pillBorder)),
          child: Row(children: [
            Text(label, style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            w.Text(value, style: TextStyle(color: ink, fontSize: 15.5, fontWeight: FontWeight.w900)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final st = '${_st?['status'] ?? ''}';
    // holat umuman olinmadi (masalan, server yangilanmagan yoki internet yo'q): yolg'on «Ishga keldim» o'rniga aniq xabar
    if (_st == null) {
      if (_error == null) return const SizedBox(height: 4);
      return Glass(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const IconTile(icon: Icons.cloud_off_rounded, color: Brand.orange, size: 40),
          const SizedBox(width: 12),
          Expanded(child: Text("Ish holatini olib bo'lmadi: $_error", style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: _load, child: const Text('Qayta')),
        ]),
      );
    }
    final (title, sub, label, act, tint) = switch (st) {
      'working' => ('Siz ishdasiz', '${_st?['in']} dan beri', 'Ketdim', 'end', Brand.teal),
      'left' => ('Ish kuni tugadi', 'Bugungi ish vaqti', 'Qaytdim', 'reopen', Brand.blue),
      _ => ('Ishga keldingizmi?', 'Tugmani bosing — joylashuvingiz belgilanadi', 'Ishga keldim', 'start', Brand.green),
    };
    final ink = context.isDark ? Color.lerp(tint, Colors.white, 0.72)! : Color.lerp(tint, Colors.black, 0.5)!;
    final d = _worked;
    final cs = Theme.of(context).colorScheme;
    return HeroGlass(
      tint: tint,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a), child: c)),
          child: Column(
            key: ValueKey(st),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                IconTile(icon: st == 'working' ? Icons.timer_rounded : (st == 'left' ? Icons.check_circle_rounded : Icons.location_on_rounded), color: tint, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
                    Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                  ]),
                ),
                if (st == 'working' && d != null) ValueListenableBuilder<int>(valueListenable: _sec, builder: (_, _, _) { final dd = _worked ?? Duration.zero; return w.Text('${_two(dd.inHours)}:${_two(dd.inMinutes % 60)}:${_two(dd.inSeconds % 60)}', style: TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: 0.5, fontFeatures: const [FontFeature.tabularFigures()])); }),
                if (st == 'left' && d != null) Text(_human(d), style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w900)),
                if (_st?['pending'] == true) Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.cloud_upload_outlined, color: ink, size: 20)),
              ]),
              if (st != 'none') ...[
                const SizedBox(height: 12),
                Row(children: [
                  _pill('Keldi', '${_st?['in'] ?? '—'}', ink),
                  const SizedBox(width: 10),
                  _pill('Ketdi', '${_st?['out'] ?? '—'}', ink),
                ]),
              ],
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: w.Text(_error!, style: TextStyle(color: cs.error, fontSize: 12.5, fontWeight: FontWeight.w600))),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: act == 'reopen'
                    ? OutlinedButton.icon(onPressed: _busy ? null : () => _act(act), icon: const Icon(Icons.undo_rounded, size: 19), label: Text(label))
                    : FilledButton.icon(
                        onPressed: _busy ? null : () => _act(act),
                        style: act == 'end' ? FilledButton.styleFrom(backgroundColor: Colors.red.withValues(alpha: 0.13), foregroundColor: Colors.red.shade800, side: BorderSide(color: Colors.red.withValues(alpha: 0.35))) : null,
                        icon: _busy ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: ink)) : Icon(act == 'start' ? Icons.login_rounded : Icons.logout_rounded, size: 19),
                        label: Text(_busy ? 'Joylashuv aniqlanmoqda…' : label),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
