// 开发工具：用 shared_preferences.json 里的 refresh_token 续期 access_token 并写回。
//
// 用法（在 app/ 目录下）：
//   dart run tool/refresh_token.dart
//
// 只更新 sp_access_token / sp_access_token_expiry / sp_refresh_token（轮换时）三个键。
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutify_app/services/auth/auth_constants.dart';

Future<void> main() async {
  final prefsFile =
      File('${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json');
  final prefs = jsonDecode(prefsFile.readAsStringSync()) as Map<String, dynamic>;

  final refreshToken = prefs['flutter.sp_refresh_token'] as String? ?? '';
  if (refreshToken.isEmpty) {
    stderr.writeln('没有保存 refresh_token，请先在 App 登录');
    exit(1);
  }

  final res = await http.post(
    Uri.parse('https://accounts.spotify.com/api/token'),
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': SpotifyAuthConstants.desktopUserAgent,
    },
    body: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': SpotifyAuthConstants.desktopClientId,
    },
  ).timeout(const Duration(seconds: 20));

  final json = jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode != 200) {
    stderr.writeln('续期失败 HTTP ${res.statusCode}: ${json['error']} ${json['error_description']}');
    exit(1);
  }

  final accessToken = json['access_token'] as String;
  final newRefresh = json['refresh_token'] as String? ?? '';
  final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
  final expiry = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;

  prefs['flutter.sp_access_token'] = accessToken;
  prefs['flutter.sp_access_token_expiry'] = expiry;
  if (newRefresh.isNotEmpty) prefs['flutter.sp_refresh_token'] = newRefresh;
  prefsFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(prefs));

  stdout.writeln('✅ 续期成功，有效 ${expiresIn ~/ 60} 分钟'
      '${newRefresh.isNotEmpty ? '（refresh_token 已轮换）' : ''}');
}
