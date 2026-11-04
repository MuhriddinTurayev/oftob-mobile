import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oftob_mobile/api.dart';
import 'package:oftob_mobile/company.dart';
import 'package:oftob_mobile/format.dart';
import 'package:oftob_mobile/main.dart';
import 'package:oftob_mobile/session.dart';

void main() {
  test('server manzili tozalanadi', () {
    expect(ApiClient.normalizeUrl(' oftob.example.uz/ '), 'https://oftob.example.uz');
    expect(ApiClient.normalizeUrl('http://192.168.1.55:8000/api/v1'), 'http://192.168.1.55:8000');
  });

  test('summa formati', () {
    expect(money(10000000), '10 000 000');
    expect(money(-1500), '-1 500');
    expect(money(null), '—');
  });

  test('korxona kodi turli yozuvdan ajratiladi', () {
    expect(parseCompanyCode('Navruz-Qurilish'), 'navruz-qurilish');
    expect(parseCompanyCode(' navruz-qurilish '), 'navruz-qurilish');
    expect(parseCompanyCode('https://navruz-qurilish.oftob.5-189-163-130.sslip.io/login'), 'navruz-qurilish');
    expect(parseCompanyCode('https://oftob.5-189-163-130.sslip.io/c/mosgrad-development'), 'mosgrad-development');
    expect(parseCompanyCode(''), isNull);
    expect(parseCompanyCode('!!!'), isNull);
  });

  test('korxona topiladi (200) va nomi sarlavhadan olinadi', () async {
    final client = MockClient((r) async {
      expect(r.url.path, '/c/navruz-qurilish');
      return http.Response.bytes(utf8.encode('<html><title>Navruz Qurilish — Oftob_Sohtumon</title></html>'), 200);
    });
    final c = await lookupCompany('https://x.uz', 'navruz-qurilish', client: client);
    expect(c?.name, 'Navruz Qurilish');
    expect(c?.initials, 'NQ');
  });

  test('korxona topilmasa (404) null', () async {
    final client = MockClient((_) async => http.Response('', 404));
    expect(await lookupCompany('https://x.uz', 'yoq', client: client), isNull);
  });

  test('/me javobi o\'qiladi va kalit headerda yuboriladi', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(
        jsonEncode({
          'data': {
            'company': {'name': 'Test MChJ', 'currency': 'UZS'},
            'key': {'name': 'Telefon', 'role_name': 'Rahbar', 'read_only': false, 'scopes': ['objects:read', 'leads:read']},
          }
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = ApiClient(serverUrl: 'https://x.uz', apiKey: 'oft_abc', client: client);
    final me = await api.me();
    expect(seen.headers['Authorization'], 'Bearer oft_abc');
    expect(me.company, 'Test MChJ');
    expect(me.can('objects:read'), isTrue);
    expect(me.can('cash:read'), isFalse);
  });

  test('server xatosi tushunarli matnga aylanadi', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({'error': {'code': 'invalid_key', 'message': 'Invalid API key'}}), 401));
    final api = ApiClient(serverUrl: 'https://x.uz', apiKey: 'oft_bad', client: client);
    await expectLater(api.me(), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('noto\'g\'ri'))));
  });

  testWidgets('kirish oynasi: korxona tanlash bor, server manzili ko\'rinmaydi', (tester) async {
    final session = Session();
    session.loading = false;
    await tester.pumpWidget(OftobApp(session: session));
    expect(find.text('Oftob CRM'), findsOneWidget);
    expect(find.text('Korxonani tanlang'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // faqat korxona kodi
    expect(find.textContaining('sslip'), findsNothing);
    expect(find.textContaining('http'), findsNothing);
    expect(find.text('Server manzili'), findsNothing);
  });
}
