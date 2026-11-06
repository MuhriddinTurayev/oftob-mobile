import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as w show Text;

import '../api.dart';
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

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && '${_st?['status']}' == 'working') setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
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
      final r = await currentFix();
      fix = r.fix;
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
      final d = await s.api!.shiftAct(act, lat: fix?.lat, lng: fix?.lng, acc: fix?.acc);
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

  Widget _pill(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white.withValues(alpha: 0.22))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            w.Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
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
    final (title, sub, label, act, colors) = switch (st) {
      'working' => ('Siz ishdasiz', '${_st?['in']} dan beri', 'Ketdim', 'end', const [Color(0xFF0B7A3B), Color(0xFF0F9460), Color(0xFF0F8F8A)]),
      'left' => ('Ish kuni tugadi', 'Bugungi ish vaqti', 'Qaytdim', 'reopen', const [Color(0xFF39556F), Color(0xFF4A7392)]),
      _ => ('Ishga keldingizmi?', 'Tugmani bosing — joylashuvingiz belgilanadi', 'Ishga keldim', 'start', const [Color(0xFF0B7A3B), Color(0xFF12A15C)]),
    };
    final d = _worked;
    final clock = d == null ? '' : '${_two(d.inHours)}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.32), blurRadius: 26, offset: const Offset(0, 12))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(children: [
          Positioned(right: -36, top: -44, child: Container(width: 170, height: 170, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10)))),
          Positioned(left: -50, bottom: -70, child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.amber.withValues(alpha: st == 'left' ? 0.0 : 0.14)))),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: Icon(st == 'working' ? Icons.timer_rounded : (st == 'left' ? Icons.check_circle_rounded : Icons.location_on_rounded), color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12.5)),
                  ]),
                ),
                if (_st?['pending'] == true) const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 20),
              ]),
              if (st == 'working' && d != null) ...[
                const SizedBox(height: 14),
                Center(child: w.Text(clock, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontFeatures: [FontFeature.tabularFigures()]))),
                Center(child: Text('ishlagan vaqt', style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12.5))),
              ],
              if (st == 'left' && d != null) ...[
                const SizedBox(height: 12),
                Center(child: Text(_human(d), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900))),
              ],
              if (st != 'none') ...[
                const SizedBox(height: 12),
                Row(children: [
                  _pill('Keldi', '${_st?['in'] ?? '—'}'),
                  const SizedBox(width: 10),
                  _pill('Ketdi', '${_st?['out'] ?? '—'}'),
                ]),
              ],
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: w.Text(_error!, style: const TextStyle(color: Color(0xFFFFE0E0), fontSize: 12.5, fontWeight: FontWeight.w600))),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _act(act),
                  style: FilledButton.styleFrom(backgroundColor: act == 'end' ? Colors.white : Colors.white.withValues(alpha: act == 'reopen' ? 0.2 : 1), foregroundColor: act == 'end' ? const Color(0xFFC62828) : (act == 'reopen' ? Colors.white : colors.first), disabledBackgroundColor: Colors.white.withValues(alpha: 0.6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  icon: _busy ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: colors.first)) : Icon(act == 'start' ? Icons.login_rounded : (act == 'end' ? Icons.logout_rounded : Icons.undo_rounded), size: 20),
                  label: Text(_busy ? 'Joylashuv aniqlanmoqda…' : label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
