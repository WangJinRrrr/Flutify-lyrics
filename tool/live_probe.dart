// 开发工具：用 App 已保存的会话做端到端实测（纯 Dart，无需运行 App）。
//
// 用法（在 app 目录）：
//   dart run tool/live_probe.dart play [trackId]   完整曲目链路：metadata → storage-resolve → AP 密钥 → CDN 解密
//   dart run tool/live_probe.dart library          媒体库：collection/v2/paging、rootlist、metadata JSON、color-lyrics
//
// 终端只打印状态码、数量与字段结构，不打印任何令牌或账号数据；
// 完整响应写入 tool/probe_out/（已 gitignore，含账号数据，不得复制进测试或文档）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/auth/proto_codec.dart';
import 'package:flutify_app/services/protocol/access_point.dart';
import 'package:flutify_app/services/protocol/track_audio_loader.dart';
import 'package:flutify_app/services/protocol/track_metadata.dart';
import 'package:http/http.dart' as http;

const _ua = 'Spotify/130100234 Win32_x86_64/0 (PC desktop)';
const _appVersion = '1.3.1.234.g59d6bf59';
const _spclient = 'https://spclient.wg.spotify.com';

late final String _token;
late final String _clientToken;
late final String _username;
final _out = Directory('tool/probe_out');

Map<String, String> _headers({String accept = 'application/json'}) => {
      'Authorization': 'Bearer $_token',
      if (_clientToken.isNotEmpty) 'client-token': _clientToken,
      'User-Agent': _ua,
      'app-platform': 'Win32_x86_64',
      'spotify-app-version': _appVersion,
      'Accept': accept,
    };

Future<void> main(List<String> args) async {
  final prefs = jsonDecode(
    File('${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  _token = prefs['flutter.sp_access_token'] as String? ?? '';
  _clientToken = prefs['flutter.sp_client_token'] as String? ?? '';
  _username = prefs['flutter.sp_username'] as String? ?? '';
  final expiry = prefs['flutter.sp_access_token_expiry'] as int? ?? 0;
  final left = Duration(milliseconds: expiry - DateTime.now().millisecondsSinceEpoch);
  stdout.writeln('会话：method=${prefs['flutter.sp_auth_method']} token 剩余 ${left.inMinutes} 分钟 '
      'username=${_username.isEmpty ? '(空)' : '(已保存)'}');
  if (left.isNegative) {
    stdout.writeln('access_token 已过期，请先打开 App 让它续期');
    exit(1);
  }
  await _out.create(recursive: true);

  final mode = args.isEmpty ? 'play' : args.first;
  if (mode == 'play') await _play(args.length > 1 ? args[1] : '0VjIjW4GlUZAMYd2vXMi3b');
  if (mode == 'library') await _library();
  if (mode == 'meta') await _meta(args.length > 1 ? args[1] : '0VjIjW4GlUZAMYd2vXMi3b');
  if (mode == 'ext') await _ext(args.length > 1 ? args[1] : '0VjIjW4GlUZAMYd2vXMi3b');
  if (mode == 'profile') await _profile(prefs['flutter.sp_display_name'] as String? ?? '');
  if (mode == 'username') await _username_(prefs['flutter.sp_device_id'] as String? ?? '');
  if (mode == 'covers') await _covers();
  if (mode == 'home') await _home(args.length > 1 ? args[1] : '');
  if (mode == 'homelang') await _homeLang();
  exit(0);
}

/// 主页本地化：同一请求分别带不同 Accept-Language，问候语 / 筛选标签 / 前几个分区标题写入 probe_out/home_lang.txt。
Future<void> _homeLang() async {
  final c = http.Client();
  final out = StringBuffer();
  for (final lang in const ['', 'zh-CN', 'zh-Hans', 'zh-TW', 'zh-HK', 'en']) {
    final res = await c.post(
      Uri.parse('https://api-partner.spotify.com/pathfinder/v2/query'),
      headers: {
        ..._headers(),
        'content-type': 'application/json;charset=UTF-8',
        if (lang.isNotEmpty) 'Accept-Language': lang,
      },
      body: jsonEncode({
        'variables': {
          'homeEndUserIntegration': 'INTEGRATION_DESKTOP',
          'timeZone': 'Asia/Shanghai',
          'sp_t': '',
          'facet': '',
          'sectionItemsLimit': 10,
          'includeEpisodeContentRatingsV2': false,
        },
        'operationName': 'home',
        'extensions': {
          'persistedQuery': {'version': 1, 'sha256Hash': '76243c78b0e20ecdbe41b794dec8cbe73f75e585b0a7201b8d2e84578412847a'},
        },
      }),
    );
    stdout.writeln('home(lang="$lang") HTTP ${res.statusCode}');
    if (res.statusCode != 200) continue;
    final home = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['data']?['home'] as Map?;
    final chips = ((home?['homeChips'] as List?) ?? [])
        .map((e) => (e as Map)['label']?['transformedLabel'])
        .toList();
    final sections = ((home?['sectionContainer']?['sections']?['items'] as List?) ?? []);
    final titles = sections
        .map((s) => (s as Map)['data']?['title']?['transformedLabel'])
        .where((t) => t != null)
        .take(6)
        .toList();
    out.writeln('[$lang] greeting=${home?['greeting']?['transformedLabel']} chips=$chips sections=${sections.length}');
    out.writeln('  titles=$titles');
  }
  File('${_out.path}/home_lang.txt').writeAsStringSync(out.toString());
  c.close();
}

/// 主页结构：Pathfinder home 的分区类型、条目类型与数量（不打印标题与内容，完整响应写入 probe_out）。
Future<void> _home(String facet) async {
  final c = http.Client();
  final res = await c.post(
    Uri.parse('https://api-partner.spotify.com/pathfinder/v2/query'),
    headers: {..._headers(), 'content-type': 'application/json;charset=UTF-8'},
    body: jsonEncode({
      'variables': {
        'homeEndUserIntegration': 'INTEGRATION_DESKTOP',
        'timeZone': 'Etc/GMT-8',
        'sp_t': '',
        'facet': facet,
        'sectionItemsLimit': 10,
        'includeEpisodeContentRatingsV2': false,
      },
      'operationName': 'home',
      'extensions': {
        'persistedQuery': {'version': 1, 'sha256Hash': '76243c78b0e20ecdbe41b794dec8cbe73f75e585b0a7201b8d2e84578412847a'},
      },
    }),
  );
  stdout.writeln('home(facet="$facet") HTTP ${res.statusCode}');
  if (res.statusCode != 200) return;
  File('${_out.path}/home_${facet.isEmpty ? 'all' : facet}.json').writeAsBytesSync(res.bodyBytes);
  final home = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['data'] as Map)['home'] as Map;
  stdout.writeln('home 键=${home.keys.toList()}');
  final chips = home['homeChips'];
  if (chips is List) {
    stdout.writeln('homeChips ×${chips.length} 结构=${_shape(chips.isEmpty ? null : chips.first)}');
    for (final chip in chips) {
      // 筛选标签是通用文案（全部 / 音乐 / 播客），不含账号数据
      stdout.writeln('  chip id=${(chip as Map)['id']} label=${chip['label']?['transformedLabel']}');
    }
  }
  final sections = (home['sectionContainer']?['sections']?['items'] as List?) ?? const [];
  stdout.writeln('sections ×${sections.length}');
  for (final (i, s) in sections.indexed) {
    final section = s as Map;
    final data = section['data'] as Map?;
    final items = (section['sectionItems']?['items'] as List?) ?? const [];
    final kinds = <String, int>{};
    for (final item in items) {
      final content = (item as Map)['content'] as Map?;
      final kind = '${content?['__typename']}/${content?['data']?['__typename']}';
      kinds[kind] = (kinds[kind] ?? 0) + 1;
    }
    final title = data?['title']?['transformedLabel'];
    stdout.writeln('#$i ${data?['__typename']} 标题长度=${title is String ? title.length : '-'} '
        'subtitle=${data?['subtitle'] != null} uri=${(section['uri'] as String?)?.split(':').take(3).join(':')} '
        'items=$kinds 总数=${section['sectionItems']?['totalCount']}');
  }
  if (sections.isNotEmpty) stdout.writeln('section 结构=${_shape(sections.first)}');
  // 各类分区的 data 与条目结构（字段名 / 类型，不含值）；条目 uri 只打印类型前缀
  final seen = <String>{};
  for (final s in sections) {
    final section = s as Map;
    final type = section['data']?['__typename'] as String? ?? '';
    final items = (section['sectionItems']?['items'] as List?) ?? const [];
    for (final item in items) {
      final content = (item as Map)['content'] as Map?;
      final key = '$type/${content?['__typename']}/${content?['data']?['__typename']}';
      if (!seen.add(key)) continue;
      stdout.writeln('== $key');
      stdout.writeln('  section.data=${_shape(section['data'])}');
      stdout.writeln('  item.uri 前缀=${(item['uri'] as String?)?.split(':').take(2).join(':')} '
          'item.data=${_shape(item['data'])}');
      stdout.writeln('  content.data=${_shape(content?['data'], 1)}');
    }
  }
  // 标题 / 副标题 / 图标名摘要只写文件（可能含昵称），供本地对照官方界面
  final summary = StringBuffer('greeting=${home['greeting']?['transformedLabel']}\n');
  for (final (i, s) in sections.indexed) {
    final data = (s as Map)['data'] as Map?;
    summary.writeln('#$i ${data?['__typename']} title=${data?['title']?['transformedLabel']} '
        'subtitle=${data?['subtitle']?['transformedLabel']} icon=${data?['iconName']} '
        'header=${data?['headerEntity']?['data']?['__typename']}');
    if (data?['__typename'] == 'HomeRecentlyPlayedSectionData') {
      final list = ((s['sectionItems']['items'] as List).first as Map)['content']['data'] as Map;
      final first = (list['items']['items'] as List).firstOrNull;
      summary.writeln('  recent item 结构=${_shape(first)}');
      final entity = (first as Map?)?['entity']?['data'] as Map?;
      summary.writeln('  identityTrait=${_shape(entity?['identityTrait'], 1)}');
      summary.writeln('  visualIdentityTrait=${_shape(entity?['visualIdentityTrait'], 0)}');
      summary.writeln('  entityTypeTrait=${entity?['entityTypeTrait']}');
      summary.writeln('  typedEntity=${_shape(entity?['typedEntity'], 1)}');
      summary.writeln('  formatListAttributes=${first?['formatListAttributes']}');
      final types = <String, int>{};
      for (final it in (list['items']['items'] as List)) {
        final t = '${(it as Map)['entity']?['data']?['entityTypeTrait']?['type']}|${(it['entity']?['_uri'] as String?)?.split(':').elementAtOrNull(1)}';
        types[t] = (types[t] ?? 0) + 1;
      }
      summary.writeln('  recent 类型=$types');
    }
    if (data?['__typename'] == 'HomeShortsSectionData') {
      for (final it in (s['sectionItems']['items'] as List)) {
        final m = it as Map;
        summary.writeln('  short uri=${m['uri']} content=${_shape(m['content'], 0)}');
      }
    }
  }
  File('${_out.path}/home_summary.txt').writeAsStringSync(summary.toString());
  c.close();
}

/// 歌单封面排查：rootlist 中缺 pictureSize 的条目还有哪些封面相关字段（只打印字段结构与计数）。
Future<void> _covers() async {
  final c = http.Client();
  final root = await c.get(
    Uri.parse('$_spclient/playlist/v2/user/${Uri.encodeComponent(_username)}/rootlist'
        '?decorate=revision,attributes,length,owner&from=0&length=200'),
    headers: _headers(),
  );
  stdout.writeln('rootlist HTTP ${root.statusCode}');
  if (root.statusCode != 200) return;
  File('${_out.path}/covers_rootlist.json').writeAsBytesSync(root.bodyBytes);
  final contents = (jsonDecode(utf8.decode(root.bodyBytes)) as Map<String, dynamic>)['contents'] as Map<String, dynamic>;
  final items = contents['items'] as List;
  final metas = contents['metaItems'] as List;
  final missing = <String>[];
  for (var i = 0; i < items.length && i < metas.length; i++) {
    final uri = (items[i] as Map)['uri'] as String? ?? '';
    if (!uri.startsWith('spotify:playlist:')) continue;
    final attrs = ((metas[i] as Map)['attributes'] as Map?) ?? {};
    if ((attrs['pictureSize'] as List?)?.isNotEmpty ?? false) continue;
    missing.add(uri.split(':').last);
    stdout.writeln('缺 pictureSize #${missing.length}: attributes=${_shape(attrs)}');
    final picture = attrs['picture'];
    if (picture is String) {
      stdout.writeln('  picture 长度=${picture.length} 十六进制=${RegExp(r'^[0-9a-f]+$').hasMatch(picture)} '
          'base64=${RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(picture)} '
          'base64解码字节=${(() { try { return base64.decode(picture).length; } catch (_) { return -1; } })()}');
    }
  }
  stdout.writeln('歌单条目 ${items.length}，缺 pictureSize ${missing.length}');

  // 逐个查歌单本体：attributes 是否带封面，第一页曲目（用于拼 mosaic）
  for (final (n, id) in missing.take(4).indexed) {
    final res = await c.get(
      Uri.parse('$_spclient/playlist/v2/playlist/$id?decorate=attributes,length,owner&from=0&length=4'),
      headers: _headers(),
    );
    stdout.writeln('playlist#${n + 1} HTTP ${res.statusCode}');
    if (res.statusCode != 200) continue;
    File('${_out.path}/covers_playlist_${n + 1}.json').writeAsBytesSync(res.bodyBytes);
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final attrs = j['attributes'] as Map<String, dynamic>;
    final picture = attrs['picture'];
    if (picture is String) {
      final hex = base64.decode(picture).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final img = await c.get(Uri.parse('https://i.scdn.co/image/$hex'));
      stdout.writeln('  上传封面 i.scdn.co HTTP ${img.statusCode} ${img.headers['content-type']}');
      continue;
    }
    // 无封面：取前 4 首曲目的专辑封面拼 mosaic
    final ids = <String>[];
    for (final item in (j['contents']['items'] as List)) {
      final uri = (item as Map)['uri'] as String;
      if (!uri.startsWith('spotify:track:')) continue;
      final meta = await c.get(
        Uri.parse('$_spclient/metadata/4/track/${_hex(uri.split(':').last)}?market=from_token'),
        headers: _headers(),
      );
      if (meta.statusCode != 200) continue;
      final images = ((jsonDecode(meta.body) as Map)['album']?['cover_group']?['image'] as List?) ?? [];
      final large = images.cast<Map>().where((i) => i['size'] == 'LARGE').firstOrNull ?? images.cast<Map?>().firstOrNull;
      final id = large?['file_id'] as String?;
      if (id != null && !ids.contains(id)) ids.add(id);
    }
    stdout.writeln('  曲目专辑封面 ${ids.length} 个，id 长度=${ids.map((e) => e.length).toList()}');
    if (ids.length >= 4) {
      final mosaic = await c.get(Uri.parse('https://mosaic.scdn.co/640/${ids.take(4).join()}'));
      stdout.writeln('  mosaic HTTP ${mosaic.statusCode} ${mosaic.headers['content-type']} ${mosaic.bodyBytes.length}B');
    }
  }
  c.close();
}

/// 用 access_token 登录 AP，从 APWelcome 取 canonical username，并验证它能读 rootlist / 收藏（只打印状态）。
Future<void> _username_(String deviceId) async {
  final ap = await SpotifyAccessPoint.connect();
  try {
    final welcome = await ap.authenticate(ApCredentials.accessToken(_token), deviceId: deviceId.isEmpty ? null : deviceId);
    final user = welcome.canonicalUsername;
    stdout.writeln('APWelcome username 非空=${user.isNotEmpty} 长度=${user.length}');
    final c = http.Client();
    final root = await c.get(
      Uri.parse('$_spclient/playlist/v2/user/${Uri.encodeComponent(user)}/rootlist?from=0&length=5'),
      headers: _headers(),
    );
    stdout.writeln('rootlist（AP 用户名）HTTP ${root.statusCode}');
    final prof = await c.get(
      Uri.parse('$_spclient/user-profile-view/v3/profile/${Uri.encodeComponent(user)}?playlist_limit=0&artist_limit=0'),
      headers: _headers(),
    );
    stdout.writeln('profile/{AP 用户名} HTTP ${prof.statusCode}');
    final paging = await c.post(
      Uri.parse('$_spclient/collection/v2/paging'),
      headers: {
        ..._headers(accept: 'application/vnd.collection-v2.spotify.proto'),
        'Content-Type': 'application/vnd.collection-v2.spotify.proto',
      },
      body: (ProtoWriter()
            ..string(1, user)
            ..string(2, 'collection')
            ..varintAlways(4, 50))
          .toBytes(),
    );
    var tracks = 0;
    if (paging.statusCode == 200) {
      ProtoReader(paging.bodyBytes).forEach((f) {
        if (f.number == 1 && f.wireType == 2) {
          f.asMessage.forEach((i) {
            if (i.number == 1 && i.wireType == 2 && i.asString.startsWith('spotify:track:')) tracks++;
          });
        }
      });
    }
    stdout.writeln('collection/v2/paging HTTP ${paging.statusCode} 首页曲目数=$tracks');
    c.close();
  } finally {
    ap.close();
  }
}

/// 账号资料：对比 `profile/me` 与 `profile/{username}` 是否为同一人、是否与已保存昵称一致（只打印布尔值）。
Future<void> _profile(String savedName) async {
  final c = http.Client();
  final names = <String, String>{};
  for (final who in ['me', Uri.encodeComponent(_username)]) {
    final res = await c.get(
      Uri.parse('$_spclient/user-profile-view/v3/profile/$who?playlist_limit=0&artist_limit=0'),
      headers: _headers(),
    );
    final label = who == 'me' ? 'profile/me' : 'profile/{username}';
    stdout.writeln('$label HTTP ${res.statusCode}');
    if (res.statusCode != 200) continue;
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    File('${_out.path}/profile_${who == 'me' ? 'me' : 'user'}.json').writeAsBytesSync(res.bodyBytes);
    names[label] = (j['name'] as String? ?? '').trim();
    stdout.writeln('  结构键=${j.keys.toList()}  uri 指向本账号=${j['uri'] == 'spotify:user:$_username'}');
  }
  stdout.writeln('已保存昵称 == profile/me：${names['profile/me'] == savedName}');
  stdout.writeln('已保存昵称 == profile/{username}：${names['profile/{username}'] == savedName}');
  c.close();
}

/// extended-metadata：按扩展类型请求，打印响应的字段树（只含字段号 / 长度）。
Future<void> _ext(String track) async {
  final c = http.Client();
  for (final path in ['/extended-metadata/v0/extended-metadata', '/extended-metadata/v3/extensions/batch-get']) {
    for (final kind in [5, 10]) {
      final req = ProtoWriter()
        ..message(1, ProtoWriter()..string(1, 'from_token'))
        ..message(
          2,
          ProtoWriter()
            ..string(1, 'spotify:track:$track')
            ..message(2, ProtoWriter()..varintAlways(1, kind)),
        );
      final res = await c.post(
        Uri.parse('$_spclient$path'),
        headers: {
          ..._headers(accept: 'application/protobuf'),
          'Content-Type': 'application/protobuf',
        },
        body: req.toBytes(),
      );
      stdout.writeln('$path kind=$kind HTTP ${res.statusCode} ${res.bodyBytes.length}B');
      if (res.statusCode == 200) {
        File('${_out.path}/ext_${path.split('/')[2]}_$kind.bin').writeAsBytesSync(res.bodyBytes);
        stdout.writeln(_tree(res.bodyBytes, 0));
      }
    }
  }
  c.close();
}

/// 递归打印 protobuf 字段树（嵌套消息尽力解析；只显示字段号、类型与长度）。
String _tree(List<int> bytes, int depth) {
  final sb = StringBuffer();
  try {
    ProtoReader(Uint8List.fromList(bytes)).forEach((f) {
      final pad = '  ' * (depth + 1);
      if (f.wireType == 2) {
        final b = f.bytesValue;
        final printable = b.every((x) => x >= 0x20 && x < 0x7f);
        if (printable && b.isNotEmpty && b.length < 80) {
          sb.writeln('$pad#${f.number} str(${b.length}) ${String.fromCharCodes(b).replaceAll(RegExp(r'[0-9a-zA-Z]{20,}'), '<id>')}');
        } else {
          sb.writeln('$pad#${f.number} bytes(${b.length})');
          if (depth < 6 && b.isNotEmpty) {
            final sub = _tree(b, depth + 1);
            if (!sub.contains('!parse')) sb.write(sub);
          }
        }
      } else {
        sb.writeln('$pad#${f.number} varint=${f.wireType == 0 ? f.varintValue : '?'}');
      }
    });
  } catch (_) {
    return '!parse';
  }
  return sb.toString();
}

/// 列出 metadata/4/track 顶层字段号与各版本的音频格式（不输出值）。
Future<void> _meta(String track) async {
  final c = http.Client();
  for (final q in ['', '?market=from_token']) {
    final res = await c.get(
      Uri.parse('$_spclient/metadata/4/track/${_hex(track)}$q'),
      headers: _headers(accept: 'application/x-protobuf'),
    );
    stdout.writeln('metadata$q HTTP ${res.statusCode} ${res.bodyBytes.length}B');
    if (res.statusCode != 200) continue;
    final fields = <int, int>{};
    ProtoReader(res.bodyBytes).forEach((f) => fields[f.number] = (fields[f.number] ?? 0) + 1);
    stdout.writeln('  顶层字段号×次数=$fields');
    final meta = TrackMetadata.parse(res.bodyBytes);
    stdout.writeln('  files=${meta.files.map((f) => f.format.name).toList()} '
        'alternatives=${meta.alternatives.map((a) => a.files.map((f) => f.format.name).toList()).toList()}');
  }
  c.close();
}

Future<void> _play(String track) async {
  final loader = TrackAudioLoader(
    accessToken: () async => _token,
    clientToken: () async => _clientToken,
    cacheDirectory: _out.path,
  );
  final sw = Stopwatch()..start();
  try {
    final audio = await loader.load(track);
    final head = await audio.file.openRead(0, 4).fold<List<int>>([], (a, b) => a..addAll(b));
    stdout.writeln('✅ ${sw.elapsedMilliseconds}ms 格式=${audio.source.format.name} '
        '大小=${audio.file.lengthSync()}B 文件头=${String.fromCharCodes(head)} 时长=${audio.durationMs}ms');
  } catch (e, s) {
    stdout.writeln('❌ ${sw.elapsedMilliseconds}ms $e');
    stdout.writeln(s.toString().split('\n').take(6).join('\n'));
  } finally {
    loader.dispose();
  }
}

Future<void> _library() async {
  final c = http.Client();
  // collection/v2/paging：tracks+albums 在 "collection" 集合，关注艺人在 "artist" 集合
  for (final set in ['collection', 'artist']) {
    final body = ProtoWriter()
      ..string(1, _username)
      ..string(2, set)
      ..varintAlways(4, 300);
    final res = await c.post(
      Uri.parse('$_spclient/collection/v2/paging'),
      headers: {
        ..._headers(accept: 'application/vnd.collection-v2.spotify.proto'),
        'Content-Type': 'application/vnd.collection-v2.spotify.proto',
      },
      body: body.toBytes(),
    );
    final kinds = <String, int>{};
    var next = false;
    if (res.statusCode == 200) {
      ProtoReader(res.bodyBytes).forEach((f) {
        if (f.number == 1 && f.wireType == 2) {
          f.asMessage.forEach((i) {
            if (i.number == 1 && i.wireType == 2) {
              final kind = i.asString.split(':').elementAt(1);
              kinds[kind] = (kinds[kind] ?? 0) + 1;
            }
          });
        }
        if (f.number == 2 && f.wireType == 2) next = f.bytesValue.isNotEmpty;
      });
      File('${_out.path}/collection_$set.bin').writeAsBytesSync(res.bodyBytes);
    }
    stdout.writeln('collection[$set] HTTP ${res.statusCode} 条目=$kinds 还有下一页=$next');
  }

  // rootlist（JSON）
  final root = await c.get(
    Uri.parse('$_spclient/playlist/v2/user/${Uri.encodeComponent(_username)}/rootlist'
        '?decorate=revision,attributes,length,owner&from=0&length=200'),
    headers: _headers(),
  );
  stdout.writeln('rootlist HTTP ${root.statusCode}');
  if (root.statusCode == 200) {
    File('${_out.path}/rootlist.json').writeAsBytesSync(root.bodyBytes);
    final j = jsonDecode(utf8.decode(root.bodyBytes)) as Map<String, dynamic>;
    stdout.writeln('  顶层键=${j.keys.toList()}');
    final contents = j['contents'] as Map<String, dynamic>? ?? {};
    stdout.writeln('  contents 键=${contents.keys.toList()}');
    final items = contents['items'] as List? ?? [];
    final metas = contents['metaItems'] as List? ?? [];
    stdout.writeln('  items=${items.length} metaItems=${metas.length}');
    if (metas.isNotEmpty) stdout.writeln('  metaItem 结构=${_shape(metas.first)}');
    if (items.isNotEmpty) stdout.writeln('  item 结构=${_shape(items.first)}');
  }

  // metadata JSON：专辑 / 艺人（After Hours / The Weeknd，公开实体）
  for (final (kind, hex) in [
    ('album', _hex('4yP0hdKOZPNshxUOjY0cZj')),
    ('artist', _hex('1Xyo4u8uXC1ZmMpatF05PJ')),
  ]) {
    final res = await c.get(Uri.parse('$_spclient/metadata/4/$kind/$hex?market=from_token'), headers: _headers());
    stdout.writeln('metadata/$kind HTTP ${res.statusCode}');
    if (res.statusCode == 200) {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      File('${_out.path}/metadata_$kind.json').writeAsStringSync(jsonEncode(j));
      stdout.writeln('  结构=${_shape(j)}');
    }
  }

  // color-lyrics（Blinding Lights）
  final ly = await c.get(
    Uri.parse('$_spclient/color-lyrics/v2/track/0VjIjW4GlUZAMYd2vXMi3b?format=json&vocalRemoval=false&market=from_token'),
    headers: _headers(),
  );
  stdout.writeln('color-lyrics HTTP ${ly.statusCode}');
  if (ly.statusCode == 200) {
    stdout.writeln('  结构=${_shape(jsonDecode(utf8.decode(ly.bodyBytes)))}');
  }
  c.close();
}

/// 只输出字段名与类型，不输出值。
String _shape(Object? v, [int depth = 0]) {
  if (depth > 3) return '…';
  if (v is Map) return '{${v.entries.map((e) => '${e.key}:${_shape(e.value, depth + 1)}').join(', ')}}';
  if (v is List) return v.isEmpty ? '[]' : '[${_shape(v.first, depth + 1)} ×${v.length}]';
  return v.runtimeType.toString();
}

/// base62 → 32 位十六进制 GID。
String _hex(String base62) {
  const alphabet = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  var n = BigInt.zero;
  for (final ch in base62.split('')) {
    n = n * BigInt.from(62) + BigInt.from(alphabet.indexOf(ch));
  }
  return n.toRadixString(16).padLeft(32, '0');
}