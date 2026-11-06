import 'package:flutter/material.dart' hide Text;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home.dart';
import 'screens/login.dart';
import 'session.dart';
import 'l10n.dart';
import 'assistant.dart';
import 'splash.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await L.load(); // saqlangan (yoki telefon) tili birinchi kadrdan to'g'ri bo'lsin
  BackdropClock.start();
  await ThemeController.load();
  final session = Session()..restore();
  L.notifier.addListener(session.refreshMe); // til o'zgarsa — rol nomi kabi server matnlari yangi tilda olinadi
  runApp(OftobApp(session: session));
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
  AssistantController? _ai;

  /// AI yordamchi har kirgan hisob uchun alohida (chiqqanda o'chadi)
  AssistantController? _assistant() {
    if (!session.signedIn || session.api == null) {
      _ai?.dispose();
      _ai = null;
      return null;
    }
    return _ai ??= AssistantController(session);
  }

  Session get session => widget.session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: L.notifier,
      builder: (context, lang, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.mode,
        builder: (context, tm, _) => MaterialApp(
        title: 'Oftob Building',
        navigatorKey: _navKey,
        navigatorObservers: [ModalWatcher()],
        debugShowCheckedModeBanner: false,
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
            final ai = _splashDone ? _assistant() : null;
            return Stack(children: [
              child ?? const SizedBox.shrink(),
              if (ai != null) AiBubble(controller: ai, navigatorKey: _navKey),
            ]);
          },
        ),
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 550),
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
                    builder: (context, _) => session.signedIn ? HomeScreen(session: session) : LoginScreen(session: session),
                  ),
                ),
        ),
      ),
      ),
    );
  }
}
