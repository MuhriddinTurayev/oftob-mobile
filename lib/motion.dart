import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lite.dart';

/// Bosilganda yumshoq kichrayadi va qo'yib yuborilganda qaytadi (iOS kabi), yengil titrash bilan.
class Tappable extends StatefulWidget {
  const Tappable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.965, this.haptic = true});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _down = false;
  bool _hover = false; // kompyuter: sichqoncha ustiga kelganda yengil ko'tariladi

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final clickable = widget.onTap != null || widget.onLongPress != null;
    final lite = LiteScope.of(context); // yengil rejim: faqat bosilganda kichrayish (arzon); hover kattalashish va shaffoflik qatlami yo'q
    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: clickable ? (_) => setState(() => _hover = true) : null,
      onExit: clickable ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : (_hover ? 1.02 : 1),
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: lite ? widget.child : AnimatedOpacity(opacity: _down ? 0.88 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
      ),
      ),
    );
  }
}

/// Kompyuterda: birinchi 8 element ketma-ket yumshoq paydo bo'ladi (shaffoflik + biroz siljish: arzon, GPU'ni yuklamaydi).
/// Telefonda va 8-elementdan keyin — darhol ko'rinadi (ro'yxat aylantirilganda kadr tushmasin).
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.dy = 22});

  final Widget child;
  final int index;
  final double dy;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late final Animation<double> _a;

  @override
  void initState() {
    super.initState();
    if (Lite.desktop && widget.index < 8) {
      final delay = widget.index * 45;
      final total = 260 + delay;
      _c = AnimationController(vsync: this, duration: Duration(milliseconds: total));
      _a = CurvedAnimation(parent: _c!, curve: Interval(delay / total, 1, curve: Curves.easeOutCubic));
      _c!.forward();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_c == null) return widget.child;
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero).animate(_a), child: widget.child),
    );
  }
}

/// Raqam darhol ko'rsatiladi (oldin 0 dan sanalardi — har ochilishda ~1 soniya qayta chizish).
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.builder, this.duration = Duration.zero});

  final num value;
  final Widget Function(BuildContext context, num v) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) => builder(context, value.round());
}

/// Yuklanayotgan joy uchun tinch «skelet» (yaltirash animatsiyasi yo'q).
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.height = 80, this.width, this.radius = 22});

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.6)),
    );
  }
}

/// Pastki bo'limlar: faqat BIRINCHI ochilganda quriladi (ilova ochilganda hammasi birdaniga yuklanmaydi) va bo'limlar orasida
/// o'tish bir lahzada — ikkita og'ir ekran bir vaqtda chizilmaydi (telefon qotmaydi). Har bo'lim holati (ro'yxat joyi) saqlanadi.
class AnimatedTabs extends StatefulWidget {
  const AnimatedTabs({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<AnimatedTabs> createState() => _AnimatedTabsState();
}

class _AnimatedTabsState extends State<AnimatedTabs> with SingleTickerProviderStateMixin {
  final Set<int> _built = {};
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: 1);
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didUpdateWidget(AnimatedTabs old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && Lite.desktop) _c.forward(from: 0.0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _built.add(widget.index);
    return Stack(fit: StackFit.expand, children: [
      for (var i = 0; i < widget.children.length; i++)
        if (_built.contains(i))
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(
              enabled: i == widget.index,
              // hamma bo'lim bir xil o'ramda (holati saqlanadi); animatsiya faqat faol bo'limga
              child: FadeTransition(
                opacity: i == widget.index ? Tween<double>(begin: 0.0, end: 1.0).animate(_fade) : kAlwaysCompleteAnimation,
                child: SlideTransition(
                  position: (i == widget.index ? Tween<Offset>(begin: const Offset(0, 0.012), end: Offset.zero).animate(_fade) : kAlwaysCompleteAnimation.drive(Tween<Offset>(begin: Offset.zero, end: Offset.zero))),
                  child: widget.children[i],
                ),
              ),
            ),
          ),
    ]);
  }
}
