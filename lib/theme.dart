import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider, TickerCallback;
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'motion.dart';

/// Brend ranglari (logotip: to'q yashil + sariq) va «shisha» (glass) uslubi:
/// yumshoq gradient fon, yarim shaffof oq kartalar, suzuvchi pastki panel.
class Brand {
  static const green = Color(0xFF0B7A3B);
  static const greenDark = Color(0xFF064D26);
  static const amber = Color(0xFFF2A900);
  static const blue = Color(0xFF2F6FDE);
  static const purple = Color(0xFF7B5CE0);
  static const pink = Color(0xFFE0457B);
  static const teal = Color(0xFF14A39A);
  static const orange = Color(0xFFF27A1A);
}

/// Mavzu ranglari: yorug' va qorong'i rejimda o'qiladigan «siyoh» va shaffof belgi (pill) ranglari.
extension GlassColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Shisha kartadagi asosiy yirik matn rangi (yorug'da — to'q yashil, qorong'ida — och mint)
  Color get ink => isDark ? const Color(0xFFC6F3DA) : const Color(0xFF0A4D2A);

  /// Ikkinchi darajali matn (yorliqlar)
  Color get inkSoft => isDark ? const Color(0xFF9DBBAA) : const Color(0xFF3F5A4B);

  /// Karta ichidagi kichik belgi (chip) foni va chegarasi
  Color get pill => isDark ? Colors.white.withValues(alpha: 0.09) : Colors.white.withValues(alpha: 0.6);
  Color get pillBorder => isDark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.9);
}

/// Mavzu rejimi: Avto (telefon sozlamasi) / Kunduzgi / Tungi. Tanlov qurilmada saqlanadi.
class ThemeController {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);
  static const _store = FlutterSecureStorage();

  static Future<void> load() async {
    try {
      final v = await _store.read(key: 'theme_mode');
      mode.value = switch (v) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
    } catch (_) {}
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      await _store.write(key: 'theme_mode', value: m == ThemeMode.light ? 'light' : (m == ThemeMode.dark ? 'dark' : 'system'));
    } catch (_) {}
  }
}

/// Hamma sahifalar uchun umumiy «soat»: fon sharlari bir xil fazada sekin suzadi (sahifa almashganda ham sakramaydi).
class BackdropClock {
  static final ValueNotifier<double> t = ValueNotifier(0);
  static Ticker? _ticker;
  static Duration _last = Duration.zero;

  static void start() {
    if (_ticker != null) return;
    _ticker = const _Provider().createTicker((e) {
      if ((e - _last).inMilliseconds < 33) return; // ~30 kadr/s yetarli: fon sekin harakatlanadi
      _last = e;
      t.value = e.inMilliseconds / 1000.0;
    })
      ..start();
  }
}

class _Provider implements TickerProvider {
  const _Provider();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// Butun ilova foni: jonli — rangli yorug' sharlar sekin suzib yuradi; ustidagi shisha kartalar ularning rangini tovlantiradi.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final base = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark ? const [Color(0xFF0A1410), Color(0xFF0C1822), Color(0xFF0B1711)] : const [Color(0xFFD6EFE2), Color(0xFFE6EEFB), Color(0xFFF4F7E8)],
        ),
      ),
      child: const SizedBox.expand(),
    );
    Widget orbs(double t) {
      Alignment p(double ax, double ay, double bx, double by, double sx, double sy, double ph) => Alignment(ax + bx * math.cos(t * sx + ph), ay + by * math.sin(t * sy + ph * 1.3));
      return Stack(fit: StackFit.expand, children: [
        _Glow(alignment: p(0.95, -0.75, 0.30, 0.22, 0.11, 0.13, 0.0), color: dark ? const Color(0xFF2F63B8) : const Color(0xFF6EA8FF), radius: 0.95, alpha: dark ? 0.55 : 0.78),
        _Glow(alignment: p(-1.05, -0.05, 0.28, 0.55, 0.09, 0.07, 1.4), color: dark ? const Color(0xFF1C8556) : const Color(0xFF45D6A0), radius: 0.9, alpha: dark ? 0.6 : 0.72),
        _Glow(alignment: p(1.0, 0.55, 0.32, 0.40, 0.10, 0.08, 2.6), color: dark ? const Color(0xFF7255C8) : const Color(0xFFB59BFF), radius: 0.8, alpha: dark ? 0.45 : 0.66),
        _Glow(alignment: p(-0.8, 1.05, 0.42, 0.30, 0.06, 0.09, 3.7), color: dark ? const Color(0xFF9A7014) : const Color(0xFFFFC94A), radius: 0.9, alpha: dark ? 0.4 : 0.74),
        _Glow(alignment: p(0.1, -0.2, 0.55, 0.45, 0.05, 0.06, 4.8), color: dark ? const Color(0xFF1E5A7A) : const Color(0xFF7DE3FF), radius: 0.65, alpha: dark ? 0.32 : 0.6),
      ]);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent, systemNavigationBarDividerColor: Colors.transparent),
      child: Stack(fit: StackFit.expand, children: [
        base,
        if (still) orbs(0) else ValueListenableBuilder<double>(valueListenable: BackdropClock.t, builder: (_, t, _) => orbs(t)),
        child,
      ]),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.alignment, required this.color, required this.radius, required this.alpha});

  final Alignment alignment;
  final Color color;
  final double radius;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(center: alignment, radius: radius, colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)]),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Har bir sahifa o'z fonini oladi (o'tish animatsiyasida sahifalar bir-birining ichidan ko'rinmasin).
class GlassTransitions extends PageTransitionsBuilder {
  const GlassTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final page = GlassBackdrop(child: child);
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return const CupertinoPageTransitionsBuilder().buildTransitions<T>(route, context, animation, secondaryAnimation, page);
    }
    return const FadeForwardsPageTransitionsBuilder().buildTransitions<T>(route, context, animation, secondaryAnimation, page);
  }
}

/// Shisha karta: yarim shaffof oq, yupqa oq chegara, yumshoq soya. [blur] — orqasidagi narsani xira qiladi (suzuvchi panellar uchun).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding,
    this.margin,
    this.blur = true,
    this.onTap,
    this.onLongPress,
    this.tint,
    this.gradient,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool blur;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? tint;
  final Gradient? gradient;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final br = BorderRadius.circular(radius);
    final fill = tint;
    final fillGradient = gradient ?? (tint != null ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: dark ? [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.04)] : [Colors.white.withValues(alpha: blur ? 0.46 : 0.5), Colors.white.withValues(alpha: blur ? 0.16 : 0.2)]));
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        color: fillGradient == null ? fill : null,
        gradient: fillGradient,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.9), width: 1.1),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    if (blur) {
      body = BackdropFilter(filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26), child: body);
    }
    body = ClipRRect(borderRadius: br, child: body);
    Widget out = Container(
      margin: margin,
      decoration: shadow ? BoxDecoration(borderRadius: br, boxShadow: [BoxShadow(color: (dark ? Colors.black : const Color(0xFF1B4332)).withValues(alpha: dark ? 0.35 : 0.10), blurRadius: 22, offset: const Offset(0, 8))]) : null,
      child: body,
    );
    if (onTap != null || onLongPress != null) {
      out = Semantics(container: true, button: true, onTap: onTap, child: Tappable(onTap: onTap, onLongPress: onLongPress, child: out));
    }
    return out;
  }
}

/// Dumaloq shisha tugma (sarlavhadagi qo'ng'iroq, sinxronlash va h.k.)
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onTap, this.badge = 0, this.tooltip, this.size = 44});

  final Widget icon;
  final VoidCallback onTap;
  final int badge;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = SizedBox(
      width: size,
      height: size,
      child: Glass(
        radius: size / 2,
        blur: true,
        onTap: onTap,
        child: Center(child: Badge(isLabelVisible: badge > 0, label: Text(badge > 99 ? '99+' : '$badge'), child: icon)),
      ),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

class NavItem {
  const NavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Suzuvchi shisha pastki panel (HEMIS uslubi): tanlangan bo'lim yumshoq «tabletka» ichida.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.items, required this.index, required this.onTap});

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        child: SizedBox(
          height: 66,
          child: Glass(
            radius: 33,
            blur: true,
            padding: const EdgeInsets.all(6),
            child: LayoutBuilder(
              builder: (context, bc) {
                final w = bc.maxWidth / items.length;
                return Stack(children: [
                  // tanlangan bo'lim ostidagi «tabletka» — bo'limlar orasida sirpanib yuradi
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutBack,
                    left: w * index,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(27), color: cs.primary.withValues(alpha: 0.15))),
                  ),
                  Row(children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: Tappable(
                          scale: 0.9,
                          onTap: () => onTap(i),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            AnimatedScale(
                              scale: i == index ? 1.12 : 1,
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutBack,
                              child: Icon(i == index ? items[i].activeIcon : items[i].icon, size: 24, color: i == index ? cs.primary : cs.outline),
                            ),
                            const SizedBox(height: 2),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 250),
                              style: TextStyle(fontSize: 11, fontWeight: i == index ? FontWeight.w800 : FontWeight.w600, color: i == index ? cs.primary : cs.outline),
                              child: Text(tr(items[i].label), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        ),
                      ),
                  ]),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Rangli yumaloq kvadrat ichida ikonka (xizmat tugmalari, ro'yxat qatorlari)
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.color, this.size = 44, this.iconSize});

  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.10)]),
      ),
      child: Icon(icon, size: iconSize ?? size * 0.5, color: color),
    );
  }
}

class AppTheme {
  static ThemeData build(Brightness b) {
    final dark = b == Brightness.dark;
    final text = dark ? const Color(0xFFEAF2ED) : const Color(0xFF10201A);
    final card = dark ? const Color(0x14FFFFFF) : const Color(0x99FFFFFF); // yarim shaffof («shisha»)
    final solid = dark ? const Color(0xFF16221C) : const Color(0xFFF7FAF8); // dialog, varaq, menyu — shaffof emas
    final border = dark ? const Color(0x1FFFFFFF) : const Color(0x14123524);
    final primary = dark ? const Color(0xFF4CC38A) : Brand.green;
    final scheme = ColorScheme.fromSeed(seedColor: Brand.green, brightness: b).copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF05301A) : Colors.white,
      primaryContainer: dark ? const Color(0xFF14432A) : const Color(0xFFD3EEDD),
      onPrimaryContainer: dark ? const Color(0xFFD7F5E3) : const Color(0xFF05301A),
      secondaryContainer: dark ? const Color(0xFF1D4A31) : const Color(0xFFD3EEDD),
      onSecondaryContainer: dark ? const Color(0xFFD7F5E3) : const Color(0xFF05301A),
      tertiary: Brand.amber,
      surface: card,
      onSurface: text,
      surfaceContainerHighest: card,
      surfaceContainerHigh: solid,
      surfaceContainer: solid,
      surfaceContainerLow: solid,
      outline: dark ? const Color(0xFF9DB0A5) : const Color(0xFF5E6F66),
      outlineVariant: border,
    );
    OutlineInputBorder ob(Color c, double w) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent, // fon — GlassBackdrop (har sahifada)
      canvasColor: solid,
      visualDensity: VisualDensity.standard,
      textTheme: Typography.material2021(platform: TargetPlatform.android).black.apply(bodyColor: text, displayColor: text).copyWith(
            bodyLarge: TextStyle(fontSize: 15.5, color: text),
            bodyMedium: TextStyle(fontSize: 14, color: text),
            titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: text),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: text, letterSpacing: -0.3),
        iconTheme: IconThemeData(color: text),
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(color: card, elevation: 0, margin: const EdgeInsets.only(bottom: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: border))),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: primary.withValues(alpha: dark ? 0.32 : 0.20),
        side: BorderSide(color: border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        labelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: text),
        secondaryLabelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: dark ? const Color(0xFFC6F3DA) : const Color(0xFF075F2E)),
        checkmarkColor: dark ? const Color(0xFFC6F3DA) : const Color(0xFF075F2E),
        iconTheme: IconThemeData(color: text, size: 18),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0x12FFFFFF) : const Color(0x66FFFFFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: ob(border, 1),
        enabledBorder: ob(dark ? const Color(0x24FFFFFF) : const Color(0xF2FFFFFF), 1.2),
        focusedBorder: ob(primary, 1.6),
        labelStyle: TextStyle(color: scheme.outline),
        hintStyle: TextStyle(color: scheme.outline),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(56, 50)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? primary.withValues(alpha: 0.06) : primary.withValues(alpha: st.contains(WidgetState.pressed) ? 0.28 : 0.17)),
          foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? scheme.outline : (dark ? const Color(0xFF8FE5BB) : const Color(0xFF075F2E))),
          iconColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? scheme.outline : (dark ? const Color(0xFF8FE5BB) : const Color(0xFF075F2E))),
          side: WidgetStateProperty.resolveWith((st) => BorderSide(color: primary.withValues(alpha: st.contains(WidgetState.disabled) ? 0.1 : 0.34), width: 1.1)),
          overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.08)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(56, 50)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          backgroundColor: WidgetStateProperty.resolveWith((st) => (dark ? Colors.white : Colors.white).withValues(alpha: dark ? 0.06 : (st.contains(WidgetState.pressed) ? 0.8 : 0.5))),
          foregroundColor: WidgetStatePropertyAll(dark ? const Color(0xFF8FE5BB) : const Color(0xFF075F2E)),
          iconColor: WidgetStatePropertyAll(dark ? const Color(0xFF8FE5BB) : const Color(0xFF075F2E)),
          side: WidgetStatePropertyAll(BorderSide(color: dark ? border : Colors.white.withValues(alpha: 0.95), width: 1.4)),
          overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.08)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: dark ? const Color(0x33FFFFFF) : const Color(0xCCFFFFFF),
        foregroundColor: dark ? const Color(0xFF8FE5BB) : const Color(0xFF075F2E),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: primary.withValues(alpha: 0.35), width: 1.2)),
        extendedTextStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2)),
      dividerTheme: DividerThemeData(color: border, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary, linearTrackColor: primary.withValues(alpha: 0.14), circularTrackColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(color: solid, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
          backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? primary.withValues(alpha: dark ? 0.32 : 0.20) : (dark ? const Color(0x0FFFFFFF) : const Color(0x66FFFFFF))),
          foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? (dark ? const Color(0xFFC6F3DA) : const Color(0xFF075F2E)) : text),
          side: WidgetStateProperty.resolveWith((st) => BorderSide(color: st.contains(WidgetState.selected) ? primary.withValues(alpha: 0.5) : (dark ? border : const Color(0xCCFFFFFF)))),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: dark ? const Color(0xFF263530) : const Color(0xFF16261E), contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: solid, surfaceTintColor: Colors.transparent, showDragHandle: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
      dialogTheme: DialogThemeData(backgroundColor: solid, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: GlassTransitions(),
        TargetPlatform.iOS: GlassTransitions(),
      }),
    );
  }
}


/// Ro'yxat qatori: alohida shisha karta, orasida masofa (hamma ro'yxatlarda bir xil).
class GlassRow extends StatelessWidget {
  const GlassRow({super.key, required this.child, this.onTap, this.onLongPress, this.padding, this.tint, this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 5)});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Glass(blur: false, radius: 20, shadow: false, margin: margin, tint: tint, onTap: onTap, onLongPress: onLongPress, padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: child);
  }
}

/// Katta ma'lumot kartasi (kassa, pul, ish vaqti): yarim shaffof rangli shisha, ustida yumshoq yorug' doiralar.
/// Matn qora-yashil (ochiq fonda yaxshi o'qiladi), yashil to'ldirilgan blok emas.
class HeroGlass extends StatelessWidget {
  const HeroGlass({super.key, required this.child, this.tint = Brand.green, this.padding = const EdgeInsets.all(18), this.radius = 26, this.onTap});

  final Widget child;
  final Color tint;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Glass(
      radius: radius,
      blur: true,
      onTap: onTap,
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: dark ? 0.28 : 0.17), tint.withValues(alpha: dark ? 0.08 : 0.05), Colors.white.withValues(alpha: dark ? 0.04 : 0.46)]),
      child: Stack(children: [
        Positioned(right: -34, top: -46, child: IgnorePointer(child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, color: tint.withValues(alpha: 0.07))))),
        Positioned(left: -40, bottom: -64, child: IgnorePointer(child: Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.amber.withValues(alpha: 0.07))))),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}


/// Shaffof shisha suzuvchi tugma (orqasidagi ro'yxat xira ko'rinadi).
class GlassFab extends StatelessWidget {
  const GlassFab({super.key, required this.onPressed, required this.icon, required this.label});

  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = context.isDark ? const Color(0xFF8FE5BB) : const Color(0xFF075F2E);
    return Padding(
      padding: const EdgeInsets.only(bottom: 92),
      child: Tappable(
        onTap: onPressed,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(colors: [cs.primary.withValues(alpha: context.isDark ? 0.30 : 0.20), Colors.white.withValues(alpha: context.isDark ? 0.06 : 0.36)]),
                border: Border.all(color: cs.primary.withValues(alpha: 0.4), width: 1.1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: fg, size: 22),
                const SizedBox(width: 9),
                Text(tr(label), style: TextStyle(color: fg, fontSize: 14.5, fontWeight: FontWeight.w800, decoration: TextDecoration.none)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
