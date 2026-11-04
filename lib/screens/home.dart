import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session.dart';
import 'cash.dart';
import 'dashboard.dart';
import 'leads.dart';
import 'objects.dart';
import 'stock.dart';
import 'tasks.dart';

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

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  Session get s => widget.session;

  /// Rol (kalit ruxsatlari) bo'yicha: asosiy tablar
  List<_Tab> get _primary {
    final me = s.me!;
    return [
      _Tab('Bosh', Icons.home_outlined, Icons.home, (x) => DashboardScreen(session: x, onOpen: _open)),
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
      if (me.can('tasks:read')) _Tab('Vazifalar', Icons.checklist, Icons.checklist, (x) => TasksScreen(session: x)),
      if (me.can('stock:read')) _Tab('Ombor', Icons.inventory_2_outlined, Icons.inventory_2, (x) => StockScreen(session: x)),
      if (me.can('objects:read') && !primary.contains('Obyektlar')) _Tab('Obyektlar', Icons.apartment_outlined, Icons.apartment, (x) => ObjectsScreen(session: x)),
      if (me.can('cash:read') && !primary.contains('Kassa')) _Tab('Kassa', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, (x) => CashScreen(session: x)),
      if (me.can('leads:read') && !primary.contains('Lidlar')) _Tab('Lidlar', Icons.people_alt_outlined, Icons.people_alt, (x) => LeadsScreen(session: x)),
    ];
  }

  /// Bosh ekrandan bo'limga o'tish: asosiy tab bo'lsa — tab almashadi, bo'lmasa — to'liq ekran sifatida ochiladi
  void _open(String label) {
    final p = _primary;
    final i = p.indexWhere((e) => e.label == label);
    if (i >= 0) {
      HapticFeedback.selectionClick();
      setState(() => _index = i);
      return;
    }
    final m = _more.where((e) => e.label == label);
    if (m.isNotEmpty) _push(m.first);
  }

  void _push(_Tab t) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(appBar: AppBar(title: Text(t.label)), body: t.builder(s)),
    ));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chiqish'),
        content: const Text('Hisobdan chiqasizmi?'),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            CircleAvatar(radius: 24, backgroundColor: cs.primary, foregroundColor: cs.onPrimary, child: Text(_initials(s.userName.isEmpty ? me.company : s.userName), style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.userName.isEmpty ? me.company : s.userName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text('${me.company} · ${me.roleName}${me.readOnly ? ' · faqat ko\'rish' : ''}', style: TextStyle(color: cs.outline, fontSize: 13)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        for (final t in _more)
          ListTile(
            leading: Icon(t.icon, color: cs.primary),
            title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => _push(t),
          ),
        if (s.slug.isNotEmpty)
          ListTile(
            leading: Icon(Icons.language, color: cs.primary),
            title: const Text('To\'liq sayt versiyasi', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Davomat, hisobotlar va boshqa bo\'limlar'),
            trailing: const Icon(Icons.chevron_right),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => s.startWeb(s.serverUrl, s.slug),
          ),
        const SizedBox(height: 8),
        ListTile(
          leading: Icon(Icons.logout, color: cs.error),
          title: Text('Chiqish', style: TextStyle(fontWeight: FontWeight.w600, color: cs.error)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: _logout,
        ),
      ],
    );
  }

  static String _initials(String name) {
    final p = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    return (p.first[0] + (p.length > 1 ? p[1][0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _primary;
    final moreIndex = tabs.length; // oxirgi — «Yana»
    final i = _index.clamp(0, moreIndex);
    final title = i == moreIndex ? 'Yana' : (i == 0 ? s.me!.company : tabs[i].label);
    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), centerTitle: false, scrolledUnderElevation: 0),
      body: IndexedStack(index: i, children: [for (final t in tabs) t.builder(s), _moreTab()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) {
          HapticFeedback.selectionClick();
          setState(() => _index = v);
        },
        destinations: [
          for (final t in tabs) NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.activeIcon), label: t.label),
          const NavigationDestination(icon: Icon(Icons.menu), label: 'Yana'),
        ],
      ),
    );
  }
}
