import 'api.dart';
import 'offline.dart';
import 'session.dart';

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
    'Bildirishnomalar': () async {
      await api.notifications();
    },
  };
  var i = 0;
  var network = false;
  for (final e in steps.entries) {
    Offline.progress.value = '${e.key} (${++i}/${steps.length})';
    try {
      await e.value();
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
