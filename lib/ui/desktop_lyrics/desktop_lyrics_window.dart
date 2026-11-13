import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show MethodCall;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/desktop_lyrics/desktop_lyric_model.dart';
import '../../services/desktop_lyrics/desktop_lyric_motion.dart';
import '../../services/desktop_lyrics/desktop_lyrics_bounds.dart';
import '../../services/desktop_lyrics/desktop_lyrics_protocol.dart';
import 'lyric_breath.dart';

Future<void> runDesktopLyricsWindow() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 子引擎跑在独立 UI 线程上，原生侧注册 desktop_multi_window /
  // window_manager 插件与 Dart 启动并发。若在 runApp 之前就 await 插件调用，
  // release 包会因为注册尚未完成抛出 MissingPluginException，窗口一直停在
  // 隐藏的空白状态。先画出第一帧，再带重试连接父窗口。
  runApp(const DesktopLyricsApp());
}

class DesktopLyricsApp extends StatefulWidget {
  const DesktopLyricsApp({super.key});

  @override
  State<DesktopLyricsApp> createState() => _DesktopLyricsAppState();
}

class _DesktopLyricsAppState extends State<DesktopLyricsApp>
    with WindowListener, SingleTickerProviderStateMixin {
  static const _host = WindowMethodChannel(
    desktopLyricsHostChannel,
    mode: ChannelMode.unidirectional,
  );

  DesktopLyricsSnapshotView? _view;
  DesktopLyricPresentation _presentation = const DesktopLyricPresentation(
    phase: DesktopLyricPhase.empty,
    text: DesktopLyricCopy.empty,
    units: [],
    breathing: false,
  );
  bool _locked = false;
  bool _windowReady = false;
  String _lockTip = '锁定';
  String _closeTip = '关闭';
  Timer? _saveTimer;
  late final Ticker _ticker = createTicker((_) => _tick());

  @override
  void initState() {
    super.initState();
    _ticker.start();
    unawaited(_start());
  }

  Future<void> _start() async {
    String? windowId;
    try {
      // fromCurrentEngine / window_manager 都要等原生插件注册完成。
      // 两者与 Dart main 并发，release 包里这个窗口经常输在起跑线上。
      final controller = await _retry<WindowController>(
        WindowController.fromCurrentEngine,
      );
      windowId = controller.windowId;
      if (!mounted) return;
      await _retry<void>(
        () => controller.setWindowMethodHandler(_onWindowCall),
      );
      await _retry<void>(windowManager.ensureInitialized);
      if (!mounted) return;
      await _prepareWindow();
      if (!mounted) return;
      setState(() => _windowReady = true);
      // 带上 windowId：主窗口可能已经因为超时重建了窗口，旧引擎的就绪消息
      // 不能把新窗口误判为已就绪。
      await _retry<void>(() => _host.invokeMethod<void>('ready', windowId));
    } catch (error, stack) {
      _logFailure(error, stack);
      try {
        await _host.invokeMethod<void>('failed', {
          'windowId': windowId,
          'error': '$error',
        });
      } catch (_) {}
    }
  }

  /// 子引擎没有走 [installFileLog]，release 包里的 debugPrint 也看不到。
  /// 初始化失败时单独留一份日志，方便定位「开关打开了但窗口一直空白」。
  void _logFailure(Object error, StackTrace stack) {
    debugPrint('[desktop-lyrics] 子窗口初始化失败: $error\n$stack');
    try {
      File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'flutify-desktop-lyrics.log',
      ).writeAsStringSync(
        '${DateTime.now().toIso8601String()} $error\n$stack\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  Future<dynamic> _onWindowCall(MethodCall call) async {
    if (call.method == 'snapshot' && call.arguments is Map) {
      _apply(Map<dynamic, dynamic>.from(call.arguments as Map));
    }
    return null;
  }

  /// 插件注册和子引擎启动是并行的，早期调用会抛 MissingPluginException。
  /// 在 [timeout] 内不断重试，直到原生侧就位。
  Future<T> _retry<T>(
    Future<T> Function() action, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        return await action();
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  Future<void> _step(String name, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('[desktop-lyrics] $name 失败，继续显示窗口: $error');
    }
  }

  Future<void> _prepareWindow() async {
    final bounds = await _restoredBounds();
    await _step(
      'setMinimumSize',
      () => windowManager.setMinimumSize(
        const Size(DesktopLyricsBounds.minWidth, DesktopLyricsBounds.minHeight),
      ),
    );
    await _step(
      'setBounds',
      () => windowManager.setBounds(
        Rect.fromLTWH(bounds.x, bounds.y, bounds.width, bounds.height),
      ),
    );
    await _step('setTitle', () => windowManager.setTitle('桌面歌词'));
    // Windows 上 setAsFrameless / setAlwaysOnTop 会把进程打成 0xC0000005，
    // 无边框和置顶由子窗口创建回调直接写子 HWND。
    if (!Platform.isWindows) {
      await _step('setAsFrameless', windowManager.setAsFrameless);
      await _step('setSkipTaskbar', () => windowManager.setSkipTaskbar(true));
      await _step('setAlwaysOnTop', () => windowManager.setAlwaysOnTop(true));
    }
    // 透明背景只改 DWM 合成属性，不碰窗口样式；逐窗口的调用不会动主窗口。
    await _step(
      'setBackgroundColor',
      () => windowManager.setBackgroundColor(Colors.transparent),
    );
    windowManager.addListener(this);
    // 不在这里 show：主窗口只会在「已经收到快照」时把窗口显示出来。
    // 否则子窗口如果晚了几秒才连上，会在用户已经关掉开关之后自己冒出来。
  }

  Future<DesktopLyricsBounds> _restoredBounds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = DesktopLyricsBounds.decode(
        prefs.getString(DesktopLyricsBounds.storageKey) ?? '',
      );
      if (saved != null) return saved;
    } catch (_) {}
    const width = 860.0;
    const height = 320.0;
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final origin = display.visiblePosition ?? Offset.zero;
      final size = display.visibleSize ?? display.size;
      return DesktopLyricsBounds(
        x: origin.dx + (size.width - width) / 2,
        y: origin.dy + size.height - height - 72,
        width: width,
        height: height,
      );
    } catch (_) {
      return const DesktopLyricsBounds(
        x: 240,
        y: 640,
        width: width,
        height: height,
      );
    }
  }

  void _apply(Map<dynamic, dynamic> raw) {
    final view = DesktopLyricsSnapshotView.decode(raw);
    _view = view;
    final tips = raw['tooltips'];
    if (tips is Map) {
      final lock = tips['lock'];
      final close = tips['close'];
      if (lock is String && lock.isNotEmpty) _lockTip = lock;
      if (close is String && close.isNotEmpty) _closeTip = close;
    }
    final locked = view.locked;
    if (locked != _locked && _windowReady) {
      unawaited(_applyLock(locked));
    }
    _locked = locked;
    _presentation = view.presentAt(DateTime.now().millisecondsSinceEpoch);
    if (mounted) setState(() {});
  }

  void _tick() {
    final view = _view;
    if (view == null || !mounted) return;
    final next = view.presentAt(DateTime.now().millisecondsSinceEpoch);
    if (_samePresentation(next, _presentation)) return;
    setState(() => _presentation = next);
  }

  bool _samePresentation(
    DesktopLyricPresentation next,
    DesktopLyricPresentation current,
  ) {
    return next.phase == current.phase &&
        next.text == current.text &&
        next.translation == current.translation &&
        next.breathing == current.breathing;
  }

  Future<void> _applyLock(bool locked) async {
    try {
      await windowManager.setIgnoreMouseEvents(locked, forward: true);
      // window_manager 的点击穿透只给窗口加上 WS_EX_LAYERED，却没有设置
      // 分层属性；Windows 上这样的窗口不会绘制，歌词会直接消失。
      // setOpacity(1) 会补上 SetLayeredWindowAttributes，保持完全不透明。
      if (locked && Platform.isWindows) {
        await windowManager.setOpacity(1);
      }
    } catch (error) {
      debugPrint('[desktop-lyrics] 锁定鼠标失败: $error');
    }
    if (mounted) setState(() => _locked = locked);
  }

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowResized() => _scheduleSave();

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveBounds());
    });
  }

  Future<void> _saveBounds() async {
    try {
      final rect = await windowManager.getBounds();
      final encoded = DesktopLyricsBounds(
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height,
      ).encode();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(DesktopLyricsBounds.storageKey, encoded);
    } catch (error) {
      debugPrint('[desktop-lyrics] 保存位置失败: $error');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _ticker.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(_view?.accent ?? 0xFF1ED760);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        fontFamily: 'MiSans',
        splashFactory: NoSplash.splashFactory,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: _locked
              ? null
              : (_) {
                  unawaited(windowManager.startDragging());
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 20, 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_locked) _controls(),
                LyricBreath(
                  paused: !_presentation.breathing,
                  child: _line(accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _lockTip,
            onPressed: () => unawaited(_host.invokeMethod<void>('setLocked', true)),
            icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
          ),
          IconButton(
            tooltip: _closeTip,
            onPressed: () => unawaited(_host.invokeMethod<void>('close')),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _line(Color accent) {
    final presentation = _presentation;
    final identity =
        '${presentation.phase.name}|${presentation.text}|${presentation.translation}';
    return AnimatedSwitcher(
      duration: LyricMotion.lineMoveDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) {
        return Stack(
          alignment: Alignment.center,
          children: [...previous, ?current],
        );
      },
      transitionBuilder: (child, animation) {
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final exiting =
                animation.status == AnimationStatus.reverse ||
                animation.status == AnimationStatus.dismissed;
            final pose = exiting
                ? LyricMotion.lineSettledPose.lerp(
                    LyricMotion.lineExitPose,
                    1 - animation.value,
                  )
                : LyricMotion.lineEnterPose.lerp(
                    LyricMotion.lineSettledPose,
                    animation.value,
                  );
            Widget body = Opacity(
              opacity: pose.opacity.clamp(0, 1),
              child: Transform.scale(scale: pose.scale, child: child),
            );
            if (pose.blur > 0.05) {
              body = ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: pose.blur,
                  sigmaY: pose.blur,
                  tileMode: TileMode.decal,
                ),
                child: body,
              );
            }
            return body;
          },
        );
      },
      child: _lineBody(ValueKey(identity), presentation, accent),
    );
  }

  Widget _lineBody(
    Key key,
    DesktopLyricPresentation presentation,
    Color accent,
  ) {
    final poses = glyphPosesFor(presentation);
    final lit = poses.length == 1 && poses.single == GlyphPose.active;
    final style = TextStyle(
      fontFamily: 'MiSans',
      color: Colors.white,
      fontSize: presentation.phase == DesktopLyricPhase.line ? 64 : 36,
      fontWeight: FontWeight.w700,
      height: 1.2,
      shadows: lit
          ? lyricGlowShadows(accent)
          : const [
              Shadow(
                color: Color(0xCC000000),
                offset: Offset(0, 2),
                blurRadius: 8,
              ),
            ],
    );
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: lit ? GlyphPose.active.scale : 1,
          child: Text(
            presentation.text,
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
        if (presentation.translation.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            presentation.translation,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'MiSans',
              color: Color(0xE6FFFFFF),
              fontSize: 18,
              fontWeight: FontWeight.w500,
              height: 1.25,
              shadows: [
                Shadow(
                  color: Color(0xCC000000),
                  offset: Offset(0, 1),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
