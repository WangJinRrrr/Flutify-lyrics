import 'dart:convert';

import 'package:flutify_app/services/pathfinder/pathfinder_client.dart';
import 'package:flutify_app/services/pathfinder/pathfinder_operations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Pathfinder 客户端：桌面客户端升级后查询哈希失效（PersistedQueryNotFound）要能识别并给出升级提示。
void main() {
  PathfinderClient clientReturning(String body, {int status = 200}) {
    return PathfinderClient(
      MockClient((_) async => http.Response(body, status)),
      headers: () async => const {},
    );
  }

  test('查询成功返回 data', () async {
    final client = clientReturning(jsonEncode({
      'data': {
        'home': {'sections': []},
      },
    }));
    final data = await client.query(PathfinderOperation.home, const {});
    expect(data.containsKey('home'), isTrue);
  });

  test('PersistedQueryNotFound → 识别为 hash 失效，提示升级客户端', () async {
    for (final errors in [
      [
        {'message': 'PersistedQueryNotFound', 'extensions': {'code': 'PERSISTED_QUERY_NOT_FOUND'}},
      ],
      [
        {'message': 'Persisted Query not found', 'extensions': {}},
      ],
    ]) {
      final client = clientReturning(jsonEncode({'errors': errors}));
      await expectLater(
        client.query(PathfinderOperation.home, const {}),
        throwsA(
          isA<PathfinderException>()
              .having((e) => e.hashStale, 'hashStale', isTrue)
              .having((e) => e.message, 'message', contains('更新')),
        ),
      );
    }
  });

  test('其它 GraphQL 错误不算 hash 失效', () async {
    final client = clientReturning(jsonEncode({
      'errors': [
        {'message': 'Forbidden', 'extensions': {'code': 'FORBIDDEN'}},
      ],
    }));
    await expectLater(
      client.query(PathfinderOperation.home, const {}),
      throwsA(isA<PathfinderException>().having((e) => e.hashStale, 'hashStale', isFalse)),
    );
  });

  test('HTTP 非 200 且无 errors → hashStale false', () async {
    final client = clientReturning('server error', status: 500);
    await expectLater(
      client.query(PathfinderOperation.home, const {}),
      throwsA(isA<PathfinderException>().having((e) => e.hashStale, 'hashStale', isFalse)),
    );
  });
}
