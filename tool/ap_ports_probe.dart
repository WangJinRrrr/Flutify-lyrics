// 开发工具：AP 可达性探针（无需任何凭据，不读取本机登录状态）。
//
// 用途：分别以「直连」与「HTTP CONNECT 代理隧道」向接入点发送 ClientHello，
// 用于区分「协议问题」与「网络环境（代理 / TUN）吞掉 AP 长连接」。
// 用法（在 app 目录）：dart run tool/ap_ports_probe.dart [--proxy 127.0.0.1:7890]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/auth/proto_codec.dart';
import 'package:flutify_app/services/protocol/ap_crypto.dart' as ap_crypto;

Future<void> main(List<String> args) async {
  final proxyIndex = args.indexOf('--proxy');
  final proxy = proxyIndex >= 0 ? args[proxyIndex + 1] : null;

  final client = HttpClient();
  final req = await client.getUrl(Uri.parse('https://apresolve.spotify.com/?type=accesspoint'));
  final body = await (await req.close()).transform(utf8.decoder).join();
  client.close(force: true);
  final entries = RegExp(r'"([a-z0-9.-]+:\d+)"').allMatches(body).map((m) => m.group(1)!).toList();
  final byPort = <String, String>{};
  for (final e in entries) {
    byPort.putIfAbsent(e.split(':')[1], () => e);
  }

  for (final target in byPort.values) {
    stdout.writeln(await _probe(target, proxy));
  }
  exit(0);
}

Future<String> _probe(String target, String? proxy) async {
  final mode = proxy == null ? '直连' : '代理';
  final sw = Stopwatch()..start();
  Socket? socket;
  try {
    final hostPort = (proxy ?? target).split(':');
    socket = await Socket.connect(hostPort[0], int.parse(hostPort[1]), timeout: const Duration(seconds: 6));
    final done = Completer<String>();
    var tunnelReady = proxy == null;
    final buf = BytesBuilder();
    socket.listen((d) {
      buf.add(d);
      if (!tunnelReady) {
        final text = latin1.decode(buf.toBytes());
        final end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        if (!text.startsWith('HTTP/1.1 200') && !text.startsWith('HTTP/1.0 200')) {
          done.complete('代理拒绝 CONNECT：${text.split('\r\n').first}');
          return;
        }
        tunnelReady = true;
        stdout.writeln('  CONNECT → ${text.split('\r\n').first}');
        buf.clear();
        socket!.add(_hello());
        return;
      }
      if (buf.length >= 4 && !done.isCompleted) done.complete('收到 APResponse（${buf.length}B）');
    }, onDone: () {
      if (!done.isCompleted) done.complete('连接被关闭');
    }, onError: (Object e) {
      if (!done.isCompleted) done.complete('错误 $e');
    });
    if (proxy == null) {
      socket.add(_hello());
    } else {
      socket.write('CONNECT $target HTTP/1.1\r\nHost: $target\r\n\r\n');
    }
    final r = await done.future.timeout(const Duration(seconds: 6), onTimeout: () => '6s 内无响应');
    return '$target $mode  $r  ${sw.elapsedMilliseconds}ms';
  } catch (e) {
    return '$target $mode  失败：$e';
  } finally {
    socket?.destroy();
  }
}

Uint8List _hello() {
  final dh = ap_crypto.DhLocalKeys.random();
  stdout.writeln('  gc=${dh.publicKey.length}B');
  final buildInfo = ProtoWriter()
    ..varintAlways(10, 0)
    ..varintAlways(20, 0)
    ..varintAlways(30, 0x27)
    ..int64(40, 124200290);
  final hello = ProtoWriter()
    ..message(10, buildInfo)
    ..varintAlways(30, 0)
    ..message(50, ProtoWriter()..message(10, ProtoWriter()..bytes(10, dh.publicKey)..varintAlways(20, 1)))
    ..bytes(60, Uint8List(16))
    ..bytes(70, Uint8List.fromList([0x1e]));
  final bytes = hello.toBytes();
  final n = 6 + bytes.length;
  return Uint8List.fromList([0, 4, (n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255, ...bytes]);
}
