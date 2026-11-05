import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';

/// Navbatdagi (yuborilmagan) amal: kvartirani sotish/bron, to'lov qabul qilish, narx/holat o'zgartirish.
class QueuedOp {
  QueuedOp({required this.id, required this.kind, required this.objectId, required this.aptId, required this.method, required this.path, required this.body, required this.label, required this.createdAt, this.state = 'pending', this.error, this.file, this.amount = 0});

  factory QueuedOp.fromJson(Map<String, dynamic> j) => QueuedOp(
        id: '${j['id']}',
        kind: '${j['kind']}',
        objectId: '${j['objectId']}',
        aptId: '${j['aptId']}',
        method: '${j['method']}',
        path: '${j['path']}',
        body: Map<String, dynamic>.from((j['body'] as Map?) ?? const {}),
        label: '${j['label']}',
        createdAt: '${j['createdAt']}',
        state: '${j['state'] ?? 'pending'}',
        error: j['error'] as String?,
        file: j['file'] as String?,
        amount: (j['amount'] as num?) ?? 0,
      );

  final String id;
  final String kind; // deal | pay | update
  final String objectId;
  final String aptId;
  final String method;
  final String path;
  final Map<String, dynamic> body;
  final String label;
  final String createdAt;
  String state; // pending | failed
  String? error;
  final String? file; // xarid chekining telefondagi nusxasi (offline saqlangan surat)
  final num amount; // xarid: taxminiy summa (kompaniya valyutasida) — balansda ko'rsatish uchun

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind, 'objectId': objectId, 'aptId': aptId, 'method': method, 'path': path, 'body': body, 'label': label, 'createdAt': createdAt, 'state': state, 'error': error, 'file': file, 'amount': amount};
}

/// Offline rejim: server javoblarining lokal nusxasi, kvartiralarning to'liq ro'yxati va yuborilmagan sotuv/to'lovlar navbati.
/// Ma'lumot xodim bo'yicha alohida papkada (ilova qutisida) saqlanadi; "Chiqish"da nusxa o'chadi, lekin yuborilmagan amallar QOLADI.
class Offline {
  static bool enabled = false;
  static Directory? _dir;
  static String scope = '';

  /// Oxirgi so'rov internetga yetganmi
  static final ValueNotifier<bool> online = ValueNotifier(true);
  static final ValueNotifier<int> pending = ValueNotifier(0);
  static final ValueNotifier<int> failed = ValueNotifier(0);
  static final ValueNotifier<String?> progress = ValueNotifier(null); // oldindan yuklash holati
  static final ValueNotifier<String?> lastPrefetch = ValueNotifier(null);
  static List<QueuedOp> ops = [];
  static bool _syncing = false;

  static String newId() {
    final r = Random.secure();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }

  /// Xodim kirganda: shu xodimning papkasi ochiladi, navbat o'qiladi.
  static Future<void> init(String newScope) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final safe = newScope.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final d = Directory('${docs.path}/offline/$safe');
      await d.create(recursive: true);
      _dir = d;
      scope = newScope;
      enabled = true;
      await _loadQueue();
      try {
        lastPrefetch.value = (await _readRaw('meta_prefetch.json')) as String?;
      } catch (_) {}
    } catch (_) {
      enabled = false; // fayl tizimi yo'q (test) — oddiy online rejim
    }
  }

  static void markOnline(bool v) {
    if (online.value != v) online.value = v;
  }

  /* ---------------- fayllar ---------------- */

  static String _fname(String key) {
    var h = 0xcbf29ce484222325;
    for (final c in key.codeUnits) {
      h = (h ^ c) * 0x100000001b3;
    }
    final slug = key.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return 'c_${slug.length > 60 ? slug.substring(0, 60) : slug}_${(h & 0x7fffffffffffffff).toRadixString(36)}.json';
  }

  static Future<void> _writeRaw(String name, Object? value) async {
    final d = _dir;
    if (d == null) return;
    final f = File('${d.path}/$name');
    final tmp = File('${d.path}/$name.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(f.path);
  }

  static Future<Object?> _readRaw(String name) async {
    final d = _dir;
    if (d == null) return null;
    final f = File('${d.path}/$name');
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  /* ---------------- javoblar keshi ---------------- */

  static Future<void> put(String key, Object body) async {
    if (!enabled) return;
    try {
      await _writeRaw(_fname(key), {'at': DateTime.now().toIso8601String(), 'body': body});
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> get(String key) async {
    if (!enabled) return null;
    final v = await _readRaw(_fname(key));
    if (v is Map && v['body'] is Map) return Map<String, dynamic>.from(v['body'] as Map);
    return null;
  }

  /* ---------------- kvartiralar (to'liq nusxa) ---------------- */

  static Future<void> saveApartments(String objectId, List<Map<String, dynamic>> items) async {
    if (!enabled) return;
    try {
      await _writeRaw('apts_${_fname(objectId)}', {'at': DateTime.now().toIso8601String(), 'items': items});
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>?> loadApartments(String objectId) async {
    if (!enabled) return null;
    final v = await _readRaw('apts_${_fname(objectId)}');
    if (v is Map && v['items'] is List) return (v['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    return null;
  }

  /// Kvartiralar ro'yxati lokal nusxadan: holat/xona filtri va sahifalash serverniki kabi.
  static Future<Paged?> localApartments(String objectId, {String? status, int? rooms, int page = 1, int perPage = 50}) async {
    final all = await loadApartments(objectId);
    if (all == null) return null;
    final rows = all.where((a) => (status == null || a['status'] == status) && (rooms == null || '${a['rooms']}' == '$rooms')).toList();
    final last = max(1, (rows.length / perPage).ceil());
    final p = page.clamp(1, last);
    final slice = rows.skip((p - 1) * perPage).take(perPage).toList();
    return Paged(slice, PageMeta(page: p, lastPage: last, total: rows.length));
  }

  /// Offline bajarilgan amalning kvartiraga ta'siri — telefondagi nusxada darhol ko'rinadi ("yuborilmagan" belgisi bilan).
  static Future<Map<String, dynamic>?> applyOptimistic(QueuedOp op, {num bookingAmount = 0}) async {
    final all = await loadApartments(op.objectId);
    if (all == null) return null;
    final i = all.indexWhere((a) => '${a['id']}' == op.aptId);
    if (i < 0) return null;
    final a = Map<String, dynamic>.from(all[i]);
    num n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final payments = ((a['payments'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final b = op.body;
    void addPayment(num amount, String? method) {
      if (amount <= 0) return;
      payments.add({'id': 'pending-${op.id}', 'date': (b['date'] ?? today), 'amount': amount, 'method': (method != null && method.isNotEmpty) ? method : null, 'pending': true});
      a['paid'] = n(a['paid']) + amount;
    }

    switch (op.kind) {
      case 'deal':
        final booking = b['status'] == 'booked';
        a['status'] = b['status'];
        a['buyer'] = {'name': b['buyer_name'], 'phone': b['buyer_phone']};
        if (b['price'] != null) a['price'] = n(b['price']);
        final months = n(b['months']).toInt();
        a['plan'] = booking ? "Bron" : (months > 0 ? "Bo'lib to'lash $months oy" : "To'liq to'lov");
        a['months'] = booking ? 0 : months;
        addPayment(booking ? bookingAmount : n(b['down']), b['method'] as String?);
      case 'pay':
        addPayment(n(b['amount']), b['method'] as String?);
      case 'update':
        if (b['status'] != null) a['status'] = b['status'];
        if (b['buyer_name'] != null) a['buyer'] = (b['buyer_name'] as String).isEmpty ? null : {'name': b['buyer_name'], 'phone': b['buyer_phone'] ?? ((a['buyer'] as Map?)?['phone'])};
        if (b['price'] != null) a['price'] = n(b['price']);
        if (a['status'] == 'free') a['buyer'] = null;
    }
    a['payments'] = payments;
    a['debt'] = (a['status'] == 'sold' || a['status'] == 'booked') ? max<num>(0, n(a['price']) - n(a['paid'])) : 0;
    a['pending'] = true;
    all[i] = a;
    await saveApartments(op.objectId, all);

    return a;
  }

  /* ---------------- navbat ---------------- */

  static void _count() {
    pending.value = ops.where((o) => o.state == 'pending').length;
    failed.value = ops.where((o) => o.state == 'failed').length;
  }

  static Future<void> _loadQueue() async {
    final v = await _readRaw('queue.json');
    ops = (v is List ? v : const []).whereType<Map>().map((e) => QueuedOp.fromJson(Map<String, dynamic>.from(e))).toList();
    _count();
  }

  static Future<void> _saveQueue() async {
    try {
      await _writeRaw('queue.json', ops.map((e) => e.toJson()).toList());
    } catch (_) {}
    _count();
  }

  static Future<void> enqueue(QueuedOp op) async {
    ops.add(op);
    await _saveQueue();
  }

  static Future<void> discard(String id) async {
    final o = ops.where((e) => e.id == id).firstOrNull;
    ops.removeWhere((e) => e.id == id);
    await _saveQueue();
    await _deleteFile(o?.file);
  }

  /// Chek suratini ilovaning doimiy papkasiga ko'chiradi (kamera vaqtinchalik fayli o'chib ketishi mumkin)
  static Future<String?> stashFile(String? src) async {
    final d = _dir;
    if (src == null || d == null) return null;
    try {
      final dir = Directory('${d.path}/receipts');
      await dir.create(recursive: true);
      final ext = src.contains('.') ? src.substring(src.lastIndexOf('.')) : '.jpg';
      final dst = '${dir.path}/${newId()}$ext';
      await File(src).copy(dst);
      return dst;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteFile(String? p) async {
    if (p == null) return;
    try {
      await File(p).delete();
    } catch (_) {}
  }

  /// Yuborilmagan xaridlarning (taxminiy) summasi: 'cash' | 'card' — balansdan ayirib ko'rsatiladi
  static num pendingSpend(String kind) => ops.where((o) => o.kind == 'spend' && o.state == 'pending' && o.body['kind'] == kind).fold<num>(0, (a, o) => a + o.amount);

  static Future<void> retryFailed() async {
    for (final o in ops) {
      if (o.state == 'failed') {
        o.state = 'pending';
        o.error = null;
      }
    }
    await _saveQueue();
  }

  /// Navbatni tartib bilan yuboradi. Internet yo'q bo'lsa to'xtaydi; server rad etsa ("kvartira allaqachon sotilgan") — amal "xato" belgisi bilan qoladi.
  static Future<int> sync(ApiClient api) async {
    if (!enabled || _syncing) return 0;
    _syncing = true;
    var done = 0;
    final touched = <String>{};
    try {
      for (final op in List<QueuedOp>.of(ops)) {
        if (op.state != 'pending') continue;
        try {
          await api.sendQueuedOp(op);
          ops.remove(op);
          await _deleteFile(op.file);
          touched.add(op.objectId);
          done++;
          await _saveQueue();
        } on ApiException catch (e) {
          if (e.isNetwork) {
            markOnline(false);
            break;
          }
          if (e.unauthorized) break; // kirish muddati tugagan — navbat saqlanadi, qayta kirgach yuboriladi
          op.state = 'failed';
          op.error = e.message;
          await _saveQueue();
        }
      }
      for (final o in touched) {
        try {
          await api.downloadAllApartments(o);
        } catch (_) {}
      }
    } finally {
      _syncing = false;
    }
    return done;
  }

  /* ---------------- oldindan yuklash va tozalash ---------------- */

  static Future<void> markPrefetched() async {
    final now = DateTime.now().toIso8601String();
    lastPrefetch.value = now;
    try {
      await _writeRaw('meta_prefetch.json', now);
    } catch (_) {}
  }

  /// "Chiqish": ma'lumot nusxasi o'chadi (boshqa odam ko'rmasin), yuborilmagan amallar fayli qoladi.
  static Future<void> clearCache() async {
    final d = _dir;
    if (d != null && await d.exists()) {
      await for (final e in d.list()) {
        if (e is File && !e.path.endsWith('queue.json')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    }
    lastPrefetch.value = null;
    progress.value = null;
  }

  static void disable() {
    enabled = false;
    _dir = null;
    ops = [];
    _count();
  }
}
