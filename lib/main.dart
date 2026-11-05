import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'screens/home.dart';
import 'screens/login.dart';
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
      title: 'Oftob Building',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * 1.08)), child: child!);
      },
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (session.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          return session.signedIn ? HomeScreen(session: session) : LoginScreen(session: session);
        },
      ),
    );
  }

  static const _green = Color(0xFF0B7A3B);

  /// Brend: kran va binolar logotipidagi to'q yashil + sariq. Kontrastli: kulrang-yashil fon, oq kartalar, qalin tab-bar.
  static ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    final bg = dark ? const Color(0xFF0D1210) : const Color(0xFFE9EFEB);
    final card = dark ? const Color(0xFF18211C) : Colors.white;
    final text = dark ? const Color(0xFFEAF2ED) : const Color(0xFF0E1A13);
    final border = dark ? const Color(0xFF2A3730) : const Color(0xFFCBD7CF);
    final primary = dark ? const Color(0xFF4CC38A) : _green;
    final scheme = ColorScheme.fromSeed(seedColor: _green, brightness: b).copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF05301A) : Colors.white,
      primaryContainer: dark ? const Color(0xFF14432A) : const Color(0xFFBFE6CF),
      onPrimaryContainer: dark ? const Color(0xFFD7F5E3) : const Color(0xFF05301A),
      secondaryContainer: dark ? const Color(0xFF1D4A31) : const Color(0xFFBFE6CF),
      onSecondaryContainer: dark ? const Color(0xFFD7F5E3) : const Color(0xFF05301A),
      tertiary: const Color(0xFFF2A900),
      surface: card,
      onSurface: text,
      surfaceContainerHighest: card,
      outline: dark ? const Color(0xFF9DB0A5) : const Color(0xFF5B6B61),
      outlineVariant: border,
    );
    OutlineInputBorder ob(Color c, double w) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      visualDensity: VisualDensity.standard,
      textTheme: Typography.material2021(platform: TargetPlatform.android).black.apply(bodyColor: text, displayColor: text).copyWith(
            bodyLarge: TextStyle(fontSize: 16.5, color: text),
            bodyMedium: TextStyle(fontSize: 15, color: text),
            titleMedium: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: text),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: text, letterSpacing: -0.4),
        iconTheme: IconThemeData(color: text),
        // holat paneli yozuvlari fonga qarab: yorug' mavzuda qora, qorong'i mavzuda oq
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(color: card, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: border))),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black,
        indicatorColor: primary,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(size: 27, color: st.contains(WidgetState.selected) ? scheme.onPrimary : scheme.outline)),
        labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(fontSize: 12.5, fontWeight: st.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600, color: st.contains(WidgetState.selected) ? text : scheme.outline)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: primary,
        side: BorderSide(color: border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        labelStyle: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: text),
        secondaryLabelStyle: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: scheme.onPrimary),
        checkmarkColor: scheme.onPrimary,
        iconTheme: IconThemeData(color: text, size: 18),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: ob(border, 1),
        enabledBorder: ob(border, 1),
        focusedBorder: ob(primary, 2),
        labelStyle: TextStyle(color: scheme.outline),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 50), side: BorderSide(color: border, width: 1.4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: primary, foregroundColor: scheme.onPrimary, elevation: 4, extendedTextStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
      dividerTheme: DividerThemeData(color: border, space: 1),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
          backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? primary : card),
          foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? scheme.onPrimary : text),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent, showDragHandle: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
      dialogTheme: DialogThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
