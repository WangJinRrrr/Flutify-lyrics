import 'package:flutify_app/ui/widgets/liquid_glass.dart';
import 'package:flutify_app/ui/widgets/menu/desktop_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> host(
    WidgetTester tester,
    List<PopupMenuEntry<int>> items,
    ValueChanged<int?> onSelected,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassMenuScope(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final result = await DesktopMenu.show(
                    context,
                    const Offset(40, 60),
                    items,
                  );
                  onSelected(result);
                },
                child: const Text('Open menu'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlass), findsOneWidget);
  }

  List<PopupMenuEntry<int>> actions() => [
    DesktopMenu.item(0, Icons.block, 'Unavailable', enabled: false),
    DesktopMenu.item(1, Icons.play_arrow, 'Play'),
    DesktopMenu.divider,
    DesktopMenu.item(2, Icons.queue, 'Add to queue'),
  ];

  testWidgets(
    'glass menu supports arrow keys and Enter, skipping disabled items',
    (tester) async {
      int? selected;
      await host(tester, actions(), (value) => selected = value);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(find.byType(LiquidGlass), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('glass menu supports Tab and rejects a disabled click', (
    tester,
  ) async {
    int? selected;
    await host(tester, actions(), (value) => selected = value);
    await tester.tap(find.text('Unavailable'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.byType(LiquidGlass), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Esc and outside click dismiss without choosing an action', (
    tester,
  ) async {
    final results = <int?>[];
    await host(tester, actions(), results.add);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(results, [null]);
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(750, 550));
    await tester.pumpAndSettle();
    expect(results, [null, null]);
    expect(find.byType(LiquidGlass), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long glass menu scrolls to the last action without overflow', (
    tester,
  ) async {
    int? selected;
    await host(tester, [
      for (var i = 0; i < 30; i++)
        DesktopMenu.item(i, Icons.music_note, 'Action $i'),
    ], (value) => selected = value);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Action 29'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action 29'));
    await tester.pumpAndSettle();
    expect(selected, 29);
    expect(tester.takeException(), isNull);
  });
}
