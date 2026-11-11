import 'keyboard.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home.dart';
import 'platform/platform_home.dart';
import 'screens/login.dart';
import 'session.dart';
import 'l10n.dart';
import 'assistant.dart';
import 'fcm.dart';
import 'push.dart';
import 'splash.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await L.load(); // saqlangan (yoki telefon) tili birinchi kadrdan to'g'ri bo'lsin
  await ThemeController.load();
  await Push.init(); // telefon bildirishnomalari va ilova yopiq paytdagi tekshiruv (Android)
  await Fcm.init(); // Firebase push (sozlangan bo'lsa): ilova yopiq / telefon qulflangan bo'lsa ham darhol
  final session = Session()..restore();
  L.notifier.addListener(session.refreshMe); // til o'zgarsa — rol nomi kabi server matnlari yangi tilda olinadi
  if (_fpsLog) _startFpsLog();
  runApp(OftobApp(session: session));
}

/// Faqat sinov qurilmasida (--dart-define=OFTOB_FPSLOG=true): har soniyada nechta kadr chizilgani va eng sekin kadr.
/// Ilova tinch turganda kadr 0 bo'lishi kerak — aks holda nimadir bekorga to'xtovsiz chizilyapti.
const _fpsLog = bool.fromEnvironment('OFTOB_FPSLOG');
final bool _desktopOs = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

void _startFpsLog() {
  var n = 0, worstBuild = 0, worstRaster = 0;
  SchedulerBinding.instance.addTimingsCallback((list) {
    for (final t in list) {
      n++;
      if (t.buildDuration.inMicroseconds > worstBuild) worstBuild = t.buildDuration.inMicroseconds;
      if (t.rasterDuration.inMicroseconds > worstRaster) worstRaster = t.rasterDuration.inMicroseconds;
    }
  });
  Timer.periodic(const Duration(seconds: 1), (_) {
    debugPrint('FPSLOG frames=$n build=${(worstBuild / 1000).toStringAsFixed(1)}ms raster=${(worstRaster / 1000).toStringAsFixed(1)}ms');
    n = worstBuild = worstRaster = 0;
  });
}

class _DesktopScroll extends MaterialScrollBehavior {
  const _DesktopScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => {...super.dragDevices, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus};
}

class OftobApp extends StatefulWidget {
  const OftobApp({super.key, required this.session, this.skipSplash = false});

  final Session session;

  /// Sinovlarda ochilish animatsiyasini o'tkazib yuboradi
  final bool skipSplash;

  @override
  State<OftobApp> createState() => _OftobAppState();
}

class _OftobAppState extends State<OftobApp> {
  late bool _splashDone = widget.skipSplash;
  final _navKey = GlobalKey<NavigatorState>();
  final _msgKey = GlobalKey<ScaffoldMessengerState>();
  bool _wasIn = false;
  AssistantController? _ai;

  /// AI yordamchi har kirgan hisob uchun alohida (chiqqanda o'chadi)
  AssistantController? _assistant() {
    if (!session.signedIn || session.api == null) {
      _ai?.dispose();
      _ai = null;
      return null;
    }
    return _ai ??= (AssistantController(session)
      // yozishma yopiq paytda SI javob bersa (masalan, buyruq bajarildi) — pastda xabar, «Ochish» bilan
      ..onBackgroundReply = (text) {
        final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        _msgKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            content: Text('${tr('SI javob berdi')}: ${t.length > 120 ? '${t.substring(0, 120)}…' : t}', maxLines: 3),
            action: SnackBarAction(label: tr('Ochish'), onPressed: () => _ai?.openRequest.value++),
          ));
      });
  }

  Session get session => widget.session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: L.notifier,
      builder: (context, lang, _) => LangScope(
        code: lang,
        child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.mode,
        builder: (context, tm, _) => MaterialApp(
        title: 'Oftob Building',
        navigatorKey: _navKey,
        scaffoldMessengerKey: _msgKey,
        navigatorObservers: [ModalWatcher(), KeyboardRouteObserver()],
        debugShowCheckedModeBanner: false,
        // kompyuter: karusel va ro'yxatlarni sichqoncha bilan ham surish mumkin
        scrollBehavior: const _DesktopScroll(),
        theme: AppTheme.build(Brightness.light),
        darkTheme: AppTheme.build(Brightness.dark),
        themeMode: tm,
        themeAnimationDuration: const Duration(milliseconds: 450),
        themeAnimationCurve: Curves.easeOutCubic,
        locale: materialLocale(lang, (l) => GlobalMaterialLocalizations.delegate.isSupported(l)),
        supportedLocales: const [Locale('uz'), Locale('ru'), Locale('tg')],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        localeResolutionCallback: (loc, supported) => loc,
        builder: (context, child) => ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            // hisobdan chiqilganda oldingi foydalanuvchining pastki xabarlari ekranda qolmasin
            if (_wasIn && !session.signedIn && !session.platformIn) WidgetsBinding.instance.addPostFrameCallback((_) => _msgKey.currentState?.clearSnackBars());
            _wasIn = session.signedIn || session.platformIn;
            final ai = _splashDone ? _assistant() : null;
            // klaviatura: bo'sh joyga bosish yoki «Tayyor» bilan yopiladi (iPhone raqam klaviaturasida yopish tugmasi yo'q)
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.15)),
              child: KeyboardDismiss(
                child: Stack(children: [
                  NotificationListener<ScrollUpdateNotification>(
                    onNotification: (n) {
                      AiBubble.onScroll(n);
                      return false;
                    },
                    child: child ?? const SizedBox.shrink(),
                  ),
                  if (ai != null) AiBubble(controller: ai, navigatorKey: _navKey),
                ]),
              ),
            );
          },
        ),
        home: AnimatedSwitcher(
          duration: Duration(milliseconds: _desktopOs ? 200 : 550),
          switchInCurve: Curves.easeOut,
          child: !_splashDone
              ? ListenableBuilder(
                  key: const ValueKey('splash'),
                  listenable: session,
                  builder: (context, _) => OftobSplash(ready: !session.loading, onDone: () => setState(() => _splashDone = true)),
                )
              : KeyedSubtree(
                  key: ValueKey('app-$lang'), // til almashganda butun ekran yangi tilda qayta quriladi
                  child: ListenableBuilder(
                    listenable: session,
                    builder: (context, _) => session.platformIn ? PlatformHome(session: session) : session.signedIn ? HomeScreen(session: session) : LoginScreen(session: session),
                  ),
                ),
        ),
      ),
      ),
      ),
    );
  }
}
