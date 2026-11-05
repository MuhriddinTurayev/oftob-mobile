import 'package:flutter/material.dart' hide Text;


import 'api.dart';
import 'offline.dart';
import 'session.dart';
import 'l10n.dart';

/// Sahifalab yuklanadigan ro'yxat: tortib yangilash, pastga tushganda yana yuklash, xatoda "Qayta urinish".
class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.session,
    required this.fetch,
    required this.itemBuilder,
    this.emptyText = 'Ma\'lumot yo\'q',
    this.header,
  });

  final Session session;
  final Future<Paged> Function(int page) fetch;
  final Widget Function(BuildContext context, Map<String, dynamic> item) itemBuilder;
  final String emptyText;
  final Widget? header;

  @override
  State<PagedList> createState() => PagedListState();
}

class PagedListState extends State<PagedList> {
  final _items = <Map<String, dynamic>>[];
  final _scroll = ScrollController();
  PageMeta _meta = const PageMeta();
  bool _loading = true;
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final p = await widget.fetch(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(p.items);
        _meta = p.meta;
        _loading = false;
      });
    } catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _more || !_meta.hasMore) return;
    setState(() => _more = true);
    try {
      final p = await widget.fetch(_meta.page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(p.items);
        _meta = p.meta;
        _more = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _more = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return ErrorView(message: _error!, onRetry: reload);
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: (widget.header != null ? 1 : 0) + (_items.isEmpty ? 1 : _items.length) + (_more ? 1 : 0),
        itemBuilder: (context, i) {
          if (widget.header != null) {
            if (i == 0) return widget.header!;
            i -= 1;
          }
          if (_items.isEmpty) {
            return Padding(padding: const EdgeInsets.all(48), child: Center(child: Text(widget.emptyText)));
          }
          if (i >= _items.length) {
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          }
          return widget.itemBuilder(context, _items[i]);
        },
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Qayta urinish')),
          ],
        ),
      ),
    );
  }
}

/// Bir martalik yuklanadigan ma'lumot (ro'yxat emas) uchun.
class FutureBody<T> extends StatefulWidget {
  const FutureBody({super.key, required this.session, required this.load, required this.builder});

  final Session session;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<FutureBody<T>> createState() => _FutureBodyState<T>();
}

class _FutureBodyState<T> extends State<FutureBody<T>> {
  T? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) return ErrorView(message: _error!, onRetry: _reload);
    return RefreshIndicator(onRefresh: _reload, child: widget.builder(context, _data as T, _reload));
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.text, this.color, {super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Til tanlash: O'zbekcha / Русский / Тоҷикӣ (butun ilova shu tilga o'tadi)
class LangSwitch extends StatelessWidget {
  const LangSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: L.notifier,
      builder: (context, cur, _) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final c in L.codes) ChoiceChip(label: Text(L.name(c)), selected: cur == c, onSelected: (_) => L.set(c)),
        ],
      ),
    );
  }
}

/// Tepadagi holat paneli: offline rejim, yuborilmagan amallar, ma'lumot yuklanishi (hammasi joyida bo'lsa ko'rinmaydi)
class OfflineBar extends StatelessWidget {
  const OfflineBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Offline.online, Offline.pending, Offline.failed, Offline.progress]),
      builder: (context, _) {
        final online = Offline.online.value;
        final p = Offline.pending.value, f = Offline.failed.value;
        final loading = Offline.progress.value != null && online;
        if (online && p == 0 && f == 0 && !loading) return const SizedBox.shrink();
        final text = [
          if (!online) "Offline — saqlangan ma'lumot",
          if (loading) "Ma'lumotlar telefonga yuklanmoqda…",
          if (p > 0) '$p ta amal yuborilmagan',
          if (f > 0) '$f ta xato',
        ].join(' · ');
        return Material(
          color: f > 0 ? Colors.red.shade700 : (online ? Colors.blueGrey.shade600 : Colors.orange.shade800),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(online ? Icons.sync : Icons.cloud_off, size: 18, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                const Icon(Icons.chevron_right, size: 18, color: Colors.white),
              ]),
            ),
          ),
        );
      },
    );
  }
}
