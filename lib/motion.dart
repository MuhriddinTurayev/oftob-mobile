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
    return MouseRegion(
      cursor: (widget.onTap != null || widget.onLongPress != null) ? SystemMouseCursors.click : MouseCursor.defer,
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
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: AnimatedOpacity(opacity: _down ? 0.88 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
      ),
      ),
    );
  }
}

/// Oldin ro'yxat qatorlari ketma-ket «ko'tarilib» chiqardi — har ochilishda kadr tushirardi. Endi darhol ko'rinadi
/// (chaqiruvlar o'zgarmasligi uchun nom qoldirildi).
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.dy = 22});

  final Widget child;
  final int index;
  final double dy;

  @override
  Widget build(BuildContext context) => child;
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

class _AnimatedTabsState extends State<AnimatedTabs> {
  final Set<int> _built = {};

  @override
  Widget build(BuildContext context) {
    _built.add(widget.index);
    return Stack(fit: StackFit.expand, children: [
      for (var i = 0; i < widget.children.length; i++)
        if (_built.contains(i))
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(enabled: i == widget.index, child: widget.children[i]),
          ),
    ]);
  }
}
