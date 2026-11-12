import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutify_app/ui/screens/settings/widgets/settings_menu_field.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  );

  const options = [
    SettingsMenuOption(value: 'a', label: 'Alpha'),
    SettingsMenuOption(value: 'b', label: 'Beta'),
    SettingsMenuOption(value: 'c', label: 'Gamma'),
  ];

  testWidgets('shows the current value and selects through an M3 menu', (
    tester,
  ) async {
    var value = 'a';
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => SettingsMenuField<String>(
            semanticLabel: 'Pick one',
            value: value,
            options: options,
            buttonKey: const ValueKey('field'),
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();

    // 菜单展开：三项都在，当前项带对勾，触发器箭头翻转
    expect(find.byType(MenuItemButton), findsNWidgets(3));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);

    await tester.tap(find.widgetWithText(MenuItemButton, 'Gamma'));
    await tester.pumpAndSettle();

    expect(value, 'c');
    expect(find.byType(MenuItemButton), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('field')),
        matching: find.text('Gamma'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('is disabled when onChanged is null', (tester) async {
    await tester.pumpWidget(
      host(
        const SettingsMenuField<String>(
          semanticLabel: 'Pick one',
          value: 'b',
          options: options,
          onChanged: null,
          buttonKey: ValueKey('field'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();

    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
  });
}
