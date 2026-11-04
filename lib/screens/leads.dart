import 'package:flutter/material.dart';

import '../format.dart';
import '../session.dart';
import '../widgets.dart';

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key, required this.session});

  final Session session;

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  Key _key = UniqueKey();

  Future<void> _add() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LeadForm(session: widget.session),
    );
    if (created == true) setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = widget.session.me!.can('leads:write');
    return Scaffold(
      body: PagedList(
        key: _key,
        session: widget.session,
        emptyText: 'Hozircha arizalar yo\'q',
        fetch: (p) => widget.session.api!.leads(page: p),
        itemBuilder: (context, l) {
          final name = '${l['name'] ?? ''}'.trim();
          final phone = '${l['phone'] ?? ''}'.trim();
          final info = <String>[
            if (l['source'] != null && '${l['source']}'.isNotEmpty) '${l['source']}',
            if (l['rooms'] != null) '${l['rooms']} xona',
            if (l['budget'] != null) 'byudjet ${money(l['budget'] as num?)}',
          ].join(' · ');
          final msg = '${l['message'] ?? ''}'.trim();
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(name.isNotEmpty ? name : (phone.isNotEmpty ? phone : 'Nomsiz ariza')),
            subtitle: Text([if (name.isNotEmpty && phone.isNotEmpty) phone, if (info.isNotEmpty) info, if (msg.isNotEmpty) msg].join('\n')),
            isThreeLine: msg.isNotEmpty,
            trailing: Text(formatDate('${l['created_at']}'), style: Theme.of(context).textTheme.bodySmall),
          );
        },
      ),
      floatingActionButton: canWrite ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Ariza')) : null,
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

  @override
  void dispose() {
    for (final c in [_name, _phone, _rooms, _budget, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty && _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ism yoki telefonni kiriting')));
      return;
    }
    setState(() => _busy = true);
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
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Yangi ariza', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Ism', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _rooms, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Xona', border: OutlineInputBorder()))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: TextField(controller: _budget, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Byudjet', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _message, maxLines: 3, decoration: const InputDecoration(labelText: 'Izoh', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Saqlash'))),
          ],
        ),
      ),
    );
  }
}
