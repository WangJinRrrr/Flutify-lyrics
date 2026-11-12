import 'dart:io';

import 'package:flutify_app/core/constants/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设置页「关于」显示的版本号必须与 pubspec.yaml 一致（发版改版本时防止漏改）。
void main() {
  test('AppInfo version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([\d.]+)\+(\d+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 缺少 version: x.y.z+n');
    expect(AppInfo.version, match!.group(1));
    expect(AppInfo.build, int.parse(match.group(2)!));
    expect(AppInfo.displayVersion, '${AppInfo.version} (${AppInfo.build})');
  });
}
