import 'dart:async';
import 'dart:typed_data';

import 'package:flutify_app/services/protocol/aes.dart';
import 'package:flutify_app/services/protocol/audio_normalization.dart';
import 'package:flutify_app/services/protocol/decrypt/decrypt_backend.dart';
import 'package:flutify_app/services/protocol/progressive_download.dart';
import 'package:flutify_app/services/protocol/track_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 合成一个「Spotify Ogg」：0xa7 字节私有头（偏移 144 处为响度数据）+ `OggS` 开头的正文。
Uint8List _spotifyOgg(int bodyLength) {
  final data = Uint8List(SpotifyAudioHeader.oggHeaderEnd + bodyLength);
  final loudness = ByteData.sublistView(data, AudioNormalization.headerOffset);
  loudness.setFloat32(0, -6.0, Endian.little); // track_gain_db
  loudness.setFloat32(4, 0.9, Endian.little); // track_peak
  data.setAll(SpotifyAudioHeader.oggHeaderEnd, 'OggS'.codeUnits);
  for (var i = SpotifyAudioHeader.oggHeaderEnd + 4; i < data.length; i++) {
    data[i] = (i * 31 + 7) & 0xff;
  }
  return data;
}

final _key = Uint8List.fromList(List.generate(16, (i) => i * 3));
final _iv = Uint8List.fromList(List.generate(16, (i) => 0xf0 + i));
final _spec = AesCtrDecryptSpec(key: _key, iv: _iv);

Uint8List _encrypt(Uint8List plain) {
  final out = Uint8List.fromList(plain);
  AesCtr(_key, _iv).process(out);
  return out;
}

Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: true);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Stream<List<int>> _chunks(Uint8List data, {int size = 1000}) async* {
  for (var i = 0; i < data.length; i += size) {
    yield data.sublist(i, (i + size).clamp(0, data.length));
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final isolateBackend = IsolateDecryptBackend();
  tearDownAll(isolateBackend.dispose);

  // 同一组用例分别在当前线程和常驻后台 Isolate 里解密，结果必须一致
  for (final (name, backend) in <(String, DecryptBackend)>[
    ('当前线程解密', const InlineDecryptBackend()),
    ('后台 Isolate 解密', isolateBackend),
  ]) {
    group(name, () => _suite(backend));
  }
}

void _suite(DecryptBackend backend) {
  test('解密、去掉私有头、读出响度数据；任意区间读取正确', () async {
    final plain = _spotifyOgg(20000);
    final cipher = _encrypt(plain);
    final client = MockClient.streaming((request, _) async {
      return http.StreamedResponse(_chunks(cipher), 200, contentLength: cipher.length);
    });

    final download = ProgressiveDownload(
      urls: ['https://cdn.test/a'],
      decrypt: _spec,
      backend: backend,
      format: AudioFileFormat.oggVorbis160,
      client: client,
    )..start();

    await download.ready;
    expect(download.length, plain.length - SpotifyAudioHeader.oggHeaderEnd);
    expect(download.normalization?.trackGainDb, closeTo(-6.0, 1e-6));
    expect(download.contentType, 'audio/ogg');

    // 头部到达后立即开始读，读取会等待后续数据
    final body = Uint8List.sublistView(plain, SpotifyAudioHeader.oggHeaderEnd);
    final all = await _collect(download.read(0));
    expect(all, body);

    final middle = await _collect(download.read(5000, 12345));
    expect(middle, Uint8List.sublistView(body, 5000, 12345));

    await download.done;
    expect(download.isComplete, isTrue);
    expect(download.playableBytes, body);
    expect(download.normalizationBytes, isNotNull);
  });

  test('中途断线后用 Range 续传，并换到下一个 CDN 地址', () async {
    final plain = _spotifyOgg(30000);
    final cipher = _encrypt(plain);
    const cutAt = 12000;
    final requests = <http.BaseRequest>[];

    final client = MockClient.streaming((request, _) async {
      requests.add(request);
      if (request.url.host == 'cdn1.test') {
        // 发出一部分后断开
        Stream<List<int>> broken() async* {
          yield* _chunks(Uint8List.sublistView(cipher, 0, cutAt));
          throw http.ClientException('connection reset');
        }

        return http.StreamedResponse(broken(), 200, contentLength: cipher.length);
      }
      final range = request.headers['Range']!;
      final start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      return http.StreamedResponse(
        _chunks(Uint8List.sublistView(cipher, start)),
        206,
        contentLength: cipher.length - start,
        headers: {'content-range': 'bytes $start-${cipher.length - 1}/${cipher.length}'},
      );
    });

    final download = ProgressiveDownload(
      urls: ['https://cdn1.test/a', 'https://cdn2.test/a'],
      decrypt: _spec,
      backend: backend,
      format: AudioFileFormat.oggVorbis160,
      client: client,
    )..start();

    final read = _collect(download.read(0));
    await download.done;
    expect(requests, hasLength(2));
    expect(requests[1].headers['Range'], 'bytes=$cutAt-');
    expect(await read, Uint8List.sublistView(plain, SpotifyAudioHeader.oggHeaderEnd));
  });

  test('所有地址都失败：ready 抛错', () async {
    final client = MockClient((request) async => http.Response('nope', 403));
    final download = ProgressiveDownload(
      urls: ['https://cdn.test/a'],
      decrypt: _spec,
      backend: backend,
      format: AudioFileFormat.oggVorbis160,
      client: client,
      maxAttempts: 2,
    )..start();
    await expectLater(download.ready, throwsStateError);
    await expectLater(download.done, throwsStateError);
  });

  test('MP3 不跳过任何字节', () async {
    final plain = Uint8List.fromList(List.generate(4000, (i) => i & 0xff));
    final cipher = _encrypt(plain);
    final client = MockClient.streaming((request, _) async {
      return http.StreamedResponse(_chunks(cipher), 200, contentLength: cipher.length);
    });
    final download = ProgressiveDownload(
      urls: ['https://cdn.test/a'],
      decrypt: _spec,
      backend: backend,
      format: AudioFileFormat.mp3_160,
      client: client,
    )..start();
    await download.done;
    expect(download.length, plain.length);
    expect(download.normalization, isNull);
    expect(await _collect(download.read(0)), plain);
  });
}
