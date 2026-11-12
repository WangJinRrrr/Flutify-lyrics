// Web token 探针：用本机已存的 sp_dc 铸 Web token，检查是否匿名，并测试 melody license_url 分配接口。
//
//   dart run tool/web_token_probe.dart
//
// 不发 license 请求（避免加重限流）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36';

String _totp(List<int> secret, int ms) {
  final msg = ByteData(8)..setUint64(0, ms ~/ 1000 ~/ 30, Endian.big);
  final h = Hmac(sha1, secret).convert(msg.buffer.asUint8List()).bytes;
  final off = h.last & 0x0F;
  final code = (ByteData.sublistView(Uint8List.fromList(h), off, off + 4).getUint32(0) & 0x7FFFFFFF) % 1000000;
  return code.toString().padLeft(6, '0');
}

Future<void> main() async {
  final prefs = jsonDecode(File(
          '${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final dc = prefs['flutter.sp_dc'] as String;

  const obf = ',7/*F("rLJ2oxaKL^f+E1xvP@N';
  final secret = utf8.encode([for (var i = 0; i < obf.length; i++) obf.codeUnitAt(i) ^ ((i % 33) + 9)].join());
  final st = jsonDecode((await http.get(Uri.parse('https://open.spotify.com/api/server-time'))).body);
  final now = DateTime.now().millisecondsSinceEpoch;
  final uri = Uri.parse('https://open.spotify.com/api/token').replace(queryParameters: {
    'reason': 'transport',
    'productType': 'web-player',
    'totp': _totp(secret, now),
    'totpVer': '61',
    'totpServer': _totp(secret, (st['serverTime'] as num).toInt() * 1000),
  });
  final res = await http.get(uri, headers: {'Cookie': 'sp_dc=$dc', 'User-Agent': _ua});
  stdout.writeln('/api/token HTTP ${res.statusCode}');
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  stdout.writeln('isAnonymous=${body['isAnonymous']} clientId=${body['clientId']} '
      'totpVerExpired=${body['totpVerExpired']}');
  final token = body['accessToken'] as String;

  final me = await http.get(Uri.parse('https://api.spotify.com/v1/me'), headers: {'Authorization': 'Bearer $token'});
  stdout.writeln('/v1/me HTTP ${me.statusCode} ${me.body.length > 120 ? me.body.substring(0, 120) : me.body}');

  final ctRes = await http.post(Uri.parse('https://clienttoken.spotify.com/v1/clienttoken'),
      headers: {'content-type': 'application/json', 'accept': 'application/json', 'User-Agent': _ua},
      body: jsonEncode({
        'client_data': {
          'client_version': '1.3.5.31.ga27a71fef885',
          'client_id': body['clientId'],
          'js_sdk_data': {
            'device_brand': 'unknown',
            'device_model': 'unknown',
            'os': 'windows',
            'os_version': 'NT 10.0',
            'device_id': md5.convert(utf8.encode('$now')).toString(),
            'device_type': 'computer',
          },
        },
      }));
  final ct = (jsonDecode(ctRes.body)['granted_token'] as Map)['token'];
  for (final host in ['gae2-spclient.spotify.com', 'spclient.wg.spotify.com']) {
    final lu = await http.get(
        Uri.parse('https://$host/melody/v1/license_url?keysystem=com.widevine.alpha&mediatype=audio'
            '&sdk_name=harmony&sdk_version=4.62.0'),
        headers: {
          'Authorization': 'Bearer $token',
          'client-token': ct,
          'User-Agent': _ua,
          'Origin': 'https://open.spotify.com',
          'Referer': 'https://open.spotify.com/',
        });
    stdout.writeln('$host license_url HTTP ${lu.statusCode} ${lu.body}');
  }

  // 故意发无效请求体：400 = 服务器读了请求；429 = 网关层直接拦截（与请求内容无关）
  final garbage = await http.post(
      Uri.parse('https://gae2-spclient.spotify.com/widevine-license/v1/audio/license'),
      headers: {
        'Authorization': 'Bearer $token',
        'client-token': ct,
        'User-Agent': _ua,
        'Origin': 'https://open.spotify.com',
        'Referer': 'https://open.spotify.com/',
        'app-platform': 'WebPlayer',
        'Content-Type': 'application/octet-stream',
      },
      body: [1, 2, 3, 4]);
  stdout.writeln('dart garbage license HTTP ${garbage.statusCode} ${garbage.body}');
  File('${Directory.systemTemp.path}\\flutify_probe_tokens.txt').writeAsStringSync('$token\n$ct');
}
