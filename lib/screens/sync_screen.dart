import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../format.dart';
import '../l10n.dart';
import '../offline.dart';
import '../prefetch.dart';
import '../session.dart';
import '../webcache.dart';
import '../widgets.dart';

/// Sinxronlash: yuborilmagan (offline qilingan) sotuv va to'lovlar, telefondagi ma'lumot holati.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.session});

  final Session session;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool _busy = false;

  Future<void> _send() async {
    final api = widget.session.api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final n = await Offline.sync(api);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n > 0 ? '$n ta amal yuborildi' : (Offline.online.value ? 'Yuboriladigan amal yo\'q' : 'Internet yo\'q — keyinroq urinib ko\'ring'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contracts() async {
    setState(() => _busy = true);
    try {
      final n = await prefetchContracts(widget.session);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n > 0 ? '$n ta shartnoma telefonga saqlandi' : "Yuklab bo'lmadi — internetni tekshiring")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ({int files, int bytes})? _web;

  @override
  void initState() {
    super.initState();
    _loadWeb();
  }

  Future<void> _loadWeb() async {
    final st = await WebCache.stats();
    final idx = await WebCache.index();
    var objs = _objs;
    try {
      objs = await widget.session.api!.objects();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _web = st;
        _idx = idx;
        _objs = objs;
      });
    }
  }

  List<Map<String, dynamic>> _objs = const [];
  Map<String, Map<String, dynamic>> _idx = const {};
  int _perObject = 30;
  String? _busyObj;

  Future<void> _save3d(String objectId, String name) async {
    setState(() {
      _busy = true;
      _busyObj = objectId;
    });
    try {
      final r = await WebCache.prefetchObject(widget.session, objectId, perObject: _perObject);
      await _loadWeb();
      if (!mounted) return;
      final mb = (r.bytes / 1048576).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.network ? "Internet uzildi — ${r.files} fayl ($mb MB) saqlandi, qolganini keyinroq qayta urinib ko'ring" : '$name: ${r.apts} ta kvartira, ${r.files} fayl ($mb MB) saqlandi${r.errors > 0 ? ' · ${r.errors} ta yuklanmadi' : ''}'),
      ));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyObj = null;
        });
      }
    }
  }

  Future<void> _clear3d() async {
    await WebCache.clearDisk();
    await _loadWeb();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await prefetchAll(widget.session);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sinxronlash')),
      body: ListenableBuilder(
        listenable: Listenable.merge([Offline.online, Offline.pending, Offline.failed, Offline.progress, Offline.lastPrefetch, WebCache.status]),
        builder: (context, _) {
          final last = DateTime.tryParse(Offline.lastPrefetch.value ?? '')?.toLocal();
          final ops = Offline.ops;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Offline.online.value ? cs.primaryContainer.withValues(alpha: 0.6) : Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(18)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Offline.online.value ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
                    const SizedBox(width: 10),
                    Expanded(child: Text(Offline.online.value ? 'Internet bor' : "Offline — saqlangan ma'lumot ko'rsatilmoqda", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  ]),
                  const SizedBox(height: 8),
                  Text(last == null ? "Ma'lumotlar hali telefonga yuklanmagan." : "Telefondagi ma'lumot: ${formatDate(last.toIso8601String())} ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}"),
                  if (Offline.progress.value != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Yuklanmoqda: ${Offline.progress.value}', style: TextStyle(color: cs.outline))),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: _busy || Offline.pending.value == 0 ? null : _send, icon: const Icon(Icons.cloud_upload_outlined), label: const Text('Hozir yuborish'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: _busy || Offline.progress.value != null ? null : _refresh, icon: const Icon(Icons.cloud_download_outlined), label: const Text("Ma'lumotni yangilash"), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)))),
              ]),
              const SizedBox(height: 10),
              if (widget.session.me!.can('sales:read'))
                OutlinedButton.icon(
                  onPressed: _busy || Offline.progress.value != null ? null : _contracts,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text("Shartnomalarni offline uchun saqlash (oxirgi 20 ta)"),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              if (widget.session.me!.can('objects:read')) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outlineVariant)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.view_in_ar_outlined, color: cs.primary),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('3D va 360° (offline)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      _web == null || _web!.files == 0 ? 'Telefonda saqlanmagan.' : 'Saqlangan: ${_web!.files} fayl · ${(_web!.bytes / 1048576).toStringAsFixed(1)} MB',
                      style: TextStyle(color: cs.outline),
                    ),
                    if (WebCache.status.value != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(WebCache.status.value!, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600))),
                    const SizedBox(height: 10),
                    Text('Har obyektdan nechta kvartira', style: TextStyle(color: cs.outline, fontSize: 13)),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      segments: const [ButtonSegment(value: 10, label: Text('10')), ButtonSegment(value: 30, label: Text('30')), ButtonSegment(value: 60, label: Text('60'))],
                      selected: {_perObject},
                      onSelectionChanged: _busy ? null : (v) => setState(() => _perObject = v.first),
                    ),
                    const SizedBox(height: 10),
                    for (final o in _objs)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${o['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                _idx['${o['id']}'] == null ? 'Saqlanmagan' : '${_idx['${o['id']}']!['apts']} ta kvartira · ${((_idx['${o['id']}']!['bytes'] as num) / 1048576).toStringAsFixed(0)} MB',
                                style: TextStyle(color: cs.outline, fontSize: 12.5),
                              ),
                            ]),
                          ),
                          FilledButton.tonal(
                            onPressed: _busy || WebCache.status.value != null ? null : () => _save3d('${o['id']}', '${o['name']}'),
                            child: _busyObj == '${o['id']}' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_idx['${o['id']}'] == null ? 'Saqlash' : 'Yangilash'),
                          ),
                        ]),
                      ),
                    if (_web != null && _web!.files > 0)
                      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _busy ? null : _clear3d, icon: const Icon(Icons.delete_outline), label: const Text("Hammasini o'chirish"))),
                    const SizedBox(height: 6),
                    Text("Wi-Fi bilan saqlang. Har bir kvartiraning 3D, 360° va «uyda joyi» ko'rinishlari yuklanadi; uyning 3D modeli obyekt uchun bir marta saqlanadi (u 100 MB dan katta bo'lishi mumkin). Bir marta ochgan ko'rinishlaringiz o'zi ham saqlanadi.", style: TextStyle(color: cs.outline, fontSize: 12.5)),
                  ]),
                ),
              ],
              const SizedBox(height: 18),
              Text('Yuborilmagan amallar', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (ops.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text("Hammasi yuborilgan"))),
              for (final o in ops)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w800))),
                        o.state == 'failed' ? const StatusChip('Xato', Colors.red) : const StatusChip('Navbatda', Colors.orange),
                      ]),
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text(timeAgo(o.createdAt), style: TextStyle(color: cs.outline, fontSize: 12.5))),
                      if (o.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(o.error!, style: TextStyle(color: cs.error))),
                      if (o.state == 'failed')
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          TextButton(
                            onPressed: () async {
                              await Offline.discard(o.id);
                              if (mounted) setState(() {});
                            },
                            child: Text("O'chirish", style: TextStyle(color: cs.error)),
                          ),
                          TextButton(
                            onPressed: () async {
                              await Offline.retryFailed();
                              await _send();
                            },
                            child: const Text('Qayta urinish'),
                          ),
                        ]),
                    ]),
                  ),
                ),
              const SizedBox(height: 12),
              Text("Offline'da sotuv, bron va to'lovlar telefonda saqlanadi va internet paydo bo'lganda avtomatik yuboriladi. Shartnoma, chek va 3D internetsiz ochilishi uchun ularni oldin shu ekrandan (yoki internet bilan bir marta ochib) saqlab qo'ying.", style: TextStyle(color: cs.outline, fontSize: 13)),
            ],
          );
        },
      ),
    );
  }
}
