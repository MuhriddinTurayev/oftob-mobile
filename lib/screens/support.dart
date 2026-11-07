import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import '../l10n.dart';

/// Yordam (support): xodim → kompaniya direktori; direktor → platforma administratori.
/// Xodimda — to'g'ridan-to'g'ri direktor bilan chat. Direktorda — xodimlar murojaatlari ro'yxati va o'zining platforma chati.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.session});

  final Session session;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  Timer? _t;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 6), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final d = await s.api!.supportIndex();
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      await s.handleError(e);
      if (mounted && !quiet) setState(() => _error = '$e');
    }
  }

  void _open(Map<String, dynamic>? thread, String title) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SupportChat(session: s, thread: thread, title: title))).then((_) => _load(quiet: true));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_d == null) return _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    final d = _d!;
    final own = d['own'] as Map?;
    final level = '${d['own_level'] ?? ''}';
    final desk = d['desk'] == true;
    // oddiy xodim: darhol direktor bilan chat
    if (!desk && level == 'company') {
      return SupportChat(session: s, thread: own == null ? null : Map<String, dynamic>.from(own), title: tr('Direktor'), embedded: true);
    }
    final inbox = ((d['inbox'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
        children: [
          if (level == 'platform')
            _ThreadTile(
              icon: Icons.support_agent_rounded,
              color: Brand.blue,
              title: tr('Platforma administratori'),
              sub: own?['last_text'] != null ? '${own!['last_text']}' : tr('Platforma bo\'yicha savol yoki taklif yozing'),
              unread: (own?['unread'] as num?)?.toInt() ?? 0,
              at: own?['last_at'] as String?,
              onTap: () => _open(own == null ? null : Map<String, dynamic>.from(own), tr('Platforma administratori')),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Text('Xodimlar murojaatlari', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (inbox.isEmpty)
            Padding(padding: const EdgeInsets.all(28), child: Center(child: Text("Hozircha murojaat yo'q", style: TextStyle(color: cs.outline)))),
          for (final t in inbox)
            _ThreadTile(
              icon: Icons.person_rounded,
              color: Brand.green,
              title: '${t['title']}',
              sub: '${t['role'] ?? ''}${'${t['last_text'] ?? ''}'.isEmpty ? '' : ' · ${t['last_text']}'}',
              unread: (t['unread'] as num?)?.toInt() ?? 0,
              at: t['last_at'] as String?,
              onTap: () => _open(t, '${t['title']}'),
            ),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.icon, required this.color, required this.title, required this.sub, required this.unread, required this.onTap, this.at});

  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final int unread;
  final String? at;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassRow(
        margin: EdgeInsets.zero,
        onTap: onTap,
        child: Row(children: [
          IconTile(icon: icon, color: color, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (at != null) Text(formatDateTime(at).split(' ').last, style: TextStyle(color: cs.outline, fontSize: 11.5)),
            if (unread > 0)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(10)),
                child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// Chat oynasi: xabarlar har 4 soniyada yangilanadi (ochiq turganda), yuborish — darhol ko'rinadi
class SupportChat extends StatefulWidget {
  const SupportChat({super.key, required this.session, required this.thread, required this.title, this.embedded = false});

  final Session session;
  final Map<String, dynamic>? thread;
  final String title;

  /// Bo'lim ichida (o'z sarlavhasisiz) ko'rsatiladi
  final bool embedded;

  @override
  State<SupportChat> createState() => _SupportChatState();
}

class _SupportChatState extends State<SupportChat> {
  final _items = <Map<String, dynamic>>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int? _id;
  int _last = 0;
  bool _loading = true, _sending = false;
  Timer? _t;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _id = (widget.thread?['id'] as num?)?.toInt();
    _poll(first: true);
    _t = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _t?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _poll({bool first = false}) async {
    if (_id == null) {
      if (first && mounted) setState(() => _loading = false);
      return;
    }
    try {
      final r = await s.api!.supportMessages(_id!, after: _last);
      final list = ((r['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      if (list.isNotEmpty || first) {
        setState(() {
          for (final m in list) {
            if (_items.any((x) => x['id'] == m['id'])) continue;
            _items.add(m);
            _last = ((m['id'] as num?)?.toInt() ?? 0) > _last ? (m['id'] as num).toInt() : _last;
          }
          _loading = false;
        });
        if (list.isNotEmpty) _toBottom();
      }
    } catch (e) {
      await s.handleError(e);
      if (mounted && first) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final r = await s.api!.supportSend(body: body, threadId: _id);
      final m = Map<String, dynamic>.from((r['message'] as Map?) ?? const {});
      _id ??= (((r['thread'] as Map?)?['id']) as num?)?.toInt();
      _input.clear();
      HapticFeedback.selectionClick();
      if (mounted) {
        setState(() {
          _items.add(m);
          final id = (m['id'] as num?)?.toInt() ?? 0;
          if (id > _last) _last = id;
        });
        _toBottom();
      }
    } catch (e) {
      await s.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : '$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = Column(children: [
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.forum_outlined, size: 48, color: cs.outline),
                        const SizedBox(height: 10),
                        Text("Savolingizni yozing — javob shu yerga va bildirishnomaga keladi", textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
                      ]),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    itemCount: _items.length,
                    itemBuilder: (_, i) => _Bubble(m: _items[i]),
                  ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, widget.embedded ? NavInset.of(context) + 8 : 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: tr('Xabar yozing…'), counterText: '', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
            ),
          ]),
        ),
      ),
    ]);
    if (widget.embedded) return body;
    return Scaffold(backgroundColor: Colors.transparent, appBar: AppBar(title: Text(widget.title)), body: body);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m});

  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = m['mine'] == true;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
        decoration: BoxDecoration(
          color: me ? cs.primary : (context.isDark ? const Color(0xCC24302B) : Colors.white.withValues(alpha: 0.85)),
          borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(me ? 18 : 4), bottomRight: Radius.circular(me ? 4 : 18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!me) Text('${m['author'] ?? ''}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: cs.primary)),
          SelectableText('${m['body'] ?? ''}', style: TextStyle(color: me ? Colors.white : context.ink, fontSize: 14.5, height: 1.3)),
          const SizedBox(height: 2),
          Align(alignment: Alignment.bottomRight, child: Text(formatDateTime('${m['at'] ?? ''}'), style: TextStyle(fontSize: 10.5, color: me ? Colors.white70 : cs.outline))),
        ]),
      ),
    );
  }
}
