import 'dart:async';

import 'package:flutify_app/models/catalog_page.dart';
import 'package:flutify_app/models/home_feed.dart';

import 'fake_spotify_api_service.dart';

class ControlledSearchApi extends FakeSpotifyApiService {
  final bool signedIn;
  final requests =
      <
        ({String query, int offset, String? type, Completer<SearchPage> result})
      >[];

  ControlledSearchApi(super.storage, {this.signedIn = true})
    : super(homeFeed: HomeFeed.empty);

  @override
  bool get isConfigured => signedIn;

  @override
  Future<SearchPage> searchPage(
    String query, {
    int offset = 0,
    int limit = 20,
    String? type,
  }) {
    final result = Completer<SearchPage>();
    requests.add((query: query, offset: offset, type: type, result: result));
    return result.future;
  }
}
