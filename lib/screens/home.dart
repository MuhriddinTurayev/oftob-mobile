import 'package:flutter/material.dart';

import '../session.dart';
import 'cash.dart';
import 'leads.dart';
import 'objects.dart';
import 'stock.dart';
import 'tasks.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final Widget Function(Session) builder;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  /// Faqat kalitga ruxsat berilgan bo'limlar ko'rsatiladi.
  List<_Tab> get _tabs {
    final me = widget.session.me!;
    return [
      if (me.can('objects:read')) _Tab('Obyektlar', Icons.apartment, (s) => ObjectsScreen(session: s)),
      if (me.can('leads:read')) _Tab('Lidlar', Icons.people_alt_outlined, (s) => LeadsScreen(session: s)),
      if (me.can('cash:read')) _Tab('Kassa', Icons.account_balance_wallet_outlined, (s) => CashScreen(session: s)),
      if (me.can('stock:read')) _Tab('Ombor', Icons.inventory_2_outlined, (s) => StockScreen(session: s)),
      if (me.can('tasks:read')) _Tab('Vazifalar', Icons.checklist, (s) => TasksScreen(session: s)),
    ];
  }

  void _profile() {
    final me = widget.session.me!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(me.company, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Rol: ${me.roleName}${me.readOnly ? ' (faqat ko\'rish)' : ''}'),
              Text('Kalit: ${me.keyName}'),
              Text('Server: ${widget.session.serverUrl}'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Chiqish'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.session.signOut();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Oftob CRM'), actions: [IconButton(icon: const Icon(Icons.account_circle_outlined), onPressed: _profile)]),
        body: const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Bu API kalitda hech qaysi bo\'limga ruxsat yo\'q. Boshqa kalit so\'rang.', textAlign: TextAlign.center))),
      );
    }
    final i = _index.clamp(0, tabs.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: Text(tabs[i].label),
        actions: [IconButton(tooltip: 'Profil', icon: const Icon(Icons.account_circle_outlined), onPressed: _profile)],
      ),
      body: IndexedStack(index: i, children: [for (final t in tabs) t.builder(widget.session)]),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: i,
              onDestinationSelected: (v) => setState(() => _index = v),
              destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label)],
            ),
    );
  }
}
