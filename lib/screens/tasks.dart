import 'package:flutter/material.dart';

import '../format.dart';
import '../session.dart';
import '../widgets.dart';

Color _taskColor(String? s) => switch (s) {
      'done' => Colors.green,
      'doing' => Colors.blue,
      'review' => Colors.orange,
      _ => Colors.blueGrey,
    };

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.session});

  final Session session;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String? _status;
  Key _key = UniqueKey();

  Future<void> _setStatus(Map<String, dynamic> t) async {
    final next = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in const ['todo', 'doing', 'review', 'done'])
              ListTile(
                leading: Icon(s == t['status'] ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: _taskColor(s)),
                title: Text(taskStatus(s)),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (next == null || next == t['status'] || !mounted) return;
    try {
      await widget.session.api!.taskUpdate(t['id'] as int, status: next, progress: next == 'done' ? 100 : null);
      if (mounted) setState(() => _key = UniqueKey());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = widget.session.me!.can('tasks:write');
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final f in const [(null, 'Hammasi'), ('todo', 'Qilish kerak'), ('doing', 'Jarayonda'), ('review', 'Tekshiruvda'), ('done', 'Bajarildi')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.$2),
                    selected: _status == f.$1,
                    onSelected: (_) => setState(() {
                      _status = f.$1;
                      _key = UniqueKey();
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: PagedList(
            key: _key,
            session: widget.session,
            emptyText: 'Vazifalar yo\'q',
            fetch: (p) => widget.session.api!.tasks(page: p, status: _status),
            itemBuilder: (context, t) {
              final who = (t['assignee'] as Map?)?['name'];
              final due = formatDate('${t['due_date']}');
              final progress = ((t['progress'] as num?) ?? 0).toInt();
              return ListTile(
                onTap: canWrite ? () => _setStatus(t) : null,
                title: Text('${t['title']}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text([if (who != null) '$who', if (due.isNotEmpty) 'muddat $due'].join(' · ')),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: progress / 100, borderRadius: BorderRadius.circular(4)),
                  ],
                ),
                trailing: StatusChip(taskStatus('${t['status']}'), _taskColor('${t['status']}')),
              );
            },
          ),
        ),
      ],
    );
  }
}
