import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

/// Klaviaturani yopish — butun ilova bo'ylab (har bir maydonga alohida yozish shart emas):
/// * bo'sh joyga bosilsa klaviatura yopiladi (iPhone raqam klaviaturasida «Enter» yo'q — shu yo'l bilan yopiladi);
/// * yangi oyna/varaq ochilganda klaviatura yopiladi ([KeyboardRouteObserver]) — aks holda u oynani berkitib qo'yardi;
/// * pastdagi «Yuborish/Saqlash» tugmalari klaviatura bilan birga tepaga ko'tariladi ([KeyboardLift]).
/// Klaviatura ustida alohida «Tayyor» tugmasi yo'q — u chatdagi yuborish tugmasini to'sib qo'yardi.
class KeyboardDismiss extends StatelessWidget {
  const KeyboardDismiss({super.key, required this.child});

  final Widget child;

  static void hide() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: hide,
      child: child,
    );
  }
}

/// Ekran pastidagi tugmalar paneli (Scaffold.bottomNavigationBar): klaviatura ochilganda uning ustiga ko'tariladi,
/// yopilganda joyiga tushadi — tugma hech qachon klaviatura ostida qolmaydi.
class KeyboardLift extends StatelessWidget {
  const KeyboardLift({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
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
