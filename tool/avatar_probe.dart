// 开发工具：用 App 已保存的桌面版会话实测「更换头像」（会写入账号！）。
//
// 流程：POST https://image-upload.spotify.com/v4/user-profile（JPEG 原始字节）→ 拿 uploadToken
//      → POST spclient identity/v2/profile-image/{用户名}/{uploadToken} → 重新读资料确认 image_url。
// 用法（在 app 目录）：dart run tool/avatar_probe.dart <jpeg 路径>
// 终端只打印状态码与字段结构，不打印令牌；响应写入 tool/probe_out/（已 gitignore）。
import 'dart:convert';
import 'dart:io';

const _ua = 'Spotify/130100234 Win32_x86_64/0 (PC desktop)';
const _appVersion = '1.3.1.234.g59d6bf59';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('用法：dart run tool/avatar_probe.dart <jpeg 路径>');
    exit(1);
  }
  final prefs = jsonDecode(
    File('${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final token = prefs['flutter.sp_access_token'] as String;
  final clientToken = prefs['flutter.sp_client_token'] as String? ?? '';
  final me = prefs['flutter.sp_username'] as String? ?? '';
  final headers = {
    'authorization': 'Bearer $token',
    'client-token': clientToken,
    'user-agent': _ua,
    'app-platform': 'Win32_x86_64',
    'spotify-app-version': _appVersion,
  };
  final out = Directory('tool/probe_out')..createSync(recursive: true);
  final client = HttpClient();

  // 1. 上传图片
  final up = await client.postUrl(Uri.parse('https://image-upload.spotify.com/v4/user-profile'));
  headers.forEach(up.headers.set);
  up.headers.set('content-type', 'image/jpeg');
  up.add(File(args.first).readAsBytesSync());
  final upRes = await up.close();
  final upText = await upRes.transform(utf8.decoder).join();
  File('${out.path}/avatar_upload.json').writeAsStringSync(upText);
  stdout.writeln('[upload] HTTP ${upRes.statusCode}  ${upRes.headers.contentType}');
  Map<String, dynamic>? upJson;
  try {
    upJson = jsonDecode(upText) as Map<String, dynamic>;
    stdout.writeln('  keys: ${upJson.keys.toList()}');
  } catch (_) {
    stdout.writeln('  非 JSON 响应，${upText.length} 字符');
  }
  final uploadToken = upJson?['uploadToken'] as String? ?? upJson?['upload_token'] as String? ?? '';
  if (upRes.statusCode != 200 || uploadToken.isEmpty) {
    client.close();
    exit(2);
  }

  // 2. 设为头像
  final set = await client.postUrl(Uri.parse(
      'https://spclient.wg.spotify.com/identity/v2/profile-image/${Uri.encodeComponent(me)}/${Uri.encodeComponent(uploadToken)}'));
  headers.forEach(set.headers.set);
  set.contentLength = 0;
  final setRes = await set.close();
  final setBody = await setRes.transform(utf8.decoder).join();
  stdout.writeln('[set] HTTP ${setRes.statusCode}  ${setBody.length} 字符');

  // 3. 重新读资料
  await Future<void>.delayed(const Duration(seconds: 2));
  final get = await client.getUrl(
      Uri.parse('https://spclient.wg.spotify.com/user-profile-view/v3/profile/${Uri.encodeComponent(me)}?playlist_limit=0&artist_limit=0'));
  headers.forEach(get.headers.set);
  get.headers.set('accept', 'application/json');
  final getRes = await get.close();
  final profile = jsonDecode(await getRes.transform(utf8.decoder).join()) as Map<String, dynamic>;
  File('${out.path}/avatar_profile_after.json').writeAsStringSync(jsonEncode(profile));
  stdout.writeln('[profile] HTTP ${getRes.statusCode}  image_url: ${(profile['image_url'] as String? ?? '').isEmpty ? '无' : '有'}'
      '  has_spotify_image: ${profile['has_spotify_image']}');
  client.close();
}
