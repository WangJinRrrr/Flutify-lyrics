import 'package:flutify_app/services/auth/proto_codec.dart';
import 'package:flutify_app/services/library/collection_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个 CollectionItem { 1 uri; 2 added_at; 3 is_removed }。
ProtoWriter _item(String uri, {int addedAt = 0, bool removed = false}) {
  final w = ProtoWriter()..string(1, uri);
  if (addedAt != 0) w.int32(2, addedAt);
  if (removed) w.boolValue(3, true);
  return w;
}

void main() {
  group('CollectionCodec.decodePage', () {
    test('解析条目、加入时间与下一页游标', () {
      final data = (ProtoWriter()
            ..message(1, _item('spotify:track:aaa', addedAt: 1700000100))
            ..message(1, _item('spotify:album:bbb', addedAt: 1700000000))
            ..string(2, 'next-token'))
          .toBytes();

      final page = CollectionCodec.decodePage(data);

      expect(page.items.map((e) => e.uri), ['spotify:track:aaa', 'spotify:album:bbb']);
      expect(page.items.first.kind, 'track');
      expect(page.items.first.id, 'aaa');
      expect(page.items.first.addedAt, 1700000100);
      expect(page.nextToken, 'next-token');
    });

    test('已移除（is_removed）与空 URI 的条目被过滤', () {
      final data = (ProtoWriter()
            ..message(1, _item('spotify:track:gone', removed: true))
            ..message(1, _item(''))
            ..message(1, _item('spotify:track:kept')))
          .toBytes();

      final page = CollectionCodec.decodePage(data);

      expect(page.items.map((e) => e.id), ['kept']);
      expect(page.nextToken, isEmpty);
    });

    test('响应被截断时保留已解析的条目，不抛错', () {
      final full = (ProtoWriter()
            ..message(1, _item('spotify:track:first'))
            ..message(1, _item('spotify:track:second')))
          .toBytes();
      final truncated = full.sublist(0, full.length - 4);

      final page = CollectionCodec.decodePage(truncated);

      expect(page.items.first.id, 'first');
    });

    test('空响应与乱码都不抛错', () {
      expect(CollectionCodec.decodePage(ProtoWriter().toBytes()).items, isEmpty);
    });
  });

  group('请求编码', () {
    test('分页请求字段：username / set / token / limit', () {
      final bytes = CollectionCodec.encodePageRequest(
        username: 'tester',
        set: CollectionCodec.setArtist,
        token: 'tok',
        limit: 50,
      );

      final fields = <int, dynamic>{};
      ProtoReader(bytes).forEach((f) {
        fields[f.number] = f.wireType == 2 ? f.asString : f.varintValue;
      });
      expect(fields, {1: 'tester', 2: 'artist', 3: 'tok', 4: 50});
    });

    test('写请求：添加与移除的 is_removed 相反', () {
      Map<int, dynamic> decodeItem(bool added) {
        final bytes = CollectionCodec.encodeWriteRequest(
          username: 'tester',
          set: CollectionCodec.setCollection,
          uri: 'spotify:track:aaa',
          added: added,
          now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          clientUpdateId: 'cid',
        );
        Map<int, dynamic>? item;
        ProtoReader(bytes).forEach((f) {
          if (f.number == 3) {
            item = {};
            ProtoReader(f.bytesValue).forEach((g) {
              item![g.number] = g.wireType == 2 ? g.asString : g.varintValue;
            });
          }
        });
        return item!;
      }

      final add = decodeItem(true);
      expect(add[1], 'spotify:track:aaa');
      expect(add[2], 1700000000);
      expect(add[3] ?? 0, 0);

      expect(decodeItem(false)[3], 1);
    });
  });
}
