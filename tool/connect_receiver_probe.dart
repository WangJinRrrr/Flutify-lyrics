// Connect 播放端注册探针（track-playback 协议，Web 播放器同款）。
//
//   dart run tool/connect_receiver_probe.dart [在线秒数，默认 90]
//
// 流程：铸 Web token → Web client-token → 连 dealer 拿 connection_id → 注册设备 →
// 保持在线并打印收到的命令（此时可在手机 Spotify 的设备列表里找「Flutify」）→ 注销。
// 不处理播放、不请求 license。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36';
const _spclient = 'https://gae2-spclient.spotify.com';
const _dealer = 'wss://gae2-dealer.spotify.com/';

String _totp(List<int> secret, int ms) {
  final msg = ByteData(8)..setUint64(0, ms ~/ 1000 ~/ 30, Endian.big);
  final h = Hmac(sha1, secret).convert(msg.buffer.asUint8List()).bytes;
  final off = h.last & 0x0F;
  final code = (ByteData.sublistView(Uint8List.fromList(h), off, off + 4).getUint32(0) & 0x7FFFFFFF) % 1000000;
  return code.toString().padLeft(6, '0');
}

/// sp_dc + TOTP(v61) → Web token（与 WebTokenService 同算法）。
Future<(String token, String clientId)> _mintWebToken() async {
  final prefs = jsonDecode(File(
          '${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final dc = prefs['flutter.sp_dc'] as String;
  const obf = ',7/*F("rLJ2oxaKL^f+E1xvP@N';
  final secret = utf8.encode([for (var i = 0; i < obf.length; i++) obf.codeUnitAt(i) ^ ((i % 33) + 9)].join());
  final st = jsonDecode((await http.get(Uri.parse('https://open.spotify.com/api/server-time'))).body);
  final now = DateTime.now().millisecondsSinceEpoch;
  final res = await http.get(
      Uri.parse('https://open.spotify.com/api/token').replace(queryParameters: {
        'reason': 'transport',
        'productType': 'web-player',
        'totp': _totp(secret, now),
        'totpVer': '61',
        'totpServer': _totp(secret, (st['serverTime'] as num).toInt() * 1000),
      }),
      headers: {'Cookie': 'sp_dc=$dc', 'User-Agent': _ua});
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return (body['accessToken'] as String, body['clientId'] as String);
}

Future<String> _webClientToken(String clientId, String deviceId) async {
  final res = await http.post(Uri.parse('https://clienttoken.spotify.com/v1/clienttoken'),
      headers: {'content-type': 'application/json', 'accept': 'application/json', 'User-Agent': _ua},
      body: jsonEncode({
        'client_data': {
          'client_version': '1.3.5.31.ga27a71fef885',
          'client_id': clientId,
          'js_sdk_data': {
            'device_brand': 'unknown',
            'device_model': 'unknown',
            'os': 'windows',
            'os_version': 'NT 10.0',
            'device_id': deviceId,
            'device_type': 'computer',
          },
        },
      }));
  return (jsonDecode(res.body)['granted_token'] as Map)['token'] as String;
}

Future<void> main(List<String> args) async {
  final onlineSeconds = args.isEmpty ? 90 : int.parse(args.first);
  final deviceId = md5.convert(utf8.encode('flutify-connect-probe')).toString() +
      sha1.convert(utf8.encode('flutify')).toString().substring(0, 8);

  final (token, clientId) = await _mintWebToken();
  final ct = await _webClientToken(clientId, deviceId);
  stdout.writeln('Web token OK（client_id=$clientId），device_id=$deviceId');

  Map<String, String> headers() => {
        'Authorization': 'Bearer $token',
        'client-token': ct,
        'User-Agent': _ua,
        'Origin': 'https://open.spotify.com',
        'Referer': 'https://open.spotify.com/',
        'app-platform': 'WebPlayer',
        'spotify-app-version': '1.3.5.31.ga27a71fef885',
        'Content-Type': 'application/json',
      };

  // dealer：第一条 hm://pusher/v1/connections/ 消息的 Spotify-Connection-Id 头即 connection_id
  final ws = await WebSocket.connect('$_dealer?access_token=$token', headers: {'Origin': 'https://open.spotify.com'});
  final connectionId = Completer<String>();
  ws.listen((raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final uri = msg['uri'] as String? ?? '';
    if (uri.startsWith('hm://pusher/v1/connections/')) {
      final id = (msg['headers'] as Map?)?['Spotify-Connection-Id'] as String?;
      if (id != null && !connectionId.isCompleted) connectionId.complete(id);
      return;
    }
    if (msg['type'] == 'pong' || uri.startsWith('hm://playlist/')) return;
    if (uri == 'hm://track-playback/v1/command') {
      // 完整保存，供分析状态机结构
      final file = File('tool/probe_out/tp_command_${DateTime.now().millisecondsSinceEpoch}.json');
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(msg));
      final types = (msg['payloads'] as List).map((p) => (p as Map)['type']).join(',');
      stdout.writeln('[command] $types → ${file.path}');
      return;
    }
    final text = jsonEncode(msg);
    stdout.writeln('[dealer] ${msg['type']} $uri ${text.length > 600 ? '${text.substring(0, 600)}…' : text}');
  }, onDone: () => stdout.writeln('[dealer] 连接关闭 ${ws.closeCode} ${ws.closeReason}'));
  final ping = Timer.periodic(const Duration(seconds: 30), (_) => ws.add(jsonEncode({'type': 'ping'})));
  final cid = await connectionId.future.timeout(const Duration(seconds: 10));
  stdout.writeln('dealer 已连接，connection_id=${cid.substring(0, 16)}…');

  final reg = await http.post(Uri.parse('$_spclient/track-playback/v1/devices'),
      headers: headers(),
      body: jsonEncode({
        'device': {
          'brand': 'spotify',
          'capabilities': {
            'change_volume': true,
            'enable_play_token': true,
            'supports_file_media_type': true,
            'play_token_lost_behavior': 'pause',
            'disable_connect': false,
            'audio_podcasts': true,
            'video_playback': false,
            'manifest_formats': ['file_ids_mp3', 'file_urls_mp3', 'file_ids_mp4', 'file_ids_mp4_dual'],
          },
          'device_id': deviceId,
          'device_type': 'computer',
          'metadata': {},
          'model': 'web_player',
          'name': 'Flutify',
          'platform_identifier': 'web_player windows 10;chrome 154.0.0.0;desktop',
          'is_group': false,
        },
        'outro_endcontent_snooping': false,
        'connection_id': cid,
        'client_version': 'harmony:4.62.0',
        'volume': 65535,
      }));
  stdout.writeln('注册 HTTP ${reg.statusCode} ${reg.body.length > 400 ? reg.body.substring(0, 400) : reg.body}');

  if (reg.statusCode == 200) {
    stdout.writeln('>>> 在线 $onlineSeconds 秒：现在打开手机 Spotify → 设备列表，看有没有「Flutify」，可以试着选它或点播放');
    await Future<void>.delayed(Duration(seconds: onlineSeconds));
    // 注销要带最终状态（网页版 DELETE 带 seq_num / state_ref / sub_state）
    final del = await http.delete(Uri.parse('$_spclient/track-playback/v1/devices/$deviceId'),
        headers: headers(),
        body: jsonEncode({
          'seq_num': 2,
          'state_ref': null,
          'sub_state': {'playback_speed': 0, 'position': 0, 'duration': 0},
          'debug_source': 'deregister',
        }));
    stdout.writeln('注销 HTTP ${del.statusCode}');
  }
  ping.cancel();
  await ws.close();
  exit(0);
}
