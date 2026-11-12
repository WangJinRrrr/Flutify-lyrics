import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutify_app/ui/widgets/cover_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Duration> _fadeIn(WidgetTester tester, {required bool tickers}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TickerMode(
        enabled: tickers,
        child: const CoverImage(
          url: 'https://example.invalid/cover.jpg',
          size: 64,
        ),
      ),
    ),
  );
  return tester
      .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
      .fadeInDuration;
}

void main() {
  // The lyrics card pauses tickers around its small cover. A fade driven by a
  // paused ticker never starts, so the next track's cover stayed a dark
  // placeholder until the view changed.
  testWidgets('cover fades in normally while tickers run', (tester) async {
    expect(
      await _fadeIn(tester, tickers: true),
      const Duration(milliseconds: 150),
    );
  });

  testWidgets('cover skips the fade while tickers are paused', (tester) async {
    expect(await _fadeIn(tester, tickers: false), Duration.zero);
  });
}
