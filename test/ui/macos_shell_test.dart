import 'package:flutify_app/l10n/l10n.dart';
import 'package:flutify_app/services/media_controls/macos_media_controls.dart';
import 'package:flutify_app/services/media_controls/system_media_controls.dart';
import 'package:flutify_app/ui/shell/desktop/desktop_window.dart';
import 'package:flutify_app/ui/shell/desktop/mac_menu_bar.dart';
import 'package:flutify_app/ui/widgets/connect/playback_shortcuts.dart';
import 'package:flutify_app/ui/widgets/keyboard_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// macOS 壳层：⌘ 快捷键与键帽、原生菜单栏、系统媒体控制通道（与 MediaControlsChannel.swift 同协议）。
/// 用 [DesktopWindow.debugMacNativeWindowOverride] 在任意平台模拟 macOS 原生窗口模式。
void main() {
  tearDown(() => DesktopWindow.debugMacNativeWindowOverride = null);

  group('PlatformShortcuts', () {
    test('macOS：主修饰键为 ⌘，提示按 ⌥⇧⌘ 顺序紧凑排', () {
      DesktopWindow.debugMacNativeWindowOverride = true;
      final k = PlatformShortcuts.primary(LogicalKeyboardKey.keyK);
      expect(k.meta, isTrue);
      expect(k.control, isFalse);
      expect(PlatformShortcuts.hintText('Ctrl K'), '⌘K');
      expect(PlatformShortcuts.hintText('Alt+Shift+B'), '⌥⇧B');
      expect(PlatformShortcuts.hintText('Shift+Ctrl+S'), '⇧⌘S');
      expect(PlatformShortcuts.keyCaps('Alt+Shift+B'), ['⌥', '⇧', 'B']);
    });

    test('其余平台：Ctrl / Alt 原样不变', () {
      DesktopWindow.debugMacNativeWindowOverride = false;
      final k = PlatformShortcuts.primary(LogicalKeyboardKey.keyK, shift: true);
      expect(k.control, isTrue);
      expect(k.meta, isFalse);
      expect(k.shift, isTrue);
      expect(PlatformShortcuts.hintText('Ctrl K'), 'Ctrl K');
      expect(PlatformShortcuts.keyCaps('Alt+Shift+B'), ['Alt', 'Shift', 'B']);
    });
  });

  group('MacOSMediaControls', () {
    const channel = MethodChannel('flutify/media_controls');

    testWidgets('曲目与播放状态按 Swift 端约定的键名下发', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final controls = MacOSMediaControls();
      addTearDown(controls.dispose);

      await controls.setTrack(
        const MediaTrackInfo(
          id: 't1',
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          artUrl: 'https://i.scdn.co/image/x',
          duration: Duration(seconds: 200),
        ),
      );
      await controls.setPlayback(
        const MediaPlaybackInfo(
          playing: true,
          buffering: false,
          position: Duration(milliseconds: 1500),
          canNext: true,
          canPrevious: false,
        ),
      );
      await controls.setTrack(null);

      expect(calls.map((c) => c.method), [
        'setTrack',
        'setPlayback',
        'setTrack',
      ]);
      expect(calls[0].arguments, {
        'title': 'Song',
        'artist': 'Artist',
        'album': 'Album',
        'artUrl': 'https://i.scdn.co/image/x',
        'durationMs': 200000,
      });
      expect(calls[1].arguments, {
        'playing': true,
        'buffering': false,
        'positionMs': 1500,
        'canNext': true,
        'canPrevious': false,
      });
      expect(calls[2].arguments, isNull);
      expect(controls.needsPeriodicTimeline, isFalse);
    });

    testWidgets('媒体键 / 控制中心的按键与拖动进度转成事件', (tester) async {
      final controls = MacOSMediaControls();
      addTearDown(controls.dispose);
      final events = <MediaControlEvent>[];
      final sub = controls.events.listen(events.add);
      addTearDown(sub.cancel);

      Future<void> fromNative(String method, Object? args) =>
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall(method, args)),
            (_) {},
          );
      await fromNative('button', 'toggle');
      await fromNative('button', 'next');
      await fromNative('button', 'unknown'); // 未知按键忽略
      await fromNative('seek', 12345);
      await tester.pump();

      expect(events, hasLength(3));
      expect((events[0] as MediaButtonEvent).button, MediaButton.toggle);
      expect((events[1] as MediaButtonEvent).button, MediaButton.next);
      expect(
        (events[2] as MediaSeekEvent).position,
        const Duration(milliseconds: 12345),
      );
    });
  });

  group('MacMenuBar', () {
    /// 在 Menu.setMenus 的载荷里按 label 找第一个节点（深度优先）。
    Map<Object?, Object?>? findMenu(Object? node, String label) {
      if (node is Map) {
        if (node['label'] == label) return node;
        for (final value in node.values) {
          final hit = findMenu(value, label);
          if (hit != null) return hit;
        }
      } else if (node is List) {
        for (final value in node) {
          final hit = findMenu(value, label);
          if (hit != null) return hit;
        }
      }
      return null;
    }

    testWidgets(
      '「窗口」菜单能叫回主窗口、打开全屏歌词；依赖主界面的项在注册前禁用',
      (tester) async {
        DesktopWindow.debugMacNativeWindowOverride = true;
        addTearDown(() => MacMenuBar.actions.value = null);
        final menus = <Object?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.menu,
          (call) async {
            if (call.method == 'Menu.setMenus') menus.add(call.arguments);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.menu,
            null,
          ),
        );
        final l10n = lookupAppLocalizations(const Locale('en'));

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MacMenuBar(child: child!),
            home: const SizedBox(key: ValueKey('home')),
          ),
        );
        await tester.pump();

        Map<Object?, Object?> windowItem(String label) => findMenu(
          findMenu(menus.last, l10n.menuWindow)!["children"],
          label,
        )!;
        final mainWindow = windowItem('Flutify');
        expect(mainWindow['enabled'], isTrue);
        expect(mainWindow['shortcutTrigger'], LogicalKeyboardKey.digit0.keyId);
        final immersive = windowItem(l10n.shortcutImmersive);
        expect(immersive['shortcutTrigger'], LogicalKeyboardKey.keyF.keyId);
        expect(immersive['enabled'], isFalse);
        expect(findMenu(menus.last, l10n.menuSettings)!['enabled'], isFalse);

        // 主界面挂载后登记动作：相关菜单项变为可用
        final context = tester.element(find.byKey(const ValueKey('home')));
        MacMenuBar.actions.value = MacMenuActions(
          onSearch: () {},
          onBack: () {},
          onForward: () {},
          onHome: () {},
          onOpenSettings: () {},
          onImmersive: () {},
          onTogglePlayPause: () {},
          playback: PlaybackShortcuts.actions(context),
        );
        await tester.pump();
        await tester.pump();
        expect(windowItem(l10n.shortcutImmersive)['enabled'], isTrue);
        expect(findMenu(menus.last, l10n.menuSettings)!['enabled'], isTrue);
      },
      // 系统提供的菜单项（关于 / 退出 / 最小化……）只在 macOS 目标平台存在
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });
}
