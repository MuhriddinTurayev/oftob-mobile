import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../format.dart';
import '../l10n.dart';
import '../offline.dart';
import '../prefetch.dart';
import '../session.dart';
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
        listenable: Listenable.merge([Offline.online, Offline.pending, Offline.failed, Offline.progress, Offline.lastPrefetch]),
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
              Text("Offline'da sotuv, bron va to'lovlar telefonda saqlanadi va internet paydo bo'lganda avtomatik yuboriladi. Shartnoma, chek va 3D uchun internet kerak.", style: TextStyle(color: cs.outline, fontSize: 13)),
            ],
          );
        },
      ),
    );
  }
}
