import 'dart:convert';

import 'package:flutify_app/services/connect/connect_state_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 合成 cluster：一台活动设备 + 一台隐藏观察者（后者不应出现在设备列表）。
const _clusterJson = {
  'timestamp': '1700000000000',
  'active_device_id': 'dev-1',
  'server_timestamp_ms': '1700000000500',
  'player_state': {'is_playing': true, 'is_paused': false},
  'devices': {
    'dev-1': {
      'device_id': 'dev-1',
      'name': 'Test Speaker',
      'device_type': 'SPEAKER',
      'volume': 32768,
      'capabilities': {'volume_steps': 16, 'can_be_player': true},
    },
    'hobs_x': {
      'name': 'observer',
      'capabilities': {'hidden': true},
    },
  },
};

({ConnectStateClient client, List<http.Request> requests}) _build(
  http.Response Function(http.Request request) respond, {
  String? connectionId = 'conn-1',
}) {
  final requests = <http.Request>[];
  final mock = MockClient((request) async {
    requests.add(request);
    return respond(request);
  });
  final client = ConnectStateClient(
    client: mock,
    headers: () async => {'Authorization': 'Bearer test-token', 'Accept': 'application/json'},
    spclientHost: () => 'spclient.test',
    connectionId: () => connectionId,
  );
  return (client: client, requests: requests);
}

void main() {
  test('429 blocks repeated controls and registration until Retry-After, without minting tokens', () async {
    var now = DateTime.utc(2026, 10, 4);
    var requests = 0;
    var headers = 0;
    final client = ConnectStateClient(
      client: MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('', 429, headers: {'retry-after': '120'})
            : http.Response('', 204);
      }),
      headers: () async { headers++; return {}; },
      spclientHost: () => 'spclient.test',
      connectionId: () => 'connection',
      now: () => now,
    );
    final limited = throwsA(isA<ConnectException>().having((e) => e.statusCode, 'status', 429));
    await expectLater(client.command('from', 'to', 'resume'), limited);
    now = now.add(const Duration(seconds: 119));
    await expectLater(client.registerObserver('observer', 'connection'), limited);
    await expectLater(client.setVolume('from', 'to', 42), limited);
    expect(requests, 1);
    expect(headers, 1);
    now = now.add(const Duration(seconds: 1));
    await client.command('from', 'to', 'pause');
    expect(requests, 2);
    expect(headers, 2);
  });

  group('registerObserver', () {
    test('PUT 路径 / 请求头 / body 正确，无 content-type 的 JSON 响应能解析', () async {
      final h = _build((_) => http.Response.bytes(utf8.encode(jsonEncode(_clusterJson)), 200));

      final cluster = await h.client.registerObserver('hobs_abc', 'conn-xyz');

      final req = h.requests.single;
      expect(req.method, 'PUT');
      expect(req.url.toString(), 'https://spclient.test/connect-state/v1/devices/hobs_abc');
      expect(req.headers['X-Spotify-Connection-Id'], 'conn-xyz');
      expect(req.headers['Authorization'], 'Bearer test-token');
      expect(req.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(req.body), {
        'member_type': 'CONNECT_STATE',
        'device': {
          'device_info': {
            'capabilities': {'can_be_player': false, 'hidden': true, 'needs_full_player_state': true},
          },
        },
      });

      expect(cluster.activeDeviceId, 'dev-1');
      expect(cluster.devices.map((d) => d.id), ['dev-1']);
      expect(cluster.player.isPlaying, isTrue);
      expect(cluster.serverTimestampMs, 1700000000500);
    });

    test('响应不是 JSON 对象：抛 ConnectException', () async {
      final h = _build((_) => http.Response.bytes([1, 2, 3], 200));
      await expectLater(
        h.client.registerObserver('hobs_abc', 'c'),
        throwsA(isA<ConnectException>().having((e) => e.statusCode, 'statusCode', 200)),
      );
    });
  });

  test('unregister：DELETE 同一路径，带连接 id', () async {
    final h = _build((_) => http.Response('', 204));

    await h.client.unregister('hobs_abc', 'conn-xyz');

    final req = h.requests.single;
    expect(req.method, 'DELETE');
    expect(req.url.path, '/connect-state/v1/devices/hobs_abc');
    expect(req.headers['X-Spotify-Connection-Id'], 'conn-xyz');
  });

  group('控制命令', () {
    test('transfer：路径与 restore_paused', () async {
      final h = _build((_) => http.Response('', 200));

      await h.client.transfer('hobs_me', 'dev-1');
      await h.client.transfer('hobs_me', 'dev-1', play: false);

      expect(h.requests[0].method, 'POST');
      expect(
        h.requests[0].url.toString(),
        'https://spclient.test/connect-state/v1/connect/transfer/from/hobs_me/to/dev-1',
      );
      expect(h.requests[0].headers['X-Spotify-Connection-Id'], 'conn-1');
      expect(jsonDecode(h.requests[0].body), {
        'transfer_options': {'restore_paused': 'restore'},
      });
      expect(jsonDecode(h.requests[1].body), {
        'transfer_options': {'restore_paused': 'pause'},
      });
    });

    test('command：endpoint 与附加字段', () async {
      final h = _build((_) => http.Response('', 200));

      await h.client.command('hobs_me', 'dev-1', 'pause');
      await h.client.command('hobs_me', 'dev-1', 'seek_to', extra: {'value': 4200});

      expect(h.requests[0].method, 'POST');
      expect(h.requests[0].url.path, '/connect-state/v1/player/command/from/hobs_me/to/dev-1');
      expect(jsonDecode(h.requests[0].body), {
        'command': {'endpoint': 'pause'},
      });
      expect(jsonDecode(h.requests[1].body), {
        'command': {'endpoint': 'seek_to', 'value': 4200},
      });
    });

    test('setVolume：PUT，越界值被截断', () async {
      final h = _build((_) => http.Response('', 200));

      await h.client.setVolume('hobs_me', 'dev-1', 30000);
      await h.client.setVolume('hobs_me', 'dev-1', 99999);
      await h.client.setVolume('hobs_me', 'dev-1', -5);

      expect(h.requests[0].method, 'PUT');
      expect(h.requests[0].url.path, '/connect-state/v1/connect/volume/from/hobs_me/to/dev-1');
      expect(h.requests.map((r) => jsonDecode(r.body)['volume']), [30000, 65535, 0]);
    });

    test('没有连接 id：抛 ConnectException 且不发请求', () async {
      final h = _build((_) => http.Response('', 200), connectionId: null);
      await expectLater(h.client.command('a', 'b', 'pause'), throwsA(isA<ConnectException>()));
      await expectLater(h.client.transfer('a', 'b'), throwsA(isA<ConnectException>()));
      await expectLater(h.client.setVolume('a', 'b', 1), throwsA(isA<ConnectException>()));
      expect(h.requests, isEmpty);
    });
  });

  group('错误处理', () {
    for (final entry in {401: '登录已过期', 403: '免费账号', 404: '离线', 429: '频繁', 503: '暂时不可用', 400: '失败'}.entries) {
      test('HTTP ${entry.key} → ConnectException(${entry.key})', () async {
        final h = _build((_) => http.Response('nope', entry.key));
        await expectLater(
          h.client.command('a', 'b', 'pause'),
          throwsA(
            isA<ConnectException>()
                .having((e) => e.statusCode, 'statusCode', entry.key)
                .having((e) => e.message, 'message', contains(entry.value)),
          ),
        );
      });
    }

    test('网络异常 → statusCode 为 null', () async {
      final client = ConnectStateClient(
        client: MockClient((_) async => throw http.ClientException('down')),
        headers: () async => {},
        spclientHost: () => 'spclient.test',
        connectionId: () => 'c',
      );
      await expectLater(
        client.unregister('a', 'c'),
        throwsA(isA<ConnectException>().having((e) => e.statusCode, 'statusCode', isNull)),
      );
    });
  });
}
