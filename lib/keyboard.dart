import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'l10n.dart';

/// Klaviaturani yopish — butun ilova bo'ylab (har bir maydonga alohida yozish shart emas):
/// * bo'sh joyga bosilsa klaviatura yopiladi;
/// * klaviatura ochiq turganda uning ustida «Tayyor» tugmasi chiqadi — iPhone'ning raqam klaviaturasida
///   «Enter/Готово» tugmasi yo'q, usiz summa kiritilgach klaviatura yopilmay qolardi;
/// * yangi oyna/varaq ochilganda klaviatura yopiladi ([KeyboardRouteObserver]) — aks holda u oynani berkitib qo'yardi.
class KeyboardDismiss extends StatelessWidget {
  const KeyboardDismiss({super.key, required this.child});

  final Widget child;

  static void hide() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(children: [
      GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: hide,
        child: child,
      ),
      if (kb > 80)
        Positioned(
          right: 10,
          bottom: kb + 6,
          child: _DoneButton(onTap: hide),
        ),
    ]);
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF2A3430) : Colors.white,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const ValueKey('kb-done'),
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.keyboard_hide_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(tr('Tayyor'), style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
          ]),
        ),
      ),
    );
  }
}

/// Yangi sahifa, varaq yoki oyna ochilganda klaviaturani yopadi (masalan, «Chek surati» tanlash varag'i klaviatura ostida qolmasin)
class KeyboardRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) FocusManager.instance.primaryFocus?.unfocus();
  }
}
