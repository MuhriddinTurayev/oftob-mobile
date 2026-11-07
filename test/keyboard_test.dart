import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oftob_mobile/keyboard.dart';

/// Klaviatura: «Tayyor» tugmasi, bo'sh joyga bosish va yangi oyna ochilganda yopilishi (iPhone raqam klaviaturasi muammosi)
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
              const SizedBox(height: 200, width: 300, child: ColoredBox(color: Colors.white)),
              ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox(height: 100, child: Text('sheet'))),
                child: const Text('open'),
              ),
            ]),
          ),
        ),
      );

  testWidgets('Tayyor ko\'rinadi va bosilsa klaviatura yopiladi', (t) async {
    final node = FocusNode();
    await t.pumpWidget(app(kb: 300, node: node));
    await t.tap(find.byType(TextField));
    await t.pump();
    expect(node.hasFocus, isTrue);
    expect(find.byKey(const ValueKey('kb-done')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kb-done')));
    await t.pump();
    expect(node.hasFocus, isFalse);
  });

  testWidgets('klaviatura yopiq bo\'lsa Tayyor ko\'rinmaydi', (t) async {
    final node = FocusNode();
    await t.pumpWidget(app(kb: 0, node: node));
    expect(find.byKey(const ValueKey('kb-done')), findsNothing);
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
