import 'dart:async';
import 'dart:io';

import 'package:flutify_app/services/audio/audio_engine.dart';
import 'package:flutify_app/services/eme/eme_player.dart';
import 'package:flutify_app/services/eme/native_drm_audio_engine.dart';
import 'package:flutify_app/services/eme/native_drm_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_dealer.dart' show until;

class _Server implements EmePlayer {
  final prepared = <String>[];
  Completer<void>? gate;

  @override
  EmePlaybackException? lastError;

  @override
  Future<({String hlsUrl, String licenseUrl, String provisionUrl})>
  serveHlsForNative({
    required File m4a,
    required String m3u8,
    required Future<Uint8List> Function(Uint8List) licensePoster,
    required Future<Uint8List> Function() certFetcher,
  }) async {
    lastError = null;
    prepared.add(m3u8);
    await gate?.future;
    return (hlsUrl: m3u8, licenseUrl: 'license', provisionUrl: 'provision');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('flutify/native_drm');
  const events = MethodChannel('flutify/native_drm/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Server server;
  late NativeDrmAudioEngine engine;
  late List<MethodCall> calls;
  Completer<void>? prepareGate;
  Completer<void>? resumeGate;
  var audible = false;

  setUp(() {
    calls = [];
    prepareGate = null;
    resumeGate = null;
    audible = false;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'play':
          // Model the native command's intent; completion can arrive after pause.
          audible = call.arguments['autoplay'] != false;
          await prepareGate?.future;
        case 'resume':
          audible = true;
          await resumeGate?.future;
        case 'pause' || 'stop' || 'dispose':
          audible = false;
      }
      return null;
    });
    server = _Server();
    engine = NativeDrmAudioEngine(
      server: server,
      player: NativeDrmPlayer(),
      licensePoster: (_) async => Uint8List(0),
      certFetcher: () async => Uint8List(0),
    );
  });

  tearDown(() async {
    engine.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  EmeTrackContent content([String id = 'a']) => EmeTrackContent(
    fileIdHex: '0000000000000000000000000000000000000000',
    m4aPath: '$id.m4a',
    m3u8: id,
  );

  Future<void> nativeError(String message) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'type': 'error',
        'code': 'ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED',
        'message': message,
      }),
      (_) {},
    );
  }

  for (final status in [401, 403]) {
    test('native HTTP $status text does not imply Web sign-in', () async {
      await engine.playEme(content());
      final errorEvent = engine.emeErrors.first;
      await nativeError('media or provisioning HTTP $status');
      final error = await errorEvent;
      expect(error.webSignInSuggested, isFalse);
      expect(error.message, contains('HTTP $status'));
      expect(engine.hasSource, isFalse);
      expect(engine.isPlaying, isFalse);
    });
  }

  for (final signIn in [false, true]) {
    test(
      'relay classification $signIn survives generic native error',
      () async {
        await engine.playEme(content());
        final cause = StateError('original relay cause');
        final relayError = EmePlaybackException(
          'license relay failed',
          webSignInSuggested: signIn,
          cause: cause,
        );
        server.lastError = relayError;
        final errors = <EmePlaybackException>[];
        final subscription = engine.emeErrors.listen(errors.add);
        addTearDown(subscription.cancel);
        await nativeError('DRM session failed');
        await until(() => errors.isNotEmpty);
        expect(errors.single, same(relayError));
        expect(errors.single.cause, same(cause));
        await nativeError('duplicate media failure');
        await Future<void>.delayed(Duration.zero);
        expect(errors, hasLength(1));

        await engine.playEme(content('next'));
        await nativeError('next track media HTTP 403');
        await until(() => errors.length == 2);
        expect(errors.last.webSignInSuggested, isFalse);
        expect(errors.last.cause, isNull);
      },
    );
  }

  test(
    'paused preparation passes intent and seek to native before starting',
    () async {
      await engine.playEme(
        content(),
        autoplay: false,
        initialPosition: const Duration(seconds: 42),
      );
      final prepare = calls.singleWhere((call) => call.method == 'play');
      expect(prepare.arguments['autoplay'], false);
      expect(prepare.arguments['positionMs'], 42000);
      expect(calls.where((call) => call.method == 'resume'), isEmpty);
      expect(audible, isFalse);
      expect(engine.hasSource, isTrue);
      await engine.play();
      expect(audible, isTrue);
    },
  );

  for (final stop in [false, true]) {
    test(
      '${stop ? 'stop' : 'pause'} cancels pending loopback preparation',
      () async {
        server.gate = Completer<void>();
        final loading = engine.playEme(content());
        await until(() => server.prepared.isNotEmpty);
        await (stop ? engine.stop() : engine.pause());
        server.gate!.complete();
        await loading;
        expect(calls.where((call) => call.method == 'play'), isEmpty);
        expect(audible, isFalse);
        expect(engine.hasSource, isFalse);
      },
    );

    test(
      '${stop ? 'stop' : 'pause'} during native preparation prevents late autoplay',
      () async {
        prepareGate = Completer<void>();
        final loading = engine.playEme(content());
        await until(() => calls.any((call) => call.method == 'play'));
        await (stop ? engine.stop() : engine.pause());
        prepareGate!.complete();
        await loading;
        expect(calls.where((call) => call.method == 'resume'), isEmpty);
        expect(audible, isFalse);
        expect(engine.isPlaying, isFalse);
      },
    );
  }

  test('newer track owns the server and only it resumes', () async {
    server.gate = Completer<void>();
    final old = engine.playEme(content('old'));
    await until(() => server.prepared.isNotEmpty);
    final fresh = engine.playEme(content('new'));
    server.gate!.complete();
    await Future.wait([old, fresh]);
    expect(server.prepared, ['old', 'new']);
    expect(
      calls.singleWhere((call) => call.method == 'play').arguments['hlsUrl'],
      'new',
    );
    expect(calls.where((call) => call.method == 'resume').length, 1);
    expect(audible, isTrue);
  });

  test('late resume acknowledgement cannot undo pause', () async {
    await engine.playEme(content(), autoplay: false);
    resumeGate = Completer<void>();
    final resuming = engine.play();
    await until(() => calls.any((call) => call.method == 'resume'));
    await engine.pause();
    resumeGate!.complete();
    await resuming;
    expect(engine.isPlaying, isFalse);
    expect(audible, isFalse);
  });

  test('disposed engine never starts pending preparation', () async {
    server.gate = Completer<void>();
    final loading = engine.playEme(content());
    await until(() => server.prepared.isNotEmpty);
    engine.dispose();
    server.gate!.complete();
    await loading;
    expect(calls.where((call) => call.method == 'play'), isEmpty);
    expect(audible, isFalse);
  });
}
