/// Spotify API & SpClient reverse-engineering endpoint registry
class SpotifyEndpoints {
  SpotifyEndpoints._();

  // Base URLs
  static const String defaultWebApiBase = 'https://api.spotify.com/v1';
  static const String defaultAccountsBase = 'https://accounts.spotify.com';
  static const String defaultSpClientBase = 'https://spclient.wg.spotify.com';

  // Auth Endpoints
  static const String token = '/api/token';
  static const String authorize = '/authorize';

  // User Profile
  static const String me = '/me';
  static const String userProfile = '/users/{user_id}';

  // Player & Spotify Connect
  static const String playerState = '/me/player';
  static const String playerDevices = '/me/player/devices';
  static const String currentlyPlaying = '/me/player/currently-playing';
  static const String play = '/me/player/play';
  static const String pause = '/me/player/pause';
  static const String seek = '/me/player/seek';
  static const String repeat = '/me/player/repeat';
  static const String volume = '/me/player/volume';
  static const String next = '/me/player/next';
  static const String previous = '/me/player/previous';
  static const String shuffle = '/me/player/shuffle';
  static const String queue = '/me/player/queue';

  // Browse & Discovery
  static const String newReleases = '/browse/new-releases';
  static const String featuredPlaylists = '/browse/featured-playlists';
  static const String categories = '/browse/categories';
  static const String categoryPlaylists = '/browse/categories/{category_id}/playlists';

  // Search
  static const String search = '/search';

  // Library & Playlists
  static const String myPlaylists = '/me/playlists';
  static const String playlist = '/playlists/{playlist_id}';
  static const String playlistTracks = '/playlists/{playlist_id}/tracks';
  static const String savedTracks = '/me/tracks';
  static const String checkSavedTracks = '/me/tracks/contains';
  static const String savedAlbums = '/me/albums';
  static const String followedArtists = '/me/following?type=artist';

  // Entities
  static const String track = '/tracks/{id}';
  static const String album = '/albums/{id}';
  static const String artist = '/artists/{id}';
  static const String artistTopTracks = '/artists/{id}/top-tracks';
  static const String artistAlbums = '/artists/{id}/albums';

  // SpClient Internal Reverse-Engineered Endpoints
  static const String spclientColorLyrics = '/color-lyrics/v2/track/{track_id}';
  static const String spclientHomeFeed = '/homeview/v1/home';
  static const String spclientMetadata = '/metadata/4/{entity_type}/{id}';
}
