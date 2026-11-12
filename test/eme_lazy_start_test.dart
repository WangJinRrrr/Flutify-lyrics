import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/audio/audio_engine.dart';
import 'package:flutify_app/services/eme/eme_audio_engine.dart';
import 'package:flutify_app/services/eme/eme_player.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingPlayer extends EmePlayer {
  final events = <String>[];
  @override
  Future<void> play({
    required File m4a,
    required String m3u8,
    required Future<Uint8List> Function(Uint8List) licensePoster,
    required Future<Uint8List> Function() certFetcher,
    bool fairPlay = false,
    String? fairPlayFileId,
    bool autoplay = true,
    Duration? initialPosition,
  }) async {
    events.add('play');
    lastAutoplay = autoplay;
    lastPosition = initialPosition;
  }

  bool? lastAutoplay;
  Duration? lastPosition;
  Completer<void>? resumeDone;
  @override
  Future<void> pause() async => events.add('pause');
  @override
  Future<void> stop() async => events.add('stop');
  @override
  Future<void> resume() async {
    events.add('resume');
    await resumeDone?.future;
  }

  @override
  Future<void> setVolume(double volume) async => events.add('volume:$volume');
}

void main() {
  const content = EmeTrackContent(
    fileIdHex: '0000000000000000000000000000000000000000',
    m4aPath: 'unused.m4a',
    m3u8: '#EXTM3U',
  );

  for (final cancel in ['pause', 'stop', 'dispose']) {
    test(
      '$cancel during initialization prevents delayed audible playback',
      () async {
        final ready = Completer<void>();
        final player = RecordingPlayer();
        final engine = EmeAudioEngine(
          player: player,
          licensePoster: (bytes) async => bytes,
          certFetcher: () async => Uint8List(0),
          initialize: () => ready.future,
        );
        if (cancel != 'dispose') addTearDown(engine.dispose);
        final loading = engine.playEme(content);
        if (cancel == 'pause') await engine.pause();
        if (cancel == 'stop') await engine.stop();
        if (cancel == 'dispose') engine.dispose();
        ready.complete();
        await loading;
        expect(engine.isPlaying, isFalse);
        if (cancel == 'pause') {
          expect(player.lastAutoplay, isFalse);
        } else {
          expect(player.events, isNot(contains('play')));
          expect(engine.hasSource, isFalse);
        }
      },
    );
  }

  test('paused handoff forwards its position without autoplay', () async {
    final player = RecordingPlayer();
    final engine = EmeAudioEngine(
      player: player,
      licensePoster: (bytes) async => bytes,
      certFetcher: () async => Uint8List(0),
    );
    addTearDown(engine.dispose);
    await engine.playEme(
      content,
      autoplay: false,
      initialPosition: const Duration(seconds: 42),
    );
    expect(player.lastAutoplay, isFalse);
    expect(player.lastPosition, const Duration(seconds: 42));
    expect(engine.isPlaying, isFalse);
    expect(engine.hasSource, isTrue);
    await engine.play();
    expect(engine.isPlaying, isTrue);
  });

  test('late resume acknowledgement cannot override a newer pause', () async {
    final player = RecordingPlayer()..resumeDone = Completer<void>();
    final engine = EmeAudioEngine(
      player: player,
      licensePoster: (bytes) async => bytes,
      certFetcher: () async => Uint8List(0),
    );
    addTearDown(engine.dispose);
    await engine.playEme(content, autoplay: false);
    final resuming = engine.play();
    await engine.pause();
    player.resumeDone!.complete();
    await resuming;
    expect(engine.isPlaying, isFalse);
  });

  test(
    'desktop DRM initializes on demand and restores volume before playback',
    () async {
      final ready = Completer<void>();
      final player = RecordingPlayer();
      var starts = 0;
      final engine = EmeAudioEngine(
        player: player,
        licensePoster: (bytes) async => bytes,
        certFetcher: () async => Uint8List(0),
        initialize: () {
          starts++;
          return ready.future;
        },
      );
      addTearDown(engine.dispose);
      expect(starts, 0);
      await engine.setVolume(0.25);
      player.events.clear();
      final playing = engine.playEme(content);
      expect(starts, 1);
      expect(player.events, isEmpty);
      ready.complete();
      await playing;
      expect(player.events, ['volume:0.25', 'play']);
      await engine.playEme(content);
      expect(starts, 1);
    },
  );

  test(
    'failed initialization exposes the error and retries on next playback',
    () async {
      final player = RecordingPlayer();
      var starts = 0;
      final engine = EmeAudioEngine(
        player: player,
        licensePoster: (bytes) async => bytes,
        certFetcher: () async => Uint8List(0),
        initialize: () async {
          if (++starts == 1) throw StateError('WebView unavailable');
        },
      );
      addTearDown(engine.dispose);
      await expectLater(engine.playEme(content), throwsStateError);
      expect(player.events, isEmpty);
      await engine.playEme(content);
      expect(starts, 2);
      expect(player.events.last, 'play');
    },
  );
}
