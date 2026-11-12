import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/eme/segmented_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 假 CDN：按 Range 返回 [body] 的切片；[supportRange] 为 false 时总回 200 整份。
/// [failOnce] 中的起始偏移第一次请求时只吐一半数据就断开。
class _FakeCdn extends http.BaseClient {
  final Uint8List body;
  final bool supportRange;
  final Set<int> failOnce;
  int requests = 0;

  _FakeCdn(this.body, {this.supportRange = true, Set<int>? failOnce}) : failOnce = failOnce ?? {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    final range = request.headers['Range'];
    if (!supportRange || range == null) {
      return http.StreamedResponse(Stream.value(body), 200, contentLength: body.length);
    }
    final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
    final start = int.parse(m.group(1)!);
    final end = int.parse(m.group(2)!).clamp(0, body.length - 1);
    var slice = Uint8List.sublistView(body, start, end + 1);
    if (failOnce.remove(start)) slice = Uint8List.sublistView(slice, 0, slice.length ~/ 2);
    // 拆成小块模拟网络分包
    final chunks = [
      for (var i = 0; i < slice.length; i += 1000)
        Uint8List.sublistView(slice, i, (i + 1000).clamp(0, slice.length)),
    ];
    return http.StreamedResponse(Stream.fromIterable(chunks), 206,
        headers: {'content-range': 'bytes $start-$end/${body.length}'});
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('segdl'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Uint8List sample(int n) => Uint8List.fromList(List.generate(n, (i) => (i * 31 + 7) & 0xff));

  Future<(Uint8List, List<int>)> download(_FakeCdn cdn, {int segment = 10000}) async {
    final dest = File('${tmp.path}/out.m4a');
    final reports = <int>[];
    await SegmentedDownload(
      client: cdn,
      urls: const ['https://cdn-a/x', 'https://cdn-b/x'],
      dest: dest,
      segmentBytes: segment,
      onContiguous: (got, _) => reports.add(got),
    ).run();
    return (dest.readAsBytesSync(), reports);
  }

  test('多段并行下载后内容与原文件逐字节一致，连续字节单调不减', () async {
    final body = sample(95001);
    final cdn = _FakeCdn(body);
    final (out, reports) = await download(cdn);
    expect(out, body);
    expect(cdn.requests, 10);
    for (var i = 1; i < reports.length; i++) {
      expect(reports[i], greaterThanOrEqualTo(reports[i - 1]));
    }
    expect(reports.last, body.length);
  });

  test('服务器不支持 Range 时退化为单连接整份下载', () async {
    final body = sample(30000);
    final cdn = _FakeCdn(body, supportRange: false);
    final (out, reports) = await download(cdn);
    expect(out, body);
    expect(cdn.requests, 1);
    expect(reports.last, body.length);
  });

  test('某段中途断开时续传补齐', () async {
    final body = sample(50000);
    final cdn = _FakeCdn(body, failOnce: {20000});
    final (out, _) = await download(cdn);
    expect(out, body);
  });
}
