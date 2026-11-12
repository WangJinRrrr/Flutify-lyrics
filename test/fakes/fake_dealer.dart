import 'dart:async';
import 'dart:convert';

import 'package:flutify_app/services/connect/dealer_client.dart';

/// 内存版 dealer 通道：测试里手动推送服务端消息、观察客户端发出的帧。
class FakeDealerChannel implements DealerChannel {
  final StreamController<String> _incoming = StreamController<String>();
  final List<String> sent = [];
  final bool autoPong;
  bool closed = false;

  FakeDealerChannel({this.autoPong = true});

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String text) {
    sent.add(text);
    if (autoPong && text.contains('"ping"')) push(jsonEncode({'type': 'pong'}));
  }

  @override
  Future<void> close() async {
    closed = true;
    // 不等待：没人监听时 close 的 Future 不会完成
    unawaited(_incoming.close());
  }

  int get pingCount => sent.where((s) => s.contains('"ping"')).length;

  /// 服务端推一帧原始文本。
  void push(String text) {
    if (!_incoming.isClosed) _incoming.add(text);
  }

  /// 服务端在连接建立后推的第一条消息，带连接 id。
  void pushConnectionId(String id) => push(
    jsonEncode({
      'type': 'message',
      'uri': 'hm://pusher/v1/connections/synthetic-path',
      'headers': {'Spotify-Connection-Id': id},
    }),
  );

  /// 服务端推一条 JSON 对象 payload 的消息。
  void pushJson(String uri, Map<String, Object?> payload) => push(
    jsonEncode({
      'type': 'message',
      'uri': uri,
      'headers': {'content-type': 'application/json'},
      'payloads': [payload],
    }),
  );

  /// 模拟服务端关闭连接。
  void drop() => unawaited(_incoming.close());
}

/// 假的 dealer 服务端：每次连接新建一个通道，并按序号发出连接 id（`conn-id-1`、`conn-id-2`…）。
class FakeDealerServer {
  final List<FakeDealerChannel> channels = [];
  final List<Uri> uris = [];
  final List<Map<String, String>> handshakeHeaders = [];
  final bool autoPong;

  /// 为 true 时连接成功后立即推连接 id。
  bool sendConnectionId = true;

  /// 为 true 时连接直接失败（模拟网络不可达）。
  bool failConnect = false;

  /// 每次连接尝试的时刻，用来检查退避间隔。
  final List<DateTime> attemptTimes = [];

  FakeDealerServer({this.autoPong = true});

  Future<DealerChannel> connect(Uri uri, Map<String, String> headers) async {
    attemptTimes.add(DateTime.now());
    if (failConnect) throw StateError('network unreachable');
    uris.add(uri);
    handshakeHeaders.add(headers);
    final channel = FakeDealerChannel(autoPong: autoPong);
    channels.add(channel);
    if (sendConnectionId) channel.pushConnectionId('conn-id-${channels.length}');
    return channel;
  }
}

/// 轮询等待条件成立（测试里的计时都很短，轮询比固定 sleep 稳）。
Future<void> until(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('等待条件超时');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
