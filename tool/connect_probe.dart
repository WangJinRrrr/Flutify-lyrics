// Spotify Connect 实测：用 App 已保存的会话，验证 dealer 长连接 + connect-state 注册 + 推送格式。
//
// 用法（在 app 目录）：
//   dart run tool/connect_probe.dart [监听秒数，默认 25]
//   dart run tool/connect_probe.dart service [秒数，默认 20]   # 用 ConnectService 做只读验证（不发任何控制命令）
//
// 步骤：apresolve → dealer WebSocket（取 Spotify-Connection-Id）→
//       PUT connect-state/v1/devices/hobs_{id}（隐藏观察者，不出现在别人的设备列表里）→ 监听推送。
// 终端只打印状态码、字段结构与计数，设备名只显示长度；完整响应写入 tool/probe_out/（已 gitignore），
// 含账号数据，不得复制进测试或文档。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutify_app/services/connect/connect_service.dart';
import 'package:http/http.dart' as http;

const _ua = 'Spotify/130100234 Win32_x86_64/0 (PC desktop)';
const _appVersion = '1.3.1.234.g59d6bf59';

final _out = Directory('tool/probe_out');

Future<void> main(List<String> args) async {
  // service 模式：用 App 里的 ConnectService 跑一遍（见文件末尾）
  if (args.isNotEmpty && args.first == 'service') {
    await _runServiceMode(args.length > 1 ? int.tryParse(args[1]) ?? 20 : 20);
    exit(0);
  }
  final listenSeconds = args.isNotEmpty ? int.tryParse(args.first) ?? 25 : 25;
  final prefs =
      jsonDecode(
            File(
              '${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final token = prefs['flutter.sp_access_token'] as String? ?? '';
  final clientToken = prefs['flutter.sp_client_token'] as String? ?? '';
  final expiry = prefs['flutter.sp_access_token_expiry'] as int? ?? 0;
  final left = Duration(milliseconds: expiry - DateTime.now().millisecondsSinceEpoch);
  stdout.writeln('会话：method=${prefs['flutter.sp_auth_method']} token 剩余 ${left.inMinutes} 分钟');
  if (token.isEmpty || left.isNegative) {
    stdout.writeln('access_token 缺失或已过期，请先打开一次 App 刷新');
    exit(1);
  }
  await _out.create(recursive: true);

  Map<String, String> headers({String accept = 'application/json'}) => {
    'Authorization': 'Bearer $token',
    if (clientToken.isNotEmpty) 'client-token': clientToken,
    'User-Agent': _ua,
    'app-platform': 'Win32_x86_64',
    'spotify-app-version': _appVersion,
    'Accept': accept,
  };

  // 1. apresolve：dealer 与 spclient 接入点
  final resolve = await http.get(Uri.parse('https://apresolve.spotify.com/?type=dealer&type=spclient'));
  final hosts = jsonDecode(resolve.body) as Map<String, dynamic>;
  final dealer = (hosts['dealer'] as List).first as String;
  final spclient = (hosts['spclient'] as List).first as String;
  stdout.writeln(
    'apresolve ${resolve.statusCode}: dealer=${dealer.split('.').skip(1).join('.')} '
    'spclient=${spclient.split('.').skip(1).join('.')}',
  );

  // 2. dealer：第一条消息的 headers 里带连接 id
  final ws = await WebSocket.connect(
    'wss://${dealer.replaceAll(':443', '')}/?access_token=$token',
    headers: {'User-Agent': _ua},
  );
  stdout.writeln('dealer 已连接');
  final messages = StreamController<Map<String, dynamic>>.broadcast();
  final log = StringBuffer();
  ws.listen((raw) {
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    final msg = jsonDecode(text) as Map<String, dynamic>;
    messages.add(msg);
  }, onDone: () => stdout.writeln('dealer 关闭：code=${ws.closeCode} reason=${ws.closeReason}'));
  final ping = Timer.periodic(const Duration(seconds: 10), (_) => ws.add(jsonEncode({'type': 'ping'})));

  final first = await messages.stream.first.timeout(const Duration(seconds: 10));
  final connHeaders = (first['headers'] as Map?)?.cast<String, dynamic>() ?? const {};
  final connectionId = connHeaders['Spotify-Connection-Id'] as String? ?? '';
  stdout.writeln(
    '首条消息 type=${first['type']} uri=${_maskUri(first['uri'] as String?)} '
    'connectionId 长度=${connectionId.length}',
  );
  if (connectionId.isEmpty) {
    stdout.writeln('没有拿到连接 id，退出');
    exit(1);
  }

  // 收集之后的推送
  var count = 0;
  final uriCounts = <String, int>{};
  final sub = messages.stream.listen((msg) {
    count++;
    final uri = _maskUri(msg['uri'] as String?);
    uriCounts[uri] = (uriCounts[uri] ?? 0) + 1;
    log.writeln('--- #$count type=${msg['type']} uri=${msg['uri']}');
    log.writeln('headers=${jsonEncode(msg['headers'])}');
    final payloads = msg['payloads'] as List?;
    if (payloads != null) {
      for (final p in payloads) {
        log.writeln('payload: ${_describePayload(p, msg['headers'] as Map?)}');
      }
    }
    if (msg['payload'] != null) log.writeln('payload(obj): ${jsonEncode(msg['payload'])}');
  });

  // 3. 注册隐藏观察者，读回 cluster
  final deviceId = 'hobs_${_hex(20)}';
  final put = await http.put(
    Uri.parse('https://${spclient.replaceAll(':443', '')}/connect-state/v1/devices/$deviceId'),
    headers: {...headers(), 'Content-Type': 'application/json', 'X-Spotify-Connection-Id': connectionId},
    body: jsonEncode({
      'member_type': 'CONNECT_STATE',
      'device': {
        'device_info': {
          'capabilities': {'can_be_player': false, 'hidden': true, 'needs_full_player_state': true},
        },
      },
    }),
  );
  stdout.writeln(
    'PUT connect-state ${put.statusCode} content-type=${put.headers['content-type']} '
    'bytes=${put.bodyBytes.length}',
  );
  File('${_out.path}/connect_cluster.raw').writeAsBytesSync(put.bodyBytes);
  _summarizeCluster(put);

  // 4. 监听推送
  stdout.writeln('监听推送 $listenSeconds 秒（可在手机上切歌 / 暂停，观察消息）…');
  await Future<void>.delayed(Duration(seconds: listenSeconds));
  await sub.cancel();
  ping.cancel();
  File('${_out.path}/connect_messages.txt').writeAsStringSync(log.toString());
  stdout.writeln('推送 $count 条：${uriCounts.entries.map((e) => '${e.key}×${e.value}').join(', ')}');

  // 5. 注销观察者
  final del = await http.delete(
    Uri.parse('https://${spclient.replaceAll(':443', '')}/connect-state/v1/devices/$deviceId'),
    headers: {...headers(), 'X-Spotify-Connection-Id': connectionId},
  );
  stdout.writeln('DELETE connect-state ${del.statusCode}');
  await ws.close();
  exit(0);
}

/// cluster 概要：只打印结构、计数与设备类型，名字只给长度。
void _summarizeCluster(http.Response res) {
  // 实测响应不带 content-type，按首字节判断是否 JSON
  final looksJson = res.bodyBytes.isNotEmpty && res.bodyBytes.first == 0x7b;
  if (!looksJson) {
    stdout.writeln(
      'cluster 非 JSON（前 16 字节 ${res.bodyBytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}）',
    );
    return;
  }
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  File('${_out.path}/connect_cluster.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  stdout.writeln('cluster 顶层字段：${data.keys.join(', ')}');
  stdout.writeln('active_device_id ${data['active_device_id'] == null ? '无' : '有'}');
  final devices = (data['devices'] as Map?)?.cast<String, dynamic>() ?? const {};
  stdout.writeln('devices ${devices.length} 台');
  for (final d in devices.values.cast<Map<String, dynamic>>()) {
    final caps = (d['capabilities'] as Map?)?.keys.length ?? 0;
    stdout.writeln(
      '  - type=${d['device_type']} nameLen=${(d['name'] as String?)?.length ?? 0} '
      'volume=${d['volume']} can_play=${(d['capabilities'] as Map?)?['can_be_player']} '
      'caps=$caps 字段=${d.keys.join('/')}',
    );
  }
  final player = data['player_state'] as Map?;
  if (player != null) {
    stdout.writeln(
      'player_state 字段：${player.keys.take(20).join(', ')}'
      '${player.keys.length > 20 ? ' …共 ${player.keys.length}' : ''}',
    );
    stdout.writeln(
      '  is_playing=${player['is_playing']} is_paused=${player['is_paused']} '
      'track=${player['track'] == null ? '无' : '有'}',
    );
  }
}

/// 推送 payload 的格式描述：JSON / base64（可能 gzip）/ 其他。
String _describePayload(Object? p, Map? headers) {
  if (p is Map) return 'json-object keys=${p.keys.join(',')} ${jsonEncode(p)}';
  if (p is! String) return 'unknown ${p.runtimeType}';
  try {
    List<int> bytes = base64.decode(p);
    final gzip_ = (headers?['Transfer-Encoding'] ?? headers?['transfer-encoding']) == 'gzip';
    if (gzip_ || (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b)) bytes = gzip.decode(bytes);
    try {
      final text = utf8.decode(bytes);
      final json = jsonDecode(text);
      return 'base64→${gzip_ ? 'gzip→' : ''}json ${json is Map ? 'keys=${json.keys.join(',')}' : ''} $text';
    } catch (_) {
      return 'base64→${gzip_ ? 'gzip→' : ''}binary ${bytes.length}B '
          '${bytes.take(24).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}';
    }
  } catch (_) {
    return 'string ${p.length} chars';
  }
}

/// uri 里可能带连接 id / 用户名，终端只保留路径骨架。
String _maskUri(String? uri) {
  if (uri == null) return '-';
  return uri.replaceAll(RegExp(r'connections/[^/]+'), 'connections/*').replaceAll(RegExp(r'user/[^/]+'), 'user/*');
}

String _hex(int bytes) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// service 模式：用 App 的 [ConnectService] 走完 start → 监听 → stop，只读，绝不发控制命令。
/// 终端只打印状态变化、设备数与推送次数；观察者 id 每次随机，不会与真实设备冲突。
Future<void> _runServiceMode(int seconds) async {
  final prefs =
      jsonDecode(
            File(
              '${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final token = prefs['flutter.sp_access_token'] as String? ?? '';
  final clientToken = prefs['flutter.sp_client_token'] as String? ?? '';
  final expiry = prefs['flutter.sp_access_token_expiry'] as int? ?? 0;
  final left = Duration(milliseconds: expiry - DateTime.now().millisecondsSinceEpoch);
  stdout.writeln('会话：method=${prefs['flutter.sp_auth_method']} token 剩余 ${left.inMinutes} 分钟');
  if (token.isEmpty || left.isNegative) {
    stdout.writeln('access_token 缺失或已过期，请先打开一次 App 刷新');
    return;
  }

  final client = http.Client();
  final service = ConnectService(
    client: client,
    headers: () async => {
      'Authorization': 'Bearer $token',
      if (clientToken.isNotEmpty) 'client-token': clientToken,
      'User-Agent': _ua,
      'app-platform': 'Win32_x86_64',
      'spotify-app-version': _appVersion,
      'Accept': 'application/json',
    },
    deviceId: () => '',
  );

  final watch = Stopwatch()..start();
  String at() => '[${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s]';
  var clusterCount = 0;
  final statusSub = service.statusChanges.listen((s) => stdout.writeln('${at()} 状态 → ${s.name}'));
  final clusterSub = service.clusters.listen((c) {
    clusterCount++;
    stdout.writeln(
      '${at()} cluster #$clusterCount 设备 ${c.devices.length} 台 '
      '活动设备=${c.activeDeviceId.isEmpty ? '无' : '有'} '
      '播放=${c.player.isPlaying} 暂停=${c.player.isPaused} 有曲目=${c.player.hasTrack}',
    );
  });

  stdout.writeln('observerId 格式正确=${RegExp(r'^hobs_[0-9a-f]{40}$').hasMatch(service.observerId)}');
  await service.start();
  stdout.writeln('${at()} start 完成：status=${service.status.name} 设备 ${service.current.devices.length} 台');
  stdout.writeln('监听 $seconds 秒（可在其他设备切歌 / 暂停观察推送；本脚本不发任何控制命令）…');
  await Future<void>.delayed(Duration(seconds: seconds));
  stdout.writeln(
    '${at()} 监听结束：共收到 cluster $clusterCount 次（含注册时的首个），'
    'serverNowMs 与本地时钟相差 ${(service.serverNowMs - DateTime.now().millisecondsSinceEpoch).abs()} ms',
  );

  await service.stop();
  stdout.writeln('${at()} stop 完成：status=${service.status.name}');
  await statusSub.cancel();
  await clusterSub.cancel();
  service.dispose();
  client.close();
}
