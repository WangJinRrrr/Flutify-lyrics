import 'package:flutify_app/models/album.dart';
import 'package:flutify_app/ui/navigation/app_routes.dart';
import 'package:flutify_app/ui/screens/detail/artist_catalog_screen.dart';
import 'package:flutify_app/ui/screens/detail/widgets/artist_catalog_widgets.dart';
import 'package:flutify_app/ui/screens/main_shell.dart';
import 'package:flutify_app/ui/widgets/cover_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'artist_catalog_test.dart' as fixture;

void main() {
  testWidgets('catalog arrow paints a 32px circle with a 48px hit target', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: ArtistCatalogSectionHeading(
            title: 'Albums',
            tooltip: 'All albums',
            buttonKey: const Key('catalog-arrow'),
            onOpen: () => opens++,
          ),
        ),
      ),
    );
    final button = find.byKey(const Key('catalog-arrow'));
    final circle = find.descendant(of: button, matching: find.byType(Material));
    expect(tester.getSize(circle), const Size.square(32));
    expect(tester.getSize(button), const Size.square(48));
    // Outside the visible circle, inside its padded click/touch target.
    await tester.tapAt(tester.getCenter(button) + const Offset(21, 0));
    await tester.pump();
    expect(opens, 1);
    Focus.of(
      tester.element(find.byIcon(Icons.chevron_right_rounded)),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opens, 2);
  });

  for (final (width, columns, oldColumns) in [(1120.0, 5, 4), (760.0, 4, 3)]) {
    testWidgets('album cards use about 80% of their old size at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                ArtistAlbumGrid(
                  albums: List.generate(
                    12,
                    (i) => SpotifyAlbum(
                      id: '$i',
                      name: 'A long album title for layout verification $i',
                      releaseDate: '2024',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final covers = find.byType(CoverImage);
      final size = tester.getSize(covers.first);
      final oldSize = (width - 24 * (oldColumns - 1)) / oldColumns;
      expect(size.width / oldSize, inInclusiveRange(0.72, 0.82));
      expect(size.height, size.width);
      expect(
        tester.getTopLeft(covers.at(columns - 1)).dy,
        tester.getTopLeft(covers.first).dy,
      );
      expect(
        tester.getTopLeft(covers.at(columns)).dy,
        greaterThan(tester.getTopLeft(covers.first).dy),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('only the album page uses the smaller heading', (tester) async {
    await fixture.pumpArtistApp(tester, openOverview: false);
    final context = tester.element(find.byType(MainShell));
    AppRoutes.openArtistAlbums(context, fixture.artist);
    await fixture.settle(tester);
    final title = find.descendant(
      of: find.byType(ArtistCatalogScreen),
      matching: find.text('专辑'),
    );
    expect(tester.widget<Text>(title).style?.fontSize, 28);
    AppRoutes.openArtistSongs(context, fixture.artist);
    await fixture.settle(tester);
    final songs = find.descendant(
      of: find.byType(ArtistCatalogScreen),
      matching: find.text('歌曲'),
    );
    expect(tester.widget<Text>(songs).style?.fontSize, 36);
    expect(tester.takeException(), isNull);
  });
}
