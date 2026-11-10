import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import '../l10n.dart';

const _kinds = {'supplier': 'Yetkazib beruvchi', 'contractor': 'Pudratchi', 'client': 'Mijoz', 'other': 'Boshqa'};
const _kindIcons = {'supplier': Icons.local_shipping_rounded, 'contractor': Icons.engineering_rounded, 'client': Icons.person_rounded, 'other': Icons.business_rounded};
const _kindColors = {'supplier': Brand.orange, 'contractor': Brand.blue, 'client': Brand.pink, 'other': Brand.purple};

/// Kontragentlar: qidiruv, tur bo'yicha filtr, kartochka (qo'ng'iroq) va yangisini qo'shish (saytdagi kabi «tekshiruvda» holatida).
class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key, required this.session});

  final Session session;

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  Key _key = UniqueKey();
  String _q = '';
  String? _kind;

  bool get _canWrite => widget.session.me!.can('parties:write');

  void _reload() => setState(() => _key = UniqueKey());

  void _sheet(Map<String, dynamic> c) {
    final cs = Theme.of(context).colorScheme;
    final kind = '${c['kind']}';
    final phone = '${c['phone'] ?? ''}';
    Widget line(IconData i, String label, String? v) => (v == null || v.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, size: 18, color: cs.outline),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: cs.outline, fontSize: 11.5)), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))])),
            ]),
          );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconTile(icon: _kindIcons[kind] ?? Icons.business_rounded, color: _kindColors[kind] ?? Brand.purple, size: 48),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${c['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), Text(_kinds[kind] ?? kind, style: TextStyle(color: cs.outline))])),
              _statusChip('${c['status']}'),
            ]),
            const SizedBox(height: 16),
            line(Icons.badge_outlined, 'STIR (INN)', '${c['inn'] ?? ''}'),
            line(Icons.phone_outlined, 'Telefon', phone),
            line(Icons.person_outline, 'Aloqa shaxsi', '${c['contact'] ?? ''}'),
            line(Icons.place_outlined, 'Manzil', '${c['address'] ?? ''}'),
            line(Icons.account_balance_outlined, 'Bank', '${c['bank'] ?? ''}'),
            line(Icons.sticky_note_2_outlined, 'Izoh', '${c['note'] ?? ''}'),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 4),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => launchUrl(Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}')), icon: const Icon(Icons.call_rounded, size: 18), label: const Text("Qo'ng'iroq qilish"))),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _statusChip(String st) {
    final (label, color) = switch (st) {
      'ok' => ('Tekshirilgan', Brand.green),
      'suspicious' => ('Shubhali', Colors.orange.shade800),
      'blocked' => ('Bloklangan', Colors.red.shade700),
      _ => ('Tekshiruvda', Colors.blueGrey),
    };
    return StatusChip(label, color);
  }

  Future<void> _add() async {
    final name = TextEditingController(), inn = TextEditingController(), phone = TextEditingController(), contact = TextEditingController();
    var kind = 'supplier';
    String? err;
    var busy = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Yangi kontragent', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [for (final e in _kinds.entries) ChoiceChip(label: Text(e.value), selected: kind == e.key, onSelected: (_) => set(() => kind = e.key))]),
              const SizedBox(height: 12),
              TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr('Nomi'))),
              const SizedBox(height: 10),
              TextField(controller: inn, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('STIR (INN)'))),
              const SizedBox(height: 10),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Telefon'))),
              const SizedBox(height: 10),
              TextField(controller: contact, decoration: InputDecoration(labelText: tr('Aloqa shaxsi'))),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 13))),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (name.text.trim().isEmpty) {
                            set(() => err = 'Nomini kiriting');
                            return;
                          }
                          set(() {
                            busy = true;
                            err = null;
                          });
                          try {
                            await widget.session.api!.counterpartyCreate({'name': name.text.trim(), 'kind': kind, if (inn.text.trim().isNotEmpty) 'inn': inn.text.trim(), if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(), if (contact.text.trim().isNotEmpty) 'contact': contact.text.trim()});
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } on ApiException catch (e) {
                            set(() {
                              busy = false;
                              err = e.code == 'duplicate' ? 'Bu STIR bilan kontragent allaqachon bor' : e.message;
                            });
                          }
                        },
                  child: Text(busy ? 'Saqlanmoqda…' : 'Saqlash'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _canWrite ? GlassFab(onPressed: _add, icon: Icons.add, label: "Qo'shish") : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Glass(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Icon(Icons.search_rounded, color: cs.outline),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  onSubmitted: (v) {
                    _q = v.trim();
                    _reload();
                  },
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(hintText: tr('Nomi, STIR yoki telefon'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('Hammasi'), selected: _kind == null, showCheckmark: false, onSelected: (_) => setState(() {
                    _kind = null;
                    _key = UniqueKey();
                  }))),
              for (final e in _kinds.entries)
                Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(e.value), selected: _kind == e.key, showCheckmark: false, onSelected: (_) => setState(() {
                      _kind = e.key;
                      _key = UniqueKey();
                    }))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: PagedList(
            key: _key,
            session: widget.session,
            emptyText: 'Kontragent topilmadi',
            fetch: (p) => widget.session.api!.counterparties(page: p, q: _q, kind: _kind),
            itemBuilder: (context, c) {
              final kind = '${c['kind']}';
              final sub = [if ('${c['inn'] ?? ''}'.isNotEmpty) 'STIR ${c['inn']}', if ('${c['phone'] ?? ''}'.isNotEmpty) '${c['phone']}'].join(' · ');
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Glass(
                  blur: false,
                  onTap: () => _sheet(c),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    IconTile(icon: _kindIcons[kind] ?? Icons.business_rounded, color: _kindColors[kind] ?? Brand.purple, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('${_kinds[kind] ?? kind}${sub.isEmpty ? '' : ' · $sub'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                      ]),
                    ),
                    _statusChip('${c['status']}'),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// To'lov so'rovlari: holat bo'yicha filtr; summa, maqsad, kontragent, muddat.
class PaymentRequestsScreen extends StatefulWidget {
  const PaymentRequestsScreen({super.key, required this.session});

  final Session session;

  @override
  State<PaymentRequestsScreen> createState() => _PaymentRequestsScreenState();
}

class _PaymentRequestsScreenState extends State<PaymentRequestsScreen> {
  Key _key = UniqueKey();
  String? _status;

  static const _statuses = {'pending': 'Kutilmoqda', 'approved': 'Tasdiqlangan', 'paid': "To'langan", 'rejected': 'Rad etilgan', 'cancelled': 'Bekor qilingan'};

  static Color _color(String s) => switch (s) {
        'paid' => Brand.green,
        'approved' => Brand.blue,
        'rejected' => Colors.red.shade700,
        'cancelled' => Colors.blueGrey,
        _ => Colors.orange.shade800,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('Hammasi'), selected: _status == null, showCheckmark: false, onSelected: (_) => setState(() {
                  _status = null;
                  _key = UniqueKey();
                }))),
            for (final e in _statuses.entries)
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(e.value), selected: _status == e.key, showCheckmark: false, onSelected: (_) => setState(() {
                    _status = e.key;
                    _key = UniqueKey();
                  }))),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: PagedList(
          key: _key,
          session: widget.session,
          emptyText: "To'lov so'rovi yo'q",
          fetch: (p) => widget.session.api!.paymentRequests(page: p, status: _status),
          itemBuilder: (context, r) {
            final st = '${r['status']}';
            final cp = (r['counterparty'] as Map?) ?? const {};
            final amount = (r['amount'] as num?) ?? 0;
            final c = _color(st);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Glass(
                blur: false,
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    IconTile(icon: Icons.request_quote_rounded, color: c, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${cp['name'] ?? r['category'] ?? "To'lov so'rovi"}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('№${r['number'] ?? r['id']}${r['due_date'] != null ? ' · ${tr('muddat')} ${formatDate('${r['due_date']}')}' : ''}', style: TextStyle(color: cs.outline, fontSize: 12.5)),
                      ]),
                    ),
                    StatusChip(_statuses[st] ?? st, c),
                  ]),
                  const SizedBox(height: 10),
                  Text('${money(amount)} ${r['currency'] == 'UZS' || r['currency'] == null ? "so'm" : r['currency']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                  if ('${r['purpose'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['purpose']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 13))),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
