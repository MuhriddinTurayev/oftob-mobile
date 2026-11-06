import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import 'dart:async';

import '../offline.dart';
import '../prefetch.dart';
import '../session.dart';
import 'attendance.dart';
import 'cash.dart';
import 'crew.dart';
import 'currencies.dart';
import 'dashboard.dart';
import 'funds.dart';
import 'leads.dart';
import 'notifications.dart';
import 'objects.dart';
import 'parties.dart';
import 'reports.dart';
import 'sales.dart';
import 'stock.dart';
import 'sync_screen.dart';
import 'tasks.dart';
import '../l10n.dart';
import '../widgets.dart';
import '../theme.dart';
import '../assistant.dart';
import '../avatar.dart';
import '../motion.dart';
import 'profile.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.activeIcon, this.builder);
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget Function(Session) builder;
}

/// Haqiqiy (mahalliy) ilova: pastki tab-bar, har bo'lim — Flutter ekrani, ma'lumot `/api/v1` dan.
/// Pastda eng ko'pi bilan 4 ta asosiy bo'lim + «Yana» (qolgan bo'limlar, profil, chiqish).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;
  final _dashRefresh = ValueNotifier<int>(0);
  late final NotificationCenter _nc = NotificationCenter(widget.session, onFresh: _fresh);

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nc.start();
    AppNav.open = _open;
    AppNav.sections = [..._primary.map((e) => e.label), ..._more.map((e) => e.label)];
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tickSync());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tickSync(first: true));
  }

  Timer? _syncTimer;

  /// Offline navbatni yuborish, kerak bo'lsa ma'lumotni telefonga yangilash (kirganda va har 6 soatda), internet qaytganini bilish
  Future<void> _tickSync({bool first = false}) async {
    final api = s.api;
    if (api == null || !Offline.enabled) return;
    try {
      if (Offline.pending.value > 0) {
        final n = await Offline.sync(api);
        if (n > 0 && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n ta offline amal serverga yuborildi')));
      }
      final last = DateTime.tryParse(Offline.lastPrefetch.value ?? '');
      if (first || last == null || DateTime.now().difference(last) > const Duration(hours: 6)) {
        if (Offline.progress.value == null && Offline.online.value) unawaited(prefetchAll(s));
      } else if (!Offline.online.value) {
        await api.me(); // internet qaytganini bilish uchun yengil so'rov
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (AppNav.open == _open) AppNav.open = null;
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _nc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _dashRefresh.value++;
      _nc.refresh();
      _tickSync();
    }
  }

  /// Ilova ochiq turganda yangi voqea kelsa — tepada qisqa xabar
  void _fresh(List<Map<String, dynamic>> fresh) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    final f = fresh.first;
    final more = fresh.length > 1 ? ' (+${fresh.length - 1})' : '';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Text('${f['title']}: ${f['body']}$more', maxLines: 2, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(label: tr("Ko'rish"), onPressed: _openNotifications),
      ));
  }

  void _openNotifications() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NotificationsScreen(center: _nc, onGo: _go)));
  }

  /// Bildirishnomadan tegishli bo'limga o'tish
  void _go(String go) {
    final me = s.me!;
    _open(switch (go) {
      'tasks' => 'Vazifalar',
      'leads' => 'Lidlar',
      'funds' => me.role == 'foreman' ? 'Pul' : 'Prorab puli',
      'attendance' => 'Davomat',
      _ => '',
    });
  }

  /// Rol (kalit ruxsatlari) bo'yicha: asosiy tablar
  List<_Tab> get _primary {
    final me = s.me!;
    return [
      _Tab('Bosh', Icons.home_outlined, Icons.home, (x) => DashboardScreen(session: x, onOpen: _open, sections: _sections, refresh: _dashRefresh, onProfile: () => setState(() => _index = _primary.length))),
      // prorab uchun davomat — eng asosiy ish; boshqa rollarda «Yana» ichida (Bosh ekrandagi karta orqali ham ochiladi)
      if (me.can('attendance:read') && me.role == 'foreman') _Tab('Davomat', Icons.how_to_reg_outlined, Icons.how_to_reg, (x) => AttendanceScreen(session: x)),
      if (me.can('funds:read') && me.role == 'foreman') _Tab('Pul', Icons.payments_outlined, Icons.payments, (x) => FundsScreen(session: x)),
      if (me.can('crew:read') && me.role == 'foreman') _Tab('Xodimlar', Icons.groups_outlined, Icons.groups, (x) => CrewScreen(session: x)),
      if (me.can('objects:read')) _Tab('Obyektlar', Icons.apartment_outlined, Icons.apartment, (x) => ObjectsScreen(session: x)),
      if (me.can('cash:read')) _Tab('Kassa', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, (x) => CashScreen(session: x)),
      if (me.can('leads:read')) _Tab('Lidlar', Icons.people_alt_outlined, Icons.people_alt, (x) => LeadsScreen(session: x)),
    ].take(4).toList();
  }

  /// «Yana» ichidagi bo'limlar (asosiy tabga sig'masa ham shu yerda qoladi)
  List<_Tab> get _more {
    final me = s.me!;
    final primary = _primary.map((e) => e.label).toSet();
    return [
      if (me.can('attendance:read') && !primary.contains('Davomat')) _Tab('Davomat', Icons.how_to_reg_outlined, Icons.how_to_reg, (x) => AttendanceScreen(session: x)),
      if (me.can('funds:read')) _Tab('Valyutalar', Icons.currency_exchange_outlined, Icons.currency_exchange, (x) => CurrenciesScreen(session: x)),
      if (me.can('funds:read') && !primary.contains('Pul')) _Tab('Prorab puli', Icons.payments_outlined, Icons.payments, (x) => FundsScreen(session: x)),
      if (me.can('reports:read')) _Tab('Hisobotlar', Icons.description_outlined, Icons.description, (x) => ReportsScreen(session: x)),
      if (me.can('sales:read')) _Tab('Sotuv', Icons.key_outlined, Icons.key, (x) => SalesScreen(session: x)),
      if (me.can('crew:read') && !primary.contains('Xodimlar')) _Tab('Xodimlar', Icons.groups_outlined, Icons.groups, (x) => CrewScreen(session: x)),
      if (me.can('tasks:read')) _Tab('Vazifalar', Icons.checklist, Icons.checklist, (x) => TasksScreen(session: x)),
      if (me.can('parties:read')) _Tab('Kontragentlar', Icons.contacts_outlined, Icons.contacts, (x) => PartiesScreen(session: x)),
      if (me.can('payments:read')) _Tab("To'lov so'rovlari", Icons.request_quote_outlined, Icons.request_quote, (x) => PaymentRequestsScreen(session: x)),
      if (me.can('stock:read')) _Tab('Ombor', Icons.inventory_2_outlined, Icons.inventory_2, (x) => StockScreen(session: x)),
      if (me.can('objects:read') && !primary.contains('Obyektlar')) _Tab('Obyektlar', Icons.apartment_outlined, Icons.apartment, (x) => ObjectsScreen(session: x)),
      if (me.can('cash:read') && !primary.contains('Kassa')) _Tab('Kassa', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, (x) => CashScreen(session: x)),
      if (me.can('leads:read') && !primary.contains('Lidlar')) _Tab('Lidlar', Icons.people_alt_outlined, Icons.people_alt, (x) => LeadsScreen(session: x)),
    ];
  }

  static const _colors = <String, Color>{
    'Obyektlar': Brand.blue,
    'Sotuv': Brand.orange,
    'Kassa': Brand.green,
    'Lidlar': Brand.pink,
    'Vazifalar': Brand.purple,
    'Ombor': Brand.amber,
    'Davomat': Brand.teal,
    'Xodimlar': Brand.blue,
    'Pul': Brand.green,
    'Prorab puli': Brand.green,
    'Hisobotlar': Brand.purple,
    'Valyutalar': Brand.amber,
    'Kontragentlar': Brand.orange,
    "To'lov so'rovlari": Brand.blue,
  };

  /// Bosh ekrandagi «Xizmatlar» tugmalari: rol ruxsat bergan hamma bo'limlar (asosiy tablar ham, «Yana» dagilar ham)
  List<DashSection> get _sections => [
        for (final t in [..._primary.skip(1), ..._more]) DashSection(t.label, t.icon, _colors[t.label] ?? Brand.green),
      ];

  /// Bosh ekrandan bo'limga o'tish: asosiy tab bo'lsa — tab almashadi, bo'lmasa — to'liq ekran sifatida ochiladi
  bool _open(String label) {
    final p = _primary;
    if (label == 'Yana') {
      setState(() => _index = p.length);
      return true;
    }
    final i = p.indexWhere((e) => e.label == label);
    if (i >= 0) {
      HapticFeedback.selectionClick();
      // ochiq sahifalar (masalan, «Kassa» to'liq ekrani) yopilib, tab ko'rsatiladi
      Navigator.of(context).popUntil((r) => r.isFirst);
      setState(() => _index = i);
      if (i == 0) _dashRefresh.value++;
      return true;
    }
    final m = _more.where((e) => e.label == label);
    if (m.isNotEmpty) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      _push(m.first);
      return true;
    }
    return false;
  }

  void _push(_Tab t) {
    HapticFeedback.selectionClick();
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(appBar: AppBar(title: Text(t.label)), body: t.builder(s)),
        ))
        .then((_) => _dashRefresh.value++);
  }

  void _openProfile() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProfileScreen(session: s, onLogout: _logout)));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chiqish'),
        content: Text(Offline.pending.value > 0 ? 'Hisobdan chiqasizmi?\n\n${Offline.pending.value} ta yuborilmagan offline amal bor — ular telefonda saqlanadi va qayta kirib, internet bo\'lganda yuboriladi.' : 'Hisobdan chiqasizmi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Yo\'q')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Chiqish')),
        ],
      ),
    );
    if (ok == true) await s.signOut();
  }

  Widget _moreTab() {
    final cs = Theme.of(context).colorScheme;
    final me = s.me!;
    final name = s.userName.isEmpty ? me.company : s.userName;
    Widget row(IconData icon, Color color, String title, {String? sub, Widget? trailing, VoidCallback? onTap, Color? titleColor}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Glass(
            onTap: onTap,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              IconTile(icon: icon, color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: titleColor)),
                  if (sub != null) Text(sub, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                ]),
              ),
              trailing ?? (onTap == null ? const SizedBox.shrink() : Icon(Icons.chevron_right, color: cs.outline)),
            ]),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
      children: [
        Glass(
          radius: 26,
          onTap: _openProfile,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            ListenableBuilder(listenable: s, builder: (_, _) => UserAvatar(session: s, name: name, size: 54)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('${me.company} · ${me.roleName}${me.readOnly ? " · faqat ko'rish" : ''}', style: TextStyle(color: cs.outline, fontSize: 13)),
                const SizedBox(height: 4),
                Text('Profil, rasm, parol, seanslar', style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
            Icon(Icons.chevron_right, color: cs.outline),
          ]),
        ),
        const SizedBox(height: 16),
        for (final t in _more) row(t.icon, _colors[t.label] ?? Brand.green, t.label, onTap: () => _push(t)),
        ListenableBuilder(
          listenable: Listenable.merge([Offline.pending, Offline.failed]),
          builder: (context, _) {
            final n = Offline.pending.value + Offline.failed.value;
            return row(
              Icons.cloud_sync_outlined,
              Brand.blue,
              'Sinxronlash',
              sub: "Offline ma'lumot va yuborilmagan amallar",
              trailing: Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(Icons.chevron_right, color: cs.outline)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SyncScreen(session: s))),
            );
          },
        ),
      ],
    );
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 11 ? 'Xayrli tong' : (h < 18 ? 'Xayrli kun' : 'Xayrli kech');
  }

  Widget _header(int i, int moreIndex, List<_Tab> tabs) {
    final cs = Theme.of(context).colorScheme;
    final me = s.me!;
    final name = s.userName.isEmpty ? me.company : s.userName;
    final first = name.trim().split(' ').first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        if (i == 0) ...[
          GestureDetector(onTap: _openProfile, child: ListenableBuilder(listenable: s, builder: (_, _) => UserAvatar(session: s, name: name, size: 46))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(_greeting), style: TextStyle(color: cs.outline, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
            ]),
          ),
        ] else
          Expanded(child: Text(i == moreIndex ? 'Yana' : tabs[i].label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
        ListenableBuilder(
          listenable: Listenable.merge([Offline.online, Offline.pending, Offline.failed]),
          builder: (context, _) {
            final n = Offline.pending.value + Offline.failed.value;
            if (Offline.online.value && n == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GlassIconButton(
                badge: n,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SyncScreen(session: s))),
                icon: Icon(Offline.online.value ? Icons.cloud_sync_outlined : Icons.cloud_off_outlined, size: 22, color: Offline.online.value ? cs.primary : Colors.orange.shade800),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GlassIconButton(
            tooltip: tr('Kun / Tun'),
            onTap: () {
              HapticFeedback.selectionClick();
              ThemeController.set(context.isDark ? ThemeMode.light : ThemeMode.dark);
            },
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (c, a) => RotationTransition(turns: Tween(begin: 0.75, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: ScaleTransition(scale: a, child: c))),
              child: Icon(context.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, key: ValueKey(context.isDark), size: 22, color: context.isDark ? const Color(0xFFFFD36B) : const Color(0xFF5B4BC7)),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: _nc,
          builder: (context, _) => GlassIconButton(
            badge: _nc.unread,
            tooltip: tr('Bildirishnomalar'),
            onTap: _openNotifications,
            icon: Icon(_nc.unread > 0 ? Icons.notifications_active : Icons.notifications_none, size: 24, color: cs.onSurface),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _primary;
    final moreIndex = tabs.length; // oxirgi — «Yana»
    final i = _index.clamp(0, moreIndex);
    return Scaffold(
      extendBody: true, // tarkib suzuvchi panel ostidan o'tadi (xira ko'rinadi)
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _header(i, moreIndex, tabs),
          OfflineBar(onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SyncScreen(session: s)))),
          Expanded(child: AnimatedTabs(index: i, children: [for (final t in tabs) t.builder(s), _moreTab()])),
        ]),
      ),
      bottomNavigationBar: GlassNavBar(
        index: i,
        onTap: (v) {
          setState(() => _index = v);
          if (v == 0) _dashRefresh.value++;
        },
        items: [
          for (final t in tabs) NavItem(t.label, t.icon, t.activeIcon),
          const NavItem('Yana', Icons.grid_view_outlined, Icons.grid_view_rounded),
        ],
      ),
    );
  }
}
