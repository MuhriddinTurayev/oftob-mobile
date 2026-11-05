import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Server xatosi: matni foydalanuvchiga ko'rsatiladi.
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.code});

  final String message;
  final int? status;
  final String? code;

  bool get unauthorized => status == 401;

  @override
  String toString() => message;
}

/// Oftob CRM ochiq API (`/api/v1`) bilan ishlaydi.
/// Ma'lumotlar bazasiga to'g'ridan-to'g'ri EMAS — faqat server orqali (kalit bilan).
class ApiClient {
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
        'Accept-Language': 'uz',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{'lang': 'uz'};
    query?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) q[k] = '$v';
    });
    final u = Uri.parse('$base/api/v1$path');
    return u.replace(queryParameters: q);
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    final http.Response r;
    try {
      r = await call().timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw ApiException('Server javob bermadi. Internet va manzilni tekshiring.');
    } on FormatException {
      throw ApiException('Server manzili noto\'g\'ri.');
    } catch (e) {
      throw ApiException('Serverga ulanib bo\'lmadi. Internet va manzilni tekshiring.');
    }
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

  Future<Map<String, dynamic>> _getMap(String path, [Map<String, dynamic>? q]) async {
    final b = await _send(() => _http.get(_uri(path, q), headers: _headers));
    return (b is Map ? Map<String, dynamic>.from(b) : <String, dynamic>{});
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
            headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'Accept-Language': 'uz'},
            body: jsonEncode({'company': company, 'email': email, 'password': password, 'device': device}),
          ));
      return StaffLogin.fromJson(Map<String, dynamic>.from((b as Map)['data'] as Map), c.base);
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
    final m = await _getMap('/objects/${Uri.encodeComponent(objectId)}/apartments', {'status': status, 'rooms': rooms, 'page': page, 'per_page': perPage});
    return Paged(_list(m['data']), PageMeta.from(m['meta']));
  }

  /// Kvartira holatini o'zgartirish (bron / sotuv / bo'sh). Faqat o'zgargan maydonlarni yuboring.
  Future<Map<String, dynamic>> apartmentUpdate(String objectId, String apartmentId, Map<String, dynamic> body) async {
    final b = await _send(() => _http.patch(
          _uri('/objects/${Uri.encodeComponent(objectId)}/apartments/${Uri.encodeComponent(apartmentId)}'),
          headers: _headers,
          body: jsonEncode(body),
        ));
    return Map<String, dynamic>.from((b as Map)['data'] as Map);
  }

  /// Xaridorlar to'lovlari (sana oralig'i YYYY-MM-DD; sahifalanmaydi). meta: total, sum.
  Future<({List<Map<String, dynamic>> items, num sum})> salesPayments({String? from, String? to, String? object}) async {
    final m = await _getMap('/sales/payments', {'from': from, 'to': to, 'object': object});
    final meta = (m['meta'] as Map?) ?? const {};
    return (items: _list(m['data']), sum: (meta['sum'] as num?) ?? 0);
  }

  /* ---------------- lidlar ---------------- */

  Future<Paged> leads({int page = 1}) async {
    final m = await _getMap('/leads', {'page': page, 'per_page': 30});
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
    return Map<String, dynamic>.from((m['data'] as Map?) ?? const {});
  }

  /// Smenaga qo'yish (act='in') yoki smenadan olish (act='out'). Faqat bugun.
  Future<Map<String, dynamic>> attendanceMark(String act, String object, List<String> staffIds, {String? time}) async {
    final b = await _send(() => _http.post(
          _uri('/attendance/$act'),
          headers: _headers,
          body: jsonEncode({'object': object, 'staff_ids': staffIds, if (time != null && time.isNotEmpty) 'time': time}),
        ));
    return Map<String, dynamic>.from(((b as Map)['data'] as Map?) ?? const {});
  }

  /* ---------------- xodimlar (Crew) ---------------- */

  /// Xodimlar va oy bo'yicha hisoblangan / to'langan / qolgan ish haqi. [month] — YYYY-MM.
  Future<Map<String, dynamic>> crew({String? month, String? object}) async {
    final m = await _getMap('/crew', {'month': month, 'object': object});
    return Map<String, dynamic>.from((m['data'] as Map?) ?? const {});
  }

  /// Yangi xodim qabul qilish.
  Future<void> crewHire({required String object, required String name, required String role, String? phone, String pay = 'hour', num rate = 0}) async {
    await _send(() => _http.post(
          _uri('/crew'),
          headers: _headers,
          body: jsonEncode({'object': object, 'name': name, 'role': role, if (phone != null && phone.isNotEmpty) 'phone': phone, 'pay': pay, 'rate': rate}),
        ));
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

  Future<Paged> tasks({int page = 1, String? status}) async {
    final m = await _getMap('/tasks', {'page': page, 'per_page': 40, 'status': status});
    return Paged(_list(m['data']), PageMeta.from(m['meta']));
  }

  Future<void> taskUpdate(int id, {String? status, int? progress}) async {
    final body = <String, dynamic>{if (status != null) 'status': status, if (progress != null) 'progress': progress};
    await _send(() => _http.patch(_uri('/tasks/$id'), headers: _headers, body: jsonEncode(body)));
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
  StaffLogin({required this.token, required this.serverUrl, required this.userName, required this.roleName, required this.companyName, required this.companySlug});

  factory StaffLogin.fromJson(Map<String, dynamic> j, String serverUrl) {
    final u = (j['user'] as Map?) ?? const {};
    final c = (j['company'] as Map?) ?? const {};
    return StaffLogin(
      token: '${j['token']}',
      serverUrl: serverUrl,
      userName: '${u['name'] ?? ''}',
      roleName: '${u['role_name'] ?? u['role'] ?? ''}',
      companyName: '${c['name'] ?? ''}',
      companySlug: '${c['slug'] ?? ''}',
    );
  }

  final String token;
  final String serverUrl;
  final String userName;
  final String roleName;
  final String companyName;
  final String companySlug;
}
