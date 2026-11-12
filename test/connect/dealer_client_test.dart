import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/connect/dealer_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fakes/fake_dealer.dart';

/// apresolve 的合成响应。
http.Client _resolveClient({bool fail = false}) => MockClient((request) async {
  if (fail) return http.Response('boom', 500);
  return http.Response(
    jsonEncode({
      'dealer': ['dealer.test:443', 'dealer2.test:443'],
      'spclient': ['spclient.test:443'],
    }),
    200,
  );
});

DealerClient _client(
  FakeDealerServer server, {
  Future<Map<String, String>> Function()? headers,
  http.Client? resolver,
  Duration pingInterval = const Duration(seconds: 30),
  Duration pongTimeout = const Duration(seconds: 10),
  Duration initialBackoff = const Duration(milliseconds: 10),
  Duration maxBackoff = const Duration(milliseconds: 100),
}) => DealerClient(
  client: resolver ?? _resolveClient(),
  headers: headers ?? () async => {'Authorization': 'Bearer token-1', 'User-Agent': 'test-agent'},
  connector: server.connect,
  pingInterval: pingInterval,
  pongTimeout: pongTimeout,
  initialBackoff: initialBackoff,
  maxBackoff: maxBackoff,
);

void main() {
  group('DealerClient 连接', () {
    test('取连接 id、接入点与握手参数', () async {
      final server = FakeDealerServer();
      final dealer = _client(server);
      addTearDown(dealer.dispose);
      expect(dealer.status, DealerStatus.idle);
      expect(dealer.connectionId, isNull);

      final ids = <String>[];
      dealer.connectionIds.listen(ids.add);
      await dealer.connect();

      expect(dealer.status, DealerStatus.online);
      expect(dealer.connectionId, 'conn-id-1');
      await until(() => ids.isNotEmpty);
      expect(ids, ['conn-id-1']);
      expect(dealer.spclientHost, 'spclient.test');
      expect(server.uris.single.scheme, 'wss');
      expect(server.uris.single.host, 'dealer.test');
      expect(server.uris.single.queryParameters['access_token'], 'token-1');
      expect(server.handshakeHeaders.single['User-Agent'], 'test-agent');
    });

    test('connect 幂等：重复调用只建一个连接', () async {
      final server = FakeDealerServer();
      final dealer = _client(server);
      addTearDown(dealer.dispose);

      await Future.wait([dealer.connect(), dealer.connect()]);
      await dealer.connect();
      expect(server.channels, hasLength(1));
    });

    test('apresolve 失败时回退默认接入点', () async {
      final server = FakeDealerServer();
      final dealer = _client(server, resolver: _resolveClient(fail: true));
      addTearDown(dealer.dispose);

      await dealer.connect();
      expect(dealer.spclientHost, DealerClient.defaultSpclientHost);
      expect(server.uris.single.host, DealerClient.defaultDealerHost);
    });

    test('握手消息不会出现在 messages 里', () async {
      final server = FakeDealerServer();
      final dealer = _client(server);
      addTearDown(dealer.dispose);
      final received = <DealerMessage>[];
      dealer.messages.listen(received.add);

      await dealer.connect();
      server.channels.single.pushJson('hm://connect-state/v1/cluster', {'k': 1});
      await until(() => received.isNotEmpty);
      expect(received, hasLength(1));
      expect(received.single.uri, 'hm://connect-state/v1/cluster');
    });

    test('没有令牌：抛出且不重试', () async {
      final server = FakeDealerServer();
      final dealer = _client(server, headers: () async => {'Accept': 'application/json'});
      addTearDown(dealer.dispose);

      await expectLater(dealer.connect(), throwsA(isA<DealerException>()));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.attemptTimes, isEmpty);
      expect(dealer.status, DealerStatus.offline);
    });
  });

  group('DealerMessage payload 解码', () {
    Future<List<Object?>> receive(Map<String, Object?> message) async {
      final server = FakeDealerServer();
      final dealer = _client(server);
      addTearDown(dealer.dispose);
      final received = <DealerMessage>[];
      dealer.messages.listen(received.add);
      await dealer.connect();
      server.channels.single.push(jsonEncode({'type': 'message', 'uri': 'hm://x/y', ...message}));
      await until(() => received.isNotEmpty);
      return received.single.payloads;
    }

    test('JSON 对象原样', () async {
      final payloads = await receive({
        'payloads': [
          {'a': 1},
        ],
      });
      expect(payloads, [
        {'a': 1},
      ]);
    });

    test('base64 → JSON', () async {
      final payloads = await receive({
        'payloads': [base64.encode(utf8.encode('{"hello":"world"}'))],
      });
      expect(payloads.single, {'hello': 'world'});
    });

    test('base64 + gzip（头声明）→ JSON', () async {
      final payloads = await receive({
        'headers': {'Transfer-Encoding': 'gzip'},
        'payloads': [base64.encode(gzip.encode(utf8.encode('[1,2,3]')))],
      });
      expect(payloads.single, [1, 2, 3]);
    });

    test('没有头但带 gzip 魔数也会解压', () async {
      final payloads = await receive({
        'payloads': [base64.encode(gzip.encode(utf8.encode('{"z":true}')))],
      });
      expect(payloads.single, {'z': true});
    });

    test('非 JSON 内容保留为字节；坏 base64 保留原字符串', () async {
      final payloads = await receive({
        'headers': {'content-type': 'application/octet-stream'},
        'payloads': [
          base64.encode([0, 1, 2, 250]),
          '###not-base64###',
        ],
      });
      expect(payloads[0], isA<Uint8List>());
      expect(payloads[0], [0, 1, 2, 250]);
      expect(payloads[1], '###not-base64###');
    });

    test('声明 gzip 却解不开：保留未解压字节', () async {
      final payloads = await receive({
        'headers': {'Transfer-Encoding': 'gzip'},
        'payloads': [
          base64.encode([1, 2, 3, 4]),
        ],
      });
      expect(payloads.single, [1, 2, 3, 4]);
    });
  });

  group('DealerClient 心跳与重连', () {
    test('定期发 ping，收到 pong 保持在线', () async {
      final server = FakeDealerServer();
      final dealer = _client(
        server,
        pingInterval: const Duration(milliseconds: 20),
        pongTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(dealer.dispose);

      await dealer.connect();
      await until(() => server.channels.single.pingCount >= 3);
      expect(dealer.status, DealerStatus.online);
      expect(server.channels, hasLength(1));
    });

    test('发 ping 后没有 pong：视为断线并重连拿到新 id', () async {
      final server = FakeDealerServer(autoPong: false);
      final dealer = _client(
        server,
        pingInterval: const Duration(milliseconds: 20),
        pongTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(dealer.dispose);
      final ids = <String>[];
      final statuses = <DealerStatus>[];
      dealer.connectionIds.listen(ids.add);
      dealer.statusChanges.listen(statuses.add);

      await dealer.connect();
      await until(() => ids.length >= 2);

      expect(ids.take(2), ['conn-id-1', 'conn-id-2']);
      expect(server.channels.first.closed, isTrue);
      expect(statuses, containsAllInOrder([DealerStatus.connecting, DealerStatus.online, DealerStatus.offline]));
    });

    test('服务端断开后自动重连，并重新取 headers（令牌续期）', () async {
      final server = FakeDealerServer();
      var calls = 0;
      final dealer = _client(server, headers: () async => {'Authorization': 'Bearer token-${++calls}'});
      addTearDown(dealer.dispose);

      await dealer.connect();
      server.channels.first.drop();
      await until(() => server.channels.length == 2 && dealer.status == DealerStatus.online);

      expect(dealer.connectionId, 'conn-id-2');
      expect(server.uris.map((u) => u.queryParameters['access_token']), ['token-1', 'token-2']);
    });

    test('连接失败时退避翻倍并封顶', () async {
      final server = FakeDealerServer()..failConnect = true;
      final dealer = _client(
        server,
        initialBackoff: const Duration(milliseconds: 30),
        maxBackoff: const Duration(milliseconds: 100),
      );
      addTearDown(dealer.dispose);

      await expectLater(dealer.connect(), throwsA(anything));
      await until(() => server.attemptTimes.length >= 5);

      int gap(int i) => server.attemptTimes[i + 1].difference(server.attemptTimes[i]).inMilliseconds;
      // 30、60、100（封顶）、100：计时器只会晚不会早，只断言下限
      expect(gap(0), greaterThanOrEqualTo(28));
      expect(gap(1), greaterThanOrEqualTo(58));
      expect(gap(2), greaterThanOrEqualTo(98));
      expect(gap(3), greaterThanOrEqualTo(98));
      expect(dealer.status, DealerStatus.offline);
    });

    test('close 之后不再重连，connect 可重新启用', () async {
      final server = FakeDealerServer();
      final dealer = _client(server);
      addTearDown(dealer.dispose);

      await dealer.connect();
      final first = server.channels.single;
      await dealer.close();
      expect(first.closed, isTrue);
      expect(dealer.status, DealerStatus.idle);
      expect(dealer.connectionId, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.channels, hasLength(1));

      await dealer.connect();
      expect(server.channels, hasLength(2));
      expect(dealer.status, DealerStatus.online);
    });

    test('退避等待期间 close 会取消重连', () async {
      final server = FakeDealerServer();
      final dealer = _client(server, initialBackoff: const Duration(milliseconds: 60));
      addTearDown(dealer.dispose);

      await dealer.connect();
      server.channels.single.drop();
      await until(() => dealer.status == DealerStatus.offline);
      await dealer.close();

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(server.channels, hasLength(1));
      expect(dealer.status, DealerStatus.idle);
    });
  });
}
