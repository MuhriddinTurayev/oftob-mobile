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

  /// Shartnoma (kind='contract') yoki to'lov cheki (kind='receipt', id=to'lov raqami) PDF baytlari
  Future<List<int>> downloadDocument(String objectId, String apartmentId, String kind, {String? id}) async {
    final path = '/objects/${Uri.encodeComponent(objectId)}/apartments/${Uri.encodeComponent(apartmentId)}/documents/$kind${id != null ? '/${Uri.encodeComponent(id)}' : ''}';
    final http.Response r;
    try {
      r = await _http.get(_uri(path), headers: {'Authorization': 'Bearer $apiKey', 'Accept': 'application/pdf, application/json', 'Accept-Language': ApiClient.lang}).timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw ApiException('Server javob bermadi. Internetni tekshiring.');
    } catch (_) {
      throw ApiException("Serverga ulanib bo'lmadi. Internetni tekshiring.");
    }
    if (r.statusCode == 200 && r.bodyBytes.length > 4 && String.fromCharCodes(r.bodyBytes.take(4)) == '%PDF') return r.bodyBytes;
    if (r.statusCode == 401) throw ApiException('Kirish muddati tugagan.', status: 401);
    if (r.statusCode == 403) throw ApiException("Bu hujjatni ochishga ruxsat yo'q.");
    if (r.statusCode == 404) throw ApiException('Hujjat topilmadi.');
    throw ApiException("Hujjatni olib bo'lmadi (${r.statusCode}).");
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
  Future<Map<String, dynamic>> funds({int? user, String? status}) async =>
      Map<String, dynamic>.from(((await _getMap('/funds', {'user': user, 'status': status}))['data'] as Map?) ?? const {});

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

  Future<void> fundsPost(String path, [Map<String, dynamic>? body]) async {
    await _send(() => _http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? const {})));
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
  Future<Map<String, dynamic>> currencies() async => Map<String, dynamic>.from(((await _getMap('/currencies'))['data'] as Map?) ?? const {});

  /// Rahbar qo'shimcha valyutalarni yoqadi (USD va kompaniya valyutasi doim mavjud)
  Future<void> currenciesSave(List<String> codes) async {
    await _send(() => _http.post(_uri('/currencies'), headers: _headers, body: jsonEncode({'codes': codes})));
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
    final m = await _getMap('/stock/items', {'page': page, 'per_page': 40, 'q': q, 'low': low ? 1 : null});
    return Paged(_list(m['data']), PageMeta.from(m['meta']));
  }

  /* ---------------- vazifalar ---------------- */

  Future<Paged> tasks({int page = 1, String? status, int? assignee}) async {
    final m = await _getMap('/tasks', {'page': page, 'per_page': 40, 'status': status, 'assignee': assignee});
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
    final m = await _getMap('/stock/moves', {'page': page, 'per_page': 40, 'type': type});
    return Paged(_list(m['data']), PageMeta.from(m['meta']));
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
