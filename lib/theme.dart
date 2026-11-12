import 'dart:ui' as ui show Image, PictureRecorder;
import 'dart:ui' show ImageFilter;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider, TickerCallback;
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'lite.dart';
import 'motion.dart';

/// Brend ranglari (logotip: to'q yashil + sariq) va «shisha» (glass) uslubi:
/// yumshoq gradient fon, yarim shaffof oq kartalar, suzuvchi pastki panel.
class Brand {
  /// Asosiy rang (nomi tarixiy: avval yashil edi) — yangi logodagi ko'k
  static const green = Color(0xFF2563EB);
  static const greenDark = Color(0xFF1E3A8A);
  static const amber = Color(0xFFF2A900);
  static const blue = Color(0xFF3B82F6);
  static const purple = Color(0xFF6366F1);
  static const pink = Color(0xFFE0457B);
  static const teal = Color(0xFF0EA5E9);
  static const orange = Color(0xFFF27A1A);

  /// Logodagi to'q ko'k (yorug' fondagi matn va belgilar)
  static const navy = Color(0xFF11265C);

  /// Logo: yorug' fonda — to'q ko'k, tungi rejimda — oq
  static String logo(bool dark) => dark ? 'assets/brand/logo_white.png' : 'assets/brand/logo_navy.png';
  static String mark(bool dark) => dark ? 'assets/brand/mark_white.png' : 'assets/brand/mark_navy.png';
}

/// Mavzu ranglari: yorug' va qorong'i rejimda o'qiladigan «siyoh» va shaffof belgi (pill) ranglari.
extension GlassColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Shisha kartadagi asosiy yirik matn rangi (yorug'da — to'q ko'k, qorong'ida — och havorang)
  Color get ink => isDark ? const Color(0xFFE3ECFF) : const Color(0xFF0F2350);

  /// Ikkinchi darajali matn (yorliqlar)
  Color get inkSoft => isDark ? const Color(0xFFA3B4D6) : const Color(0xFF4A5B80);

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

/// Butun ilova foni: yumshoq gradient ustida rangli yorug' dog'lar; ustidagi shisha kartalar ularning rangini tovlantiradi.
///
/// TEZLIK: fon bir marta kichik rasmga chiziladi va keyin har kadrda faqat shu bitta rasm cho'ziladi.
/// Oldin har kadrda 6 ta to'liq ekranli gradient qatlami qayta chizilardi (iPhone'dagi Impeller'da RepaintBoundary
/// rasmni saqlab qolmaydi) — 120 Hz ekranda bu GPU'ni to'ldirib, ro'yxat siljiganda kadrlar tushib qolardi.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  static final Map<String, ui.Image> _cache = {};

  /// Oxirgi chizilgan fon rasmi (tun/kun) — «xira shisha» panellar o'z ostidagi fon bo'lagini shundan oladi
  static final Map<bool, ui.Image> latest = {};

  static List<Color> _base(bool dark) => dark ? const [Color(0xFF070D1C), Color(0xFF0B1631), Color(0xFF09122A)] : const [Color(0xFFC9D7EE), Color(0xFFDCE6F6), Color(0xFFEEF3FB)];

  /// (markaz, rang, radius, shaffoflik)
  static List<(Alignment, Color, double, double)> _glows(bool dark) => [
        (const Alignment(1.25, -0.75), dark ? const Color(0xFF1D4ED8) : const Color(0xFF7DB0FF), 0.95, dark ? 0.5 : 0.62),
        (const Alignment(-1.0, 0.48), dark ? const Color(0xFF1E3A8A) : const Color(0xFFA9C7FF), 0.9, dark ? 0.55 : 0.6),
        (const Alignment(0.73, 0.46), dark ? const Color(0xFF3B4FD8) : const Color(0xFFBFD6FF), 0.8, dark ? 0.35 : 0.62),
        (const Alignment(-1.16, 0.75), dark ? const Color(0xFF0C4A8A) : const Color(0xFFE6EEFF), 0.9, dark ? 0.4 : 0.8),
        (const Alignment(0.15, -0.22), dark ? const Color(0xFF0E7490) : const Color(0xFF9FD0FF), 0.65, dark ? 0.22 : 0.42),
      ];

  static void _paint(Canvas c, Rect rect, bool dark) {
    c.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _base(dark)).createShader(rect));
    for (final g in _glows(dark)) {
      c.drawRect(rect, Paint()..shader = RadialGradient(center: g.$1, radius: g.$3, colors: [g.$2.withValues(alpha: g.$4), g.$2.withValues(alpha: 0)]).createShader(rect));
    }
  }

  /// Fon rasmi (ekranning yarim o'lchamida — gradient silliq, kattalashtirilganda farqi ko'rinmaydi). Xato bo'lsa null.
  static ui.Image? _image(bool dark, Size size) {
    if (!size.isFinite || size.isEmpty) return null;
    final w = (size.width / 2).ceil(), h = (size.height / 2).ceil();
    final key = '$dark:$w:$h';
    final hit = _cache[key];
    if (hit != null) {
      latest[dark] = hit;
      return hit;
    }
    try {
      final rec = ui.PictureRecorder();
      _paint(Canvas(rec), Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), dark);
      final pic = rec.endRecording();
      final img = pic.toImageSync(w, h);
      pic.dispose();
      if (_cache.length >= 6) _cache.remove(_cache.keys.first); // eski o'lchamlar (burilish va h.k.)
      latest[dark] = img;
      return _cache[key] = img;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lite = LiteScope.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent, systemNavigationBarDividerColor: Colors.transparent),
      child: Stack(fit: StackFit.expand, children: [
        if (lite)
          ColoredBox(color: _base(dark)[1], child: const SizedBox.expand()) // yengil rejim: tekis fon
        else
        RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, bc) => CustomPaint(painter: _BackdropPainter(dark, _image(dark, bc.biggest)), child: const SizedBox.expand()),
          ),
        ),
        child,
      ]),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.dark, this.image);

  final bool dark;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final img = image;
    if (img == null) {
      GlassBackdrop._paint(canvas, dst, dark); // zaxira: to'g'ridan-to'g'ri chizish
      return;
    }
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.dark != dark || old.image != image;
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
    this.blur = false,
    this.onTap,
    this.onLongPress,
    this.tint,
    this.gradient,
    this.shadow = false,
    this.clip = false,
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

  /// Ichidagi narsa burchakdan chiqib ketsa (masalan, HeroGlass doiralari). Oddiy kartada kesish yo'q — har bir kesish GPU'ga qimmat.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lite = LiteScope.of(context);
    final br = BorderRadius.circular(radius);
    // yengil rejim: tekis rang (gradient, xira qilish, soya, kesish yo'q) — kuchsiz video-kartada ham silliq
    final fill = lite ? (tint ?? (dark ? const Color(0xE61A2542) : const Color(0xE6FFFFFF))) : tint;
    final fillGradient = lite ? null : gradient ?? (tint != null ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: dark ? const [Color(0xB31A2542), Color(0x99111A33)] : [Colors.white.withValues(alpha: blur ? 0.6 : 0.62), Colors.white.withValues(alpha: blur ? 0.26 : 0.3)]));
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        color: fillGradient == null ? fill : null,
        gradient: fillGradient,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.9), width: 1.1),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    if (blur && !lite) {
      body = BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: body);
    }
    if ((blur && !lite) || clip) body = ClipRRect(borderRadius: br, child: body);
    Widget out = Container(
      margin: margin,
      decoration: shadow && !lite ? BoxDecoration(borderRadius: br, boxShadow: [BoxShadow(color: (dark ? Colors.black : const Color(0xFF1E3A8A)).withValues(alpha: dark ? 0.35 : 0.12), blurRadius: 18, offset: const Offset(0, 7))]) : null,
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
        blur: false,
        onTap: onTap,
        child: Center(child: Badge(isLabelVisible: badge > 0, label: Text(badge > 99 ? '99+' : '$badge'), child: icon)),
      ),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}


/// Ilovaning barcha sahifa yo'nalishi. Telefonda — oddiy sahifa. Kompyuter qobig'i ichida (yon menyu bor, oyna keng) —
/// YON PANEL: asosiy bo'lim (Bosh, Yana, Lidlar…) ko'rinib turadi, ochilgan sahifa o'ng tomonda qulay kenglikdagi panelda chiqadi;
/// panel tashqarisi bosilsa yopiladi. Boshqa joyda (kirish oynalari) — markazda qulay kenglikda.
class DeskRoute<T> extends MaterialPageRoute<T> {
  DeskRoute({required super.builder, super.settings, super.fullscreenDialog, this.full = false});

  /// Katta sahifa (3D, xarita): kompyuterda yon panelda emas, butun ish maydonida ochiladi
  final bool full;

  bool? _panelCache;

  /// Yon panelmi: faqat kompyuter qobig'i ichida, boshlang'ich bo'lmagan sahifa va oyna yetarli keng bo'lganda
  bool get isPanel {
    final nav = navigator;
    if (nav == null) return _panelCache ?? false;
    return _panelCache ??= !full && !isFirst && DeskShell.inside(nav.context) && MediaQuery.sizeOf(nav.context).width >= DesktopPageTransitions.wideFrom;
  }

  @override
  bool get opaque => !isPanel;

  @override
  Color? get barrierColor => isPanel ? const Color(0x47000000) : null;

  @override
  bool get barrierDismissible => isPanel;

  @override
  String? get barrierLabel => isPanel ? 'Yopish' : null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);
}

/// Kompyuter qobig'i (yon menyu + ichki navigator) ichida ekanligini bildiradi: ichkarida ochilgan sahifalar o'z fonini chizmaydi
/// (fon butun oyna uchun bitta — yon menyu va sahifalar ostida uzluksiz).
class DeskShell extends InheritedWidget {
  const DeskShell({super.key, required super.child});

  static bool inside(BuildContext context) => context.getInheritedWidgetOfExactType<DeskShell>() != null;

  @override
  bool updateShouldNotify(DeskShell old) => false;
}

/// Sahifa o'tishlari (Windows/Linux/macOS): yon panel o'ngdan suzib chiqadi; boshqa sahifalar markazda qulay kenglikda.
class DesktopPageTransitions extends PageTransitionsBuilder {
  const DesktopPageTransitions();

  static const double maxWidth = 920;
  static const double wideFrom = 900;

  static bool _isFull(PageRoute<dynamic> r) {
    final x = r;
    return x is DeskRoute && x.full;
  }

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final inShell = DeskShell.inside(context);
    final wide = MediaQuery.sizeOf(context).width >= wideFrom && !route.isFirst && !_isFull(route);
    // yon panel
    final r = route;
    if (r is DeskRoute<T> && r.isPanel) {
      return LayoutBuilder(builder: (context, bc) {
        final w = bc.maxWidth.isFinite ? (bc.maxWidth * 0.56).clamp(560.0, 780.0).clamp(0.0, bc.maxWidth) : 680.0;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero).animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: SizedBox(
                width: w,
                height: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(30)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.55 : 0.22), blurRadius: 40, offset: const Offset(-8, 0))],
                  ),
                  child: ClipRRect(borderRadius: const BorderRadius.horizontal(left: Radius.circular(30)), child: GlassBackdrop(child: child)),
                ),
              ),
            ),
          ),
        );
      });
    }
    // oddiy sahifa: kompyuterda markazda qulay kenglikda; qobiq tashqarisida o'z fonini oladi
    Widget page = wide ? Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxWidth), child: child)) : child;
    if (!inShell) page = GlassBackdrop(child: page);
    return FadeTransition(opacity: curved, child: page);
  }
}

class NavItem {
  const NavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Pastki panel uchun qisqa nomlar (to'liq nom sahifa sarlavhasida qoladi)
const _navShort = {
  'ru': {'Davomat': 'Явка'},
};

String navLabel(String label) => _navShort[L.code]?[label] ?? tr(label);

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
          child: FrostPanel(
            radius: 33,
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
                              // uzun so'z kesilmasin («Посещаем…»): pastki panel uchun qisqa nom, baribir sig'masa — kichrayadi
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: FittedBox(fit: BoxFit.scaleDown, child: Text(navLabel(items[i].label), maxLines: 1, softWrap: false)),
                              ),
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

  /// Brend ranglari ko'k oilasiga keltiriladi (bir xil, toza ko'rinish); semantik ranglar (yashil — kirim, qizil — chiqim) o'zgarmaydi
  static Color tone(Color c) => switch (c.toARGB32()) {
        0xFF2563EB || 0xFF3B82F6 => const Color(0xFF3478F6),
        0xFF0EA5E9 => const Color(0xFF1EA7E8),
        0xFF6366F1 => const Color(0xFF5B6CF2),
        0xFFE0457B => const Color(0xFF7C6CF2),
        0xFFF2A900 => const Color(0xFF4F8DF7),
        0xFFF27A1A => const Color(0xFF3E7FEF),
        _ => c,
      };

  static Color _shade(Color c, double l) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + l).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = tone(color);
    final r = BorderRadius.circular(size * 0.3);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_shade(c, dark ? 0.08 : 0.16), c, _shade(c, -0.14)]),
        // yumshoq rangli nur (plitka «suzib» turadi)
        boxShadow: [BoxShadow(color: c.withValues(alpha: dark ? 0.28 : 0.34), blurRadius: size * 0.32, offset: Offset(0, size * 0.1))],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: r,
        // yuqoridagi yaltiroq yorug'lik (shisha/3D)
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Colors.white.withValues(alpha: dark ? 0.22 : 0.34), Colors.white.withValues(alpha: 0)]),
        border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.16 : 0.32), width: 0.8),
      ),
      child: Icon(icon, size: iconSize ?? size * 0.5, color: Colors.white),
    );
  }
}

class AppTheme {
  static ThemeData build(Brightness b) {
    final dark = b == Brightness.dark;
    final text = dark ? const Color(0xFFE8EEFC) : const Color(0xFF0E1B3D);
    final card = dark ? const Color(0xA61A2542) : const Color(0x99FFFFFF); // yarim shaffof («shisha»)
    final solid = dark ? const Color(0xFF121A31) : const Color(0xFFF5F8FE); // dialog, varaq, menyu — shaffof emas
    final border = dark ? const Color(0x1FFFFFFF) : const Color(0x161E3A8A);
    final primary = dark ? const Color(0xFF6EA8FF) : Brand.green;
    final onTint = dark ? const Color(0xFFBFD6FF) : const Color(0xFF1D4ED8); // ko'k fondagi matn
    final scheme = ColorScheme.fromSeed(seedColor: Brand.green, brightness: b).copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF0B1E4D) : Colors.white,
      primaryContainer: dark ? const Color(0xFF1E3A8A) : const Color(0xFFDBE7FF),
      onPrimaryContainer: dark ? const Color(0xFFDDE8FF) : const Color(0xFF0B1E4D),
      secondaryContainer: dark ? const Color(0xFF1E3570) : const Color(0xFFDBE7FF),
      onSecondaryContainer: dark ? const Color(0xFFDDE8FF) : const Color(0xFF0B1E4D),
      tertiary: Brand.amber,
      surface: card,
      onSurface: text,
      surfaceContainerHighest: card,
      surfaceContainerHigh: solid,
      surfaceContainer: solid,
      surfaceContainerLow: solid,
      outline: dark ? const Color(0xFF98A9CB) : const Color(0xFF5B6886),
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
        secondaryLabelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: onTint),
        checkmarkColor: onTint,
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
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled)
              ? (dark ? Colors.white.withValues(alpha: 0.06) : const Color(0x332563EB))
              : (st.contains(WidgetState.pressed) ? (dark ? const Color(0xFF2B63D9) : const Color(0xFF1D4ED8)) : (dark ? const Color(0xFF3274F0) : const Color(0xFF2F6BF0)))),
          foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? scheme.outline : Colors.white),
          iconColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? scheme.outline : Colors.white),
          side: const WidgetStatePropertyAll(BorderSide.none),
          overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.1)),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(56, 50)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          backgroundColor: WidgetStateProperty.resolveWith((st) => Colors.white.withValues(alpha: dark ? (st.contains(WidgetState.pressed) ? 0.12 : 0.07) : (st.contains(WidgetState.pressed) ? 0.95 : 0.82))),
          foregroundColor: WidgetStatePropertyAll(onTint),
          iconColor: WidgetStatePropertyAll(onTint),
          side: WidgetStatePropertyAll(BorderSide(color: dark ? const Color(0x2EFFFFFF) : Colors.white, width: 1.2)),
          overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.08)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: dark ? const Color(0x33FFFFFF) : const Color(0xCCFFFFFF),
        foregroundColor: onTint,
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
          foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? onTint : text),
          side: WidgetStateProperty.resolveWith((st) => BorderSide(color: st.contains(WidgetState.selected) ? primary.withValues(alpha: 0.5) : (dark ? border : const Color(0xCCFFFFFF)))),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: dark ? const Color(0xFF223156) : const Color(0xFF13234A), contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: solid, surfaceTintColor: Colors.transparent, showDragHandle: true, constraints: const BoxConstraints(maxWidth: 620), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
      dialogTheme: DialogThemeData(backgroundColor: solid, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: GlassTransitions(),
        TargetPlatform.iOS: GlassTransitions(),
        TargetPlatform.windows: DesktopPageTransitions(),
        TargetPlatform.linux: DesktopPageTransitions(),
        TargetPlatform.macOS: DesktopPageTransitions(),
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
      blur: false,
      clip: true,
      shadow: true,
      onTap: onTap,
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: dark ? [Color.alphaBlend(tint.withValues(alpha: 0.22), const Color(0xB81A2542)), Color.alphaBlend(tint.withValues(alpha: 0.07), const Color(0xA8141D36)), const Color(0x9E10182E)] : [tint.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.4)]),
      child: Stack(children: [
        Positioned(right: -34, top: -46, child: IgnorePointer(child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, color: tint.withValues(alpha: 0.07))))),
        Positioned(left: -40, bottom: -64, child: IgnorePointer(child: Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7DB0FF).withValues(alpha: 0.10))))),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}


/// Pastki suzuvchi panel egallagan joy: bosh sahifaning tablarida bor (panel ostida kontent o'tadi), «Yana»dan ochilgan to'liq sahifalarda yo'q.
/// Suzuvchi tugmalar va ro'yxatlarning pastki bo'sh joyi shunga qarab moslashadi.
class NavInset extends InheritedWidget {
  const NavInset({super.key, required this.inset, required super.child});

  final double inset;

  static const double bar = 92;

  /// Panel bor joyda [bar], yo'q joyda 0
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NavInset>()?.inset ?? 0;

  /// Ro'yxat oxiridagi bo'sh joy: oxirgi karta pastki panel va suzuvchi AI tugmasidan YUQORIGA chiqa olsin (bosish qulay bo'lsin)
  static double listBottom(BuildContext context) {
    final nav = of(context);
    return nav > 0 ? nav + 96 : 96 + MediaQuery.paddingOf(context).bottom;
  }

  @override
  bool updateShouldNotify(NavInset old) => old.inset != inset;
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
    final fg = context.isDark ? const Color(0xFFBFD6FF) : const Color(0xFF1D4ED8);
    return Padding(
      padding: EdgeInsets.only(bottom: NavInset.of(context) + 6),
      child: Tappable(
        onTap: onPressed,
        // xira qilish (BackdropFilter) yo'q: ro'yxat ostida siljiganda har kadrda butun ekranni nusxalardi
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(colors: context.isDark ? [Color.alphaBlend(cs.primary.withValues(alpha: 0.32), const Color(0xF0121A31)), const Color(0xEE121A31)] : [Color.alphaBlend(cs.primary.withValues(alpha: 0.16), const Color(0xF5FFFFFF)), const Color(0xF0FFFFFF)]),
            border: Border.all(color: cs.primary.withValues(alpha: 0.4), width: 1.1),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.08), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: 9),
            Text(tr(label), style: TextStyle(color: fg, fontSize: 14.5, fontWeight: FontWeight.w800, decoration: TextDecoration.none)),
          ]),
        ),
      ),
    );
  }
}


/// «Xira shisha» panel (pastki menyu): ostidagi fonning silliq rangli bo'lagi + yarim shaffof qatlam + yupqa chegara.
/// Haqiqiy BackdropFilter iPhone'da har kadrda butun ekranni qayta ishlaydi (qotish va qizish) — bu esa bitta tayyor rasmni
/// chizadi, ko'rinishi esa xira shishaga o'xshaydi: fon ranglari ko'rinadi, ortidagi matn esa xalaqit bermaydi.
class FrostPanel extends StatelessWidget {
  const FrostPanel({super.key, required this.radius, this.padding = EdgeInsets.zero, required this.child});

  final double radius;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => _FrostBox(radius: radius, dark: context.isDark, screen: MediaQuery.sizeOf(context), child: Padding(padding: padding, child: child));
}

class _FrostBox extends SingleChildRenderObjectWidget {
  const _FrostBox({required this.radius, required this.dark, required this.screen, required super.child});

  final double radius;
  final bool dark;
  final Size screen;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFrost(radius, dark, screen);

  @override
  void updateRenderObject(BuildContext context, _RenderFrost r) {
    r
      ..radius = radius
      ..dark = dark
      ..screen = screen;
  }
}

class _RenderFrost extends RenderProxyBox {
  _RenderFrost(this._radius, this._dark, this._screen);

  double _radius;
  bool _dark;
  Size _screen;

  set radius(double v) {
    if (v == _radius) return;
    _radius = v;
    markNeedsPaint();
  }

  set dark(bool v) {
    if (v == _dark) return;
    _dark = v;
    markNeedsPaint();
  }

  set screen(Size v) {
    if (v == _screen) return;
    _screen = v;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = context.canvas;
    final rect = offset & size;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(_radius));
    // soya
    c.drawRRect(rr.shift(const Offset(0, 6)), Paint()
      ..color = (_dark ? Colors.black : const Color(0xFF1E3A8A)).withValues(alpha: _dark ? 0.35 : 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    c.save();
    c.clipRRect(rr);
    final img = GlassBackdrop.latest[_dark];
    if (img != null) {
      // ekrandagi o'z joyidagi fon bo'lagi
      final g = localToGlobal(Offset.zero);
      final dst = Rect.fromLTWH(offset.dx - g.dx, offset.dy - g.dy, _screen.width, _screen.height);
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.medium);
    }
    // xira qatlam: tunda to'q, kunduzi oq — matn va ikonkalar aniq o'qiladi
    c.drawRect(rect, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _dark ? const [Color(0xBA121A31), Color(0xC80C1326)] : const [Color(0xBFFFFFFF), Color(0xA8FFFFFF)],
      ).createShader(rect));
    c.restore();
    c.drawRRect(rr.deflate(0.55), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = _dark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.9));
    super.paint(context, offset);
  }
}
