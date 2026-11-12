import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'progressive_download.dart';

/// Full external podcast audio, read on demand through the app HTTP client.
/// A seek requests the relevant range instead of buffering an entire episode.
class HttpRangeAudio implements ProgressiveAudio {
  final http.Client client;
  final Uri url;
  @override
  final int length;
  @override
  final String contentType;
  HttpRangeAudio._(this.client, this.url, this.length, this.contentType);

  static Future<HttpRangeAudio> open(http.Client client, String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https')
      throw const FormatException('Expected HTTPS podcast URL');
    final request = http.Request('GET', uri)..headers['Range'] = 'bytes=0-0';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 15));
    await response.stream.listen(null).cancel();
    if (response.statusCode != 200 && response.statusCode != 206)
      throw StateError('Podcast HTTP ${response.statusCode}');
    final total = response.statusCode == 206
        ? int.tryParse(response.headers['content-range']?.split('/').last ?? '')
        : response.contentLength;
    if (total == null || total <= 0)
      throw const FormatException('Podcast length unavailable');
    final mime =
        response.headers['content-type']?.split(';').first ?? 'audio/mpeg';
    if (!mime.startsWith('audio/') && mime != 'application/octet-stream')
      throw const FormatException('Podcast URL is not audio');
    return HttpRangeAudio._(client, uri, total, mime);
  }

  @override
  double get progress => 1;
  // No background prefetch: ranges are available from the origin on demand.
  @override
  Future<void> get done => Future.value();

  @override
  Stream<List<int>> read(int start, [int? end]) async* {
    final stop = (end ?? length).clamp(0, length);
    if (start < 0 || start > stop) throw RangeError.range(start, 0, stop);
    if (start == stop) return;
    final request = http.Request('GET', url)
      ..headers['Range'] = 'bytes=$start-${stop - 1}';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.stream.listen(null).cancel();
      throw StateError('Podcast HTTP ${response.statusCode}');
    }
    if (response.statusCode == 206 &&
        !((response.headers['content-range'] ?? '').startsWith(
          'bytes $start-',
        ))) {
      await response.stream.listen(null).cancel();
      throw const FormatException('Podcast range mismatch');
    }
    var skip = response.statusCode == 200 ? start : 0;
    var remaining = stop - start;
    await for (final bytes in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      final from = math.min(skip, bytes.length);
      skip -= from;
      final count = math.min(remaining, bytes.length - from);
      if (count > 0) {
        yield bytes.sublist(from, from + count);
        remaining -= count;
      }
      if (remaining == 0) return;
    }
    if (remaining > 0) throw StateError('Podcast connection ended early');
  }
}
