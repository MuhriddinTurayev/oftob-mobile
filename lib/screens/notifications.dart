import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../format.dart';
import '../session.dart';
import '../l10n.dart';
import '../theme.dart';

/// Bildirishnomalar markazi: serverdan voqealar lentasini har 10 soniyada (ilova ochiq turganda) so'raydi,
/// o'qilmaganlarni sanaydi va yangi voqea kelganda [onFresh] orqali xabar beradi.
/// Ilova yopiq/fonda bo'lsa — telefonga bildirishnomani push.dart (WorkManager, Android) chiqaradi; darhol — Telegram bot (tg_connect.dart).
class NotificationCenter extends ChangeNotifier with WidgetsBindingObserver {
  NotificationCenter(this.session, {this.onFresh});

  final Session session;
  final void Function(List<Map<String, dynamic>> fresh)? onFresh;

  static const _storage = FlutterSecureStorage();
  List<Map<String, dynamic>> items = const [];
  String _seen = '';
  final _known = <String>{};
  bool _first = true;
  bool _busy = false;
  bool _disposed = false;
  Timer? _timer;

  String get _key => 'notif_seen_${session.userId}';

  int get unread => items.where((e) => '${e['at']}'.compareTo(_seen) > 0).length;

  bool isUnread(Map<String, dynamic> e) => '${e['at']}'.compareTo(_seen) > 0;

  Future<void> start() async {
    try {
      _seen = await _storage.read(key: _key) ?? '';
    } catch (_) {}
    await refresh();
    WidgetsBinding.instance.addObserver(this);
    _arm();
  }

  /// Ilova ochiq turganda har 10 soniyada yangilanadi (deyarli real vaqt); fonda — to'xtaydi (batareya), qaytganda darhol yangilanadi
  static const period = Duration(seconds: 10);

  void _arm() {
    _timer?.cancel();
    if (!_disposed) _timer = Timer.periodic(period, (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      _arm();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _timer?.cancel();
    }
  }

  Future<void> refresh() async {
    final api = session.anyApi;
    if (api == null || _busy || _disposed) return;
    _busy = true;
    try {
      final list = await api.notifications();
      if (_disposed) return;
      final fresh = _first ? <Map<String, dynamic>>[] : list.where((e) => !_known.contains('${e['id']}') && isUnread(e)).toList();
      _known
        ..clear()
        ..addAll(list.map((e) => '${e['id']}'));
      _first = false;
      items = list;
      notifyListeners();
      if (fresh.isNotEmpty) onFresh?.call(fresh);
    } catch (e) {
      await session.handleError(e); // 401 bo'lsa — chiqarib yuboradi; boshqa xatolar jim (keyingi urinishda)
    } finally {
      _busy = false;
    }
  }

  /// Hammasini o'qilgan deb belgilash
  Future<void> markSeen() async {
    if (items.isEmpty) return;
    final latest = items.map((e) => '${e['at']}').reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    if (latest.compareTo(_seen) <= 0) return;
    _seen = latest;
    notifyListeners();
    try {
      await _storage.write(key: _key, value: _seen);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Qo'ng'iroqcha tugmasi (o'qilmaganlar soni bilan)
class BellButton extends StatelessWidget {
  const BellButton({super.key, required this.center, required this.onTap});

  final NotificationCenter center;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: center,
      builder: (context, _) {
        final n = center.unread;
        return IconButton(
          tooltip: tr('Bildirishnomalar'),
          onPressed: onTap,
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n > 99 ? '99+' : '$n'),
            child: Icon(n > 0 ? Icons.notifications_active : Icons.notifications_none, size: 28),
          ),
        );
      },
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.center, required this.onGo});

  final NotificationCenter center;
  final void Function(String go) onGo;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // ochilganda qaysilar yangi ekani ko'rinib turishi uchun — o'qilgan deb belgilash chiqishda
  late final Set<String> _newIds = widget.center.items.where(widget.center.isUnread).map((e) => '${e['id']}').toSet();

  @override
  void initState() {
    super.initState();
    widget.center.refresh();
  }

  @override
  void dispose() {
    widget.center.markSeen();
    super.dispose();
  }

  (IconData, Color) _look(String type) => switch (type) {
        'task' => (Icons.checklist, Colors.blue.shade700),
        'late' => (Icons.alarm, Colors.red.shade700),
        'money' => (Icons.payments_outlined, Brand.green),
        'receipt' => (Icons.receipt_long, Brand.teal),
        'ok' => (Icons.check_circle_outline, Brand.green),
        'alert' => (Icons.error_outline, Colors.red.shade700),
        'lead' => (Icons.person_add_alt, Colors.orange.shade800),
        'shift' => (Icons.how_to_reg, Brand.teal),
        'report' => (Icons.outgoing_mail, Colors.deepPurple.shade400),
        'support' => (Icons.support_agent, Brand.teal),
        'ai' => (Icons.auto_awesome, Colors.purple.shade400),
        _ => (Icons.notifications_none, Colors.blueGrey),
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Bildirishnomalar')),
      body: ListenableBuilder(
        listenable: widget.center,
        builder: (context, _) {
          final items = widget.center.items;
          return RefreshIndicator(
            onRefresh: widget.center.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                if (items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: Text('So\'nggi 14 kunda yangi voqea yo\'q'))),
                for (final e in items)
                  Card(
                    color: _newIds.contains('${e['id']}') ? cs.primaryContainer.withValues(alpha: 0.55) : null,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: e['go'] == null
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(context);
                              widget.onGo('${e['go']}');
                            },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CircleAvatar(backgroundColor: _look('${e['type']}').$2.withValues(alpha: 0.12), foregroundColor: _look('${e['type']}').$2, child: Icon(_look('${e['type']}').$1, size: 22)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${e['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                              if ('${e['body'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text('${e['body']}')),
                              Padding(padding: const EdgeInsets.only(top: 4), child: Text(timeAgo('${e['at']}'), style: TextStyle(color: cs.outline, fontSize: 12.5))),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    'Yangi voqealar ilova ochiq turganda har daqiqada tekshiriladi. Ilova yopiq turganda xabarlar Telegram orqali keladi — saytdagi profilingizdan Telegram\'ni ulang.',
                    style: TextStyle(color: cs.outline, fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
