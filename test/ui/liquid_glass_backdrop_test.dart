import 'package:flutify_app/ui/widgets/liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({required bool backdrop}) => MaterialApp(
    home: Center(
      child: LiquidGlass(
        backdrop: backdrop,
        child: const SizedBox(width: 120, height: 48),
      ),
    ),
  );

  testWidgets('samples the backdrop by default', (tester) async {
    await tester.pumpWidget(host(backdrop: true));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('skips the backdrop copy but keeps shape and size when disabled', (tester) async {
    await tester.pumpWidget(host(backdrop: false));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(tester.getSize(find.byType(LiquidGlass)), const Size(120, 48));
  });
}
