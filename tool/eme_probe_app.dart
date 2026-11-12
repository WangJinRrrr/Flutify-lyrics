// EME 探针：验证「WebView2 隐藏页 + Widevine 隐私模式 + MSE」能否播放协议下载的加密曲目。
// 运行：flutter run -d windows -t tool/eme_probe_app.dart
//
// 用已下载的 blinding_128.m4a + pssh128.bin（D:\tmp），token 从 Flutify 的
// shared_preferences.json 读。成功标志：状态栏显示 playing 且进度推进、能听到歌。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:flutify_app/services/eme/eme_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EmeProbeApp());
}

class EmeProbeApp extends StatefulWidget {
  const EmeProbeApp({super.key});

  @override
  State<EmeProbeApp> createState() => _EmeProbeAppState();
}

class _EmeProbeAppState extends State<EmeProbeApp> {
  final EmePlayer _eme = EmePlayer();
  bool _ready = false;
  String _status = '初始化…';
  double _position = 0;
  double _duration = 0;

  @override
  void initState() {
    super.initState();
    _eme.stateStream.listen((s) => setState(() => _status = '状态: $s'));
    _eme.positionStream.listen((p) => setState(() => _position = p.inMilliseconds / 1000));
    _eme.durationStream.listen((d) => setState(() => _duration = d.inMilliseconds / 1000));
    _boot();
  }

  Future<void> _boot() async {
    // 先起服务 + 建自定义 WebView 环境（关自动播放限制），再启动无头 WebView
    await _eme.init();
    await EmePlayer.ensureEnvironment();
    await _eme.start();
    if (mounted) setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Map<String, dynamic> _prefs() {
    final appdata = Platform.environment['APPDATA']!;
    final f = File('$appdata\\com.flutify.music\\flutify_app\\shared_preferences.json');
    return jsonDecode(f.readAsStringSync());
  }

  String _pref(String key) {
    final v = _prefs()['flutter.$key'];
    if (v is String && v.startsWith('"')) return jsonDecode(v);
    return v?.toString() ?? '';
  }

  Future<Uint8List> _postLicense(Uint8List request) async {
    // 请求体大小是隐私模式判据：~4278B=加密 client_id（真密钥），~1741/2214B=明文（假密钥）
    debugPrint('[probe] license 请求体 ${request.length}B');
    // token 来源隔离实验：tmp\token_mix.txt 写 "web,app"（auth来源,ct来源），默认 web,web
    String auth = 'Bearer ${_pref('sp_access_token')}';
    String ct = _pref('sp_client_token');
    final wa = File(r'D:\Flutify\SpotifyApi\tmp\web_auth.txt');
    final wc = File(r'D:\Flutify\SpotifyApi\tmp\web_ct.txt');
    String mix = 'web,web';
    final mixFile = File(r'D:\Flutify\SpotifyApi\tmp\token_mix.txt');
    if (mixFile.existsSync()) mix = mixFile.readAsStringSync().trim();
    final parts = mix.split(',');
    final authSrc = parts.isNotEmpty ? parts[0] : 'web';
    final ctSrc = parts.length > 1 ? parts[1] : 'web';
    if (authSrc == 'web' && wa.existsSync()) auth = wa.readAsStringSync().trim();
    if (ctSrc == 'web' && wc.existsSync()) ct = wc.readAsStringSync().trim();
    debugPrint('[probe] token 来源: auth=$authSrc ct=$ctSrc');
    final res = await http.post(
      Uri.parse('https://gae2-spclient.spotify.com/widevine-license/v1/audio/license'),
      headers: {
        'Authorization': auth,
        'client-token': ct,
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36',
        'Referer': 'https://open.spotify.com/',
        'Content-Type': 'application/octet-stream',
      },
      body: request,
    );
    setState(() => _status = 'license HTTP ${res.statusCode} (${res.bodyBytes.length}B)');
    if (res.statusCode != 200) {
      throw StateError('license POST 失败: ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  Future<Uint8List> _fetchCert() async {
    final res = await http.get(
      Uri.parse('https://spclient.wg.spotify.com/widevine-license/v1/application-certificate'),
      headers: {
        'client-token': _pref('sp_client_token'),
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36',
        'Referer': 'https://open.spotify.com/',
      },
    );
    return res.bodyBytes;
  }

  Future<void> _run() async {
    try {
      setState(() => _status = '加载 HLS.js…');
      EmePlayer.hlsJsSource =
          File(r'D:\Flutify\SpotifyApi\tmp\hls.min.js').readAsStringSync();
      final m3u8 =
          File(r'D:\Flutify\SpotifyApi\tmp\blinding_p1.m3u8').readAsStringSync();
      setState(() => _status = 'EME 启动…');
      await _eme.play(
        m4a: File(r'D:\tmp\blinding_128.m4a'),
        m3u8: m3u8,
        licensePoster: _postLicense,
        certFetcher: _fetchCert,
      );
      setState(() => _status = '播放流程已启动');
    } catch (e) {
      setState(() => _status = '失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // EME WebView 是无头的（不进 widget 树），这里只需展示状态
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_ready ? _status : '初始化…', style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 12),
                  Text(
                    '${_position.toStringAsFixed(1)} / ${_duration.toStringAsFixed(1)} 秒',
                    style: const TextStyle(color: Colors.green, fontSize: 24),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(onPressed: _eme.pause, child: const Text('暂停')),
                      TextButton(onPressed: _eme.resume, child: const Text('继续')),
                      TextButton(
                        onPressed: () => _eme.seek(const Duration(seconds: 60)),
                        child: const Text('跳 60s'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
