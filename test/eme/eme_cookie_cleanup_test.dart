import 'dart:io';

import 'package:flutify_app/services/eme/eme_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// Exercise the Windows implementation supplied by flutter_inappwebview.
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Windows Cookie cleanup uses the shared EME environment and reports failure',
    () async {
      final previousPlatform = InAppWebViewPlatform.instance;
      WindowsInAppWebViewPlatform.registerWith();
      const environmentChannel = MethodChannel(
        'com.pichillilorenzo/flutter_webview_environment',
      );
      const cookieChannel = MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_cookiemanager',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? environmentId;
      final deletes = <MethodCall>[];
      var result = true;
      messenger.setMockMethodCallHandler(environmentChannel, (call) async {
        expect(call.method, 'create');
        environmentId = (call.arguments as Map)['id'] as String;
        return null;
      });
      messenger.setMockMethodCallHandler(cookieChannel, (call) async {
        deletes.add(call);
        return result;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(environmentChannel, null);
        messenger.setMockMethodCallHandler(cookieChannel, null);
        if (previousPlatform != null) {
          InAppWebViewPlatform.instance = previousPlatform;
        }
      });
      await EmePlayer.clearSessionCookies();
      expect(environmentId, isNotNull);
      expect(EmePlayer.cachedEnvironment?.id, environmentId);
      expect(deletes.single.method, 'deleteAllCookies');
      expect(
        (deletes.single.arguments as Map)['webViewEnvironmentId'],
        environmentId,
      );
      result = false;
      await expectLater(EmePlayer.clearSessionCookies(), throwsStateError);
      expect(
        (deletes.last.arguments as Map)['webViewEnvironmentId'],
        environmentId,
      );
    },
    skip: !Platform.isWindows,
  );
}
