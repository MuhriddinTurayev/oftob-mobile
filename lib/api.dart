import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'offline.dart';

/// Server xatosi: matni foydalanuvchiga ko'rsatiladi.
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
  /// Server matnlari tili: uz | ru | tg (ilova tili o'zgarganda L.set yangilaydi)
  static String lang = 'uz';

  ApiClient({required String serverUrl, required this.apiKey, http.Client? client})
      : base = normalizeUrl(serverUrl),
        _http = client ?? http.Client();

  final String base; // masalan https://oftob.37-60-247-120.sslip.io
  final String apiKey;
  final http.Client _http;

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

  Future<dynamic> _send(Future<http.Response> Function() call, {Duration timeout = const Duration(seconds: 25)}) async {
    final http.Response r;
    try {
      r = await call().timeout(timeout);
    } on TimeoutException {
      Offline.markOnline(false);
      throw ApiException('Server javob bermadi. Internet va manzilni tekshiring.', code: 'network');
    } on FormatException {
      throw ApiException('Server manzili noto\'g\'ri.');
    } catch (e) {
      Offline.markOnline(false);
      throw ApiException('Serverga ulanib bo\'lmadi. Internet va manzilni tekshiring.', code: 'network');
    }
    Offline.markOnline(true); // server javob berdi (xato bo'lsa ham) — internet bor
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;

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
        msg = 'Kompaniya tarifi faol emas.';
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
  Future<Map<String, dynamic>> _getMap(String path, [Map<String, dynamic>? q]) async {
    final uri = _uri(path, q);
    final qs = (uri.queryParameters.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join('&');
    final key = '${uri.path.replaceFirst('/api/v1', '')}?$qs';
    try {
      final b = await _send(() => _http.get(uri, headers: _headers), timeout: Offline.online.value ? const Duration(seconds: 25) : const Duration(seconds: 6));
      final m = b is Map ? Map<String, dynamic>.from(b) : <String, dynamic>{};
      if (Offline.enabled) unawaited(Offline.put(key, m));
      return m;
    } on ApiException catch (e) {
      if (e.isNetwork && Offline.enabled) {
        final c = await Offline.get(key);
        if (c != null) return c;
      }
      rethrow;
    }
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
  Future<({bool queued, Map<String, dynamic> data})> _queueGeneric({required String kind, required String method, required String path, required Map<String, dynamic> body, required String label, String objectId = '', String refId = ''}) async {
    final id = Offline.newId();
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

  Future<dynamic> _postSpend(Map<String, String> fields, String? receiptPath, String idemKey) {
    return _send(() async {
      final req = http.MultipartRequest('POST', _uri('/funds/spend'))
        ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang, 'Idempotency-Key': idemKey})
        ..fields.addAll(fields);
      if (receiptPath != null && await File(receiptPath).exists()) req.files.add(await http.MultipartFile.fromPath('receipt', receiptPath));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 90)));
    }, timeout: const Duration(seconds: 100));
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
  Future<Me> me() async => Me.fromJson((await _getMap('/me'))['data'] as Map);

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
  Future<Map<String, dynamic>> apartmentUpdate(String objectId, String apartmentId, Map<String, dynamic> body) async {
    return _queueable(kind: 'update', method: 'PATCH', path: '/objects/${Uri.encodeComponent(objectId)}/apartments/${Uri.encodeComponent(apartmentId)}', body: body, objectId: objectId, aptId: apartmentId, label: 'Kvartira $apartmentId — o\'zgartirish');
  }

  /// Muddatli to'lov stavkalari, bron sharti (zadatok, kun), stavka/narxni kim o'zgartira olishi
  Future<Map<String, dynamic>> salesTerms() async => Map<String, dynamic>.from(((await _getMap('/sales/terms'))['data'] as Map?) ?? const {});

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
  Future<List<int>> downloadDocument(String objectId, String apartmentId, String kind, {String? id}) async {
    final path = '/objects/${Uri.encodeComponent(objectId)}/apartments/${Uri.encodeComponent(apartmentId)}/documents/$kind${id != null ? '/${Uri.encodeComponent(id)}' : ''}';
    final ckey = 'doc:$path';
    final http.Response r;
    try {
      r = await _http.get(_uri(path), headers: {'Authorization': 'Bearer $apiKey', 'Accept': 'application/pdf, application/json', 'Accept-Language': ApiClient.lang}).timeout(Offline.online.value ? const Duration(seconds: 90) : const Duration(seconds: 8));
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
  Future<Map<String, dynamic>> shiftAct(String act, {double? lat, double? lng, double? acc}) async {
    // bosilgan HAQIQIY vaqt yuboriladi: offline'da keyin sinxronlansa ham server shu vaqtni yozadi
    final body = <String, dynamic>{if (lat != null && lng != null) 'lat': lat, if (lat != null && lng != null) 'lng': lng, if (acc != null) 'acc': acc, 'at': DateTime.now().toUtc().toIso8601String()};
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
    return Map<String, dynamic>.from((m['data'] as Map?) ?? const {});
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
  Future<List<Map<String, dynamic>>> notifications() async => _list((await _getMap('/notifications'))['data']);

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
    for (var i = 0; i < lines.length; i++) {
      lines[i].forEach((k, v) {
        if (v != null && '$v'.isNotEmpty) fields['lines[$i][$k]'] = '$v';
      });
    }
    final id = Offline.newId();
    try {
      final b = await _postSpend(fields, receiptPath, id);
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
      if (i['base'] != true && i['code'] != 'USD') i['enabled'] = codes.contains('${i['code']}');
    }
    d['items'] = items;
    return d;
  }

  /// Rahbar qo'shimcha valyutalarni yoqadi (USD va kompaniya valyutasi doim mavjud)
  Future<bool> currenciesSave(List<String> codes) async {
    final r = await _queueGeneric(kind: 'f_cur', method: 'POST', path: '/currencies', body: {'codes': codes}, label: 'Valyutalar — ${codes.isEmpty ? 'qo\'shimcha yo\'q' : codes.join(', ')}');
    return r.queued;
  }

  /// Keyinroq chek qo'shish
  Future<void> fundsAddReceipt(int op, String path) async {
    await _send(() async {
      final req = http.MultipartRequest('POST', _uri('/funds/$op/receipt'))
        ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang});
      req.files.add(await http.MultipartFile.fromPath('receipt', path));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 90)));
    });
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
  Future<void> crewPay({required String object, required String staffId, required String month, required num amount, String? kind, int? deskId, String? note, required String idemKey}) async {
    final body = <String, dynamic>{'object': object, 'staff_id': staffId, 'month': month, 'amount': amount, if (kind != null) 'kind': kind, if (deskId != null) 'desk_id': deskId, if (note != null && note.isNotEmpty) 'note': note};
    await _send(() => _http.post(_uri('/crew/pay'), headers: {..._headers, 'Idempotency-Key': idemKey}, body: jsonEncode(body)));
  }

  /* ---------------- profil: rasm, parol, faol seanslar ---------------- */

  Future<Map<String, dynamic>> profile() async => Map<String, dynamic>.from(((await _getMap('/profile'))['data'] as Map?) ?? const {});

  /// Rasm yuklash (galereya/kamera); qaytadi: yangi rasm manzili
  Future<String?> profilePhotoUpload(String path) async {
    final b = await _send(() async {
      final req = http.MultipartRequest('POST', _uri('/profile/photo'))..headers.addAll({'Authorization': 'Bearer $apiKey', 'Accept': 'application/json', 'Accept-Language': ApiClient.lang});
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

  /// Savolga javob (server tugatguncha kutadi: odatda 3–20 soniya)
  Future<({String text, String? line})> aiSend(String text, String conv) async {
    final b = await _send(() => _http.post(_uri('/ai/chat'), headers: _headers, body: jsonEncode({'text': text, 'conv': conv})), timeout: const Duration(seconds: 150));
    final d = (b as Map)['data'] as Map;
    return (text: '${d['text']}', line: d['limit_line'] == null ? null : '${d['limit_line']}');
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
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 90)));
    }, timeout: const Duration(seconds: 100));
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
