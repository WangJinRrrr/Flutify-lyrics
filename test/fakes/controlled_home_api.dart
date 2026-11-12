import 'dart:async';

import 'package:flutify_app/models/home_feed.dart';
import 'package:flutify_app/models/user_profile.dart';

import 'fake_spotify_api_service.dart';

class ControlledHomeApi extends FakeSpotifyApiService {
  final requests = <({String facet, Completer<HomeFeed> result})>[];
  int userRequests = 0;

  ControlledHomeApi(super.storage) : super(homeFeed: HomeFeed.empty);

  @override
  Future<HomeFeed> getHome({String facet = ''}) {
    final result = Completer<HomeFeed>();
    requests.add((facet: facet, result: result));
    return result.future;
  }

  @override
  Future<SpotifyUser> getCurrentUser() {
    userRequests++;
    return super.getCurrentUser();
  }
}
