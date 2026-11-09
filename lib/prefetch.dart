import 'api.dart';
import 'l10n.dart';
import 'offline.dart';
import 'session.dart';

/// Bitta so'rov: ruxsat yo'q (403) kabi xato qolganlarini to'xtatmaydi; internet yo'q bo'lsa — butun yuklash to'xtaydi
Future<void> _try(Future<Object?> Function() f) async {
  try {
    await f();
  } on ApiException catch (e) {
    if (e.isNetwork || e.unauthorized) rethrow;
  }
}

String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Kirgandan keyin (va har 6 soatda) barcha asosiy ma'lumotni telefonga yuklaydi — keyin internetsiz ham ishlash mumkin:
/// obyektlar va BARCHA kvartiralar (offline sotuv uchun), to'lovlar, lidlar, kassa, ombor, vazifalar, davomat, xodimlar, pul va h.k.
/// Ekranlar o'zlarining odatiy so'rovlarini yuboradi — shu so'rovlarning javoblari saqlanadi (kalitlar bir xil).
Future<void> prefetchAll(Session s) async {
  final api = s.api;
  final me = s.me;
  if (api == null || me == null || !Offline.enabled || Offline.progress.value != null) return;
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final monthEnd = DateTime(now.year, now.month + 1, 0);
  final steps = <String, Future<void> Function()>{
    if (me.can('objects:read'))
      'Obyektlar va kvartiralar': () async {
        final objs = await api.objects();
        for (final o in objs) {
          await api.downloadAllApartments('${o['id']}');
        }
      },
    if (me.can('sales:read')) ...{
      'Sotuv shartlari': () async {
        await api.salesTerms();
        await api.payMethods();
      },
      "To'lovlar": () async {
        await api.salesPayments(from: _d(monthStart), to: _d(monthEnd));
      },
    },
    if (me.can('leads:read'))
      'Lidlar': () async {
        for (var p = 1; p <= 5; p++) {
          final r = await api.leads(page: p, perPage: 100);
          if (!r.meta.hasMore) break;
        }
        await _try(() => api.leads()); // bosh sahifa va «Lidlar» ro'yxati shu so'rovni yuboradi
        await _try(() => api.leadSources());
      },
    if (me.can('cash:read'))
      'Kassa': () async {
        await api.cashDesks();
        for (var p = 1; p <= 3; p++) {
          final r = await api.cashOps(page: p);
          if (!r.meta.hasMore) break;
        }
      },
    if (me.can('stock:read'))
      'Ombor': () async {
        for (var p = 1; p <= 3; p++) {
          final r = await api.stockItems(page: p);
          if (!r.meta.hasMore) break;
        }
        for (var p = 1; p <= 2; p++) {
          final r = await api.stockMoves(page: p);
          if (!r.meta.hasMore) break;
        }
        await _try(() => api.stockWarehouses());
      },
    if (me.can('tasks:read'))
      'Vazifalar': () async {
        for (var p = 1; p <= 3; p++) {
          final r = await api.tasks(page: p);
          if (!r.meta.hasMore) break;
        }
        await api.tasks(page: 1, assignee: s.userId);
        await api.users();
      },
    if (me.can('attendance:read'))
      'Davomat': () async {
        await api.attendance(date: _d(now));
        await _try(() => api.attendance()); // bosh sahifadagi «Bugun ishda» (sanasiz so'rov)
      },
    if (me.can('crew:read'))
      'Xodimlar': () async {
        await api.crew(month: '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}');
      },
    if (me.can('funds:read'))
      'Pul': () async {
        await api.funds();
        await api.currencies();
      },
    if (me.can('journal:read'))
      'Fotohisobotlar': () async {
        await _try(() => api.journal());
      },
    if (me.can('sales:read'))
      'Qarzdorlar': () async {
        await _try(() => api.salesDebtors());
      },
    if (me.can('parties:read'))
      'Kontragentlar': () async {
        await _try(() => api.counterparties());
      },
    if (me.can('payments:read'))
      "To'lov so'rovlari": () async {
        await _try(() => api.paymentRequests());
      },
    if (me.can('reports:read'))
      'Hisobotlar': () async {
        final p = await api.reportPeople();
        if (const ['admin', 'viewer', 'accountant', 'cashier'].contains(me.role)) await _try(() => api.reportFeed());
        final today = _d(now);
        final fm = ((p['foremen'] as List?) ?? const []).whereType<Map>().toList();
        final sl = ((p['sellers'] as List?) ?? const []).whereType<Map>().toList();
        if (fm.isNotEmpty) await _try(() => api.reportForeman(user: (fm.first['id'] as num).toInt(), from: today, to: today));
        if (sl.isNotEmpty) await _try(() => api.reportSales(user: (sl.first['id'] as num).toInt(), from: today, to: today));
      },
    if (me.role == 'admin' || const ['accountant', 'foreman', 'viewer'].contains(me.role))
      'Ish vaqti': () async {
        await _try(() => api.aGet('/work'));
        if (me.role != 'foreman') {
          await _try(() => api.aGet('/work/staff', {'month': '${now.year}-${now.month.toString().padLeft(2, '0')}'}));
        }
      },
    if (me.can('cash:read') || me.can('funds:read'))
      'Kassa shakli': () async {
        await _try(() => api.aGet('/cash/form'));
      },
    if (me.role == 'admin' || me.role == 'accountant')
      'Boshqaruv': () async {
        await _try(() => api.aGet('/billing'));
        if (me.role == 'admin') await _try(() => api.aGet('/team'));
      },
    'Profil va smena': () async {
      await _try(() => api.profile());
      await _try(() => api.shift());
    },
    'Bildirishnomalar': () async {
      await api.notifications();
    },
  };
  var i = 0;
  var network = false;
  for (final e in steps.entries) {
    Offline.progress.value = '${tr(e.key)} (${++i}/${steps.length})';
    try {
      await e.value();
      await Future.delayed(const Duration(milliseconds: 400)); // ketma-ket og'ir ishlar orasida nafas: ilova qotmasin
    } on ApiException catch (ex) {
      if (ex.isNetwork) {
        network = true;
        break; // internet yo'q — qolganlarini keyinroq
      }
      if (ex.unauthorized) break;
    } catch (_) {}
  }
  Offline.progress.value = null;
  if (!network) await Offline.markPrefetched();
}

/// Oxirgi sotilgan kvartiralar shartnomalarini telefonga yuklaydi (offline'da ochish uchun). Eng ko'pi bilan [limit] ta.
Future<int> prefetchContracts(Session s, {int limit = 20}) async {
  final api = s.api;
  if (api == null || !Offline.enabled || Offline.progress.value != null) return 0;
  final rows = <({String obj, String apt, String sale})>[];
  try {
    for (final o in await api.objects()) {
      final id = '${o['id']}';
      for (final a in (await Offline.loadApartments(id)) ?? const <Map<String, dynamic>>[]) {
        if (a['status'] == 'sold' && a['pending'] != true) rows.add((obj: id, apt: '${a['id']}', sale: '${a['sale_date'] ?? ''}'));
      }
    }
  } catch (_) {}
  rows.sort((a, b) => b.sale.compareTo(a.sale));
  var done = 0;
  for (final r in rows.take(limit)) {
    Offline.progress.value = 'Shartnomalar (${done + 1}/${rows.take(limit).length})';
    try {
      if (await api.documentCached(r.obj, r.apt, 'contract')) {
        done++;
        continue;
      }
      await api.downloadDocument(r.obj, r.apt, 'contract');
      done++;
    } on ApiException catch (e) {
      if (e.isNetwork || e.unauthorized) break;
    } catch (_) {}
  }
  Offline.progress.value = null;
  return done;
}
