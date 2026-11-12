import 'device.dart';
import 'track.dart';

enum SpotifyRepeatMode { off, context, track }

class SpotifyPlaybackState {
  final SpotifyTrack? currentTrack;
  final bool isPlaying;
  final int progressMs;
  final int durationMs;
  final bool shuffleState;
  final SpotifyRepeatMode repeatMode;
  final SpotifyDevice? device;
  final List<SpotifyTrack> queue;

  const SpotifyPlaybackState({
    this.currentTrack,
    this.isPlaying = false,
    this.progressMs = 0,
    this.durationMs = 0,
    this.shuffleState = false,
    this.repeatMode = SpotifyRepeatMode.off,
    this.device,
    this.queue = const [],
  });

  SpotifyPlaybackState copyWith({
    SpotifyTrack? currentTrack,
    bool? isPlaying,
    int? progressMs,
    int? durationMs,
    bool? shuffleState,
    SpotifyRepeatMode? repeatMode,
    SpotifyDevice? device,
    List<SpotifyTrack>? queue,
  }) {
    return SpotifyPlaybackState(
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      progressMs: progressMs ?? this.progressMs,
      durationMs: durationMs ?? this.durationMs,
      shuffleState: shuffleState ?? this.shuffleState,
      repeatMode: repeatMode ?? this.repeatMode,
      device: device ?? this.device,
      queue: queue ?? this.queue,
    );
  }

  factory SpotifyPlaybackState.fromJson(Map<String, dynamic> json) {
    SpotifyRepeatMode parseRepeat(String? mode) {
      switch (mode?.toLowerCase()) {
        case 'track':
          return SpotifyRepeatMode.track;
        case 'context':
          return SpotifyRepeatMode.context;
        default:
          return SpotifyRepeatMode.off;
      }
    }

    return SpotifyPlaybackState(
      currentTrack: json['item'] != null ? SpotifyTrack.fromJson(json['item']) : null,
      isPlaying: json['is_playing'] as bool? ?? false,
      progressMs: json['progress_ms'] as int? ?? 0,
      shuffleState: json['shuffle_state'] as bool? ?? false,
      repeatMode: parseRepeat(json['repeat_state'] as String?),
      device: json['device'] != null ? SpotifyDevice.fromJson(json['device']) : null,
    );
  }
}
