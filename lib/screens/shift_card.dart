import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../location.dart';
import '../session.dart';
import '../l10n.dart';

/// «Men ishga keldim» kartasi: bosilganda joylashuv olinadi va smena boshlanadi. Keyin «Ketdim» (va xato yopilsa «Qaytdim»).
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

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await s.api!.shift();
      if (mounted) setState(() => _st = d);
    } catch (e) {
      await s.handleError(e);
      if (mounted) setState(() => _error = '$e');
    }
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(switch (act) {
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = '${_st?['status'] ?? ''}';
    if (_st == null && _error == null) return const SizedBox.shrink();
    final (title, sub, label, act, color) = switch (st) {
      'working' => ('Siz ishdasiz', '${_st?['in']} dan beri', 'Ketdim', 'end', cs.error),
      'left' => ('Ish kuni tugadi', '${_st?['in']} – ${_st?['out']}', 'Qaytdim', 'reopen', cs.primary),
      _ => ('Ishga keldingizmi?', 'Tugmani bosing — joylashuvingiz belgilanadi', 'Ishga keldim', 'start', cs.primary),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(st == 'working' ? Icons.work : (st == 'left' ? Icons.check_circle : Icons.location_on), color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(sub, style: TextStyle(color: cs.outline, fontSize: 13)),
            ]),
          ),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13))),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _act(act),
            style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
            icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Icon(act == 'start' ? Icons.login : (act == 'end' ? Icons.logout : Icons.undo)),
            label: Text(_busy ? 'Joylashuv aniqlanmoqda…' : label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
