import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import '../l10n.dart';
import '../sheet_select.dart';

Color _taskColor(String? s) => switch (s) {
      'done' => Brand.green,
      'doing' => Colors.blue,
      'review' => Colors.orange,
      _ => Colors.blueGrey,
    };

Color _prioColor(String? p) => switch (p) {
      'high' => Colors.red,
      'low' => Colors.blueGrey,
      _ => Colors.amber.shade700,
    };

String _prioName(String? p) => switch (p) {
      'high' => 'Yuqori',
      'low' => 'Past',
      _ => 'Oddiy',
    };

bool _overdue(Map t) {
  if ('${t['status']}' == 'done') return false;
  final due = '${t['due_date'] ?? ''}';
  if (due.length < 10) return false;
  return due.substring(0, 10).compareTo(DateTime.now().toIso8601String().substring(0, 10)) < 0;
}

/// Vazifalar: holat va "Mening vazifalarim" filtri, muddati o'tganlar qizil, karta orqali holat/progress o'zgartirish, yangi vazifa qo'yish.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.session});

  final Session session;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String? _status;
  bool _mine = false;
  Key _key = UniqueKey();
  Map<String, String> _objects = {};

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _loadObjects();
  }

  Future<void> _loadObjects() async {
    if (!s.me!.can('objects:read')) return;
    try {
      final o = await s.api!.objects();
      if (mounted) setState(() => _objects = {for (final x in o) '${x['id']}': '${x['name']}'});
    } catch (_) {}
  }

  void _reload() => setState(() => _key = UniqueKey());

  Future<void> _create() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewTaskSheet(session: s, objects: _objects),
    );
    if (ok == true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vazifa qo\'yildi')));
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canWrite = s.me!.can('tasks:write');
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canWrite ? GlassFab(onPressed: _create, icon: Icons.add_task, label: 'Yangi vazifa') : null,
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                if (s.userId > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: const Icon(Icons.person, size: 18),
                      label: const Text('Mening'),
                      selected: _mine,
                      showCheckmark: false,
                      onSelected: (v) => setState(() {
                        _mine = v;
                        _key = UniqueKey();
                      }),
                    ),
                  ),
                for (final f in const [(null, 'Hammasi'), ('todo', 'Qilish kerak'), ('doing', 'Jarayonda'), ('review', 'Tekshiruvda'), ('done', 'Bajarildi')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: _status == f.$1,
                      showCheckmark: false,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _status = f.$1;
                          _key = UniqueKey();
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PagedList(
              key: _key,
              session: s,
              emptyText: 'Vazifalar yo\'q',
              fetch: (p) => s.api!.tasks(page: p, status: _status, assignee: _mine ? s.userId : null),
              itemBuilder: (context, t) {
                final who = '${(t['assignee'] as Map?)?['name'] ?? ''}';
                final due = formatDate('${t['due_date']}');
                final progress = ((t['progress'] as num?) ?? 0).toInt();
                final late = _overdue(t);
                final st = '${t['status']}';
                return GlassRow(onTap: () => _open(t, canWrite), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 4, height: 54, margin: const EdgeInsets.only(right: 12, top: 2), decoration: BoxDecoration(color: _prioColor('${t['priority']}'), borderRadius: BorderRadius.circular(2))),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${t['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, decoration: st == 'done' ? TextDecoration.lineThrough : null, color: st == 'done' ? cs.outline : null)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 10, runSpacing: 2, children: [
                            if (who.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.person_outline, size: 15, color: cs.outline), const SizedBox(width: 3), Text(who, style: TextStyle(color: cs.outline, fontSize: 12.5))]),
                            if (due.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.event, size: 15, color: late ? cs.error : cs.outline), const SizedBox(width: 3), Text(due, style: TextStyle(color: late ? cs.error : cs.outline, fontSize: 12.5, fontWeight: late ? FontWeight.w700 : FontWeight.w400))]),
                            if ('${t['object_id'] ?? ''}'.isNotEmpty && _objects['${t['object_id']}'] != null) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.apartment, size: 15, color: cs.outline), const SizedBox(width: 3), Text(_objects['${t['object_id']}']!, style: TextStyle(color: cs.outline, fontSize: 12.5))]),
                          ]),
                          const SizedBox(height: 8),
                          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: progress / 100, minHeight: 5, color: _taskColor(st))),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        StatusChip(taskStatus(st), _taskColor(st)),
                        if (t['pending'] == true) const Padding(padding: EdgeInsets.only(top: 4), child: StatusChip('Yuborilmagan', Colors.orange)),
                      ]),
                    ]));
              },
            ),
          ),
        ],
      ),
    );
  }

  void _open(Map<String, dynamic> t, bool canWrite) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TaskSheet(session: s, task: t, canWrite: canWrite, objectName: _objects['${t['object_id']}'], onChanged: _reload),
    );
  }
}

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({required this.session, required this.task, required this.canWrite, required this.objectName, required this.onChanged});

  final Session session;
  final Map<String, dynamic> task;
  final bool canWrite;
  final String? objectName;
  final VoidCallback onChanged;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late String _status = '${widget.task['status']}';
  late double _progress = ((widget.task['progress'] as num?) ?? 0).toDouble();
  bool _busy = false;

  Future<void> _save({String? status, int? progress}) async {
    setState(() => _busy = true);
    try {
      final queued = await widget.session.api!.taskUpdate(widget.task['id'] as int, status: status, progress: progress);
      HapticFeedback.mediumImpact();
      widget.onChanged();
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        if (queued) {
          messenger.showSnackBar(const SnackBar(content: Text("Offline saqlandi — internet paydo bo'lganda yuboriladi")));
        } else if (status == 'done' && widget.task['can_accept'] == false) {
          // ijrochi «Bajarildi» bossa — rahbar tekshiradi va qabul qiladi (web bilan bir xil)
          messenger.showSnackBar(const SnackBar(content: Text('Rahbar tekshiruviga yuborildi')));
        }
      }
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, color: color))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = widget.task;
    final who = '${(t['assignee'] as Map?)?['name'] ?? ''}';
    final due = formatDate('${t['due_date']}');
    final desc = '${t['description'] ?? ''}'.trim();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, ctl) => ListView(
        controller: ctl,
        padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + MediaQuery.of(context).viewInsets.bottom),
        children: [
          Text('${t['title']}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          if (desc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(desc)),
          const SizedBox(height: 14),
          if (who.isNotEmpty) _kv('Ijrochi', who),
          if (due.isNotEmpty) _kv('Muddat', due, color: _overdue(t) ? cs.error : null),
          _kv('Muhimlik', _prioName('${t['priority']}'), color: _prioColor('${t['priority']}')),
          if (widget.objectName != null) _kv('Obyekt', widget.objectName!),
          if (widget.canWrite) ...[
            const SizedBox(height: 16),
            Text('Holati', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in const ['todo', 'doing', 'review', 'done'])
                ChoiceChip(
                  label: Text(taskStatus(s)),
                  selected: _status == s,
                  showCheckmark: false,
                  selectedColor: _taskColor(s).withValues(alpha: 0.2),
                  onSelected: _busy ? null : (_) => setState(() => _status = s),
                ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Text('Bajarilish', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${_progress.round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            Slider(value: _progress, min: 0, max: 100, divisions: 20, onChanged: _busy ? null : (v) => setState(() => _progress = v)),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        final changedStatus = _status != '${t['status']}';
                        final prog = _status == 'done' ? 100 : _progress.round();
                        _save(status: changedStatus ? _status : null, progress: prog != ((t['progress'] as num?) ?? 0).toInt() ? prog : null);
                      },
                child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Saqlash', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ] else
            Padding(padding: const EdgeInsets.only(top: 16), child: StatusChip(taskStatus(_status), _taskColor(_status))),
        ],
      ),
    );
  }
}

class _NewTaskSheet extends StatefulWidget {
  const _NewTaskSheet({required this.session, required this.objects});

  final Session session;
  final Map<String, String> objects;

  @override
  State<_NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends State<_NewTaskSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  List<Map<String, dynamic>> _users = const [];
  int? _assignee;
  String? _object;
  DateTime? _due;
  String _prio = 'normal';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.session.api!.users().then((u) {
      if (mounted) setState(() => _users = u);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Nima qilish kerakligini yozing.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final queued = await widget.session.api!.taskCreate(title: _title.text.trim(), description: _desc.text.trim(), objectId: _object, assigneeId: _assignee, dueDate: _due == null ? null : _d(_due!), priority: _prio);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        if (queued) messenger.showSnackBar(const SnackBar(content: Text("Offline saqlandi — internet paydo bo'lganda yuboriladi va ijrochiga xabar boradi")));
      }
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
          Text('Yangi vazifa', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(controller: _title, textCapitalization: TextCapitalization.sentences, decoration: dec('Nima qilish kerak')),
          const SizedBox(height: 12),
          TextField(controller: _desc, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: dec('Tafsilotlar (ixtiyoriy)')),
          const SizedBox(height: 12),
          SheetDropdown<int>(
            initialValue: _assignee,
            decoration: dec('Ijrochi'),
            items: [for (final u in _users) DropdownMenuItem(value: (u['id'] as num).toInt(), child: Text('${u['name']}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _assignee = v),
          ),
          if (widget.objects.isNotEmpty) ...[
            const SizedBox(height: 12),
            SheetDropdown<String>(
              initialValue: _object,
              decoration: dec('Obyekt (ixtiyoriy)'),
              items: [for (final e in widget.objects.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _object = v),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final p = await showDatePicker(context: context, initialDate: _due ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 730)));
              if (p != null) setState(() => _due = p);
            },
            icon: const Icon(Icons.event),
            label: Text(_due == null ? 'Muddat belgilash' : 'Muddat: ${formatDate(_d(_due!))}'),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final p in const ['low', 'normal', 'high'])
              ChoiceChip(label: Text(_prioName(p)), selected: _prio == p, showCheckmark: false, selectedColor: _prioColor(p).withValues(alpha: 0.22), onSelected: (_) => setState(() => _prio = p)),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: cs.error))),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Vazifa qo\'yish', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
