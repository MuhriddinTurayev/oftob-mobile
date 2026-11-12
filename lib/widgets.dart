import 'package:flutter/material.dart' hide Text;


import 'api.dart';
import 'offline.dart';
import 'session.dart';
import 'l10n.dart';
import 'theme.dart';
import 'motion.dart';
import 'lite.dart';

/// Sahifalab yuklanadigan ro'yxat: tortib yangilash, pastga tushganda yana yuklash, xatoda "Qayta urinish".
class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.session,
    required this.fetch,
    required this.itemBuilder,
    this.emptyText = 'Ma\'lumot yo\'q',
    this.header,
    this.refresh,
  });

  /// Signal kelganda ro'yxat jimgina qayta yuklanadi (real vaqt: Pulse)
  final Listenable? refresh;
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
    widget.refresh?.addListener(_onSignal);
    reload();
  }

  void _onSignal() {
    if (mounted && !_loading && !_more) reload();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_onSignal);
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

  /// Kompyuter (keng ro'yxat): elementlar ikki ustunda; telefon va tor panelda — null (oddiy ro'yxat)
  Widget? _wideList(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 1000 || _items.isEmpty) return null;
    return LayoutBuilder(builder: (context, bc) {
      if (bc.maxWidth < 900) return _narrowList(context);
      return ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: NavInset.listBottom(context)),
        children: [
          if (widget.header != null) widget.header!,
          DeskGrid(minColumn: 440, maxColumns: 2, children: [for (var i = 0; i < _items.length; i++) widget.itemBuilder(context, _items[i])]),
          if (_more) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        ],
      );
    });
  }

  Widget _narrowList(BuildContext context) => ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: NavInset.listBottom(context)),
        itemCount: (widget.header != null ? 1 : 0) + _items.length + (_more ? 1 : 0),
        itemBuilder: (context, i) {
          if (widget.header != null) {
            if (i == 0) return widget.header!;
            i -= 1;
          }
          if (i >= _items.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          return widget.itemBuilder(context, _items[i]);
        },
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return ErrorView(message: _error!, onRetry: reload);
    return RefreshIndicator(
      onRefresh: reload,
      child: _wideList(context) ??
      ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: NavInset.listBottom(context)),
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
          return Reveal(index: i.clamp(0, 9), child: widget.itemBuilder(context, _items[i]));
        },
      ),
    );
  }
}

/// Kenglikka qarab 1–3 ustun: telefonda — oddiy ro'yxat, kompyuterda — yonma-yon (har ustun kamida [minColumn] px).
/// Elementlar o'z bo'shliqlarini o'zlari beradi (pastdan chekinish), shuning uchun ustunlar orasidagina [gap] qo'shiladi.
class DeskGrid extends StatelessWidget {
  const DeskGrid({super.key, required this.children, this.minColumn = 500, this.gap = 4, this.maxColumns = 3});

  final List<Widget> children;
  final double minColumn;
  final double gap;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, bc) {
      final cols = ((bc.maxWidth + gap) / (minColumn + gap)).floor().clamp(1, maxColumns);
      if (cols == 1) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      final w = (bc.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, children: [for (final c in children) SizedBox(width: w, child: c)]);
    });
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
  const FutureBody({super.key, required this.session, required this.load, required this.builder, this.refresh});

  final Session session;

  /// Signal kelganda ma'lumot jim yangilanadi (eski ro'yxat ekranda qoladi, aylanuvchi belgi chiqmaydi)
  final Listenable? refresh;
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
    widget.refresh?.addListener(_quiet);
    _reload();
  }

  @override
  void didUpdateWidget(covariant FutureBody<T> old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh) {
      old.refresh?.removeListener(_quiet);
      widget.refresh?.addListener(_quiet);
    }
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_quiet);
    super.dispose();
  }

  void _quiet() {
    if (mounted) _reload();
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
      builder: (context, cur, _) {
        final cs = Theme.of(context).colorScheme;
        return Row(children: [
          for (var i = 0; i < L.codes.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Tappable(
                scale: 0.94,
                onTap: () => L.set(L.codes[i]),
                child: AnimatedContainer(
                  duration: Lite.d(const Duration(milliseconds: 220)),
                  height: 40,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: cur == L.codes[i] ? cs.primary : context.pill.withValues(alpha: context.isDark ? 0.12 : 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cur == L.codes[i] ? cs.primary : context.pillBorder),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(L.name(L.codes[i]),
                        maxLines: 1,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: cur == L.codes[i] ? Colors.white : cs.onSurface)),
                  ),
                ),
              ),
            ),
          ],
        ]);
      },
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
        final c = f > 0 ? Colors.red.shade700 : (online ? Colors.blueGrey.shade600 : Colors.orange.shade800);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Glass(
            radius: 16,
            tint: c.withValues(alpha: 0.14),
            shadow: false,
            onTap: onTap,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Icon(online ? Icons.sync_rounded : Icons.cloud_off_rounded, size: 17, color: c),
              const SizedBox(width: 9),
              Expanded(child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5))),
              Icon(Icons.chevron_right, size: 18, color: c),
            ]),
          ),
        );
      },
    );
  }
}
