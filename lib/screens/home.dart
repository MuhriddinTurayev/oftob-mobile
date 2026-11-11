import 'rates.dart';
import 'company_admin.dart';
import 'work_admin.dart';
import 'support.dart';
import 'package:flutter/material.dart' hide Text;

import 'package:flutter/services.dart';

import 'dart:async';

import '../api.dart';
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
import '../fcm.dart';
import '../push.dart';
import '../tg_connect.dart';
import 'journal.dart';

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

  /// Kompyuter (keng oyna): yon menyu qoladi, sahifalar o'ng tomondagi ichki navigatorda ochiladi
  final _deskNav = GlobalKey<NavigatorState>();
  final _deskIdx = ValueNotifier<int>(0);

  bool get _isWide => MediaQuery.sizeOf(context).width >= _wide;

  /// Sahifa ochish uchun navigator: kompyuterda — ichki (yon menyu yopilmaydi), telefonda — odatdagi
  NavigatorState get _nav => (_isWide ? _deskNav.currentState : null) ?? Navigator.of(context);

  void _setTab(int v) {
    setState(() => _index = v);
    _deskIdx.value = v;
  }
  final _dashRefresh = ValueNotifier<int>(0);
  late final NotificationCenter _nc = NotificationCenter(widget.session, onFresh: _fresh);

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nc.start();
    AppNav.open = _open;
    ApiClient.onExpired = _expired;
    AppNav.sections = [..._primary.map((e) => e.label), ..._more.map((e) => e.label)];
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tickSync());
    TgLink.load(s); // Telegram ulanganmi — ulanmagan bo'lsa bosh sahifada eslatma
    Push.syncCreds(); // fondagi tekshiruv qulflangan iPhone'da ham kirish ma'lumotini o'qiy olsin
    Fcm.register(s); // Firebase push manzilini serverga (sozlangan bo'lsa)
    Push.foregroundPing.addListener(_nc.refresh);
    Push.openGo.addListener(_pushGo);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushGo(); // ilova bildirishnoma bosilib ochilgan bo'lsa — o'sha bo'limga
      // telefon bildirishnomalariga ruxsat (Android 13+ / iPhone) — bir marta so'raladi
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Push.askPermission();
      });
    });
    // ochilgandan keyin 25 soniya o'tgach (ekran birinchi bo'lib silliq ochilsin)
    Future.delayed(const Duration(seconds: 25), () {
      if (mounted) _tickSync(first: true);
    });
  }

  Timer? _syncTimer;

  /// Ilova oxirgi marta ekranga chiqqan payt (Firebase push bilan takrorni oldini olish uchun)
  DateTime _fgSince = DateTime.now().toUtc();

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
      // katta ma'lumotni faqat birinchi marta yoki 6 soatdan keyin yuklaymiz (har ochilganda emas: telefon qizimasin)
      if (last == null || DateTime.now().difference(last) > const Duration(hours: 6)) {
        if (Offline.progress.value == null && Offline.online.value) unawaited(prefetchAll(s));
      } else if (!Offline.online.value) {
        await api.me(); // internet qaytganini bilish uchun yengil so'rov
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (AppNav.open == _open) AppNav.open = null;
    Push.openGo.removeListener(_pushGo);
    Push.foregroundPing.removeListener(_nc.refresh);
    if (ApiClient.onExpired == _expired) ApiClient.onExpired = null;
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _nc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fgSince = DateTime.now().toUtc();
      _dashRefresh.value++;
      _nc.refresh();
      _tickSync();
      TgLink.load(s);
    } else if (state == AppLifecycleState.paused) {
      Push.syncCreds();
      Push.soon(); // fonga o'tdi — 1 daqiqadan keyin yangi voqealarni tekshirib, telefonga chiqaradi
    }
  }

  /// Telefon bildirishnomasi bosildi — tegishli bo'lim (yoki bildirishnomalar ro'yxati)
  void _pushGo() {
    final go = Push.openGo.value;
    if (go == null || !mounted) return;
    Push.openGo.value = null;
    if (go == 'notifications') return _openNotifications();
    _go(go);
  }

  /// Ilova ochiq turganda yangi voqea kelsa — telefon tepasida banner (Telegram kabi, ovoz bilan);
  /// bildirishnomaga ruxsat berilmagan bo'lsa — ilova ichida pastda xabar
  Future<void> _fresh(List<Map<String, dynamic>> fresh) async {
    if (!mounted) return;
    // Firebase push yoqilgan: ilova fonda turganda kelganlari telefonga allaqachon chiqqan — qayta ko'rsatmaymiz
    if (Push.fcmOn) {
      fresh = fresh.where((e) => (DateTime.tryParse('${e['at']}')?.toUtc() ?? DateTime(2000)).isAfter(_fgSince.subtract(const Duration(seconds: 5)))).toList();
      if (fresh.isEmpty) return;
    }
    HapticFeedback.mediumImpact();
    if (await Push.showItems(fresh, uid: '${s.userId}')) return;
    if (!mounted) return;
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
    _nav.push(MaterialPageRoute<void>(builder: (_) => NotificationsScreen(center: _nc, onGo: _go)));
  }

  /// Bildirishnomadan tegishli bo'limga o'tish
  void _go(String go) {
    if (go == 'profile') return _openProfile(); // «boshqa qurilmadan kirildi» → faol seanslar
    final me = s.me!;
    _open(switch (go) {
      'tasks' => 'Vazifalar',
      'leads' => 'Lidlar',
      'funds' => me.role == 'foreman' ? 'Pul' : 'Prorab puli',
      'attendance' => 'Davomat',
      'reports' => 'Hisobotlar',
      'support' => 'Yordam',
      'billing' => "Tarif va to'lov",
      'ai' => "Sun'iy intellekt",
      'journal' => 'Fotohisobotlar',
      _ => '',
    });
  }

  /// Rol (kalit ruxsatlari) bo'yicha: asosiy tablar
  List<_Tab> get _primary {
    final me = s.me!;
    return [
      _Tab('Bosh', Icons.home_outlined, Icons.home, (x) => DashboardScreen(session: x, onOpen: _open, sections: _sections, refresh: _dashRefresh, onProfile: () => _setTab(_primary.length))),
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
      if (me.can('sales:read')) _Tab("Bo'lib to'lash foizlari", Icons.percent_rounded, Icons.percent_rounded, (x) => RatesScreen(session: x)),
      if (me.can('crew:read') && !primary.contains('Xodimlar')) _Tab('Xodimlar', Icons.groups_outlined, Icons.groups, (x) => CrewScreen(session: x)),
      if (me.can('tasks:read')) _Tab('Vazifalar', Icons.checklist, Icons.checklist, (x) => TasksScreen(session: x)),
      if (me.can('parties:read')) _Tab('Kontragentlar', Icons.contacts_outlined, Icons.contacts, (x) => PartiesScreen(session: x)),
      if (me.can('payments:read')) _Tab("To'lov so'rovlari", Icons.request_quote_outlined, Icons.request_quote, (x) => PaymentRequestsScreen(session: x)),
      if (me.can('journal:read')) _Tab('Fotohisobotlar', Icons.photo_library_outlined, Icons.photo_library, (x) => JournalScreen(session: x)),
      if (me.can('stock:read')) _Tab('Ombor', Icons.inventory_2_outlined, Icons.inventory_2, (x) => StockScreen(session: x)),
      if (me.can('objects:read') && !primary.contains('Obyektlar')) _Tab('Obyektlar', Icons.apartment_outlined, Icons.apartment, (x) => ObjectsScreen(session: x)),
      if (me.can('cash:read') && !primary.contains('Kassa')) _Tab('Kassa', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, (x) => CashScreen(session: x)),
      if (me.can('leads:read') && !primary.contains('Lidlar')) _Tab('Lidlar', Icons.people_alt_outlined, Icons.people_alt, (x) => LeadsScreen(session: x)),
      // rahbar: jamoa (bloklash, rol), AI kalitlari va limit; rahbar va buxgalter: tarif va to'lov
      if (me.role == 'admin' || const ['accountant', 'foreman', 'viewer'].contains(me.role)) _Tab('Ish vaqti va joylashuv', Icons.share_location_outlined, Icons.share_location, (x) => WorkScreen(session: x)),
      if (me.role == 'admin' || const ['accountant', 'viewer'].contains(me.role)) _Tab('KPI va ushlab qolish', Icons.query_stats_outlined, Icons.query_stats, (x) => PayrollScreen(session: x)),
      if (me.role == 'admin') _Tab('Jamoa va rollar', Icons.manage_accounts_outlined, Icons.manage_accounts, (x) => TeamScreen(session: x)),
      if (me.role == 'admin') _Tab("Sun'iy intellekt", Icons.auto_awesome_outlined, Icons.auto_awesome, (x) => AiSetupScreen(session: x)),
      if (me.role == 'admin' || me.role == 'accountant') _Tab("Tarif va to'lov", Icons.workspace_premium_outlined, Icons.workspace_premium, (x) => BillingScreen(session: x)),
      // yordam: xodim → direktor, direktor → platforma administratori
      _Tab('Yordam', Icons.support_agent_outlined, Icons.support_agent, (x) => SupportScreen(session: x)),
    ];
  }

  static const _colors = <String, Color>{
    'Obyektlar': Brand.blue,
    'Sotuv': Brand.orange,
    'Kassa': Brand.green,
    'Lidlar': Brand.pink,
    'Vazifalar': Brand.purple,
    'Ombor': Brand.amber,
    'Fotohisobotlar': Brand.teal,
    'Davomat': Brand.teal,
    'Xodimlar': Brand.blue,
    'Pul': Brand.green,
    'Prorab puli': Brand.green,
    'Hisobotlar': Brand.purple,
    'Valyutalar': Brand.amber,
    'Jamoa va rollar': Brand.blue,
    'Ish vaqti va joylashuv': Brand.teal,
    'KPI va ushlab qolish': Brand.orange,
    "Sun'iy intellekt": Brand.purple,
    "Tarif va to'lov": Brand.green,
    'Kontragentlar': Brand.orange,
    "To'lov so'rovlari": Brand.blue,
  };

  /// «Yana» ro'yxati guruhlarga bo'linadi (bittasini bosganda ochiladi); guruhga kirmaganlar pastda alohida turadi
  static const _groups = <(String, IconData, Color, List<String>)>[
    ('Pul va moliya', Icons.account_balance_wallet_rounded, Brand.green, ['Kassa', 'Prorab puli', "To'lov so'rovlari", 'Valyutalar', 'Kontragentlar', 'Hisobotlar']),
    ('Xodimlar va ish vaqti', Icons.groups_rounded, Brand.teal, ['Davomat', 'Xodimlar', 'Vazifalar', 'Ish vaqti va joylashuv', 'KPI va ushlab qolish']),
    ('Sotuv va mijozlar', Icons.key_rounded, Brand.orange, ['Sotuv', 'Lidlar', "Bo'lib to'lash foizlari"]),
    ('Obyektlar va ombor', Icons.apartment_rounded, Brand.blue, ['Obyektlar', 'Fotohisobotlar', 'Ombor']),
    ('Kompaniya sozlamalari', Icons.tune_rounded, Brand.purple, ['Jamoa va rollar', "Sun'iy intellekt", "Tarif va to'lov"]),
  ];

  /// Hozir ochiq guruh («Yana» da bir vaqtda bittasi ochiq)
  String? _openGroup;

  /// Bosh ekrandagi «Xizmatlar» tugmalari: rol ruxsat bergan hamma bo'limlar (asosiy tablar ham, «Yana» dagilar ham)
  List<DashSection> get _sections => [
        for (final t in [..._primary.skip(1), ..._more]) DashSection(t.label, t.icon, _colors[t.label] ?? Brand.green),
      ];

  /// Bosh ekrandan bo'limga o'tish: asosiy tab bo'lsa — tab almashadi, bo'lmasa — to'liq ekran sifatida ochiladi
  bool _expiredShown = false;

  /// Tarif muddati tugagan: rahbar/buxgalterga — to'lov sahifasi, boshqalarga — tushuntirish (bir marta)
  void _expired() {
    if (_expiredShown || !mounted) return;
    _expiredShown = true;
    final me = s.me;
    final can = me != null && (me.role == 'admin' || me.role == 'accountant');
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.workspace_premium_rounded, size: 36),
        title: const Text('Tarif muddati tugagan'),
        content: Text(can
            ? tr("Ishni davom ettirish uchun tarifni to'lang. To'lovni administrator tasdiqlashi bilan hammasi yana ochiladi.")
            : tr("Kompaniya tarifi muddati tugagan. Rahbar yoki buxgalter to'lov qilgach, ilova yana ishlaydi.")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Yopish')),
          if (can)
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                _open("Tarif va to'lov");
              },
              child: const Text("Tarif va to'lov"),
            ),
        ],
      ),
    ).then((_) => Future.delayed(const Duration(minutes: 3), () => _expiredShown = false));
  }

  bool _open(String label) {
    final p = _primary;
    if (label == 'Yana') {
      _setTab(p.length);
      return true;
    }
    final i = p.indexWhere((e) => e.label == label);
    if (i >= 0) {
      HapticFeedback.selectionClick();
      // ochiq sahifalar (masalan, «Kassa» to'liq ekrani) yopilib, tab ko'rsatiladi
      _nav.popUntil((r) => r.isFirst);
      _setTab(i);
      if (i == 0) _dashRefresh.value++;
      return true;
    }
    final m = _more.where((e) => e.label == label);
    if (m.isNotEmpty) {
      _nav.popUntil((r) => r.isFirst);
      _push(m.first);
      return true;
    }
    return false;
  }

  void _push(_Tab t) {
    HapticFeedback.selectionClick();
    _nav
        .push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(appBar: AppBar(title: Text(t.label)), body: t.builder(s)),
        ))
        .then((_) => _dashRefresh.value++);
  }

  void _openProfile() {
    HapticFeedback.selectionClick();
    _nav.push(MaterialPageRoute<void>(builder: (_) => ProfileScreen(session: s, onLogout: _logout)));
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
      padding: EdgeInsets.fromLTRB(16, 4, 16, NavInset.listBottom(context)),
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
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Glass(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (context, tm, _) => Row(children: [
                const IconTile(icon: Icons.contrast_rounded, color: Brand.purple, size: 40),
                const SizedBox(width: 12),
                const Expanded(child: Text("Ko'rinish", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                _ThemeDot(icon: Icons.brightness_auto_rounded, tip: 'Avto', on: tm == ThemeMode.system, onTap: () => ThemeController.set(ThemeMode.system)),
                const SizedBox(width: 6),
                _ThemeDot(icon: Icons.light_mode_rounded, tip: 'Kun', on: tm == ThemeMode.light, onTap: () => ThemeController.set(ThemeMode.light)),
                const SizedBox(width: 6),
                _ThemeDot(icon: Icons.dark_mode_rounded, tip: 'Tun', on: tm == ThemeMode.dark, onTap: () => ThemeController.set(ThemeMode.dark)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Telegram bot: ulanish holati; ulansa — xabarlar ilova yopiq bo'lsa ham darhol keladi
        ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: TgLink.state,
          builder: (context, d, _) => row(
            Icons.send_rounded,
            Brand.teal,
            'Telegram bot',
            sub: d == null ? "Xabarlar Telegram'ga" : (d['linked'] == true ? "Ulangan — xabarlar Telegram'ga keladi" : 'Ulanmagan — bosing va ulaning'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (d != null) Icon(d['linked'] == true ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: d['linked'] == true ? Brand.green : Colors.orange.shade700, size: 20),
              Icon(Icons.chevron_right, color: cs.outline),
            ]),
            onTap: () => _nav.push(MaterialPageRoute<void>(builder: (_) => TelegramConnectScreen(session: s))).then((_) => TgLink.load(s)),
          ),
        ),
        ..._moreGroups(cs, row),
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
              onTap: () => _nav.push(MaterialPageRoute<void>(builder: (_) => SyncScreen(session: s))),
            );
          },
        ),
      ],
    );
  }

  /// «Yana» bo'limlari guruhlab: guruh sarlavhasini bosish — ochiladi/yopiladi (boshqasi yopiladi).
  /// Bitta bo'limli guruh — to'g'ridan-to'g'ri qator; hech bir guruhga kirmagan bo'lim (masalan, «Yordam») — pastda alohida.
  List<Widget> _moreGroups(ColorScheme cs, Widget Function(IconData, Color, String, {String? sub, Widget? trailing, VoidCallback? onTap, Color? titleColor}) row) {
    final more = _more;
    final byLabel = {for (final t in more) t.label: t};
    final used = <String>{};
    final out = <Widget>[];
    for (final (title, icon, color, labels) in _groups) {
      final items = [for (final l in labels) if (byLabel[l] != null) byLabel[l]!];
      used.addAll(items.map((e) => e.label));
      if (items.isEmpty) continue;
      if (items.length == 1) {
        final t = items.first;
        out.add(row(t.icon, _colors[t.label] ?? color, t.label, onTap: () => _push(t)));
        continue;
      }
      final open = _openGroup == title;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Glass(
          padding: EdgeInsets.zero,
          child: Column(children: [
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _openGroup = open ? null : title);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  IconTile(icon: icon, color: color, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(items.map((e) => tr(e.label)).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Text('${items.length}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(turns: open ? 0.25 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.chevron_right, color: cs.outline)),
                ]),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !open
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: Column(children: [
                        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                        for (final t in items)
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _push(t),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                              child: Row(children: [
                                IconTile(icon: t.icon, color: _colors[t.label] ?? color, size: 34),
                                const SizedBox(width: 12),
                                Expanded(child: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
                                Icon(Icons.chevron_right, color: cs.outline, size: 20),
                              ]),
                            ),
                          ),
                      ]),
                    ),
            ),
          ]),
        ),
      ));
    }
    for (final t in more) {
      if (!used.contains(t.label)) out.add(row(t.icon, _colors[t.label] ?? Brand.green, t.label, onTap: () => _push(t)));
    }
    return out;
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
                onTap: () => _nav.push(MaterialPageRoute<void>(builder: (_) => SyncScreen(session: s))),
                icon: Icon(Offline.online.value ? Icons.cloud_sync_outlined : Icons.cloud_off_outlined, size: 22, color: Offline.online.value ? cs.primary : Colors.orange.shade800),
              ),
            );
          },
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

  /// Kompyuter (keng oyna): pastki panel o'rniga chap tomonda yon menyu, tarkib markazda keng ustunda
  static const _wide = 900.0;

  Widget _rail(int i, List<_Tab> tabs) {
    final cs = Theme.of(context).colorScheme;
    final items = <NavItem>[
      for (final t in tabs) NavItem(t.label, t.icon, t.activeIcon),
      const NavItem('Yana', Icons.grid_view_outlined, Icons.grid_view_rounded),
    ];
    return SizedBox(
      width: 232,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
        child: Glass(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.green, Brand.teal])),
                  child: Image.asset('assets/brand/mark_white.png', fit: BoxFit.contain),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text('Oftob Building', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
              ]),
            ),
            Expanded(
              child: ListView(children: [
                for (var k = 0; k < items.length; k++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: k == i ? cs.primary.withValues(alpha: 0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          _deskNav.currentState?.popUntil((r) => r.isFirst);
                          _setTab(k);
                          if (k == 0) _dashRefresh.value++;
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          child: Row(children: [
                            Icon(k == i ? items[k].activeIcon : items[k].icon, size: 22, color: k == i ? cs.primary : cs.onSurfaceVariant),
                            const SizedBox(width: 12),
                            Expanded(child: Text(navLabel(items[k].label), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: k == i ? FontWeight.w800 : FontWeight.w600, fontSize: 14.5, color: k == i ? cs.primary : null))),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.18)),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _openProfile,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListenableBuilder(
                    listenable: s,
                    builder: (_, _) {
                      final nm = s.userName.isEmpty ? s.me!.company : s.userName;
                      return Row(children: [
                        UserAvatar(session: s, name: nm, size: 36),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(nm, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                            Text(s.me!.company, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.outline, fontSize: 11.5)),
                          ]),
                        ),
                      ]);
                    },
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Kompyuter: sarlavha + ogohlantirish chizig'i + faol bo'lim (ichki navigatorning birinchi sahifasi)
  Widget _deskRoot() => ListenableBuilder(
        listenable: Listenable.merge([_deskIdx, s]),
        builder: (context, _) {
          final tabs = _primary;
          final moreIndex = tabs.length;
          final i = _deskIdx.value.clamp(0, moreIndex);
          // Bosh va Kassa — o'z keng maketi bor; qolgan bo'limlar (sarlavhasi bilan) markazda qulay kenglikda
          final broad = i < tabs.length && (tabs[i].label == 'Bosh' || tabs[i].label == 'Kassa');
          final col = Column(children: [
            _header(i, moreIndex, tabs),
            OfflineBar(onTap: () => _nav.push(MaterialPageRoute<void>(builder: (_) => SyncScreen(session: s)))),
            Expanded(child: NavInset(inset: 0, child: AnimatedTabs(index: i, children: [for (final t in tabs) t.builder(s), _moreTab()]))),
          ]);
          return broad ? col : _narrow(col);
        },
      );

  Widget _narrow(Widget w) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: DesktopPageTransitions.maxWidth), child: w));

  @override
  Widget build(BuildContext context) {
    final tabs = _primary;
    final moreIndex = tabs.length; // oxirgi — «Yana»
    final i = _index.clamp(0, moreIndex);
    final wide = MediaQuery.sizeOf(context).width >= _wide;
    final content = Column(children: [
      _header(i, moreIndex, tabs),
      OfflineBar(onTap: () => _nav.push(MaterialPageRoute<void>(builder: (_) => SyncScreen(session: s)))),
      Expanded(child: NavInset(inset: wide ? 0 : NavInset.bar, child: AnimatedTabs(index: i, children: [for (final t in tabs) t.builder(s), _moreTab()]))),
    ]);
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(children: [
            ValueListenableBuilder<int>(valueListenable: _deskIdx, builder: (_, v, _) => _rail(v.clamp(0, tabs.length), tabs)),
            // keng ekranda tarkib cho'zilib ketmaydi: markazda qulay kenglikda; ochilgan sahifalar ham shu yerda (yon menyu yopilmaydi)
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Navigator(
                    key: _deskNav,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => _deskRoot()),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    }
    return Scaffold(
      extendBody: true, // tarkib suzuvchi panel ostidan o'tadi (xira ko'rinadi)
      body: SafeArea(bottom: false, child: content),
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

/// Kun/Tun/Avto uchun kichik dumaloq tugma
class _ThemeDot extends StatelessWidget {
  const _ThemeDot({required this.icon, required this.tip, required this.on, required this.onTap});

  final IconData icon;
  final String tip;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tr(tip),
      child: Tappable(
        scale: 0.88,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? cs.primary.withValues(alpha: 0.2) : context.pill,
            border: Border.all(color: on ? cs.primary.withValues(alpha: 0.55) : context.pillBorder, width: 1.2),
          ),
          child: Icon(icon, size: 20, color: on ? cs.primary : cs.outline),
        ),
      ),
    );
  }
}
