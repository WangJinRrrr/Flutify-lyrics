// 开发工具：在当前活动的 Connect 设备上实测 `play` 命令（会让那台设备开始播放！）。
//
// 用法（在 app 目录）：dart run tool/connect_play_probe.dart <方式>
//   album   以专辑为上下文，从第 2 首开始（skip_to track_uri）
//   liked   以「已点赞的歌曲」为上下文（spotify:user:{用户名}:collection）
//   tracks  没有上下文，以临时列表（pages）播放 3 首，从第 2 首开始
//   uri <track_uri>  单曲临时列表播放指定曲目
// 终端只打印状态码与远程播放器的曲目 / 上下文 URI，不打印令牌。
import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/services/connect/connect_service.dart';
import 'package:http/http.dart' as http;

const _ua = 'Spotify/130100234 Win32_x86_64/0 (PC desktop)';
const _appVersion = '1.3.1.234.g59d6bf59';

// 样本：After Hours 专辑的前三首
const _album = 'spotify:album:4yP0hdKOZPNshxUOjY0cZj';
const _tracks = [
  'spotify:track:7szuecWAPwGoV1e5vGu8tl', // Alone Again
  'spotify:track:6bnF93Rx87YqUBLSgjiMU8', // Too Late
  'spotify:track:2YSzYUF3jWqb9YP9VXmpjE', // Hardest To Love
];

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'album' : args.first;
  final prefs =
      jsonDecode(
            File(
              '${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final token = prefs['flutter.sp_access_token'] as String;
  final clientToken = prefs['flutter.sp_client_token'] as String? ?? '';
  final username = prefs['flutter.sp_username'] as String? ?? '';
  final deviceId = prefs['flutter.sp_device_id'] as String? ?? '';
  final headers = {
    'Authorization': 'Bearer $token',
    'client-token': clientToken,
    'User-Agent': _ua,
    'App-Platform': 'Win32_x86_64',
    'Spotify-App-Version': _appVersion,
  };

  final service = ConnectService(client: http.Client(), headers: () async => headers, deviceId: () => deviceId);
  await service.start();
  for (var i = 0; i < 30 && service.status != ConnectStatus.online; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  stdout.writeln('status: ${service.status}');
  for (final d in service.current.devices) {
    stdout.writeln('device: ${d.name} (${d.type.name}) canPlay=${d.canPlay}');
  }
  final active = service.current.activeDevice ?? service.current.devices.where((d) => d.canPlay).firstOrNull;
  if (active == null) {
    stdout.writeln('没有活动的 Connect 设备');
    service.dispose();
    exit(1);
  }
  stdout.writeln('active device: ${active.name} (${active.type})');

  try {
    switch (mode) {
      case 'uri':
        final uri = args[1];
        await service.play(active.id, trackUris: [uri], trackUri: uri, trackIndex: 0);
      case 'liked':
        await service.play(active.id, contextUri: 'spotify:user:$username:collection');
      case 'tracks':
        await service.play(active.id, trackUris: _tracks, trackUri: _tracks[1], trackIndex: 1);
      default:
        await service.play(active.id, contextUri: _album, trackUri: _tracks[1]);
    }
    stdout.writeln('play: ok');
  } on ConnectException catch (e) {
    stdout.writeln('play: $e');
  }

  await Future<void>.delayed(const Duration(seconds: 3));
  final player = service.current.player;
  stdout.writeln('remote now: track=${player.trackUri}  context=${player.contextUri}  audible=${player.isAudible}');
  await service.stop();
  service.dispose();
  exit(0);
}
