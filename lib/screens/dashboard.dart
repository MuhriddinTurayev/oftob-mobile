import 'package:flutter/material.dart';

import '../format.dart';
import '../session.dart';
import '../widgets.dart';

/// Bosh ekran: rahbar uchun bir qarashda — kassa, sotuv, vazifalar, yangi lidlar, oxirgi operatsiyalar.
/// Faqat kalit (rol) ruxsat bergan bo'limlar ko'rsatiladi; har biri alohida yuklanadi — biri xato bersa, qolganlari ishlayveradi.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session, this.onOpen});

  final Session session;

  /// Bo'limga o'tish (pastki tab nomi bilan)
  final void Function(String tab)? onOpen;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;

  Map<String, num> _cash = {}; // valyuta → jami qoldiq
  int _desks = 0;
  int _apts = 0, _sold = 0, _booked = 0, _free = 0;
  int _open = 0, _overdue = 0;
  int _attStaff = 0, _attWorking = 0, _attCame = 0;
  int _leadsTotal = 0;
  List<Map<String, dynamic>> _leads = const [];
  List<Map<String, dynamic>> _ops = const [];

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = s.me!;
    final api = s.api!;
    var failed = 0, tried = 0;
    Future<void> part(bool allowed, Future<void> Function() f) async {
      if (!allowed) return;
      tried++;
      try {
        await f();
      } catch (e) {
        failed++;
        await s.handleError(e);
        _error = '$e';
      }
    }

    await Future.wait([
      part(me.can('cash:read'), () async {
        final d = await api.cashDesks();
        final m = <String, num>{};
        var n = 0;
        for (final x in d) {
          if (x['is_active'] == false) continue;
          n++;
          final cur = '${x['currency'] ?? ''}';
          m[cur] = (m[cur] ?? 0) + ((x['balance'] as num?) ?? 0);
        }
        final ops = await api.cashOps();
        if (!mounted) return;
        _cash = m;
        _desks = n;
        _ops = ops.items.take(6).toList();
      }),
      part(me.can('objects:read'), () async {
        final o = await api.objects();
        var t = 0, sold = 0, b = 0, f = 0;
        for (final x in o) {
          final a = (x['apartments'] as Map?) ?? const {};
          t += (a['total'] as num?)?.toInt() ?? 0;
          sold += (a['sold'] as num?)?.toInt() ?? 0;
          b += (a['booked'] as num?)?.toInt() ?? 0;
          f += (a['free'] as num?)?.toInt() ?? 0;
        }
        _apts = t;
        _sold = sold;
        _booked = b;
        _free = f;
      }),
      part(me.can('attendance:read'), () async {
        final a = await api.attendance();
        final sum = Map<String, dynamic>.from((a['summary'] as Map?) ?? const {});
        _attStaff = (sum['staff'] as num?)?.toInt() ?? 0;
        _attWorking = (sum['working'] as num?)?.toInt() ?? 0;
        _attCame = (sum['came'] as num?)?.toInt() ?? 0;
      }),
      part(me.can('tasks:read'), () async {
        final p = await api.tasks();
        final today = DateTime.now().toIso8601String().substring(0, 10);
        var open = 0, over = 0;
        for (final x in p.items) {
          if (x['status'] == 'done') continue;
          open++;
          final due = x['due_date'] as String?;
          if (due != null && due.compareTo(today) < 0) over++;
        }
        _open = open;
        _overdue = over;
      }),
      part(me.can('leads:read'), () async {
        final l = await api.leads();
        _leadsTotal = l.meta.total;
        _leads = l.items.take(3).toList();
      }),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = tried > 0 && failed == tried ? _error : null;
    });
  }

  String get _first {
    final n = s.userName.trim();
    return n.isEmpty ? '' : n.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = s.me!;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _cash.isEmpty && _apts == 0 && _open == 0 && _leads.isEmpty) return ErrorView(message: _error!, onRetry: _load);

    final cur = _cash.keys.isEmpty ? '' : (_cash.containsKey('UZS') ? 'UZS' : _cash.keys.first);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(_first.isEmpty ? 'Salom' : 'Salom, $_first', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('${me.company} · ${me.roleName}', style: TextStyle(color: cs.outline)),
          const SizedBox(height: 16),
          if (me.can('cash:read'))
            _CashCard(
              total: _cash[cur],
              currency: cur,
              others: {for (final e in _cash.entries) if (e.key != cur) e.key: e.value},
              desks: _desks,
              onTap: () => widget.onOpen?.call('Kassa'),
            ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (me.can('objects:read'))
              Expanded(
                child: _Stat(
                  icon: Icons.apartment,
                  title: 'Sotuv',
                  big: '$_sold',
                  sub: '$_apts xonadondan · bron $_booked · bo\'sh $_free',
                  progress: _apts == 0 ? 0 : _sold / _apts,
                  onTap: () => widget.onOpen?.call('Obyektlar'),
                ),
              ),
            if (me.can('objects:read') && me.can('tasks:read')) const SizedBox(width: 12),
            if (me.can('tasks:read'))
              Expanded(
                child: _Stat(
                  icon: Icons.checklist,
                  title: 'Vazifalar',
                  big: '$_open',
                  sub: _overdue > 0 ? 'ochiq · $_overdue ta muddati o\'tgan' : 'ochiq vazifa',
                  warn: _overdue > 0,
                  onTap: () => widget.onOpen?.call('Vazifalar'),
                ),
              ),
          ]),
          if (me.can('attendance:read')) ...[
            const SizedBox(height: 12),
            _Stat(
              icon: Icons.how_to_reg_outlined,
              title: 'Bugun ishda',
              big: '$_attWorking',
              sub: '$_attCame kishi keldi · $_attStaff ta xodimdan',
              progress: _attStaff == 0 ? 0 : _attCame / _attStaff,
              onTap: () => widget.onOpen?.call('Davomat'),
            ),
          ],
          if (me.can('leads:read')) ...[
            const SizedBox(height: 20),
            _Section(title: 'Yangi lidlar', trailing: '$_leadsTotal ta', onTap: () => widget.onOpen?.call('Lidlar')),
            if (_leads.isEmpty) const _Empty('Hozircha lid yo\'q'),
            for (final l in _leads) _LeadRow(l),
          ],
          if (me.can('cash:read')) ...[
            const SizedBox(height: 20),
            _Section(title: 'Oxirgi operatsiyalar', onTap: () => widget.onOpen?.call('Kassa')),
            if (_ops.isEmpty) const _Empty('Operatsiya yo\'q'),
            for (final o in _ops) _OpRow(o),
          ],
        ],
      ),
    );
  }
}

class _CashCard extends StatelessWidget {
  const _CashCard({required this.total, required this.currency, required this.others, required this.desks, this.onTap});

  final num? total;
  final String currency;
  final Map<String, num> others;
  final int desks;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.28)!]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.account_balance_wallet_outlined, color: cs.onPrimary.withValues(alpha: 0.85), size: 20),
              const SizedBox(width: 8),
              Text('Kassalarda jami', style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$desks ta kassa', style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.7), fontSize: 12)),
            ]),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: money(total ?? 0), style: TextStyle(color: cs.onPrimary, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                TextSpan(text: '  ${currency == 'UZS' ? 'so\'m' : currency}', style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.8), fontSize: 16, fontWeight: FontWeight.w600)),
              ])),
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(others.entries.map((e) => '${money(e.value)} ${e.key}').join('  ·  '), style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.8), fontSize: 13)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.title, required this.big, required this.sub, this.progress, this.warn = false, this.onTap});

  final IconData icon;
  final String title;
  final String big;
  final String sub;
  final double? progress;
  final bool warn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: warn ? cs.error : cs.primary),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: cs.outline, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
            const SizedBox(height: 6),
            Text(big, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: warn ? cs.error : null)),
            if (progress != null) ...[
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress, minHeight: 5)),
            ],
            const SizedBox(height: 6),
            Text(sub, style: TextStyle(color: cs.outline, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.trailing, this.onTap});

  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const Spacer(),
          if (trailing != null) Text(trailing!, style: TextStyle(color: cs.outline)),
          Icon(Icons.chevron_right, color: cs.outline, size: 20),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.outline)));
}

class _LeadRow extends StatelessWidget {
  const _LeadRow(this.l);
  final Map<String, dynamic> l;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = '${l['name'] ?? l['phone'] ?? 'Lid'}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: cs.primaryContainer, foregroundColor: cs.onPrimaryContainer, child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${l['source'] ?? ''}${l['rooms'] != null ? ' · ${l['rooms']} xona' : ''} · ${formatDate('${l['created_at'] ?? ''}')}', maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _OpRow extends StatelessWidget {
  const _OpRow(this.o);
  final Map<String, dynamic> o;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inc = o['type'] == 'in';
    final amount = (o['amount'] as num?) ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: (inc ? Colors.green : cs.error).withValues(alpha: 0.12),
        foregroundColor: inc ? Colors.green.shade700 : cs.error,
        child: Icon(inc ? Icons.south_west : Icons.north_east, size: 20),
      ),
      title: Text('${o['category'] ?? (inc ? 'Kirim' : 'Chiqim')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${formatDate('${o['date'] ?? ''}')}${(o['note'] ?? '').toString().isEmpty ? '' : ' · ${o['note']}'}', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('${inc ? '+' : '−'}${money(amount)}', style: TextStyle(fontWeight: FontWeight.w800, color: inc ? Colors.green.shade700 : cs.error)),
    );
  }
}
