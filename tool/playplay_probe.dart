// 验证 playplay 取密钥：只比对是否与抓包已知的 R1/R2 一致，不打印密钥本身。
import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/services/protocol/playplay_key.dart';

Future<void> main() async {
  final prefs = jsonDecode(
    File('${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final token = prefs['flutter.sp_access_token'] as String;
  final ct = prefs['flutter.sp_client_token'] as String;
  Future<Map<String, String>> headers() async => {
        'Authorization': 'Bearer $token',
        'client-token': ct,
        'User-Agent': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)',
        'app-platform': 'Win32_x86_64',
        'spotify-app-version': '1.3.1.234.g59d6bf59',
        'Accept': 'application/x-protobuf',
      };
  const cases = {
    '57468393583a583a4ce31082cb29987b4eccc833': '12c66c74bf62a1caa19c2feacbf921b3',
    '8f960a82e11550bcab3af70fbdbdb7d5dc778f2d': '48885a587efe473a3c3088451f45ebc3',
  };
  var ok = true;
  for (final e in cases.entries) {
    try {
      final k = await fetchPlayplayKey(fileIdHex: e.key, headers: headers);
      final r1 = k.r1.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final match = r1 == e.value && k.r2.length == 4;
      stdout.writeln('${e.key.substring(0, 8)} R1一致=$match R2长度=${k.r2.length}');
      ok = ok && match;
    } catch (err) {
      stdout.writeln('${e.key.substring(0, 8)} 失败: $err');
      ok = false;
    }
  }
  stdout.writeln(ok ? 'PLAYPLAY_OK' : 'PLAYPLAY_FAIL');
  exit(ok ? 0 : 1);
}
