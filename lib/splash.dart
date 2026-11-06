import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Ochilish ekrani: kran va binolar emblemasi pastdan «ko'tarilib» chiqadi, quyosh yonib turadi,
/// OFTOB harflari birin-ketin paydo bo'ladi, BUILDING yozuvi kengayib o'rnashadi, ostida yuklanish chizig'i.
class OftobSplash extends StatefulWidget {
  const OftobSplash({super.key, required this.onDone, this.ready = true});

  /// Animatsiya tugagach va [ready] bo'lganda chaqiriladi
  final VoidCallback onDone;
  final bool ready;

  @override
  State<OftobSplash> createState() => _OftobSplashState();
}

class _OftobSplashState extends State<OftobSplash> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_maybeDone);
  }

  @override
  void didUpdateWidget(covariant OftobSplash old) {
    super.didUpdateWidget(old);
    _maybeDone();
  }

  void _maybeDone() {
    if (_fired || !widget.ready || _c.status != AnimationStatus.completed) return;
    _fired = true;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _loop.dispose();
    super.dispose();
  }

  double _seg(double a, double b, [Curve curve = Curves.easeOutCubic]) => curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  static const _word = 'OFTOB';
  Color get _ink => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFC6F3DA) : const Color(0xFF0B4D2A);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final logoW = math.min(w * 0.56, 250.0);
    return GlassBackdrop(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: Listenable.merge([_c, _loop]),
          builder: (context, _) {
            final rise = _seg(0.02, 0.42, Curves.easeOutCubic); // emblema ko'tariladi
            final pop = _seg(0.02, 0.5, Curves.easeOutBack);
            final sun = _seg(0.30, 0.62, Curves.easeOutQuart);
            final lines = _seg(0.62, 0.84, Curves.easeOutCubic);
            final building = _seg(0.58, 0.88, Curves.easeOutCubic);
            final tag = _seg(0.80, 1.0, Curves.easeOut);
            final float = math.sin(_loop.value * 2 * math.pi) * 3; // emblema yengil tebranadi
            return Stack(children: [
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: logoW * 1.5,
                    height: logoW * 0.78 * 1.12,
                    child: Stack(alignment: Alignment.center, children: [
                      // quyosh nuri
                      Opacity(
                        opacity: sun * 0.9,
                        child: Container(
                          width: logoW * 1.45 * (0.7 + 0.3 * sun),
                          height: logoW * 1.45 * (0.7 + 0.3 * sun),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [Brand.amber.withValues(alpha: 0.38), Brand.amber.withValues(alpha: 0.0)]),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, (1 - rise) * 40 + float),
                        child: Transform.scale(
                          scale: 0.82 + 0.18 * pop,
                          child: Opacity(
                            opacity: rise.clamp(0.0, 1.0),
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                heightFactor: (0.05 + 0.95 * rise).clamp(0.0, 1.0),
                                child: Image.asset('assets/logo.png', width: logoW, filterQuality: FilterQuality.high),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  // OFTOB — harflar birin-ketin
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < _word.length; i++) _letter(i),
                  ]),
                  const SizedBox(height: 8),
                  // — BUILDING —
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 34 * lines, height: 3, decoration: BoxDecoration(color: Brand.amber, borderRadius: BorderRadius.circular(2))),
                    SizedBox(width: 12 * lines),
                    Opacity(
                      opacity: building,
                      child: Text(
                        'BUILDING',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _ink.withValues(alpha: 0.85), letterSpacing: 16 - 10 * building, decoration: TextDecoration.none),
                      ),
                    ),
                    SizedBox(width: 12 * lines),
                    Container(width: 34 * lines, height: 3, decoration: BoxDecoration(color: Brand.amber, borderRadius: BorderRadius.circular(2))),
                  ]),
                ]),
              ),
              // pastda: yuklanish chizig'i
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 56,
                child: Opacity(
                  opacity: tag,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 120,
                      height: 4,
                      decoration: BoxDecoration(color: Brand.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Align(
                          alignment: Alignment(-1 + 2 * _loop.value * 1.6 - 0.6, 0),
                          child: FractionallySizedBox(
                            widthFactor: 0.36,
                            child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Brand.green.withValues(alpha: 0), Brand.green, Brand.amber]))),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _letter(int i) {
    final t = _seg(0.34 + i * 0.045, 0.34 + i * 0.045 + 0.22, Curves.easeOutBack);
    final o = _seg(0.34 + i * 0.045, 0.34 + i * 0.045 + 0.14, Curves.easeOut);
    return Opacity(
      opacity: o,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 26),
        child: Text(
          _word[i],
          style: TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: _ink, letterSpacing: 3, height: 1.05, decoration: TextDecoration.none),
        ),
      ),
    );
  }
}
