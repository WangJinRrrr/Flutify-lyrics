import 'package:flutify_app/ui/screens/player/player_expansion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final frameRate in [60, 120]) {
    testWidgets(
      'player surface has continuous $frameRate Hz expansion and collapse',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = AnimationController(
          vsync: tester,
          duration: PlayerExpansionMotion.duration,
          reverseDuration: PlayerExpansionMotion.reverseDuration,
        );
        const source = Rect.fromLTWH(10, 654, 370, 64);
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerExpansionTransition(
              animation: controller,
              origin: const PlayerExpansionOrigin(
                bounds: source,
                color: Colors.black,
                borderRadius: BorderRadius.all(Radius.circular(32)),
                compactChild: SizedBox.shrink(),
              ),
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        );
        Path surface() => tester
            .widget<ClipPath>(
              find.byKey(const ValueKey('player-expansion-surface')),
            )
            .clipper!
            .getClip(const Size(390, 844));
        expect(surface().getBounds(), source);
        expect(surface().contains(source.topLeft), isFalse);
        controller.forward();
        await tester.pump();
        final tick = Duration(microseconds: (1000000 / frameRate).round());
        var previous = source;
        while (controller.isAnimating) {
          await tester.pump(tick);
          final bounds = surface().getBounds();
          expect(bounds.top, lessThanOrEqualTo(previous.top));
          expect(bounds.bottom, greaterThanOrEqualTo(previous.bottom));
          expect(bounds.left, lessThanOrEqualTo(previous.left));
          expect(bounds.right, greaterThanOrEqualTo(previous.right));
          expect(previous.top - bounds.top, lessThan(source.top * 0.15));
          expect(bounds.top, greaterThanOrEqualTo(0));
          expect(bounds.bottom, lessThanOrEqualTo(844));
          previous = bounds;
        }
        expect(surface().getBounds(), const Rect.fromLTWH(0, 0, 390, 844));
        expect(surface().contains(const Offset(0.1, 0.1)), isTrue);

        controller.reverse();
        await tester.pump();
        expect(surface().getBounds(), previous);
        while (controller.isAnimating) {
          await tester.pump(tick);
          final bounds = surface().getBounds();
          expect(bounds.top, greaterThanOrEqualTo(previous.top));
          expect(bounds.bottom, lessThanOrEqualTo(previous.bottom));
          expect(bounds.left, greaterThanOrEqualTo(previous.left));
          expect(bounds.right, lessThanOrEqualTo(previous.right));
          final compact = find.byKey(
            const ValueKey('player-expansion-compact'),
          );
          final returned = bounds.top / source.top;
          expect(
            tester.widget<Opacity>(compact).opacity,
            closeTo(returned, 0.000001),
            reason: 'Compact content must share every frame of the return',
          );
          expect(
            (tester.getTopLeft(compact).dy + 16) / (source.top + 16),
            closeTo(returned, 0.000001),
          );
          previous = bounds;
        }
        expect(surface().getBounds(), source);
        expect(surface().contains(source.topLeft), isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('collapse follows the pill as it is now, not as it was opened', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AnimationController(
      vsync: tester,
      duration: PlayerExpansionMotion.duration,
      reverseDuration: PlayerExpansionMotion.reverseDuration,
    );
    PlayerExpansionLook look = (
      color: Colors.red,
      compactChild: const Text('opened with', textDirection: TextDirection.ltr),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerExpansionTransition(
          animation: controller,
          origin: PlayerExpansionOrigin(
            bounds: const Rect.fromLTWH(10, 654, 370, 64),
            color: look.color,
            borderRadius: const BorderRadius.all(Radius.circular(32)),
            compactChild: look.compactChild,
            currentLook: () => look,
          ),
          child: const ColoredBox(color: Colors.blue),
        ),
      ),
    );
    controller.forward();
    await tester.pump();
    await tester.pump(PlayerExpansionMotion.duration);
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.isCompleted, isTrue);

    // The track changes while the player covers the pill.
    look = (
      color: Colors.green,
      compactChild: const Text('playing now', textDirection: TextDirection.ltr),
    );
    controller.reverse();
    await tester.pump();
    final compact = find.byKey(const ValueKey('player-expansion-compact'));
    final surface = find.byKey(const ValueKey('player-expansion-surface'));
    Color pillColor() => tester
        .widget<ColoredBox>(
          find.descendant(of: surface, matching: find.byType(ColoredBox)).first,
        )
        .color;
    while (controller.isAnimating) {
      await tester.pump(const Duration(milliseconds: 30));
      if (compact.evaluate().isEmpty) break;
      expect(find.text('opened with'), findsNothing);
      expect(
        find.descendant(of: compact, matching: find.text('playing now')),
        findsOneWidget,
      );
      expect(pillColor(), Colors.green);
    }

    // Without a live source the opening snapshot is all there is.
    const snapshot = PlayerExpansionOrigin(
      bounds: Rect.fromLTWH(10, 654, 370, 64),
      color: Colors.red,
      borderRadius: BorderRadius.all(Radius.circular(32)),
      compactChild: Text('opened with', textDirection: TextDirection.ltr),
    );
    expect(snapshot.look.color, Colors.red);
    expect(snapshot.look.compactChild, same(snapshot.compactChild));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });
}
