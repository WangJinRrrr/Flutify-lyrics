import 'package:flutify_app/models/catalog_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filtered-out pages may be empty without being terminal', () {
    const page = CatalogPage<String>(
      items: [],
      offset: 0,
      total: 30,
      nextOffset: 10,
    );
    expect(page.items, isEmpty);
    expect(page.hasMore, isTrue);
    expect(page.nextOffset, 10);
  });

  test('terminal pages and empty song catalog have no continuation', () {
    const page = CatalogPage<String>(items: ['last'], offset: 10, total: 11);
    expect(page.hasMore, isFalse);
    const tracks = ArtistTracksPage(items: []);
    expect(tracks.hasMore, isFalse);
  });

  test('short pages use the server total, not the requested page size', () {
    final page = CatalogPage<String>.fromSlice(
      items: ['a'],
      offset: 0,
      limit: 20,
      rawCount: 2,
      total: 8,
    );
    expect(page.nextOffset, 2);
  });

  test('without metadata, only a full raw page indicates another page', () {
    final full = CatalogPage<String>.fromSlice(
      items: [],
      offset: 0,
      limit: 2,
      rawCount: 2,
    );
    final last = CatalogPage<String>.fromSlice(
      items: [],
      offset: 2,
      limit: 2,
      rawCount: 0,
    );
    expect(full.nextOffset, 2);
    expect(last.hasMore, isFalse);
  });

  test(
    'empty raw page before a known end is an error, not an endless cursor',
    () {
      expect(
        () => CatalogPage<String>.fromSlice(
          items: [],
          offset: 0,
          limit: 20,
          rawCount: 0,
          total: 8,
        ),
        throwsFormatException,
      );
    },
  );
}
