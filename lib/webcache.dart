import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'offline.dart';
import 'session.dart';

class _Resp {
  _Resp(this.status, this.type, this.bytes, {this.location, this.file, int? length}) : length = length ?? bytes.length;
  final int status;
  final String type;
  final Uint8List bytes; // matnli javoblar uchun (rasm/model kabi katta fayllar `file` orqali oqim bilan beriladi)
  final String? location;
  final File? file;
  final int length;
}

/// 3D va 360° sahifalarini internetsiz ochish uchun telefon ichidagi KESH-PROKSI.
///
/// Sayt sahifasi (three.js, model-viewer, panoramalar, HDR, shriftlar, server skriptlari) `127.0.0.1` dagi shu kichik server orqali yuklanadi:
///  • internet bor — so'rov asl serverga (yoki CDN'ga) boradi, javob DISKKA yoziladi va WebView'ga beriladi;
///  • internet yo'q — javob diskdagi nusxadan beriladi.
/// Matnli javoblardagi `https://...` manzillar shu proksiga yo'naltiriladi (CDN ham keshlanishi uchun).
/// Proksi faqat shu ilova ochgan sahifaga javob beradi (tasodifiy kalit cookie'si), saytga kirish cookie'si ilova ichida qoladi.
class WebCache {
  static HttpServer? _srv;
  static HttpClient? _client;
  static String _token = '';
  static String _base = '';
  static Session? _session;
  static String _loginObject = '';
  static DateTime? _loggedAt;
  static final _cookies = <String, String>{};
  static final _importMap = <String, String>{};

  /// Oldindan saqlash jarayonining holati (ekranda ko'rsatiladi)
  static final ValueNotifier<String?> status = ValueNotifier(null);

  static String get origin => 'http://127.0.0.1:${_srv?.port ?? 0}';

  static Directory? get _dir {
    final r = Offline.root;
    return r == null ? null : Directory('${r.path}/web');
  }

  /* ---------------- ishga tushirish ---------------- */

  static Future<void> ensure(Session s) async {
    _session = s;
    _base = s.api!.base;
    if (_srv != null) {
      // iOS ilovani fonga olganda soket yopilishi mumkin — tekshiramiz
      try {
        final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        final rq = await c.getUrl(Uri.parse('$origin/__ping?__t=$_token'));
        final rs = await rq.close();
        await rs.drain<void>();
        c.close(force: true);
        return;
      } catch (_) {
        try {
          await _srv?.close(force: true);
        } catch (_) {}
        _srv = null;
      }
    }
    // oldingi uzilgan yuklashlardan qolgan vaqtinchalik fayllar
    try {
      final d = _dir;
      if (d != null && await d.exists()) {
        await for (final e in d.list()) {
          if (e is File && e.path.endsWith('.tmp')) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    final r = Random.secure();
    _token = List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join();
    _srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _srv!.listen(_serve, onError: (_) {});
  }

  /// Chiqishda: server to'xtaydi, saytga kirish cookie'lari tozalanadi
  static Future<void> reset() async {
    try {
      await _srv?.close(force: true);
    } catch (_) {}
    _srv = null;
    _cookies.clear();
    _loggedAt = null;
    _importMap.clear();
    _session = null;
  }

  /// Diskdagi 3D nusxasini o'chiradi
  static Future<void> clearDisk() async {
    final d = _dir;
    try {
      if (d != null && await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  static Future<({int files, int bytes})> stats() async {
    final d = _dir;
    var n = 0, b = 0;
    try {
      if (d != null && await d.exists()) {
        await for (final e in d.list()) {
          if (e is File && e.path.endsWith('.b')) {
            n++;
            b += await e.length();
          }
        }
      }
    } catch (_) {}
    return (files: n, bytes: b);
  }

  /* ---------------- ko'rinish manzili ---------------- */

  static String viewPath(String objectId, String view, {String? apartment}) =>
      '/company/objects/${Uri.encodeComponent(objectId)}/$view?embed=1${apartment != null && apartment.isNotEmpty ? '&u=${Uri.encodeQueryComponent(apartment)}' : ''}';

  /// WebView ochadigan manzil. Internet bo'lsa saytga kiradi (bir martalik havola orqali); bo'lmasa — keshdan ochiladi.
  static Future<String> viewUrl(Session s, String objectId, String view, {String? apartment}) async {
    await ensure(s);
    _loginObject = objectId;
    await _login();
    return '$origin${viewPath(objectId, view, apartment: apartment)}&__t=$_token';
  }

  static Future<void> _login() async {
    final s = _session;
    if (s?.api == null) return;
    if (_loggedAt != null && DateTime.now().difference(_loggedAt!) < const Duration(minutes: 50) && _cookies.isNotEmpty) return;
    try {
      final link = await s!.api!.webLink(_loginObject, '3d');
      final r = await _fetch(Uri.parse(link), timeout: const Duration(seconds: 20));
      if (r.status >= 200 && r.status < 400) _loggedAt = DateTime.now();
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow; // ruxsat yo'q va h.k. — foydalanuvchiga ko'rsatiladi
    } catch (_) {}
  }

  /* ---------------- server ---------------- */

  static bool _sameOrigin(Uri u) {
    final b = Uri.parse(_base);
    return u.scheme == b.scheme && u.host == b.host && u.port == b.port;
  }

  static bool _isText(String type) {
    final t = type.toLowerCase();
    return t.contains('text/') || t.contains('javascript') || t.contains('json') || t.contains('xml') || t.contains('css') || t.contains('svg') || t.contains('manifest');
  }

  static String _cookieHeader() => _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  static String _rewrite(String s) {
    final o = origin;
    final oEsc = o.replaceAll('/', r'\/');
    final bEsc = _base.replaceAll('/', r'\/');
    s = s.replaceAll(_base, o).replaceAll(bEsc, oEsc);
    s = s.replaceAllMapped(RegExp(r'https://([A-Za-z0-9.\-]+(?::\d+)?)'), (m) => '$o/__o/${m[1]}');
    s = s.replaceAllMapped(RegExp(r'https:\\/\\/([A-Za-z0-9.\-]+(?::\d+)?)'), (m) => '$oEsc\\/__o\\/${m[1]}');
    return s;
  }

  static Uri? _upstreamOf(String path, String query) {
    try {
      if (path.startsWith('/__o/')) {
        final segs = path.split('/'); // ['', '__o', host, ...]
        if (segs.length < 4) return null;
        return Uri.parse('https://${segs[2]}/${segs.sublist(3).join('/')}${query.isEmpty ? '' : '?$query'}');
      }
      return Uri.parse('$_base$path${query.isEmpty ? '' : '?$query'}');
    } catch (_) {
      return null;
    }
  }

  static String _offlinePage() => '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><body style="font-family:sans-serif;padding:32px;text-align:center;background:#f4f7f5;color:#1b2b22;font-size:17px;line-height:1.5">'
      '<h2>Offline</h2><p>${_msg("Bu ko'rinish telefonda saqlanmagan. Internet bilan bir marta oching yoki \"Yana → Sinxronlash\" ekranidan 3D va 360° ni offline uchun saqlang.")}</p></body>';

  static String _msg(String uz) {
    return switch (ApiClient.lang) {
      'ru' => 'Этот вид не сохранён на телефоне. Откройте его один раз с интернетом или сохраните 3D и 360° для offline на экране «Ещё → Синхронизация».',
      'tg' => 'Ин намоиш дар телефон нигоҳ дошта нашудааст. Онро як маротиба бо интернет кушоед ё 3D ва 360°-ро аз саҳифаи «Бештар → Ҳамоҳангсозӣ» барои offline нигоҳ доред.',
      _ => uz,
    };
  }

  static Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    try {
      final q = req.uri.query;
      final tokenQ = RegExp(r'(?:^|&)__t=([A-Za-z0-9]+)').firstMatch(q)?.group(1);
      final cookieOk = req.cookies.any((c) => c.name == 'wc' && c.value == _token);
      if (!cookieOk && tokenQ != _token) {
        res.statusCode = 403;
        await res.close();
        return;
      }
      if (tokenQ == _token) res.headers.add(HttpHeaders.setCookieHeader, 'wc=$_token; Path=/; HttpOnly');
      final path = req.uri.path;
      if (path == '/__ping') {
        res.statusCode = 200;
        await res.close();
        return;
      }
      if (req.method != 'GET' && req.method != 'HEAD') {
        res.statusCode = 204;
        await res.close();
        return;
      }
      if (path == '/sw.js') {
        res.statusCode = 404;
        await res.close();
        return;
      }
      final cleanQ = q.replaceAll(RegExp(r'(^|&)__t=[A-Za-z0-9]+'), '').replaceFirst(RegExp(r'^&'), '');
      final up = _upstreamOf(path, cleanQ);
      if (up == null) {
        res.statusCode = 400;
        await res.close();
        return;
      }
      final r = await _get(up);
      res.statusCode = r.status;
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      res.headers.set('Access-Control-Allow-Origin', '*');
      if (r.location != null) {
        final l = r.location!;
        res.headers.set(HttpHeaders.locationHeader, l.startsWith(_base) ? l.replaceFirst(_base, origin) : l);
      }
      res.headers.set(HttpHeaders.contentTypeHeader, r.type);
      if (r.file != null) {
        // katta fayl (model, rasm, HDR): xotiraga o'qimasdan diskdan oqim bilan beriladi
        res.headers.set(HttpHeaders.contentLengthHeader, '${r.length}');
        if (req.method != 'HEAD') await res.addStream(r.file!.openRead());
        await res.close();
        return;
      }
      Uint8List body = r.bytes;
      if (_isText(r.type) && r.status == 200) body = Uint8List.fromList(utf8.encode(_rewrite(utf8.decode(r.bytes, allowMalformed: true))));
      res.headers.set(HttpHeaders.contentLengthHeader, '${body.length}');
      if (req.method != 'HEAD') res.add(body);
      await res.close();
    } catch (_) {
      try {
        res.statusCode = 502;
        await res.close();
      } catch (_) {}
    }
  }

  /* ---------------- tarmoq + disk ---------------- */

  static int _tmpSeq = 0;

  static Future<_Resp> _fetch(Uri u, {required Duration timeout}) async {
    final c = (_client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'OftobBuilding/1.0');
    final req = await c.getUrl(u).timeout(timeout);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    req.headers.set(HttpHeaders.acceptLanguageHeader, ApiClient.lang);
    final same = _sameOrigin(u);
    if (same && _cookies.isNotEmpty) req.headers.set(HttpHeaders.cookieHeader, _cookieHeader());
    final resp = await req.close().timeout(timeout);
    if (same) {
      try {
        for (final c in resp.cookies) {
          _cookies[c.name] = c.value;
        }
      } catch (_) {}
    }
    final type = resp.headers.contentType?.toString() ?? 'application/octet-stream';
    final loc = resp.headers.value(HttpHeaders.locationHeader);
    // matn bo'lmagan (rasm, model, HDR, wasm) va muvaffaqiyatli javob — to'g'ridan-to'g'ri vaqtinchalik faylga yoziladi (xotira to'lmasligi uchun)
    final dir = _dir;
    if (resp.statusCode == 200 && !_isText(type) && dir != null) {
      await dir.create(recursive: true);
      final tmp = File('${dir.path}/dl_${DateTime.now().microsecondsSinceEpoch}_${_tmpSeq++}.tmp');
      final sink = tmp.openWrite();
      try {
        await sink.addStream(resp.timeout(timeout));
        await sink.close();
      } catch (e) {
        try {
          await sink.close();
        } catch (_) {}
        try {
          await tmp.delete();
        } catch (_) {}
        rethrow;
      }
      return _Resp(200, type, Uint8List(0), location: loc, file: tmp, length: await tmp.length());
    }
    final bb = BytesBuilder(copy: false);
    await for (final chunk in resp.timeout(timeout)) {
      bb.add(chunk);
    }
    return _Resp(resp.statusCode, type, bb.takeBytes(), location: loc);
  }

  static String _name(String key) {
    var h = 0xcbf29ce484222325;
    for (final c in key.codeUnits) {
      h = (h ^ c) * 0x100000001b3;
    }
    return (h & 0x7fffffffffffffff).toRadixString(36);
  }

  static Future<_Resp?> _read(String key) async {
    final d = _dir;
    if (d == null) return null;
    final n = _name(key);
    try {
      final m = File('${d.path}/$n.m');
      final b = File('${d.path}/$n.b');
      if (!await m.exists() || !await b.exists()) return null;
      final meta = jsonDecode(await m.readAsString()) as Map;
      if (meta['url'] != key) return null; // xesh to'qnashuvi
      final type = '${meta['type']}';
      final status = (meta['status'] as num?)?.toInt() ?? 200;
      if (_isText(type)) {
        var bytes = await b.readAsBytes();
        if (meta['gz'] == true) bytes = Uint8List.fromList(gzip.decode(bytes));
        return _Resp(status, type, bytes);
      }
      return _Resp(status, type, Uint8List(0), file: b, length: await b.length());
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String key, _Resp r) async {
    final d = _dir;
    if (d == null) return;
    try {
      await d.create(recursive: true);
      final n = _name(key);
      final fin = '${d.path}/$n.b';
      var gz = false;
      if (r.file != null) {
        if (r.file!.path != fin) {
          try {
            await r.file!.rename(fin);
          } catch (_) {
            await r.file!.copy(fin);
            await r.file!.delete();
          }
        }
      } else {
        final tmp = File('$fin.tmp');
        final text = _isText(r.type);
        await tmp.writeAsBytes(text ? gzip.encode(r.bytes) : r.bytes, flush: true);
        gz = text;
        await tmp.rename(fin);
      }
      await File('${d.path}/$n.m').writeAsString(jsonEncode({'url': key, 'status': r.status, 'type': r.type, 'gz': gz, 'at': DateTime.now().toIso8601String()}), flush: true);
    } catch (_) {}
  }

  static bool _immutable(Uri u) =>
      !_sameOrigin(u) || RegExp(r'^/company/media/\d+/file$').hasMatch(u.path) || (u.path.startsWith('/assets/') && u.query.contains('v='));

  static Future<_Resp> _get(Uri u, {bool force = false, bool patient = false}) async {
    final key = u.toString();
    if (!force && _immutable(u)) {
      final c = await _read(key);
      if (c != null) return c;
    }
    // saqlash (patient) paytida internet yo'q deb shoshilmaymiz: serverning javobini uzoqroq kutamiz
    final online = patient || Offline.online.value;
    try {
      var r = await _fetch(u, timeout: patient ? const Duration(seconds: 90) : (online ? const Duration(seconds: 45) : const Duration(seconds: 5)));
      // sayt seansi tugagan bo'lsa — qayta kiramiz (bir marta)
      if (_sameOrigin(u) && (r.status == 301 || r.status == 302 || r.status == 303 || r.status == 307) && r.location != null) {
        final lp = Uri.tryParse(r.location!)?.path ?? '';
        if (lp == '/login' || RegExp(r'^/c/[^/]+/?$').hasMatch(lp)) {
          _loggedAt = null;
          _cookies.clear();
          await _login();
          r = await _fetch(u, timeout: const Duration(seconds: 45));
        }
      }
      Offline.markOnline(true);
      if (r.status == 200 && r.length < 500 * 1024 * 1024) {
        await _write(key, r);
        if (r.file != null) {
          final stored = await _read(key); // fayl endi doimiy joyda
          if (stored != null) return stored;
        }
      } else if (r.status >= 500) {
        final c = await _read(key);
        if (c != null) return c;
      } else if (r.file != null) {
        try {
          await r.file!.delete();
        } catch (_) {}
      }
      return r;
    } catch (_) {
      if (!patient) Offline.markOnline(false);
      final c = await _read(key);
      if (c != null) return c;
      return _Resp(504, 'text/html; charset=utf-8', Uint8List.fromList(utf8.encode(_offlinePage())));
    }
  }

  /* ---------------- oldindan saqlash (crawler) ---------------- */

  static final _reAttr = RegExp(r'''(?:src|href|poster|data-src)\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  static final _reUrl = RegExp(r'''https?://[^\s"'<>)\\`,]+''');
  static final _reRoot = RegExp(r'''["'`](/(?:assets|company/media|icons)/[^"'`\s<>]+)["'`]''');
  static final _reImport = RegExp(r'''(?:import|export)\s*(?:[\w*{}\s,$]*?\s*from\s*)?["']([^"']+)["']''');
  static final _reDyn = RegExp(r'''import\s*\(\s*["']([^"']+)["']\s*\)''');
  static final _reCss = RegExp(r'''url\(\s*["']?([^"')\s]+)["']?\s*\)''');
  static final _reExt = RegExp(r'\.(js|mjs|css|hdr|glb|gltf|bin|wasm|png|jpe?g|webp|svg|ico|woff2?|ttf|json|ktx2|webmanifest)$', caseSensitive: false);

  static Uri? _resolve(Uri base, String spec, {bool fromImport = false}) {
    spec = spec.trim().replaceAll('&amp;', '&');
    if (spec.isEmpty || spec.startsWith('#') || spec.startsWith('data:') || spec.startsWith('javascript:') || spec.startsWith('mailto:') || spec.startsWith('tel:') || spec.startsWith('blob:')) return null;
    try {
      if (spec.startsWith('http://') || spec.startsWith('https://')) return Uri.parse(spec);
      if (spec.startsWith('//')) return Uri.parse('https:$spec');
      if (spec.startsWith('./') || spec.startsWith('../') || spec.startsWith('/')) return base.resolve(spec);
      if (fromImport) {
        final exact = _importMap[spec];
        if (exact != null) return Uri.parse(exact);
        for (final e in _importMap.entries) {
          if (e.key.endsWith('/') && spec.startsWith(e.key)) return Uri.parse('${e.value}${spec.substring(e.key.length)}');
        }
        return null;
      }
      return base.resolve(spec);
    } catch (_) {
      return null;
    }
  }

  static bool _wanted(Uri u) {
    if (u.scheme != 'http' && u.scheme != 'https') return false;
    final p = u.path;
    if (RegExp(r'(/logout|/interiors|/patch|/api/|/sw\.js)').hasMatch(p) || RegExp(r'/media/\d+$').hasMatch(p)) return false;
    if (_sameOrigin(u)) {
      return RegExp(r'^/(assets|icons)/').hasMatch(p) || RegExp(r'^/company/media/\d+/file$').hasMatch(p) || p == '/manifest.webmanifest' || (p.startsWith('/company/objects/') && u.query.contains('embed=1'));
    }
    // tashqi manbalar: faqat tanilgan CDN'lar (aks holda kutubxona izohlaridagi havolalar bo'yicha butun internetni aylanib chiqamiz)
    if (u.scheme != 'https' || !_cdnHosts.contains(u.host)) return false;
    return _reExt.hasMatch(p) || u.host == 'fonts.googleapis.com';
  }

  static const _cdnHosts = {'cdn.jsdelivr.net', 'cdnjs.cloudflare.com', 'unpkg.com', 'fonts.googleapis.com', 'fonts.gstatic.com', 'www.gstatic.com', 'ajax.googleapis.com'};

  static Set<Uri> _refs(Uri base, String type, String raw) {
    final out = <Uri>{};
    void add(Uri? u, {bool imp = false}) {
      if (u == null) return;
      final c = u.removeFragment();
      if (_wanted(c)) out.add(c);
    }

    final t = raw.replaceAll(r'\/', '/');
    final isHtml = type.contains('html');
    final isCss = type.contains('css');
    if (isHtml) {
      for (final m in RegExp(r'<script[^>]*type=["\x27]importmap["\x27][^>]*>(.*?)</script>', dotAll: true).allMatches(t)) {
        try {
          final j = jsonDecode(m[1]!) as Map;
          ((j['imports'] as Map?) ?? const {}).forEach((k, v) => _importMap['$k'] = '$v');
        } catch (_) {}
      }
      for (final m in _reAttr.allMatches(t)) {
        add(_resolve(base, m[1]!));
      }
    }
    for (final m in _reUrl.allMatches(t)) {
      add(Uri.tryParse(m[0]!));
    }
    for (final m in _reRoot.allMatches(t)) {
      add(_resolve(base, m[1]!));
    }
    if (isCss) {
      for (final m in _reCss.allMatches(t)) {
        add(_resolve(base, m[1]!));
      }
    }
    if (type.contains('javascript') || isHtml) {
      for (final m in _reImport.allMatches(t)) {
        add(_resolve(base, m[1]!, fromImport: true));
      }
      for (final m in _reDyn.allMatches(t)) {
        add(_resolve(base, m[1]!, fromImport: true));
      }
      // Draco dekoderi: yuklagich shu papkadan fayl nomlari bilan o'qiydi
      for (final m in RegExp(r'(https://[^\s"\x27]+/libs/draco/gltf/)').allMatches(t)) {
        for (final f in const ['draco_decoder.js', 'draco_decoder.wasm', 'draco_wasm_wrapper.js']) {
          add(Uri.tryParse('${m[1]}$f'));
        }
      }
    }
    return out;
  }

  /// Berilgan sahifalarni va ular yuklaydigan hamma narsani (skriptlar, modullar, panoramalar, HDR, shriftlar) telefonga saqlaydi.
  static Future<({int files, int bytes, int errors, bool network})> crawl(List<Uri> starts, {int maxFiles = 4000, int maxBytes = 700 * 1024 * 1024}) async {
    final queue = Queue<Uri>()..addAll(starts);
    final seen = <String>{for (final s in starts) s.toString()};
    var files = 0, bytes = 0, errors = 0, active = 0, consecutiveFails = 0;
    var network = false;
    final retried = <String>{};

    Future<void> worker() async {
      while (true) {
        if (queue.isEmpty) {
          if (active == 0) return;
          await Future<void>.delayed(const Duration(milliseconds: 60));
          continue;
        }
        if (files >= maxFiles || bytes >= maxBytes) {
          queue.clear();
          continue;
        }
        final u = queue.removeFirst();
        active++;
        try {
          final isPage = _sameOrigin(u) && u.path.startsWith('/company/objects/');
          final r = await _get(u, force: isPage, patient: true);
          if (r.status == 504) {
            // bitta uzilish butun jarayonni to'xtatmaydi: bir marta qayta urinamiz, ketma-ket 8 ta xatoda to'xtaymiz
            consecutiveFails++;
            if (retried.add(u.toString())) {
              queue.add(u);
            } else {
              errors++;
            }
            if (consecutiveFails >= 8) {
              network = true;
              queue.clear();
            }
          } else if (r.status == 200) {
            consecutiveFails = 0;
            files++;
            bytes += r.length;
            status.value = 'Yuklanmoqda: $files fayl · ${(bytes / 1048576).toStringAsFixed(1)} MB';
            if (_isText(r.type) && r.bytes.length < 4 * 1024 * 1024 && (_sameOrigin(u) || !r.type.contains('html'))) {
              for (final n in _refs(u, r.type, utf8.decode(r.bytes, allowMalformed: true))) {
                if (seen.add(n.toString())) queue.add(n);
              }
            }
          } else if (r.status >= 400) {
            errors++;
          }
        } catch (_) {
          errors++;
        } finally {
          active--;
        }
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    return (files: files, bytes: bytes, errors: errors, network: network);
  }

  /// Obyektlar bo'yicha saqlangan 3D nusxasi haqida ma'lumot: id → {files, bytes, apts, at}
  static Future<Map<String, Map<String, dynamic>>> index() async {
    final m = await Offline.get('web_index');
    final out = <String, Map<String, dynamic>>{};
    ((m?['items'] as Map?) ?? const {}).forEach((k, v) {
      if (v is Map) out['$k'] = Map<String, dynamic>.from(v);
    });
    return out;
  }

  /// Bitta obyektning kvartiralari uchun 3D / 360° / «uyda joyi» ko'rinishlarini va ularning hamma resurslarini saqlaydi.
  /// [perObject] — eng ko'pi bilan nechta kvartira (avval bo'sh, keyin bronda, keyin sotilgan). Uy modeli obyekt uchun bir marta saqlanadi.
  static Future<({int files, int bytes, int errors, bool network, int apts})> prefetchObject(Session s, String objectId, {int perObject = 30}) async {
    final api = s.api;
    if (api == null || !Offline.enabled) return (files: 0, bytes: 0, errors: 0, network: false, apts: 0);
    status.value = 'Tayyorlanmoqda…';
    try {
      await ensure(s);
      _loginObject = objectId;
      await _login();
      var apts = (await Offline.loadApartments(objectId)) ?? const <Map<String, dynamic>>[];
      if (apts.isEmpty) {
        try {
          await api.downloadAllApartments(objectId);
          apts = (await Offline.loadApartments(objectId)) ?? const <Map<String, dynamic>>[];
        } catch (_) {}
      }
      int rank(Map a) => switch (a['status']) { 'free' => 0, 'booked' => 1, _ => 2 };
      final sorted = [...apts]..sort((a, b) => rank(a).compareTo(rank(b)));
      final pick = sorted.take(perObject).toList();
      final starts = <Uri>[
        for (final a in pick)
          for (final v in const ['3d', 'locate']) Uri.parse('$_base${viewPath(objectId, v, apartment: '${a['id']}')}'),
      ];
      final r = await crawl(starts);
      if (!r.network && r.files > 0) {
        final idx = await index();
        idx[objectId] = {'files': r.files, 'bytes': r.bytes, 'apts': pick.length, 'at': DateTime.now().toIso8601String()};
        await Offline.put('web_index', {'items': idx});
      }
      return (files: r.files, bytes: r.bytes, errors: r.errors, network: r.network, apts: pick.length);
    } finally {
      status.value = null;
    }
  }
}
