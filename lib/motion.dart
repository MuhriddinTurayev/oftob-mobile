import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: AnimatedOpacity(opacity: _down ? 0.88 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
      ),
    );
  }
}

/// Ekranga chiqqanda yumshoq ko'tarilib paydo bo'ladi; [index] bo'yicha ketma-ket (har biri ~55 ms kechikib).
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.dy = 22});

  final Widget child;
  final int index;
  final double dy;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 40 + widget.index.clamp(0, 14) * 55), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (context, child) => Opacity(opacity: _a.value, child: Transform.translate(offset: Offset(0, (1 - _a.value) * widget.dy), child: child)),
    );
  }
}

/// Raqam 0 dan (yoki oldingi qiymatdan) yangisiga silliq sanaladi.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.builder, this.duration = const Duration(milliseconds: 900)});

  final num value;
  final Widget Function(BuildContext context, num v) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => builder(context, v.round()),
    );
  }
}

/// Yuklanayotgan joyda yaltiraydigan «skelet» (spinner o'rniga).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 80, this.width, this.radius = 22});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.55);
    final hi = dark ? Colors.white.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.95);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(begin: Alignment(-1.4 + 2.8 * _c.value, -0.3), end: Alignment(-0.4 + 2.8 * _c.value, 0.3), colors: [base, hi, base]),
        ),
      ),
    );
  }
}

/// Pastki bo'limlar almashganda yumshoq o'tish (eskisi so'nadi, yangisi kichik siljib kiradi); har bo'lim holati saqlanadi.
class AnimatedTabs extends StatefulWidget {
  const AnimatedTabs({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<AnimatedTabs> createState() => _AnimatedTabsState();
}

class _AnimatedTabsState extends State<AnimatedTabs> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  int _prev = 0;

  @override
  void didUpdateWidget(covariant AnimatedTabs old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _prev = old.index;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        final animating = _c.isAnimating;
        final dir = widget.index >= _prev ? 1.0 : -1.0;
        return Stack(fit: StackFit.expand, children: [
          for (var i = 0; i < widget.children.length; i++)
            () {
              final active = i == widget.index;
              final leaving = animating && i == _prev && !active;
              final visible = active || leaving;
              final v = active ? _a.value : (leaving ? 1 - _a.value : 0.0);
              final dx = active ? (1 - _a.value) * 28 * dir : (leaving ? -_a.value * 18 * dir : 0.0);
              // bir xil o'ram zanjiri: bo'lim holati (ro'yxat joyi, kiritilgan matn) yo'qolmaydi
              return Offstage(
                offstage: !visible,
                child: TickerMode(
                  enabled: visible,
                  child: IgnorePointer(
                    ignoring: !active,
                    child: Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(dx, 0), child: widget.children[i])),
                  ),
                ),
              );
            }(),
        ]);
      },
    );
  }
}
