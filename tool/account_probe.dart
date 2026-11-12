// 开发工具：用 App 已保存的桌面版会话探测账号 / 个人主页相关接口（只读），记录响应结构。
//
// 用法（在 app 目录）：dart run tool/account_probe.dart [用户名]
//   不带参数时探测当前账号；带用户名时额外探测该用户的主页（他人主页视角）。
// 响应完整写入 tool/probe_out/account_*.json / .bin（已 gitignore，含账号数据）；终端只打印状态码与字段结构，
// 不打印任何令牌。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _ua = 'Spotify/130100234 Win32_x86_64/0 (PC desktop)';
const _appVersion = '1.3.1.234.g59d6bf59';
const _spclient = 'https://spclient.wg.spotify.com';

Future<void> main(List<String> args) async {
  final prefs = jsonDecode(
    File('${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final token = prefs['flutter.sp_access_token'] as String;
  final clientToken = prefs['flutter.sp_client_token'] as String? ?? '';
  final me = prefs['flutter.sp_username'] as String? ?? '';
  final expiry = prefs['flutter.sp_access_token_expiry'] as int? ?? 0;
  if (expiry < DateTime.now().millisecondsSinceEpoch) {
    stdout.writeln('access_token 已过期，请先打开 App 让它续期');
    exit(1);
  }
  if (me.isEmpty) {
    stdout.writeln('没有保存的用户名');
    exit(1);
  }

  final headers = {
    'authorization': 'Bearer $token',
    'client-token': clientToken,
    'user-agent': _ua,
    'app-platform': 'Win32_x86_64',
    'spotify-app-version': _appVersion,
    'accept-language': 'zh-CN',
  };
  final out = Directory('tool/probe_out')..createSync(recursive: true);
  final client = HttpClient();
  final u = Uri.encodeComponent(me);

  Future<void> getJson(String label, String path) => _get(client, label, Uri.parse('$_spclient/$path'),
      {...headers, 'accept': 'application/json'}, out);

  await getJson('account_profile', 'user-profile-view/v3/profile/$u?playlist_limit=10&artist_limit=10&episode_limit=10');
  await getJson('account_followers', 'user-profile-view/v3/profile/$u/followers');
  await getJson('account_following', 'user-profile-view/v3/profile/$u/following');
  await getJson('account_playlists', 'user-profile-view/v3/profile/$u/playlists?offset=0&limit=50');
  await getJson('account_artists', 'user-profile-view/v3/profile/$u/artists');
  await getJson('account_identity', 'identity/v3/user/username/$u');

  // 隐私设置：请求体为 protobuf GetProfilePrivacyRequest { string username = 1; }
  final body = _pbString(1, me);
  for (final accept in ['application/json', 'application/x-protobuf']) {
    final label = 'account_privacy_${accept.endsWith('json') ? 'json' : 'pb'}';
    final req = await client.postUrl(Uri.parse('$_spclient/profile-privacy/v2/read-settings'));
    headers.forEach(req.headers.set);
    req.headers.set('accept', accept);
    req.headers.set('content-type', 'application/x-protobuf');
    req.add(body);
    await _report(label, await req.close(), out);
  }

  if (args.isNotEmpty) {
    final other = Uri.encodeComponent(args.first);
    await getJson('account_other_profile', 'user-profile-view/v3/profile/$other?playlist_limit=10&artist_limit=10');
    await getJson('account_other_followers', 'user-profile-view/v3/profile/$other/followers');
    await getJson('account_other_following', 'user-profile-view/v3/profile/$other/following');
    await getJson('account_other_playlists', 'user-profile-view/v3/profile/$other/playlists?offset=0&limit=5');
  }
  client.close();
}

Uint8List _pbString(int field, String value) {
  final bytes = utf8.encode(value);
  return Uint8List.fromList([(field << 3) | 2, ..._varint(bytes.length), ...bytes]);
}

List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

Future<void> _get(HttpClient c, String label, Uri uri, Map<String, String> h, Directory out) async {
  final req = await c.getUrl(uri);
  h.forEach(req.headers.set);
  await _report(label, await req.close(), out);
}

Future<void> _report(String label, HttpClientResponse res, Directory out) async {
  final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
  final type = res.headers.contentType?.mimeType ?? '';
  dynamic json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } catch (_) {}
  File('${out.path}/$label.${json == null ? 'bin' : 'json'}').writeAsBytesSync(bytes);
  stdout.writeln('[$label] HTTP ${res.statusCode}  $type  ${bytes.length} bytes');
  if (json != null) {
    stdout.writeln(_shape(json, 0, 4));
  } else if (bytes.isNotEmpty && bytes.length < 200) {
    stdout.writeln('  hex: ${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  }
}

/// 打印 JSON 结构（键名与类型），数组只展开第一个元素；字符串只显示长度，避免把资料内容打到终端。
String _shape(dynamic v, int depth, int maxDepth) {
  final pad = '  ' * (depth + 1);
  if (v is Map) {
    if (depth >= maxDepth) return '{…${v.length} keys}';
    return v.entries.map((e) => '\n$pad${e.key}: ${_shape(e.value, depth + 1, maxDepth)}').join();
  }
  if (v is List) {
    if (v.isEmpty) return '[]';
    return '[${v.length}] ${_shape(v.first, depth + 1, maxDepth)}';
  }
  if (v is String) return v.startsWith('spotify:') ? 'uri(${v.split(':')[1]})' : 'str(${v.length})';
  return '${v.runtimeType}($v)';
}
