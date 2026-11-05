import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

/// Platformadagi kompaniya (korxona): manzil kodi (slug) va nomi.
class CompanyInfo {
  const CompanyInfo({required this.slug, required this.name});

  factory CompanyInfo.fromJson(Map<String, dynamic> j) => CompanyInfo(slug: '${j['slug']}', name: '${j['name']}');

  final String slug;
  final String name;

  Map<String, dynamic> toJson() => {'slug': slug, 'name': name};

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final a = String.fromCharCode(parts.first.runes.first).toUpperCase();
    final b = parts.length > 1 ? String.fromCharCode(parts[1].runes.first).toUpperCase() : '';
    return '$a$b';
  }
}

/// Foydalanuvchi yozgan narsadan kompaniya kodini ajratadi: "Navruz Qurilish", "Navruz-Qurilish",
/// "navruz-qurilish.oftob.….io", "…/c/navruz-qurilish" — hammasi "navruz-qurilish" bo'ladi.
String? parseCompanyCode(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^https?://'), '');
  final path = RegExp(r'/c/([a-z0-9-]+)').firstMatch(s);
  if (path != null) return path.group(1);
  if (s.contains('.')) s = s.split('.').first; // nom.oftob….io
  s = s.replaceAll(RegExp(r'/.*$'), '').trim();
  s = s.replaceAll(RegExp(r'\s+'), '-'); // "Navruz Qurilish" → "navruz-qurilish"
  return RegExp(r'^[a-z0-9][a-z0-9-]{0,78}$').hasMatch(s) ? s : null;
}

/// Kompaniya mavjudligini tekshiradi (ochiq sahifa `/c/kod`: bor — 200, yo'q — 404).
/// Mavjud bo'lmasa null. Tarmoq xatosida [ApiException].
Future<CompanyInfo?> lookupCompany(String server, String code, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse('${ApiClient.normalizeUrl(server)}/c/$code'), headers: {'Accept': 'text/html'}).timeout(const Duration(seconds: 15));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw ApiException('Server javob bermadi (${r.statusCode}). Keyinroq urinib ko\'ring.');
    final html = utf8.decode(r.bodyBytes, allowMalformed: true);
    final t = RegExp(r'<title>([^<]*)</title>', caseSensitive: false).firstMatch(html)?.group(1) ?? '';
    final name = t.split('—').first.trim();
    return CompanyInfo(slug: code, name: name.isEmpty || name.toLowerCase().startsWith('kirish') ? code : _unescape(name));
  } on ApiException {
    rethrow;
  } catch (_) {
    throw ApiException('Internetga ulanib bo\'lmadi. Aloqani tekshirib, qayta urining.');
  } finally {
    if (client == null) c.close();
  }
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');
