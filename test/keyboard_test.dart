import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oftob_mobile/keyboard.dart';

/// Klaviatura: pastdagi tugma klaviatura ustiga ko'tariladi, bo'sh joyga bosish va yangi oyna ochilganda yopiladi; «Tayyor» tugmasi yo'q
void main() {
  Widget app({required double kb, required FocusNode node}) => MaterialApp(
        navigatorObservers: [KeyboardRouteObserver()],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.only(bottom: kb)),
          child: KeyboardDismiss(child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(children: [
              TextField(focusNode: node, keyboardType: TextInputType.number),
              const SizedBox(height: 150, width: 300, child: ColoredBox(color: Colors.white)),
              ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox(height: 100, child: Text('sheet'))),
                child: const Text('open'),
              ),
            ]),
            bottomNavigationBar: KeyboardLift(
              child: SafeArea(child: SizedBox(height: 52, child: FilledButton(key: const ValueKey('send'), onPressed: () {}, child: const Text('Yuborish')))),
            ),
          ),
        ),
      );

  testWidgets('pastdagi tugma klaviatura ustiga chiqadi', (t) async {
    final node = FocusNode();
    await t.pumpWidget(app(kb: 300, node: node));
    await t.pumpAndSettle();
    final screen = t.view.physicalSize.height / t.view.devicePixelRatio;
    final btn = t.getRect(find.byKey(const ValueKey('send')));
    expect(btn.bottom, lessThanOrEqualTo(screen - 300 + 0.5));
    expect(find.text('Tayyor'), findsNothing);
  });

  testWidgets('klaviatura yopiq — tugma pastda', (t) async {
    final node = FocusNode();
    await t.pumpWidget(app(kb: 0, node: node));
    await t.pumpAndSettle();
    final screen = t.view.physicalSize.height / t.view.devicePixelRatio;
    expect(t.getRect(find.byKey(const ValueKey('send'))).bottom, greaterThan(screen - 60));
  });

  testWidgets('bo\'sh joyga bosilsa klaviatura yopiladi', (t) async {
    final node = FocusNode();
    await t.pumpWidget(app(kb: 300, node: node));
    await t.tap(find.byType(TextField));
    await t.pump();
    expect(node.hasFocus, isTrue);
    await t.tap(find.byType(ColoredBox).last);
    await t.pump();
    expect(node.hasFocus, isFalse);
  });

  testWidgets('yangi varaq ochilganda klaviatura yopiladi (chek tanlash varag\'i kabi)', (t) async {
    final node = FocusNode();
    await t.pumpWidget(app(kb: 0, node: node));
    await t.tap(find.byType(TextField));
    await t.pump();
    expect(node.hasFocus, isTrue);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
    expect(node.hasFocus, isFalse);
  });
}
