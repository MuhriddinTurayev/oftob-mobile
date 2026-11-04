import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/web_shell.dart';
import 'session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(OftobApp(session: Session()..restore()));
}

class OftobApp extends StatelessWidget {
  const OftobApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oftob CRM',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (session.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (session.webActive) return WebShell(session: session);
          return session.signedIn ? HomeScreen(session: session) : LoginScreen(session: session);
        },
      ),
    );
  }

  /// Sayt rangi (yashil) — ilova ham shu uslubda: yumaloq kartalar, tekis tab-bar.
  static ThemeData _theme(Brightness b) => ThemeData(
        colorSchemeSeed: const Color(0xFF107C41),
        brightness: b,
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
        navigationBarTheme: NavigationBarThemeData(
          height: 66,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
        appBarTheme: AppBarTheme(
          scrolledUnderElevation: 0,
          // holat paneli yozuvlari fonga qarab: yorug' mavzuda qora, qorong'i mavzuda oq (kirish oynasida ko'rinmay qolmasin)
          systemOverlayStyle: b == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        }),
      );
}
