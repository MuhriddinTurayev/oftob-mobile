import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'offline.dart';
import 'upload.dart';

/// Yozish so'rovlarini (POST/PATCH/DELETE) belgilab boradi — keyingi o'qishlar yangi ma'lumotni sabr bilan kutadi
class _WriteTracker extends http.BaseClient {
  _WriteTracker(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method != 'GET' && request.method != 'HEAD') ApiClient._lastWrite = DateTime.now();
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Server xatosi: matni foydalanuvchiga ko'rsatiladi.
/// Katta JSON alohida oqimda o'qiladi (yopilma faqat baytlarni ushlaydi — boshqa obyektlar oqimga o'tmaydi).
Future<dynamic> _decodeInBackground(List<int> bytes) => Isolate.run(() => jsonDecode(utf8.decode(bytes)));

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.code});

  final String message;
  final int? status;
  final String? code;

  bool get unauthorized => status == 401;

  /// Internetga yetib bo'lmadi (javob umuman kelmadi) — offline rejim shunda ishga tushadi
  bool get isNetwork => code == 'network';

  @override
  String toString() => message;
}

/// Oftob CRM ochiq API (`/api/v1`) bilan ishlaydi.
/// Ma'lumotlar bazasiga to'g'ridan-to'g'ri EMAS — faqat server orqali (kalit bilan).
class ApiClient {
  /// 401 kelganda chaqiriladi (Session o'rnatadi): har qanday so'rov — fondagi yangilash ham — bekor qilingan kalitni sezadi
  static void Function()? onUnauthorized;

  /// Kompaniya tarifi muddati tugagan (402): ilova «Tarif va to'lov» ni taklif qiladi
  static void Function()? onExpired;

  /// Server matnlari tili: uz | ru | tg (ilova tili o'zgarganda L.set yangilaydi)
  static String lang = 'uz';

  ApiClient({required String serverUrl, required this.apiKey, http.Client? client})
      : base = normalizeUrl(serverUrl),
        _http = _WriteTracker(client ?? http.Client());

  /// Oxirgi yozish (POST/PATCH/DELETE) vaqti: shundan keyingi ~30 soniyada ro'yxatlar serverni sabr bilan kutadi —
  /// yangi saqlangan narsa eski nusxa ostida «yo'qolib» qolmasin
  static DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  final String base; // masalan https://oftob.37-60-247-120.sslip.io
  final String apiKey;
  final http.Client _http;

  /// '' — kompaniya xodimi; '/platform' — platforma administratori (yordam, bildirishnomalar shu yo'l ostida)
  String scope = '';

  static String normalizeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('/api/v1')) s = s.substring(0, s.length - 7);
    return s;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
        'Accept-Language': ApiClient.lang,
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{'lang': ApiClient.lang};
    query?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) q[k] = '$v';
    });
    final u = Uri.parse('$base/api/v1$path');
    return u.replace(queryParameters: q);
  }

  Future<dynamic> _send(Future<http.Response> Function() call, {Duration timeout = const Duration(seconds: 25), int retries = 0}) async {
    http.Response r;
    var attempt = 0;
    while (true) {
      try {
        r = await call().timeout(timeout);
        break;
      } on TimeoutException {
        Offline.markOnline(false);
        throw ApiException('Server javob bermadi. Internet va manzilni tekshiring.', code: 'network');
      } on FormatException {
        throw ApiException('Server manzili noto\'g\'ri.');
      } catch (e) {
        // mobil internetda eski ulanish uzilib qolgan bo'lishi mumkin (connection reset) — bir marta darhol qayta urinamiz
        if (attempt++ < retries) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        Offline.markOnline(false);
        throw ApiException('Serverga ulanib bo\'lmadi. Internet va manzilni tekshiring.', code: 'network');
      }
    }
    Offline.markOnline(true); // server javob berdi (xato bo'lsa ham) — internet bor
    dynamic body;
    try {
      final bytes = r.bodyBytes;
      // katta javob (ro'yxatlar) alohida oqimda o'qiladi — ekran shu paytda qotmaydi
      body = bytes.isEmpty ? null : (bytes.length > 24000 ? await _decodeInBackground(bytes) : jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      body = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    // kalit bekor qilingan (boshqa qurilmadan «seansni yopish» yoki parol almashgan): ilova darhol hisobdan chiqadi
    if (r.statusCode == 401 && ApiClient.onUnauthorized != null) scheduleMicrotask(ApiClient.onUnauthorized!);
    if (r.statusCode == 402 && ApiClient.onExpired != null) scheduleMicrotask(ApiClient.onExpired!);

    String msg = 'Xato (${r.statusCode})';
    String? code;
    if (body is Map) {
      final err = body['error'];
      if (err is Map) {
        msg = '${err['message'] ?? msg}';
        code = err['code'] as String?;
      } else if (body['errors'] is Map) {
        final first = (body['errors'] as Map).values.first;
        msg = first is List && first.isNotEmpty ? '${first.first}' : '$first';
      } else if (body['message'] != null) {
        msg = '${body['message']}';
      }
    }
    switch (code) {
      case 'invalid_key':
        msg = 'API kalit noto\'g\'ri.';
      case 'key_revoked':
        msg = 'API kalit bekor qilingan. Yangisini oling.';
      case 'key_expired':
        msg = 'API kalit muddati tugagan.';
      case 'subscription_inactive':
        msg = "Kompaniya tarifi muddati tugagan. Rahbar yoki buxgalter «Tarif va to'lov» dan to'lov qilsin.";
      case 'insufficient_scope':
        msg = 'Bu bo\'lim uchun kalitda ruxsat yo\'q.';
      case 'rate_limited':
        msg = 'So\'rovlar juda ko\'p. Biroz kuting.';
      case 'invalid_credentials':
        msg = 'Login yoki parol noto\'g\'ri.';
      case 'user_disabled':
        msg = 'Sizning kirishingiz o\'chirilgan. Rahbarga murojaat qiling.';
      case 'api_disabled':
        msg = 'Mobil kirish vaqtincha o\'chirilgan.';
    }
    if (r.statusCode == 429 && code == null) msg = 'Juda ko\'p urinish. Bir necha daqiqadan keyin qayta urining.';
    throw ApiException(msg, status: r.statusCode, code: code);
  }

  String _cacheKey(String path, [Map<String, dynamic>? q]) {
    final uri = _uri(path, q);
    final qs = (uri.queryParameters.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join('&');
    return '${uri.path.replaceFirst('/api/v1', '')}?$qs';
  }

  /// Filtrsiz saqlangan sahifalarni (1, 2, 3 …) birlashtiradi — offline'da filtr/qidiruvni telefonning o'zida bajarish uchun. Hech bir sahifa yo'q bo'lsa — null.
  Future<List<Map<String, dynamic>>?> _cachedAll(String path, Map<String, dynamic> baseQ) async {
    final all = <Map<String, dynamic>>[];
    var any = false;
    for (var p = 1; p <= 60; p++) {
      final m = await Offline.get(_cacheKey(path, {...baseQ, 'page': p}));
      if (m == null) break;
      any = true;
      all.addAll(_list(m['data']));
      if (!PageMeta.from(m['meta']).hasMore) break;
    }
    return any ? all : null;
  }

  Paged _localPaged(List<Map<String, dynamic>> rows, int page, int per) {
    final last = rows.isEmpty ? 1 : (rows.length / per).ceil();
    final p = page.clamp(1, last);
    return Paged(rows.skip((p - 1) * per).take(per).toList(), PageMeta(page: p, lastPage: last, total: rows.length));
  }

  /// GET: javob lokal nusxaga yoziladi; internet bo'lmasa — oxirgi saqlangan nusxa qaytariladi (offline rejim).
  /// Internet sekin yoki uzilib-uzilib ishlasa ekran aylanib turmaydi: saqlangan nusxa bo'lsa va server bir necha soniyada
  /// javob bermasa — darhol saqlangan nusxa ko'rsatiladi, yangisi esa fonda kelib keshga yoziladi (keyingi ochilishda yangi).
  Future<Map<String, dynamic>> _getMap(String path, [Map<String, dynamic>? q, Duration patience = const Duration(milliseconds: 3500)]) async {
    final uri = _uri(path, q);
    final qs = (uri.queryParameters.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join('&');
    final key = '${uri.path.replaceFirst('/api/v1', '')}?$qs';
    final online = Offline.online.value;
    final net = () async {
      final b = await _send(() => _http.get(uri, headers: _headers), timeout: online ? const Duration(seconds: 25) : const Duration(seconds: 8), retries: 1);
      final m = b is Map ? Map<String, dynamic>.from(b) : <String, dynamic>{};
      if (Offline.enabled) unawaited(Offline.put(key, m));
      return m;
    }();
    if (!Offline.enabled) return net;
    final cached = await _cachedFor(key, q);
    if (cached == null) return net; // saqlangan nusxa yo'q — faqat server
    final c = Completer<Map<String, dynamic>>();
    unawaited(net.then((m) {
      if (!c.isCompleted) c.complete(m);
    }, onError: (Object e) {
      if (c.isCompleted) return;
      if (e is ApiException && e.isNetwork) {
        c.complete(cached);
      } else {
        c.completeError(e);
      }
    }));
    // yaqinda biror narsa saqlangan bo'lsa — serverni ko'proq kutamiz (yangi yozuv ko'rinsin)
    final recentWrite = DateTime.now().difference(_lastWrite) < const Duration(seconds: 30);
    final wait = !online ? const Duration(milliseconds: 700) : (recentWrite ? const Duration(seconds: 12) : patience);
    Timer(wait, () {
      if (!c.isCompleted) c.complete(cached);
    });
    return c.future;
  }

  /// Saqlangan nusxa: aynan shu so'rov; bo'lmasa — bugungi sana bilan / sanasiz varianti (masalan, davomat bugun uchun)
  Future<Map<String, dynamic>?> _cachedFor(String key, Map<String, dynamic>? q) async {
    final c = await Offline.get(key);
    if (c != null) return c;
    final n = DateTime.now();
    final today = '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    final d = q?['date'];
    if (d == null || d == '' || d == today) {
      final alt = key.contains('date=$today') ? key.replaceFirst('date=$today&', '').replaceFirst('&date=$today', '').replaceFirst('?date=$today', '?') : key.replaceFirst('?', '?date=$today&');
      final a = await Offline.get(alt);
      if (a != null) return a;
    }
    return null;
  }

  /// Navbatdagi (offline yig'ilgan) amalni yuboradi; Idempotency-Key tufayli takror yuborilsa ham bir marta bajariladi.
  Future<dynamic> sendQueued(String method, String path, Map<String, dynamic> body, String idemKey, {Duration timeout = const Duration(seconds: 25)}) {
    final uri = _uri(path);
    final headers = {..._headers, 'Idempotency-Key': idemKey};
    return _send(() => method == 'PATCH' ? _http.patch(uri, headers: headers, body: jsonEncode(body)) : _http.post(uri, headers: headers, body: jsonEncode(body)), timeout: timeout);
  }

  String _hm(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    return t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// Oddiy (fayl yo'q) amalni yuboradi; internet yo'q bo'lsa navbatga qo'yadi. `null` — yuborildi (server javobi `data`), `queued` — navbatda.
  Future<({bool queued, Map<String, dynamic> data})> _queueGeneric({required String kind, required String method, required String path, required Map<String, dynamic> body, required String label, String objectId = '', String refId = '', String? idem}) async {
    final id = idem ?? Offline.newId();
    try {
      final b = await sendQueued(method, path, body, id, timeout: Offline.online.value ? const Duration(seconds: 25) : const Duration(seconds: 6));
      return (queued: false, data: Map<String, dynamic>.from(((b is Map ? b['data'] : null) as Map?) ?? const {}));
    } on ApiException catch (e) {
      if (!(e.isNetwork && Offline.enabled)) rethrow;
      await Offline.enqueue(QueuedOp(id: id, kind: kind, objectId: objectId, aptId: refId, method: method, path: path, body: body, label: label, createdAt: DateTime.now().toIso8601String()));
      return (queued: true, data: <String, dynamic>{});
    }
  }

  /// Saqlangan smena holatiga navbatdagi (yuborilmagan) bosishlarni qo'llaydi
  Map<String, dynamic> _shiftWithQueue(Map<String, dynamic> base) {
    final st = Map<String, dynamic>.from(base.isEmpty ? {'status': 'none'} : base);
    for (final o in Offline.ops.where((o) => o.kind == 'shift' && o.state == 'pending')) {
      final b = o.body;
      switch (o.aptId) {
        case 'start':
          if (st['status'] == 'none' || st['status'] == null) {
            st..['status'] = 'working'
              ..['in'] = _hm('${b['at']}')
              ..['in_ts'] = b['at']
              ..['out_ts'] = null
              ..['out'] = null
              ..['in_lat'] = b['lat']
              ..['in_lng'] = b['lng']
              ..['in_dist'] = null
              ..['pending'] = true;
          }
        case 'end':
          if (st['status'] == 'working') {
            st..['status'] = 'left'
              ..['out'] = _hm('${b['at']}')
              ..['out_ts'] = b['at']
              ..['pending'] = true;
          }
        case 'reopen':
          if (st['status'] == 'left') {
            st..['status'] = 'working'
              ..['out'] = null
              ..['pending'] = true;
          }
      }
    }
    return st;
  }

  /// Davomat: yuborilmagan «smenaga qo'yish / olish» telefondagi ro'yxatda darhol ko'rinadi
  Map<String, dynamic> _attendanceWithQueue(Map<String, dynamic> d, String? date) {
    final pend = Offline.ops.where((o) => o.kind == 'attendance' && o.state == 'pending').toList();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (pend.isEmpty || (date != null && date != today && date != '${d['date']}')) return d;
    final sites = ((d['sites'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    for (final o in pend) {
      final ids = ((o.body['staff_ids'] as List?) ?? const []).map((e) => '$e').toSet();
      for (final site in sites) {
        if ('${site['id']}' != o.objectId) continue;
        final workers = ((site['workers'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        for (final w in workers) {
          if (!ids.contains('${w['id']}')) continue;
          if (o.aptId == 'in' && w['status'] != 'working') {
            w..['status'] = 'working'
              ..['in'] = _hm('${o.body['at']}')
              ..['out'] = null
              ..['pending'] = true;
          } else if (o.aptId == 'out' && w['status'] == 'working') {
            w..['status'] = 'left'
              ..['out'] = _hm('${o.body['at']}')
              ..['pending'] = true;
          }
        }
        site['workers'] = workers;
        site['working'] = workers.where((w) => w['status'] == 'working').length;
        site['left'] = workers.where((w) => w['status'] == 'left').length;
        site['absent'] = workers.where((w) => w['status'] == 'absent').length;
        site['came'] = workers.length - (site['absent'] as int);
      }
    }
    return {...d, 'sites': sites};
  }

  /// Navbatdagi amalni turiga qarab yuboradi (xarid — chek surati bilan multipart, qolganlari — JSON)
  Future<dynamic> sendQueuedOp(QueuedOp op) {
    if (op.kind == 'spend') {
      final fields = op.body.map((k, v) => MapEntry(k, '$v'));
      return _postSpend(fields, op.file, op.id);
    }
    return sendQueued(op.method, op.path, op.body, op.id);
  }

  Future<dynamic> _postSpend(Map<String, String> fields, String? receiptPath, String idemKey, {UploadProgress? onProgress}) {
    return _send(() async {
      final req = ProgressMultipartRequest('POST', _uri('/funds/spend'), onProgress: onProgress)
        ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang, 'Idempotency-Key': idemKey})
        ..fields.addAll(fields);
      if (receiptPath != null && await File(receiptPath).exists()) req.files.add(await http.MultipartFile.fromPath('receipt', receiptPath));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 150)));
    }, timeout: const Duration(seconds: 160));
  }

  /// Offline'da ishlash uchun obyektning BARCHA kvartiralarini telefonga yuklaydi
  Future<void> downloadAllApartments(String objectId) async {
    final all = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final m = await _getMap('/objects/${Uri.encodeComponent(objectId)}/apartments', {'page': page, 'per_page': 200});
      all.addAll(_list(m['data']));
      final meta = PageMeta.from(m['meta']);
      if (!meta.hasMore || page >= 50) break;
      page++;
    }
    await Offline.saveApartments(objectId, all);
  }

  /// Amalni yuboradi; internet bo'lmasa navbatga qo'yadi va telefondagi nusxaga darhol qo'llaydi (`queued: true` qaytadi).
  Future<Map<String, dynamic>> _queueable({required String kind, required String method, required String path, required Map<String, dynamic> body, required String objectId, required String aptId, required String label}) async {
    final id = Offline.newId();
    try {
      final b = await sendQueued(method, path, body, id, timeout: Offline.online.value ? const Duration(seconds: 25) : const Duration(seconds: 6));
      return Map<String, dynamic>.from((b as Map)['data'] as Map);
    } on ApiException catch (e) {
      if (!(e.isNetwork && Offline.enabled)) rethrow;
      final op = QueuedOp(id: id, kind: kind, objectId: objectId, aptId: aptId, method: method, path: path, body: body, label: label, createdAt: DateTime.now().toIso8601String());
      num booking = 0;
      if (kind == 'deal' && body['status'] == 'booked') {
        try {
          booking = ((await salesTerms())['booking'] as Map?)?['amount'] as num? ?? 0;
        } catch (_) {}
      }
      final apt = await Offline.applyOptimistic(op, bookingAmount: booking);
      await Offline.enqueue(op);
      return {'queued': true, 'op': id, 'apartment': apt};
    }
  }

  List<Map<String, dynamic>> _list(dynamic data) =>
      (data is List ? data : const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  /* ---------------- kirish (xodim) ---------------- */

  /// Xodim kirishi: korxona kodi + login (email yoki telefon) + parol → shaxsiy kalit (roli bilan).
  static Future<StaffLogin> login(String serverUrl, {required String company, required String email, required String password, String device = 'telefon', http.Client? client}) async {
    final c = ApiClient(serverUrl: serverUrl, apiKey: '', client: client);
    try {
      final b = await c._send(() => c._http.post(
            c._uri('/auth/login'),
            headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'Accept-Language': ApiClient.lang},
            body: jsonEncode({'company': company, 'email': email, 'password': password, 'device': device}),
          ));
      return StaffLogin.fromJson(Map<String, dynamic>.from((b as Map)['data'] as Map), c.base);
    } on ApiException catch (e) {
      // yangi mobil kirish serverga hali yuklanmagan (marshrut yo'q)
      if (e.status == 404 || e.status == 405) {
        throw ApiException('Server hali yangilanmagan: mobil kirish xizmati topilmadi. Administratorga murojaat qiling.', status: e.status, code: e.code);
      }
      rethrow;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Parolni tiklash 1-qadam: kod xodimning Telegram'iga yuboriladi. Javob doim bir xil (akkaunt bor-yo'qligi oshkor bo'lmaydi).
  static Future<void> forgot(String serverUrl, {required String company, required String login, http.Client? client}) async {
    final c = ApiClient(serverUrl: serverUrl, apiKey: '', client: client);
    try {
      await c._send(() => c._http.post(c._uri('/auth/forgot'),
          headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'Accept-Language': ApiClient.lang}, body: jsonEncode({'company': company, 'email': login})));
    } on ApiException catch (e) {
      if (e.status == 404 || e.status == 405) {
        throw ApiException("Server hali yangilanmagan: parolni tiklash xizmati topilmadi. Administratorga murojaat qiling.", status: e.status);
      }
      rethrow;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Parolni tiklash 2-qadam: kod + yangi parol. Muvaffaqiyatli bo'lsa barcha eski kirishlar yopiladi.
  static Future<void> resetPassword(String serverUrl, {required String company, required String login, required String code, required String password, http.Client? client}) async {
    final c = ApiClient(serverUrl: serverUrl, apiKey: '', client: client);
    try {
      await c._send(() => c._http.post(c._uri('/auth/reset'),
          headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'Accept-Language': ApiClient.lang},
          body: jsonEncode({'company': company, 'email': login, 'code': code, 'password': password})));
    } on ApiException catch (e) {
      if (e.code == 'invalid_code') throw ApiException("Kod noto'g'ri yoki muddati tugagan. Yangi kod so'rang.", status: e.status, code: e.code);
      rethrow;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Chiqishda shu qurilmaning kaliti serverda bekor qilinadi (xato bo'lsa — e'tibor bermaymiz).
  Future<void> logout() async {
    try {
      await _send(() => _http.post(_uri('/auth/logout'), headers: _headers));
    } catch (_) {}
  }

  /* ---------------- umumiy ---------------- */

  /// Kalit egasi, kompaniya, ruxsatlar.
  /// Ilova ochilishida: saqlangan profil bo'lsa 1,5 soniyadan ortiq kutilmaydi (rol va ruxsatlar kamdan-kam o'zgaradi)
  Future<Me> me() async => Me.fromJson((await _getMap('/me', null, const Duration(milliseconds: 1500)))['data'] as Map);

  /* ---------------- obyektlar ---------------- */

  Future<List<Map<String, dynamic>>> objects() async => _list((await _getMap('/objects'))['data']);

  Future<Paged> apartments(String objectId, {String? status, int? rooms, int page = 1, int perPage = 50}) async {
    try {
      final m = await _getMap('/objects/${Uri.encodeComponent(objectId)}/apartments', {'status': status, 'rooms': rooms, 'page': page, 'per_page': perPage});
      return Paged(_list(m['data']), PageMeta.from(m['meta']));
    } on ApiException catch (e) {
      // internet yo'q: telefondagi to'liq nusxadan (filtr va sahifalash bilan)
      if (e.isNetwork) {
        final local = await Offline.localApartments(objectId, status: status, rooms: rooms, page: page, perPage: perPage);
        if (local != null) return local;
      }
      rethrow;
    }
  }

  /// Kvartira holatini o'zgartirish (bron / sotuv / bo'sh). Faqat o'zgargan maydonlarni yuboring.
  /* ---------------- yordam (support) ---------------- */

  Future<Map<String, dynamic>> supportIndex() async => Map<String, dynamic>.from(((await _getMap('$scope/support'))['data'] as Map?) ?? const {});

  Future<Map<String, dynamic>> supportMessages(int thread, {int after = 0}) async =>
      Map<String, dynamic>.from(((await _getMap('$scope/support/$thread/messages', {'after': after > 0 ? after : null}))['data'] as Map?) ?? const {});

  /// Matn va/yoki rasm (skrinshot, foto). Rasm bo'lsa — multipart, yuklanish foizi [onProgress] ga
  Future<Map<String, dynamic>> supportSend({required String body, int? threadId, String? imagePath, UploadProgress? onProgress}) async {
    final dynamic b;
    if (imagePath == null) {
      b = await _send(() => _http.post(_uri('$scope/support/send'), headers: _headers, body: jsonEncode({'body': body, if (threadId != null) 'thread_id': threadId})));
    } else {
      b = await _send(() async {
        final req = ProgressMultipartRequest('POST', _uri('$scope/support/send'), onProgress: onProgress)
          ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang})
          ..fields.addAll({if (body.isNotEmpty) 'body': body, if (threadId != null) 'thread_id': '$threadId'});
        req.files.add(await http.MultipartFile.fromPath('image', imagePath));
        return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 150)));
      }, timeout: const Duration(seconds: 160));
    }
    return Map<String, dynamic>.from(((b as Map?)?['data'] as Map?) ?? const {});
  }

  /// Chatdagi rasm manzili (Image.network uchun [authHeaders] bilan)
  String supportFileUrl(int messageId) => _uri('$scope/support/file/$messageId').toString();

  /* ---------------- platforma administratori ---------------- */

  /// Platforma egasi kirishi (login va parol). Qaytadi: shaxsiy kalit (ofp_…)
  static Future<String> platformLogin(String serverUrl, {required String email, required String password, String device = 'telefon'}) async {
    final c = ApiClient(serverUrl: serverUrl, apiKey: '');
    try {
      final b = await c._send(() => c._http.post(c._uri('/platform/login'),
          headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'Accept-Language': ApiClient.lang},
          body: jsonEncode({'email': email, 'password': password, 'device': device})));
      return '${((b as Map)['data'] as Map)['token']}';
    } on ApiException catch (e) {
      if (e.status == 404 || e.status == 405) throw ApiException('Server hali yangilanmagan: platforma kirishi topilmadi.', status: e.status);
      rethrow;
    } finally {
      c.close();
    }
  }

  /// Platforma API: GET → `data` (Map yoki List)
  Future<dynamic> pGet(String path, [Map<String, dynamic>? q]) async => (await _getMap('/platform$path', q))['data'];

  /// Platforma API: POST / PUT / DELETE → `data`
  Future<dynamic> pSend(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = _uri('/platform$path');
    final enc = jsonEncode(body ?? const {});
    final b = await _send(() => switch (method) {
          'PUT' => _http.put(uri, headers: _headers, body: enc),
          'DELETE' => _http.delete(uri, headers: _headers),
          _ => _http.post(uri, headers: _headers, body: enc),
        }, timeout: const Duration(seconds: 40));
    return b is Map ? b['data'] : null;
  }

  /// Kompaniya kodi o'rniga platforma administratori kodi yozilganmi (server so'raydi; eski serverda — false)
  static Future<bool> platformGate(String serverUrl, String code) async {
    final c = ApiClient(serverUrl: serverUrl, apiKey: '');
    try {
      final b = await c._send(() => c._http.post(c._uri('/platform/gate'),
          headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'Accept-Language': ApiClient.lang}, body: jsonEncode({'code': code})), timeout: const Duration(seconds: 12));
      return b is Map && (b['data'] as Map?)?['platform'] == true;
    } catch (_) {
      return false;
    } finally {
      c.close();
    }
  }

  /// Kirish oynasi uchun «Kirish uchun bog'laning» ma'lumoti (kirishsiz). Xato yoki internet yo'q — null
  static Future<Map<String, dynamic>?> loginInfo(String serverUrl) async {
    final c = ApiClient(serverUrl: serverUrl, apiKey: '');
    try {
      final b = await c._send(() => c._http.get(c._uri('/app/info'), headers: {'Accept': 'application/json', 'Accept-Language': ApiClient.lang}), timeout: const Duration(seconds: 10));
      return b is Map && b['data'] is Map ? Map<String, dynamic>.from(b['data'] as Map) : null;
    } catch (_) {
      return null;
    } finally {
      c.close();
    }
  }

  /// Platforma: kirishsiz so'rov (parolni tiklash) → `data`
  static Future<dynamic> platformPublic(String serverUrl, String path, Map<String, dynamic> body) async {
    final c = ApiClient(serverUrl: serverUrl, apiKey: '');
    try {
      final b = await c._send(() => c._http.post(c._uri('/platform$path'),
          headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'Accept-Language': ApiClient.lang}, body: jsonEncode(body)));
      return b is Map ? b['data'] : null;
    } finally {
      c.close();
    }
  }

  /* ---------------- umumiy: tarif, AI, jamoa (rahbar va buxgalter) ---------------- */

  /// GET → `data` (internet bo'lmasa — oxirgi nusxa)
  Future<dynamic> aGet(String path, [Map<String, dynamic>? q]) async => (await _getMap(path, q))['data'];

  /// POST / PUT / DELETE → `data`
  Future<dynamic> aSend(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = _uri(path);
    final enc = jsonEncode(body ?? const {});
    final b = await _send(() => switch (method) {
          'PUT' => _http.put(uri, headers: _headers, body: enc),
          'DELETE' => _http.delete(uri, headers: _headers),
          _ => _http.post(uri, headers: _headers, body: enc),
        }, timeout: const Duration(seconds: 45));
    return b is Map ? b['data'] : null;
  }

  /// Fayl bilan POST (chek): maydonlar + bitta fayl, foiz bilan
  Future<dynamic> aUpload(String path, Map<String, String> fields, {String? file, String field = 'receipt', UploadProgress? onProgress}) async {
    final b = await _send(() async {
      final req = ProgressMultipartRequest('POST', _uri(path), onProgress: onProgress)
        ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang})
        ..fields.addAll(fields);
      if (file != null) req.files.add(await http.MultipartFile.fromPath(field, file));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 150)));
    }, timeout: const Duration(seconds: 160));
    return b is Map ? b['data'] : null;
  }

  /// Rasm/fayl manzili (Image.network + authHeaders bilan ko'rsatiladi)
  String fileUrl(String path) => _uri(path).toString();

  /* ---------------- lid manbalari ---------------- */

  Future<Map<String, dynamic>> leadSources() async => Map<String, dynamic>.from(((await _getMap('/leads/sources'))['data'] as Map?) ?? const {});

  Future<void> leadSourceTest(String ch) async {
    await _send(() => _http.post(_uri('/leads/sources/test'), headers: _headers, body: jsonEncode({'ch': ch})));
  }

  Future<Map<String, dynamic>> leadSourceMeta({String? pageToken, String? appSecret}) async {
    final b = await _send(() => _http.post(_uri('/leads/sources/meta'), headers: _headers, body: jsonEncode({if (pageToken != null && pageToken.isNotEmpty) 'page_token': pageToken, if (appSecret != null && appSecret.isNotEmpty) 'app_secret': appSecret})), timeout: const Duration(seconds: 40));
    return Map<String, dynamic>.from(((b as Map?)?['data'] as Map?) ?? const {});
  }

  /// Bitta xonadon (to'lovlar, grafik, xaridor bilan)
  Future<Map<String, dynamic>> apartment(String objectId, String apartmentId) async =>
      Map<String, dynamic>.from(((await _getMap('/objects/${Uri.encodeComponent(objectId)}/apartments/${Uri.encodeComponent(apartmentId)}'))['data'] as Map?) ?? const {});

  Future<Map<String, dynamic>> apartmentUpdate(String objectId, String apartmentId, Map<String, dynamic> body) async {
    return _queueable(kind: 'update', method: 'PATCH', path: '/objects/${Uri.encodeComponent(objectId)}/apartments/${Uri.encodeComponent(apartmentId)}', body: body, objectId: objectId, aptId: apartmentId, label: 'Kvartira $apartmentId — o\'zgartirish');
  }

  /// Muddatli to'lov stavkalari, bron sharti (zadatok, kun), stavka/narxni kim o'zgartira olishi
  Future<Map<String, dynamic>> salesTerms() async => Map<String, dynamic>.from(((await _getMap('/sales/terms'))['data'] as Map?) ?? const {});

  /// Bo'lib to'lash foizlari va bron sharti (rahbar, buxgalter). Qaytadi: yangilangan shartlar
  Future<Map<String, dynamic>> salesTermsSave({required List<Map<String, num>> rates, num? bookingAmount, int? bookingDays}) async {
    final b = await _send(() => _http.post(_uri('/sales/terms'), headers: _headers, body: jsonEncode({'rates': rates, 'booking': {'amount': bookingAmount ?? 0, 'days': bookingDays ?? 3}})));
    return Map<String, dynamic>.from(((b as Map?)?['data'] as Map?) ?? const {});
  }

  /* ---------------- kompaniya hisobotlari ---------------- */

  /// Lenta: kompaniya kunlik hisobotlari, prorab va sotuvchi hisobotlari (har birida `pdf` yo'li)
  Future<Map<String, dynamic>> reportFeed({String? type}) async => Map<String, dynamic>.from(((await _getMap('/reports/feed', {'t': type}))['data'] as Map?) ?? const {});

  Future<void> reportCompanyRun() async {
    await _send(() => _http.post(_uri('/reports/company/run'), headers: _headers, body: '{}'), timeout: const Duration(seconds: 90));
  }

  /// Buxgalter → direktor. Javob: {message, sent_at, telegram}
  Future<Map<String, dynamic>> reportForward(String path, {required String idemKey}) async {
    final b = await _send(() => _http.post(_uri(path), headers: {..._headers, 'Idempotency-Key': idemKey}, body: '{}'), timeout: const Duration(seconds: 90));
    return Map<String, dynamic>.from(((b as Map?)?['data'] as Map?) ?? const {});
  }

  /// Istalgan PDF (API yo'li so'rov qatori bilan): baytlar; yuklanish foizi [onProgress] ga
  Future<List<int>> downloadPdf(String pathWithQuery, {UploadProgress? onProgress}) async {
    final i = pathWithQuery.indexOf('?');
    final path = i < 0 ? pathWithQuery : pathWithQuery.substring(0, i);
    final q = i < 0 ? <String, dynamic>{} : Uri.splitQueryString(pathWithQuery.substring(i + 1));
    final http.Response r;
    try {
      final req = http.Request('GET', _uri(path, q))..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/pdf, application/json', 'Accept-Language': ApiClient.lang});
      final res = await _http.send(req).timeout(const Duration(seconds: 60));
      final total = res.contentLength ?? 0;
      final buf = <int>[];
      onProgress?.call(0, total);
      await for (final c in res.stream.timeout(const Duration(seconds: 90))) {
        buf.addAll(c);
        onProgress?.call(buf.length, total);
      }
      r = http.Response.bytes(buf, res.statusCode, headers: res.headers);
    } catch (_) {
      Offline.markOnline(false);
      throw ApiException("Serverga ulanib bo'lmadi. Internet va manzilni tekshiring.", code: 'network');
    }
    if (r.statusCode == 200 && r.bodyBytes.length > 4 && String.fromCharCodes(r.bodyBytes.take(4)) == '%PDF') return r.bodyBytes;
    if (r.statusCode == 401) {
      if (ApiClient.onUnauthorized != null) scheduleMicrotask(ApiClient.onUnauthorized!);
      throw ApiException('Kirish muddati tugagan.', status: 401);
    }
    if (r.statusCode == 403) throw ApiException("Bu hujjatni ochishga ruxsat yo'q.");
    throw ApiException("Hujjatni olib bo'lmadi (${r.statusCode}).");
  }

  /// Sotish yoki bron — saytdagi «Продать / Забронировать» ning o'zi (boshlang'ich to'lov kassaga, grafik, shartnoma).
  Future<Map<String, dynamic>> apartmentDeal(String objectId, String apartmentId, Map<String, dynamic> body) async {
    return _queueable(
      kind: 'deal',
      method: 'POST',
      path: '/objects/${Uri.encodeComponent(objectId)}/apartments/${Uri.encodeComponent(apartmentId)}/deal',
      body: body,
      objectId: objectId,
      aptId: apartmentId,
      label: 'Kvartira $apartmentId — ${body['status'] == 'booked' ? 'bron' : 'sotish'}',
    );
  }

  /// Shartnoma (kind='contract') yoki to'lov cheki (kind='receipt', id=to'lov raqami) PDF baytlari.
  /// Bir marta ochilgan hujjat telefonda saqlanadi: internet bo'lmasa saqlangan nusxa ochiladi.
  Future<List<int>> downloadDocument(String objectId, String apartmentId, String kind, {String? id, UploadProgress? onProgress}) async {
    final path = '/objects/${Uri.encodeComponent(objectId)}/apartments/${Uri.encodeComponent(apartmentId)}/documents/$kind${id != null ? '/${Uri.encodeComponent(id)}' : ''}';
    final ckey = 'doc:$path';
    final http.Response r;
    try {
      final req = http.Request('GET', _uri(path))..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/pdf, application/json', 'Accept-Language': ApiClient.lang});
      final res = await _http.send(req).timeout(Offline.online.value ? const Duration(seconds: 30) : const Duration(seconds: 8));
      // qabul qilinayotgan baytlar sanaladi — ekranda foiz ko'rinadi
      final total = res.contentLength ?? 0;
      final buf = <int>[];
      onProgress?.call(0, total);
      await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
        buf.addAll(chunk);
        onProgress?.call(buf.length, total);
      }
      r = http.Response.bytes(buf, res.statusCode, headers: res.headers);
    } catch (_) {
      Offline.markOnline(false);
      final c = await Offline.getBytes(ckey);
      if (c != null) return c;
      throw ApiException("Internet yo'q va bu hujjat telefonda saqlanmagan. Avval internet bilan oching yoki \"Sinxronlash\" ekranidan yuklab qo'ying.", code: 'network');
    }
    Offline.markOnline(true);
    if (r.statusCode == 200 && r.bodyBytes.length > 4 && String.fromCharCodes(r.bodyBytes.take(4)) == '%PDF') {
      unawaited(Offline.putBytes(ckey, r.bodyBytes));
      return r.bodyBytes;
    }
    if (r.statusCode == 401) throw ApiException('Kirish muddati tugagan.', status: 401);
    if (r.statusCode == 403) throw ApiException("Bu hujjatni ochishga ruxsat yo'q.");
    if (r.statusCode == 404) throw ApiException('Hujjat topilmadi.');
    throw ApiException("Hujjatni olib bo'lmadi (${r.statusCode}).");
  }

  /// Hujjat telefonda bormi (offline ochish mumkinmi)
  Future<bool> documentCached(String objectId, String apartmentId, String kind, {String? id}) =>
      Offline.hasBytes('doc:/objects/${Uri.encodeComponent(objectId)}/apartments/${Uri.encodeComponent(apartmentId)}/documents/$kind${id != null ? '/${Uri.encodeComponent(id)}' : ''}');

  /// Xarid chekining surati (bayt): bir marta ko'rilgani telefonda saqlanadi
  Future<List<int>?> receiptBytes(int op) async {
    final key = 'rc:$op';
    try {
      final r = await _http.get(_uri('/funds/receipt/$op'), headers: {'Authorization': 'Bearer $apiKey', 'Accept': 'image/*'}).timeout(Offline.online.value ? const Duration(seconds: 60) : const Duration(seconds: 8));
      Offline.markOnline(true);
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        unawaited(Offline.putBytes(key, r.bodyBytes));
        return r.bodyBytes;
      }
      return null;
    } catch (_) {
      Offline.markOnline(false);
      return Offline.getBytes(key);
    }
  }

  /// To'lov usullari (kompaniya sozlamasi): value — serverga yuboriladi, label — ko'rsatiladi
  Future<List<Map<String, dynamic>>> payMethods() async => _list((await _getMap('/sales/pay-methods'))['data']);

  /// To'lov qabul qilish (kassaga o'tadi, chek yaratiladi). Yangilangan kvartirani qaytaradi.
  Future<Map<String, dynamic>> apartmentPay(String objectId, String apartmentId, {required num amount, String? date, String? method}) async {
    return _queueable(
      kind: 'pay',
      method: 'POST',
      path: '/objects/${Uri.encodeComponent(objectId)}/apartments/${Uri.encodeComponent(apartmentId)}/payments',
      body: {'amount': amount, if (date != null) 'date': date, if (method != null && method.isNotEmpty) 'method': method},
      objectId: objectId,
      aptId: apartmentId,
      label: 'Kvartira $apartmentId — to\'lov ${amount.round()}',
    );
  }

  /// Saytdagi 3D / 360° sahifasi uchun 90 soniyalik bir martalik havola. view: '3d' | 'locate'
  Future<String> webLink(String objectId, String view, {String? apartment}) async {
    final b = await _send(() => _http.post(_uri('/web-link'), headers: _headers, body: jsonEncode({'object': objectId, 'view': view, if (apartment != null) 'apartment': apartment})));
    return '${((b as Map)['data'] as Map)['url']}';
  }

  /// Xaridorlar to'lovlari (sana oralig'i YYYY-MM-DD; sahifalanmaydi). meta: total, sum.
  /// Qarzdorlar — server hisoblaydi (sayt bilan bir xil: jadval summasi foiz bilan − to'langan, sotilgan va bron). null — eski server
  Future<({List<Map<String, dynamic>> items, num total, num overdue})?> salesDebtors({String? object}) async {
    try {
      final m = await _getMap('/sales/debtors', {if (object != null) 'object': object});
      final meta = Map<String, dynamic>.from((m['meta'] as Map?) ?? const {});
      return (items: _list(m['data']), total: (meta['total'] as num?) ?? 0, overdue: (meta['overdue'] as num?) ?? 0);
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<({List<Map<String, dynamic>> items, num sum})> salesPayments({String? from, String? to, String? object}) async {
    final m = await _getMap('/sales/payments', {'from': from, 'to': to, 'object': object});
    final meta = (m['meta'] as Map?) ?? const {};
    return (items: _list(m['data']), sum: (meta['sum'] as num?) ?? 0);
  }

  /* ---------------- lidlar ---------------- */

  Future<Paged> leads({int page = 1, int perPage = 30}) async {
    final m = await _getMap('/leads', {'page': page, 'per_page': perPage});
    return Paged(_list(m['data']), PageMeta.from(m['meta']));
  }

  Future<void> leadCreate({String? name, String? phone, String? source, int? rooms, int? budget, String? message}) async {
    final body = <String, dynamic>{
      if (name != null && name.isNotEmpty) 'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (source != null && source.isNotEmpty) 'source': source,
      if (rooms != null) 'rooms': rooms,
      if (budget != null) 'budget': budget,
      if (message != null && message.isNotEmpty) 'message': message,
    };
    await _send(() => _http.post(_uri('/leads'), headers: _headers, body: jsonEncode(body)));
  }

  /* ---------------- kassa ---------------- */

  Future<List<Map<String, dynamic>>> cashDesks() async => _list((await _getMap('/cash/desks'))['data']);

  /// Kassalar + jami (saytdagidek: dollar kurs bo'yicha kompaniya valyutasiga o'tkazilgan bitta summa).
  /// {desks: [...], total: {amount, currency, usd_rate, by_currency}?} — eski serverda total bo'lmaydi.
  Future<Map<String, dynamic>> cashSummary() async {
    final m = await _getMap('/cash/desks');
    return {'desks': _list(m['data']), 'total': m['total'] is Map ? Map<String, dynamic>.from(m['total'] as Map) : null};
  }

  /* ---------------- ish jurnali / fotohisobotlar ---------------- */

  Future<Paged> journal({int page = 1, String? object}) async {
    final m = await _getMap('/journal', {'page': page, 'per_page': 20, 'object': object});
    return Paged(_list(m['data']), PageMeta.from(m['meta']));
  }

  /// Fotohisobot yuborish: obyekt, izoh, suratlar (1..10), qavat
  Future<Map<String, dynamic>> journalAdd({required String object, String? text, int? floor, required List<String> photos, UploadProgress? onProgress}) async {
    final b = await _send(() async {
      final req = ProgressMultipartRequest('POST', _uri('/journal'), onProgress: onProgress)
        ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang})
        ..fields.addAll({'project_id': object, if (text != null && text.trim().isNotEmpty) 'text': text.trim(), if (floor != null) 'floor': '$floor'});
      for (final p in photos) {
        req.files.add(await http.MultipartFile.fromPath('photos[]', p));
      }
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 300)));
    }, timeout: const Duration(seconds: 310));
    return Map<String, dynamic>.from(((b as Map)['data'] as Map?) ?? const {});
  }

  Future<void> journalDelete(int id) async => aSend('DELETE', '/journal/$id');

  /// Jurnal surati (offline'da oldin ko'rilgani)
  Future<List<int>?> journalBytes(int id, int i) async {
    final key = 'jl:$id:$i';
    try {
      final r = await _http.get(_uri('/journal/$id/photo/$i'), headers: {'Authorization': 'Bearer $apiKey', 'Accept': 'image/*'}).timeout(Offline.online.value ? const Duration(seconds: 60) : const Duration(seconds: 8));
      Offline.markOnline(true);
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        unawaited(Offline.putBytes(key, r.bodyBytes));
        return r.bodyBytes;
      }
      return null;
    } catch (_) {
      Offline.markOnline(false);
      return Offline.getBytes(key);
    }
  }

  Future<Paged> cashOps({int page = 1, int? desk}) async {
    final m = await _getMap('/cash/operations', {'page': page, 'per_page': 30, 'desk': desk});
    return Paged(_list(m['data']), PageMeta.from(m['meta']));
  }

  /* ---------------- davomat ---------------- */

  /// Kim ishga keldi: sana (YYYY-MM-DD) va ixtiyoriy obyekt bo'yicha.
  Future<Map<String, dynamic>> attendance({String? date, String? object}) async {
    final m = await _getMap('/attendance', {'date': date, 'object': object});
    return _attendanceWithQueue(Map<String, dynamic>.from((m['data'] as Map?) ?? const {}), date);
  }

  /* ---------------- «Men ishga keldim» (smena) ---------------- */

  Future<Map<String, dynamic>> shift() async => _shiftWithQueue(Map<String, dynamic>.from(((await _getMap('/shift'))['data'] as Map?) ?? const {}));

  /// act: start | end | reopen. Koordinatalar bo'lsa yuboriladi (lokatsiyasiz ham belgilash mumkin).
  Future<Map<String, dynamic>> shiftAct(String act, {double? lat, double? lng, double? acc, bool mocked = false}) async {
    // bosilgan HAQIQIY vaqt yuboriladi: offline'da keyin sinxronlansa ham server shu vaqtni yozadi
    final body = <String, dynamic>{if (lat != null && lng != null) 'lat': lat, if (lat != null && lng != null) 'lng': lng, if (acc != null) 'acc': acc, if (mocked) 'mocked': true, 'at': DateTime.now().toUtc().toIso8601String()};
    final r = await _queueGeneric(kind: 'shift', method: 'POST', path: '/shift/$act', body: body, refId: act, label: 'Smena — ${act == 'start' ? 'ishga keldim' : (act == 'end' ? 'ketdim' : 'qaytdim')}');
    if (!r.queued) return r.data;
    Map<String, dynamic> base = const {};
    try {
      base = Map<String, dynamic>.from(((await _getMap('/shift'))['data'] as Map?) ?? const {});
    } catch (_) {}
    return _shiftWithQueue(base)..['queued'] = true;
  }

  /// Smenaga qo'yish (act='in') yoki smenadan olish (act='out'). Faqat bugun.
  Future<Map<String, dynamic>> attendanceMark(String act, String object, List<String> staffIds, {String? time}) async {
    final body = <String, dynamic>{'object': object, 'staff_ids': staffIds, if (time != null && time.isNotEmpty) 'time': time, 'at': DateTime.now().toUtc().toIso8601String()};
    final r = await _queueGeneric(kind: 'attendance', method: 'POST', path: '/attendance/$act', body: body, objectId: object, refId: act, label: "Davomat — ${act == 'in' ? 'smenaga qo\'yish' : 'smenadan olish'} (${staffIds.length})");
    if (!r.queued) return r.data;
    return {'done': staffIds.length, 'skipped': 0, 'errors': <String>[], 'queued': true};
  }

  /* ---------------- xodimlar (Crew) ---------------- */

  /// Xodimlar va oy bo'yicha hisoblangan / to'langan / qolgan ish haqi. [month] — YYYY-MM.
  Future<Map<String, dynamic>> crew({String? month, String? object}) async {
    final m = await _getMap('/crew', {'month': month, 'object': object});
    return _crewWithQueue(Map<String, dynamic>.from((m['data'] as Map?) ?? const {}));
  }

  /// Yangi xodim qabul qilish. `true` — internet yo'q, navbatga qo'yildi.
  Future<bool> crewHire({required String object, required String name, required String role, String? phone, String pay = 'hour', num rate = 0}) async {
    final r = await _queueGeneric(
      kind: 'crew',
      method: 'POST',
      path: '/crew',
      body: {'object': object, 'name': name, 'role': role, if (phone != null && phone.isNotEmpty) 'phone': phone, 'pay': pay, 'rate': rate},
      objectId: object,
      label: 'Xodim qo\'shish — $name',
    );
    return r.queued;
  }

  /// So'nggi 14 kunlik voqealar lentasi (vazifa, pul, hisobot, lid) — rolga qarab
  Future<List<Map<String, dynamic>>> notifications() async => _list((await _getMap('$scope/notifications'))['data']);

  /* ---------------- prorab puli va chek ---------------- */

  Map<String, String> get authHeaders => {'Authorization': 'Bearer $apiKey', 'Accept': 'image/*'};

  /// Chek suratining manzili (Image.network uchun `authHeaders` bilan)
  String receiptUrl(int op) => _uri('/funds/receipt/$op').toString();

  /// Prorab: o'z balansi, so'rovlari, xarajatlari. Rahbar/buxgalter: barcha prorablar. [status]: pending | norc
  Future<Map<String, dynamic>> funds({int? user, String? status}) async {
    Map<String, dynamic> m;
    try {
      m = await _getMap('/funds', {'user': user, 'status': status});
    } on ApiException catch (e) {
      // internet yo'q va bu filtr saqlanmagan: filtrsiz nusxadan telefonda filtrlaymiz
      final b = e.isNetwork && Offline.enabled && (user != null || status != null) ? await Offline.get(_cacheKey('/funds')) : null;
      if (b == null) rethrow;
      final data = Map<String, dynamic>.from((b['data'] as Map?) ?? const {});
      var ops = _list(data['ops']);
      if (user != null) ops = ops.where((o) => '${(o['holder'] as Map?)?['id']}' == '$user').toList();
      if (status == 'pending') ops = ops.where((o) => o['fund'] == 'spend' && o['status'] == 'pending').toList();
      if (status == 'norc') ops = ops.where((o) => o['fund'] == 'spend' && o['has_receipt'] != true && o['status'] != 'rejected').toList();
      data['ops'] = ops;
      m = {'data': data};
    }
    return _fundsWithQueue(Map<String, dynamic>.from((m['data'] as Map?) ?? const {}));
  }

  /// Pul so'rash; internet yo'q bo'lsa navbatga tushadi. `true` — navbatga qo'yildi.
  Future<bool> fundsRequest({required num amount, required String kind, String? object, String? note}) async {
    final body = <String, dynamic>{'amount': amount, 'kind': kind, if (object != null && object.isNotEmpty) 'project_id': object, if (note != null && note.trim().isNotEmpty) 'note': note.trim()};
    final id = Offline.newId();
    try {
      await sendQueued('POST', '/funds/request', body, id);
      return false;
    } on ApiException catch (e) {
      if (!(e.isNetwork && Offline.enabled)) rethrow;
      await Offline.enqueue(QueuedOp(id: id, kind: 'request', objectId: object ?? '', aptId: '', method: 'POST', path: '/funds/request', body: body, label: "Pul so'rovi — ${amount.round()}", createdAt: DateTime.now().toIso8601String()));
      return true;
    }
  }

  /// Pul bo'limi amali (rahbar: berish/rad etish/tekshirish/qaytarish; prorab: so'rovni qaytarib olish).
  /// Internet yo'q bo'lsa navbatga tushadi: `true` — navbatda. [kind]: f_issue | f_check | f_reject | f_decline | f_cancel; [refId] — so'rov/operatsiya raqami.
  Future<bool> fundsAct(String kind, String path, Map<String, dynamic> body, {required String label, String refId = ''}) async {
    final r = await _queueGeneric(kind: kind, method: 'POST', path: path, body: body, label: label, refId: refId);
    return r.queued;
  }

  /// Yuborilmagan rahbar amallarining natijasi ekranda darhol ko'rinadi (so'rov yopiladi, balans o'zgaradi, hisobot belgilanadi)
  Map<String, dynamic> _fundsWithQueue(Map<String, dynamic> d) {
    final q = Offline.ops.where((o) => o.kind.startsWith('f_') && o.state == 'pending').toList();
    if (q.isEmpty) return d;
    final out = Map<String, dynamic>.from(d);
    var reqs = _list(d['requests']);
    final ops = _list(d['ops']);
    final holders = _list(d['holders']);
    num n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);
    for (final o in q) {
      final b = o.body;
      switch (o.kind) {
        case 'f_decline':
        case 'f_cancel':
          reqs = reqs.where((r) => '${r['id']}' != o.aptId).toList();
        case 'f_issue':
          reqs = reqs.where((r) => !('${r['user_id']}' == '${b['user_id']}' && r['status'] == 'new')).toList();
          for (final h in holders) {
            if ('${h['user_id']}' != '${b['user_id']}') continue;
            final k = '${b['kind']}' == 'card' ? 'card' : 'cash';
            h[k] = n(h[k]) + n(b['amount']);
            h['total'] = n(h['total']) + n(b['amount']);
            h['pending'] = true;
          }
          out['total'] = n(d['total']) + n(b['amount']);
        case 'f_check':
          for (final x in ops) {
            if ('${x['id']}' == o.aptId && x['status'] != 'rejected') {
              x['status'] = b['checked'] == true ? 'checked' : 'pending';
              x['pending'] = true;
            }
          }
        case 'f_reject':
          for (final x in ops) {
            if ('${x['id']}' == o.aptId) {
              x['status'] = 'rejected';
              x['reject_reason'] = b['reason'];
              x['pending'] = true;
            }
          }
      }
    }
    out['requests'] = reqs;
    out['ops'] = ops;
    out['holders'] = holders;
    return out;
  }

  /// Xarid hisoboti (chek surati bilan). [lines] — omborga kiradigan materiallar: {name, qty, unit, price}
  Future<Map<String, dynamic>> fundsSpend({
    required String kind,
    required String object,
    required String date,
    String? what,
    String? vendor,
    String? note,
    num? amount,
    int? warehouse,
    List<Map<String, dynamic>> lines = const [],
    String? receiptPath,
    bool noReceipt = false,
    String? currency,
    num? estimate,
    UploadProgress? onProgress,
    String? receiptUpload,
    List<String> photoUploads = const [], // mahsulot suratlari (oldindan yuklangan)
  }) async {
    final fields = <String, String>{
      'kind': kind,
      if (currency != null && currency.isNotEmpty) 'currency': currency,
      'project_id': object,
      'date': date,
      if (what != null && what.trim().isNotEmpty) 'what': what.trim(),
      if (vendor != null && vendor.trim().isNotEmpty) 'vendor': vendor.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (amount != null && amount > 0) 'amount': '$amount',
      if (warehouse != null && lines.isNotEmpty) 'warehouse_id': '$warehouse',
      if (noReceipt) 'no_receipt': '1',
    };
    for (var i = 0; i < photoUploads.length; i++) {
      fields['photo_uploads[$i]'] = photoUploads[i];
    }
    for (var i = 0; i < lines.length; i++) {
      lines[i].forEach((k, v) {
        if (v != null && '$v'.isNotEmpty) fields['lines[$i][$k]'] = '$v';
      });
    }
    final id = Offline.newId();
    try {
      // chek oldindan yuklangan bo'lsa — faylni qayta yubormaymiz (hisobot bir zumda ketadi)
      final b = receiptUpload != null
          ? await _postSpend({...fields, 'receipt_upload': receiptUpload}, null, id, onProgress: onProgress)
          : await _postSpend(fields, receiptPath, id, onProgress: onProgress);
      return Map<String, dynamic>.from(((b as Map)['data'] as Map?) ?? const {});
    } on ApiException catch (e) {
      if (!(e.isNetwork && Offline.enabled)) rethrow;
      // internet yo'q: maydonlar va chek surati telefonda saqlanadi, internet qaytganda avtomatik yuboriladi
      final saved = noReceipt ? null : await Offline.stashFile(receiptPath);
      await Offline.enqueue(QueuedOp(
        id: id,
        kind: 'spend',
        objectId: object,
        aptId: '',
        method: 'POST',
        path: '/funds/spend',
        body: Map<String, dynamic>.from(fields),
        label: 'Xarid hisoboti — ${(what ?? '').trim().isEmpty ? (lines.isNotEmpty ? '${lines.first['name']}' : 'xarid') : what!.trim()}',
        createdAt: DateTime.now().toIso8601String(),
        file: saved,
        amount: estimate ?? 0,
      ));
      return {'queued': true, 'op': id};
    }
  }

  /// Valyutalar: barcha valyuta, kurs, qaysilari yoqilgan; can_manage — faqat rahbar
  Future<Map<String, dynamic>> currencies() async {
    final d = Map<String, dynamic>.from(((await _getMap('/currencies'))['data'] as Map?) ?? const {});
    final q = Offline.ops.where((o) => o.kind == 'f_cur' && o.state == 'pending').toList();
    if (q.isEmpty) return d;
    final codes = ((q.last.body['codes'] as List?) ?? const []).map((e) => '$e').toSet();
    final items = _list(d['items']);
    for (final i in items) {
      if (i['base'] != true) i['enabled'] = codes.contains('${i['code']}');
    }
    d['items'] = items;
    return d;
  }

  /// Rahbar qo'shimcha valyutalarni yoqadi (USD va kompaniya valyutasi doim mavjud)
  Future<bool> currenciesSave(List<String> codes) async {
    final r = await _queueGeneric(kind: 'f_cur', method: 'POST', path: '/currencies', body: {'codes': codes}, label: 'Valyutalar — ${codes.isEmpty ? 'qo\'shimcha yo\'q' : codes.join(', ')}');
    return r.queued;
  }

  /// Chek suratini oldindan yuklaydi (rasm tanlanishi bilan). Qaytadi: yuklama raqami — keyin [fundsSpend] ga `receiptUpload` bilan beriladi.
  Future<String> fundsReceiptUpload(String path, {UploadProgress? onProgress}) async {
    final b = await _send(() async {
      final req = ProgressMultipartRequest('POST', _uri('/funds/receipt-upload'), onProgress: onProgress)
        ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang});
      req.files.add(await http.MultipartFile.fromPath('receipt', path));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 150)));
    }, timeout: const Duration(seconds: 160));
    return '${((b as Map)['data'] as Map)['upload']}';
  }

  /// Mahsulot suratlarini keyinroq qo'shish (hisobot tekshirilmaguncha). Qaytadi: jami suratlar soni
  Future<int> fundsAddPhotos(int op, List<String> paths, {UploadProgress? onProgress}) async {
    final b = await _send(() async {
      final req = ProgressMultipartRequest('POST', _uri('/funds/$op/photos'), onProgress: onProgress)
        ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang});
      for (final p in paths) {
        req.files.add(await http.MultipartFile.fromPath('photos[]', p));
      }
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 240)));
    }, timeout: const Duration(seconds: 250));
    return ((((b as Map)['data'] as Map?)?['photos']) as num?)?.toInt() ?? 0;
  }

  /// Mahsulot surati (i — tartib raqami); offline'da oldin ko'rilgani
  Future<List<int>?> goodsBytes(int op, int i) async {
    final key = 'gd:$op:$i';
    try {
      final r = await _http.get(_uri('/funds/photo/$op/$i'), headers: {'Authorization': 'Bearer $apiKey', 'Accept': 'image/*'}).timeout(Offline.online.value ? const Duration(seconds: 60) : const Duration(seconds: 8));
      Offline.markOnline(true);
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        unawaited(Offline.putBytes(key, r.bodyBytes));
        return r.bodyBytes;
      }
      return null;
    } catch (_) {
      Offline.markOnline(false);
      return Offline.getBytes(key);
    }
  }

  /// Keyinroq chek qo'shish
  Future<void> fundsAddReceipt(int op, String path, {UploadProgress? onProgress}) async {
    await _send(() async {
      final req = ProgressMultipartRequest('POST', _uri('/funds/$op/receipt'), onProgress: onProgress)
        ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang});
      req.files.add(await http.MultipartFile.fromPath('receipt', path));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 150)));
    }, timeout: const Duration(seconds: 160));
  }

  /* ---------------- hisobotlar ---------------- */

  /// Hisobotini ko'rish mumkin bo'lgan prorablar va sotuvchilar.
  Future<Map<String, dynamic>> reportPeople() async => Map<String, dynamic>.from(((await _getMap('/reports/people'))['data'] as Map?) ?? const {});

  /// Prorab hisoboti: pul, xaridlar, yoqilg'i, ish haqi, ish hajmi, ombordan sarf. Sana: YYYY-MM-DD.
  Future<Map<String, dynamic>> reportForeman({int? user, required String from, required String to}) async =>
      Map<String, dynamic>.from(((await _getMap('/reports/foreman', {'user': user, 'from': from, 'to': to}))['data'] as Map?) ?? const {});

  /// Sotuvchi hisoboti: sotuv, bron, to'lovlar, muddati o'tgan qarzlar, smena.
  Future<Map<String, dynamic>> reportSales({int? user, required String from, required String to}) async =>
      Map<String, dynamic>.from(((await _getMap('/reports/sales', {'user': user, 'from': from, 'to': to}))['data'] as Map?) ?? const {});

  /// Prorab — o'z hisobotini direktor va buxgalterga topshiradi; buxgalter — tanlangan prorab hisobotini direktorga yuboradi ([user]).
  /// Javob: {message, sent_at?, telegram}
  Future<Map<String, dynamic>> reportForemanSend({int? user, required String from, required String to, required String idemKey}) async {
    final b = await _send(() => _http.post(_uri('/reports/foreman/send'), headers: {..._headers, 'Idempotency-Key': idemKey}, body: jsonEncode({'from': from, 'to': to, if (user != null) 'user': user})), timeout: const Duration(seconds: 90));
    return Map<String, dynamic>.from(((b as Map?)?['data'] as Map?) ?? const {});
  }

  /// Sotuvchi kunlik hisobotini topshiradi. Javob: {message, submitted}
  Future<Map<String, dynamic>> reportSalesSubmit({required String date, String? note, required String idemKey}) async {
    final b = await _send(() => _http.post(_uri('/reports/sales/submit'), headers: {..._headers, 'Idempotency-Key': idemKey}, body: jsonEncode({'date': date, if (note != null && note.isNotEmpty) 'note': note})), timeout: const Duration(seconds: 90));
    return Map<String, dynamic>.from(((b as Map?)?['data'] as Map?) ?? const {});
  }

  /* ---------------- ombor ---------------- */

  Future<Paged> stockItems({int page = 1, String? q, bool low = false}) async {
    try {
      final m = await _getMap('/stock/items', {'page': page, 'per_page': 40, 'q': q, 'low': low ? 1 : null});
      return Paged(_list(m['data']), PageMeta.from(m['meta']));
    } on ApiException catch (e) {
      final all = e.isNetwork && Offline.enabled ? await _cachedAll('/stock/items', {'per_page': 40}) : null;
      if (all == null) rethrow;
      final t = (q ?? '').trim().toLowerCase();
      final rows = all.where((i) => (!low || i['low'] == true) && (t.isEmpty || '${i['name']} ${i['sku'] ?? ''} ${i['group'] ?? ''}'.toLowerCase().contains(t))).toList();
      return _localPaged(rows, page, 40);
    }
  }

  Future<List<Map<String, dynamic>>> stockWarehouses() async => _list((await _getMap('/stock/warehouses'))['data']);

  /// Ombordan sarflash (saytdagi «Ombordan sarfladim»): prorab — faqat o'z obyekti omboridan.
  /// Internet yo'q bo'lsa — navbatga qo'yiladi (true qaytadi), internet chiqqanda o'zi yuboriladi.
  Future<bool> stockUse({required int item, required int warehouse, required num qty, String? object, String? note, String? date, required String label}) async {
    final r = await _queueGeneric(
      kind: 'stock_use',
      method: 'POST',
      path: '/stock/use',
      label: label,
      objectId: object ?? '',
      body: {
        'item_id': item, 'warehouse_id': warehouse, 'qty': qty,
        if (object != null && object.isNotEmpty) 'object': object,
        if (note != null && note.isNotEmpty) 'note': note,
        if (date != null) 'date': date,
      },
    );
    return r.queued;
  }

  /* ---------------- vazifalar ---------------- */

  Future<Paged> tasks({int page = 1, String? status, int? assignee}) async {
    Map<String, dynamic> m;
    try {
      m = await _getMap('/tasks', {'page': page, 'per_page': 40, 'status': status, 'assignee': assignee});
    } on ApiException catch (e) {
      final all = e.isNetwork && Offline.enabled && (status != null || assignee != null) ? await _cachedAll('/tasks', {'per_page': 40}) : null;
      if (all == null) rethrow;
      final rows = all.where((t) => (status == null || '${t['status']}' == status) && (assignee == null || '${(t['assignee'] as Map?)?['id']}' == '$assignee')).toList();
      final pg = _localPaged(rows, page, 40);
      m = {'data': pg.items, 'meta': {'page': pg.meta.page, 'last_page': pg.meta.lastPage, 'total': pg.meta.total, 'per_page': 40}};
    }
    final items = _list(m['data']);
    // yuborilmagan holat/progress o'zgarishlari ro'yxatda darhol ko'rinadi
    for (final o in Offline.ops.where((o) => o.kind == 'task' && o.state == 'pending')) {
      for (final t in items) {
        if ('${t['id']}' != o.aptId) continue;
        if (o.body['status'] != null) t['status'] = o.body['status'];
        if (o.body['progress'] != null) t['progress'] = o.body['progress'];
        t['pending'] = true;
      }
    }
    return Paged(items, PageMeta.from(m['meta']));
  }

  /// Vazifani yangilash: faqat berilgan maydonlar o'zgaradi (holat, progress 0–100, muddat YYYY-MM-DD, ijrochi, muhimlik).
  Future<bool> taskUpdate(int id, {String? status, int? progress, String? dueDate, int? assigneeId, String? priority}) async {
    final body = <String, dynamic>{
      if (status != null) 'status': status,
      if (progress != null) 'progress': progress,
      if (dueDate != null) 'due_date': dueDate,
      if (assigneeId != null) 'assignee_id': assigneeId,
      if (priority != null) 'priority': priority,
    };
    final r = await _queueGeneric(kind: 'task', method: 'PATCH', path: '/tasks/$id', body: body, refId: '$id', label: 'Vazifa #$id — ${status != null ? taskStatusLabel(status) : 'progress ${progress ?? ''}%'}');
    return r.queued;
  }

  /// Yangi vazifa (ijrochi Telegram orqali xabar oladi).
  Future<bool> taskCreate({required String title, String? description, String? objectId, int? assigneeId, String? dueDate, String priority = 'normal'}) async {
    final body = <String, dynamic>{
      'title': title,
      if (description != null && description.isNotEmpty) 'description': description,
      if (objectId != null && objectId.isNotEmpty) 'object_id': objectId,
      if (assigneeId != null) 'assignee_id': assigneeId,
      if (dueDate != null && dueDate.isNotEmpty) 'due_date': dueDate,
      'priority': priority,
    };
    final r = await _queueGeneric(kind: 'taskNew', method: 'POST', path: '/tasks', body: body, label: 'Yangi vazifa — $title');
    return r.queued;
  }

  /// Kompaniya xodimlari (ijrochi tanlash uchun): id, name, role_name.
  Future<List<Map<String, dynamic>>> users() async => _list((await _getMap('/users'))['data']);

  /* ---------------- ombor (harakatlar) ---------------- */

  /// Ombor harakatlari: type = in | out | transfer | adjust.
  Future<Paged> stockMoves({int page = 1, String? type}) async {
    try {
      final m = await _getMap('/stock/moves', {'page': page, 'per_page': 40, 'type': type});
      return Paged(_list(m['data']), PageMeta.from(m['meta']));
    } on ApiException catch (e) {
      final all = e.isNetwork && Offline.enabled && type != null ? await _cachedAll('/stock/moves', {'per_page': 40}) : null;
      if (all == null) rethrow;
      return _localPaged(all.where((x) => '${x['type']}' == type).toList(), page, 40);
    }
  }

  /* ---------------- kontragentlar va to'lov so'rovlari ---------------- */

  Future<Paged> counterparties({int page = 1, String q = '', String? kind}) async {
    final m = await _getMap('/counterparties', {'page': page, 'per_page': 30, 'q': q.isEmpty ? null : q, 'kind': kind});
    return Paged(_list(m['data']), PageMeta.from(m['meta']));
  }

  Future<void> counterpartyCreate(Map<String, dynamic> body) async {
    await _send(() => _http.post(_uri('/counterparties'), headers: _headers, body: jsonEncode(body)));
  }

  Future<Paged> paymentRequests({int page = 1, String? status}) async {
    final m = await _getMap('/payment-requests', {'page': page, 'per_page': 30, 'status': status});
    return Paged(_list(m['data']), PageMeta.from(m['meta']));
  }

  /* ---------------- oylik berish ---------------- */

  /// Buxgalter/kassir/admin uchun: oylik to'lanadigan kassalar (obyekt kassasi, keyin umumiy)
  Future<List<Map<String, dynamic>>> crewDesks(String object) async {
    final m = await _getMap('/crew/desks', {'object': object});
    return _list((m['data'] as Map?)?['desks']);
  }

  /// Oylik to'lash (faqat internet bilan: pul harakati). Prorab — [kind] (cash|card), boshqalar — [deskId].
  /// Maosh to'lash. `true` — internet yo'q, navbatga qo'yildi: internet chiqqanda o'zi yuboriladi
  /// (to'lov kuni — bosilgan kun; server pulni yetarliligini o'shanda tekshiradi, yetmasa «Sinxronlash» da ko'rinadi).
  Future<bool> crewPay({required String object, required String staffId, required String month, required num amount, String? kind, int? deskId, String? note, String? workerName, required String idemKey}) async {
    final n = DateTime.now();
    final body = <String, dynamic>{
      'object': object, 'staff_id': staffId, 'month': month, 'amount': amount,
      'date': '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}',
      if (kind != null) 'kind': kind, if (deskId != null) 'desk_id': deskId, if (note != null && note.isNotEmpty) 'note': note,
    };
    final r = await _queueGeneric(kind: 'crew_pay', method: 'POST', path: '/crew/pay', body: body, objectId: object, refId: staffId, idem: idemKey,
        label: "Maosh to'lovi — ${workerName ?? staffId}: $amount");
    return r.queued;
  }

  /// Xodimlar ro'yxatiga yuborilmagan (navbatdagi) maosh to'lovlarini qo'shadi: «To'langan» / «Qoldi» darhol to'g'ri ko'rinadi
  Map<String, dynamic> _crewWithQueue(Map<String, dynamic> d) {
    final month = '${d['month'] ?? ''}';
    final pend = Offline.ops.where((o) => o.kind == 'crew_pay' && o.state == 'pending' && '${o.body['month']}' == month).toList();
    if (pend.isEmpty) return d;
    num paidAll = 0;
    final objs = ((d['objects'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    for (final ob in objs) {
      num paidObj = 0;
      final workers = ((ob['workers'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      for (final w in workers) {
        final mine = pend.where((o) => o.objectId == '${ob['id']}' && o.aptId == '${w['id']}');
        if (mine.isEmpty) continue;
        final add = mine.fold<num>(0, (a, o) => a + ((o.body['amount'] as num?) ?? 0));
        final m = Map<String, dynamic>.from((w['month'] as Map?) ?? const {});
        m['paid'] = ((m['paid'] as num?) ?? 0) + add;
        m['due'] = ((m['due'] as num?) ?? 0) - add;
        w['month'] = m;
        w['pending'] = true;
        paidObj += add;
      }
      ob['workers'] = workers;
      if (paidObj != 0 && ob['summary'] is Map) {
        final sm = Map<String, dynamic>.from(ob['summary'] as Map);
        sm['paid'] = ((sm['paid'] as num?) ?? 0) + paidObj;
        sm['due'] = ((sm['due'] as num?) ?? 0) - paidObj;
        ob['summary'] = sm;
      }
      paidAll += paidObj;
    }
    final sum = Map<String, dynamic>.from((d['summary'] as Map?) ?? const {});
    if (paidAll != 0) {
      sum['paid'] = ((sum['paid'] as num?) ?? 0) + paidAll;
      sum['due'] = ((sum['due'] as num?) ?? 0) - paidAll;
    }
    return {...d, 'objects': objs, 'summary': sum};
  }

  /* ---------------- profil: rasm, parol, faol seanslar ---------------- */

  Future<Map<String, dynamic>> profile() async => Map<String, dynamic>.from(((await _getMap('/profile'))['data'] as Map?) ?? const {});

  /// Rasm yuklash (galereya/kamera); qaytadi: yangi rasm manzili
  Future<String?> profilePhotoUpload(String path, {UploadProgress? onProgress}) async {
    final b = await _send(() async {
      final req = ProgressMultipartRequest('POST', _uri('/profile/photo'), onProgress: onProgress)..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang});
      req.files.add(await http.MultipartFile.fromPath('avatar', path));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 90)));
    }, timeout: const Duration(seconds: 100));
    return ((b as Map)['data'] as Map)['photo_url'] as String?;
  }

  Future<void> profilePhotoDelete() async {
    await _send(() => _http.delete(_uri('/profile/photo'), headers: _headers));
  }

  Future<void> profilePassword(String current, String password, String confirm) async {
    await _send(() => _http.post(_uri('/profile/password'), headers: _headers, body: jsonEncode({'current': current, 'password': password, 'password_confirmation': confirm})));
  }

  Future<List<Map<String, dynamic>>> profileSessions() async => _list((await _getMap('/profile/sessions'))['data']);

  Future<void> profileSessionRevoke(String id) async {
    await _send(() => _http.delete(_uri('/profile/sessions/$id'), headers: _headers));
  }

  Future<int> profileRevokeOthers() async {
    final b = await _send(() => _http.post(_uri('/profile/sessions/revoke-others'), headers: _headers, body: '{}'));
    return (((b as Map)['data'] as Map)['revoked'] as num?)?.toInt() ?? 0;
  }

  /* ---------------- AI yordamchi ---------------- */

  /// [conv] — suhbat identifikatori; bo'sh bo'lsa yangi (bo'sh) suhbat va tayyor savollar qaytadi
  Future<Map<String, dynamic>> aiState({String? conv}) async => Map<String, dynamic>.from(((await _getMap('/ai/chat', {'conv': conv}))['data'] as Map?) ?? const {});

  /// Suhbatlar tarixi: [{id, title, count, at}]
  Future<List<Map<String, dynamic>>> aiChats() async => _list((await _getMap('/ai/chats'))['data']);

  /// Savol — fon rejimida: server darhol qabul qiladi va javobni o'zi yozadi (chatdan, ilovadan chiqilsa ham to'xtamaydi);
  /// javob [aiMsg] bilan olinadi. text != null — javob shu zahoti tayyor (eski server).
  Future<({int? id, String? text, bool confirm, String? line})> aiSend(String text, String conv) async {
    final b = await _send(() => _http.post(_uri('/ai/chat'), headers: _headers, body: jsonEncode({'text': text, 'conv': conv, 'async': true})), timeout: const Duration(seconds: 150));
    final d = (b as Map)['data'] as Map;
    final ready = d['status'] != 'streaming' && d['text'] != null;
    return (
      id: (d['id'] as num?)?.toInt(),
      text: ready ? '${d['text']}' : null,
      confirm: d['confirm'] == true,
      line: d['limit_line'] == null ? null : '${d['limit_line']}',
    );
  }

  /// SI javobi holati: status streaming|done|error, text, confirm (pulga oid amal tasdiq kutyapti)
  Future<Map<String, dynamic>> aiMsg(int id) async {
    final b = await _send(() => _http.get(_uri('/ai/msg/$id'), headers: _headers), timeout: const Duration(seconds: 20));
    return Map<String, dynamic>.from(((b as Map)['data'] as Map?) ?? const {});
  }

  /// SI taklif qilgan amalni tasdiqlash (yes) yoki bekor qilish — natija matni qaytadi
  Future<String> aiAction(int id, bool yes) async {
    final d = await aSend('POST', '/ai/action/$id', {'yes': yes});
    return d is Map ? '${d['text'] ?? ''}' : '';
  }

  Future<void> aiClear(String conv) async {
    await _send(() => _http.delete(_uri('/ai/chat', {'conv': conv}), headers: _headers));
  }

  /// Ovoz yozuvi (wav) → matn
  Future<String> aiListen(String path) async {
    final b = await _send(() async {
      final req = http.MultipartRequest('POST', _uri('/ai/listen'))
        ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang});
      req.files.add(await http.MultipartFile.fromPath('audio', path));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 55)));
    }, timeout: const Duration(seconds: 60)); // server o'zi 40 soniyada javob beradi yoki xato qaytaradi
    return '${((b as Map)['data'] as Map)['text']}';
  }

  void close() => _http.close();
}

class PageMeta {
  const PageMeta({this.page = 1, this.lastPage = 1, this.total = 0});

  factory PageMeta.from(dynamic m) {
    if (m is! Map) return const PageMeta();
    return PageMeta(
      page: (m['page'] as num?)?.toInt() ?? 1,
      lastPage: (m['last_page'] as num?)?.toInt() ?? 1,
      total: (m['total'] as num?)?.toInt() ?? 0,
    );
  }

  final int page;
  final int lastPage;
  final int total;

  bool get hasMore => page < lastPage;
}

class Paged {
  const Paged(this.items, this.meta);
  final List<Map<String, dynamic>> items;
  final PageMeta meta;
}

class Me {
  Me({required this.company, required this.currency, required this.keyName, required this.roleName, required this.readOnly, required this.scopes, this.role = ''});

  factory Me.fromJson(Map j) {
    final c = (j['company'] as Map?) ?? const {};
    final k = (j['key'] as Map?) ?? const {};
    return Me(
      company: '${c['name'] ?? ''}',
      currency: '${c['currency'] ?? ''}',
      keyName: '${k['name'] ?? ''}',
      roleName: '${k['role_name'] ?? k['role'] ?? ''}',
      role: '${k['role'] ?? ''}',
      readOnly: k['read_only'] == true,
      scopes: ((k['scopes'] as List?) ?? const []).map((e) => '$e').toSet(),
    );
  }

  final String company;
  final String currency;
  final String keyName;
  final String roleName;
  final String role; // kalit roli: admin, foreman, accountant …
  final bool readOnly;
  final Set<String> scopes;

  bool can(String scope) => scopes.contains(scope);
}

/// Muvaffaqiyatli kirish natijasi.
class StaffLogin {
  StaffLogin({required this.token, required this.serverUrl, required this.userId, required this.userName, required this.roleName, required this.companyName, required this.companySlug});

  factory StaffLogin.fromJson(Map<String, dynamic> j, String serverUrl) {
    final u = (j['user'] as Map?) ?? const {};
    final c = (j['company'] as Map?) ?? const {};
    return StaffLogin(
      token: '${j['token']}',
      serverUrl: serverUrl,
      userId: (u['id'] as num?)?.toInt() ?? 0,
      userName: '${u['name'] ?? ''}',
      roleName: '${u['role_name'] ?? u['role'] ?? ''}',
      companyName: '${c['name'] ?? ''}',
      companySlug: '${c['slug'] ?? ''}',
    );
  }

  final String token;
  final String serverUrl;
  final int userId;
  final String userName;
  final String roleName;
  final String companyName;
  final String companySlug;
}

String taskStatusLabel(String s) => switch (s) {
      'todo' => 'qilish kerak',
      'doing' => 'jarayonda',
      'review' => 'tekshiruvda',
      'done' => 'bajarildi',
      _ => s,
    };
