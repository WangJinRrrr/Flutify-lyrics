// 对照实验：用真 Edge（带 VMP 签名的 Widevine）打开 Flutify 的 EME 本地页，调用 emePlayHls()。
// 页面、清单、license 反代全部复用正在运行的 Flutify，唯一变量是生成 license 请求的 CDM。
//
//   dart run tool/edge_eme_probe.dart <EME 本地服务端口>
//
// 结果看 %TEMP%\flutify.log 里的 `license POST → HTTP …`。
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final port = args.first;
  const debugPort = 9333;
  final edge = [
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
  ].firstWhere((p) => File(p).existsSync());
  await Process.start(edge, [
    '--user-data-dir=${Directory.systemTemp.path}\\flutify_edge_probe',
    '--remote-debugging-port=$debugPort',
    '--autoplay-policy=no-user-gesture-required',
    '--no-first-run',
    'http://127.0.0.1:$port/eme',
  ]);

  // 等页面就绪，取它的调试 WebSocket
  String? wsUrl;
  for (var i = 0; i < 30 && wsUrl == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$debugPort/json'));
      final body = await (await req.close()).transform(utf8.decoder).join();
      client.close();
      for (final t in jsonDecode(body) as List) {
        if ((t['url'] as String).contains('127.0.0.1:$port')) wsUrl = t['webSocketDebuggerUrl'] as String;
      }
    } catch (_) {}
  }
  if (wsUrl == null) {
    stdout.writeln('没找到 EME 页面');
    exit(1);
  }
  await Future<void>.delayed(const Duration(seconds: 2));

  final ws = await WebSocket.connect(wsUrl);
  var id = 0;
  void send(String method, [Map<String, dynamic>? params]) =>
      ws.add(jsonEncode({'id': ++id, 'method': method, 'params': params ?? {}}));
  ws.listen((m) {
    final msg = jsonDecode(m as String) as Map<String, dynamic>;
    if (msg['method'] == 'Network.responseReceived') {
      final r = msg['params']['response'];
      stdout.writeln('[net] ${r['status']} ${r['url']}');
    } else if (msg['method'] == 'Runtime.consoleAPICalled') {
      stdout.writeln('[console] ${(msg['params']['args'] as List).map((a) => a['value']).join(' ')}');
    } else if (msg.containsKey('result')) {
      stdout.writeln('[result ${msg['id']}] ${jsonEncode(msg['result']).substring(0, 200.clamp(0, jsonEncode(msg['result']).length))}');
    }
  });
  send('Runtime.enable');
  // 页面通过 flutter_inappwebview 回传事件；Edge 里没有这个桥，补一个打印到控制台的替身
  send('Runtime.evaluate', {
    'expression': "window.flutter_inappwebview={callHandler:(n,s)=>console.log('evt',s)};"
        "navigator.requestMediaKeySystemAccess('com.widevine.alpha',[{audioCapabilities:[{contentType:'audio/mp4; codecs=\"mp4a.40.2\"'}]}]).then(()=>console.log('widevine OK'),e=>console.log('widevine ERR',e.message))",
  });
  await Future<void>.delayed(const Duration(seconds: 1));
  send('Network.enable');
  send('Runtime.evaluate', {'expression': 'emePlayHls()', 'awaitPromise': true});
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(seconds: 2));
    send('Runtime.evaluate', {
      'expression': "(()=>{const a=document.querySelector('audio');return a?('t='+a.currentTime.toFixed(1)+' rs='+a.readyState+' mk='+!!a.mediaKeys+' err='+(a.error&&a.error.message)):'no audio'})()",
    });
  }
  await ws.close();
  exit(0);
}

