import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../session.dart';
import '../widgets.dart';
import '../l10n.dart';

/// Kanal (manba) ko'rinishi: ikonka, rang, nom.
({IconData icon, Color color, String name}) _channel(String? ch) {
  switch ((ch ?? '').toLowerCase()) {
    case 'instagram':
      return (icon: Icons.camera_alt_outlined, color: const Color(0xFFD6249F), name: 'Instagram');
    case 'facebook':
      return (icon: Icons.thumb_up_alt_outlined, color: const Color(0xFF1877F2), name: 'Facebook');
    case 'whatsapp':
      return (icon: Icons.chat_outlined, color: const Color(0xFF25D366), name: 'WhatsApp');
    case 'telegram':
      return (icon: Icons.send_outlined, color: const Color(0xFF229ED9), name: 'Telegram');
    case 'site':
    case 'form':
    case 'web':
      return (icon: Icons.language, color: const Color(0xFF107C41), name: 'Sayt');
    case 'api':
      return (icon: Icons.api, color: Colors.blueGrey, name: 'API');
    case 'phone':
    case 'call':
      return (icon: Icons.call_outlined, color: Colors.teal, name: 'Qo\'ng\'iroq');
    case '':
      return (icon: Icons.inbox_outlined, color: Colors.blueGrey, name: 'Boshqa');
    default:
      return (icon: Icons.inbox_outlined, color: Colors.blueGrey, name: ch![0].toUpperCase() + ch.substring(1));
  }
}

DateTime? _when(Map l) => DateTime.tryParse('${l['created_at'] ?? ''}')?.toLocal();

String _day(DateTime? d) {
  if (d == null) return '';
  final n = DateTime.now();
  final t = DateTime(n.year, n.month, n.day);
  final x = DateTime(d.year, d.month, d.day);
  if (x == t) return 'Bugun';
  if (x == t.subtract(const Duration(days: 1))) return 'Kecha';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

String _hm(DateTime? d) => d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// Lidlar (mijoz arizalari): kanal bo'yicha filtr, qidiruv, kunlar bo'yicha guruh, qo'ng'iroq / WhatsApp / Telegram, yangi ariza qo'shish.
class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key, required this.session});

  final Session session;

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  List<Map<String, dynamic>> _all = const [];
  bool _loading = true;
  String? _error;
  String? _channelFilter;
  String _q = '';

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = _all.isEmpty;
        _error = null;
      });
    }
    try {
      final out = <Map<String, dynamic>>[];
      var page = 1;
      while (true) {
        final p = await s.api!.leads(page: page, perPage: 100);
        out.addAll(p.items);
        if (!p.meta.hasMore || page >= 5) break;
        page++;
      }
      if (!mounted) return;
      setState(() {
        _all = out;
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

  Future<void> _add() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LeadForm(session: s),
    );
    if (created == true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ariza qo\'shildi')));
      _load(quiet: true);
    }
  }

  bool _passes(Map l) {
    if (_channelFilter != null && '${l['channel'] ?? ''}'.toLowerCase() != _channelFilter) return false;
    if (_q.isEmpty) return true;
    final t = '${l['name'] ?? ''} ${l['phone'] ?? ''} ${l['message'] ?? ''} ${l['source'] ?? ''} ${l['username'] ?? ''}'.toLowerCase();
    return t.contains(_q.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canWrite = s.me!.can('leads:write');
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _all.isEmpty) return ErrorView(message: _error!, onRetry: _load);

    final counts = <String, int>{};
    for (final l in _all) {
      final k = '${l['channel'] ?? ''}'.toLowerCase();
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final shown = _all.where(_passes).toList();
    final rows = <Widget>[];
    String? lastDay;
    for (final l in shown) {
      final d = _when(l);
      final day = _day(d);
      if (day != lastDay) {
        lastDay = day;
        rows.add(Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text(day, style: TextStyle(color: cs.outline, fontWeight: FontWeight.w800, fontSize: 13))));
      }
      rows.add(_LeadRow(l: l, onTap: () => _open(l)));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canWrite ? Padding(padding: const EdgeInsets.only(bottom: 92), child: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Ariza'))) : null,
      body: RefreshIndicator(
        onRefresh: () => _load(quiet: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 132),
          children: [
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
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text('Hammasi ${_all.length}'), selected: _channelFilter == null, showCheckmark: false, onSelected: (_) => setState(() => _channelFilter = null)),
                  ),
                  for (final e in counts.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(_channel(e.key).icon, size: 18, color: _channel(e.key).color),
                        label: Text('${_channel(e.key).name} ${e.value}'),
                        selected: _channelFilter == e.key,
                        showCheckmark: false,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _channelFilter = e.key);
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (shown.isEmpty) const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Arizalar topilmadi'))),
            ...rows,
          ],
        ),
      ),
    );
  }

  void _open(Map<String, dynamic> l) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LeadSheet(l: l),
    );
  }
}

class _LeadRow extends StatelessWidget {
  const _LeadRow({required this.l, required this.onTap});

  final Map<String, dynamic> l;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ch = _channel('${l['channel'] ?? ''}');
    final name = '${l['name'] ?? ''}'.trim();
    final phone = '${l['phone'] ?? ''}'.trim();
    final msg = '${l['message'] ?? ''}'.trim();
    final info = [
      if ('${l['source'] ?? ''}'.isNotEmpty) '${l['source']}',
      if (l['rooms'] != null) '${l['rooms']} xona',
      if (l['budget'] != null) 'byudjet ${money(l['budget'] as num?)}',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 22, backgroundColor: ch.color.withValues(alpha: 0.14), foregroundColor: ch.color, child: Icon(ch.icon, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name.isNotEmpty ? name : (phone.isNotEmpty ? phone : 'Nomsiz ariza'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                Text(_hm(_when(l)), style: TextStyle(color: cs.outline, fontSize: 12)),
              ]),
              if (name.isNotEmpty && phone.isNotEmpty) Text(phone, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 13)),
              if (info.isNotEmpty) Text(info, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
              if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _LeadSheet extends StatelessWidget {
  const _LeadSheet({required this.l});

  final Map<String, dynamic> l;

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ch = _channel('${l['channel'] ?? ''}');
    final name = '${l['name'] ?? ''}'.trim();
    final phone = '${l['phone'] ?? ''}'.trim();
    final user = '${l['username'] ?? ''}'.trim().replaceFirst('@', '');
    final msg = '${l['message'] ?? ''}'.trim();
    final d = _when(l);
    final digits = _digits(phone);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, ctl) => ListView(
        controller: ctl,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Row(children: [
            CircleAvatar(radius: 26, backgroundColor: ch.color.withValues(alpha: 0.14), foregroundColor: ch.color, child: Icon(ch.icon, size: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isNotEmpty ? name : (phone.isNotEmpty ? phone : 'Nomsiz ariza'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                Text('${ch.name} · ${_day(d)} ${_hm(d)}', style: TextStyle(color: cs.outline, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          if (phone.isNotEmpty)
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.call),
                  label: Text(phone, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (digits.length >= 9) ...[
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: tr('WhatsApp'),
                  onPressed: () => launchUrl(Uri.parse('https://wa.me/${digits.length == 9 ? '998$digits' : digits}'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.chat),
                ),
              ],
            ]),
          if (user.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('https://t.me/$user'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.send_outlined), label: Text('@$user')),
            ),
          const SizedBox(height: 14),
          if ('${l['source'] ?? ''}'.isNotEmpty) _kv(context, 'Manba', '${l['source']}'),
          if (l['rooms'] != null) _kv(context, 'Xonalar', '${l['rooms']}'),
          if (l['budget'] != null) _kv(context, 'Byudjet', '${money(l['budget'] as num?)} so\'m'),
          if (msg.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Izoh', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14)), child: Text(msg)),
          ],
        ],
      ),
    );
  }
}

class _LeadForm extends StatefulWidget {
  const _LeadForm({required this.session});

  final Session session;

  @override
  State<_LeadForm> createState() => _LeadFormState();
}

class _LeadFormState extends State<_LeadForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _rooms = TextEditingController();
  final _budget = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _rooms, _budget, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty && _phone.text.trim().isEmpty) {
      setState(() => _error = 'Ism yoki telefonni kiriting.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api!.leadCreate(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        source: 'Mobil ilova',
        rooms: int.tryParse(_rooms.text.trim()),
        budget: int.tryParse(_budget.text.replaceAll(' ', '').trim()),
        message: _message.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
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
    InputDecoration dec(String l) => InputDecoration(labelText: tr(l), filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none));
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Yangi ariza', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: dec('Ism')),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: dec('Telefon')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _rooms, keyboardType: TextInputType.number, decoration: dec('Xona'))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: TextField(controller: _budget, keyboardType: TextInputType.number, decoration: dec('Byudjet'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _message, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: dec('Izoh')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: cs.error))),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Saqlash', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
