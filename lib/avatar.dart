import 'package:flutter/material.dart';

import 'session.dart';
import 'theme.dart';

/// Xodim rasmi: rasm bo'lsa — token bilan yuklanadi; bo'lmasa yoki xato bo'lsa — bosh harflar bilan gradient doira.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.session, required this.name, this.size = 46, this.url, this.ring = true});

  final Session session;
  final String name;
  final double size;

  /// Boshqa xodimning rasmi uchun (bo'sh — joriy foydalanuvchi)
  final String? url;
  final bool ring;

  static String initials(String name) {
    final p = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    return (p.first[0] + (p.length > 1 ? p[1][0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final u = url ?? session.photoUrl;
    final fallback = Center(child: Text(initials(name), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36, decoration: TextDecoration.none)));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.green, Color(0xFF16A05A)]),
        border: ring ? Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2) : null,
        boxShadow: ring ? [BoxShadow(color: Brand.green.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 5))] : null,
      ),
      child: ClipOval(
        child: u == null
            ? fallback
            : Image.network(
                u,
                width: size,
                height: size,
                fit: BoxFit.cover,
                headers: session.api?.authHeaders,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (_, child, p) => p == null ? child : fallback,
              ),
      ),
    );
  }
}
