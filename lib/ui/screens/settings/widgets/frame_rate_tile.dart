import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/appearance.dart';
import 'settings_segmented.dart';
import 'settings_slider_tile.dart';

/// 帧率上限：快捷档位 + 逐帧可调的滑杆。
///
/// - 档位「跟随屏幕」= 0（不限）；常用档位一键切换；
/// - 当前值不是任何档位时高亮「自定义」；
/// - 滑杆 1fps 一档，拖到与某个档位相同的值时该档位自动高亮。
class FrameRateTile extends StatelessWidget {
  /// 0 = 跟随屏幕。
  final int value;
  final ValueChanged<int> onChanged;

  const FrameRateTile({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const List<int> presets = [165, 144, 120, 90, 60];

  /// 「自定义」档位的占位值（不会被保存）。
  static const int _custom = -1;

  /// 屏幕刷新率，夹在滑杆范围内；平台报不出时按 60。
  static int get displayHz {
    final displays = PlatformDispatcher.instance.displays;
    final hz = displays.isEmpty ? 0.0 : displays.first.refreshRate;
    return (hz > 1 ? hz.round() : 60).clamp(
      AppearanceSettings.minFrameRateLimit,
      AppearanceSettings.maxFrameRateLimit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = value == 0 || presets.contains(value) ? value : _custom;
    // 跟随屏幕时滑杆停在屏幕刷新率上，表示「当前实际帧率」
    final sliderValue = value == 0 ? displayHz : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: SettingsSegmented<int>(
            values: const [0, ...presets, _custom],
            selected: selected,
            labelOf: (v) => switch (v) {
              0 => l10n.settingsFrameRateFollow,
              _custom => l10n.settingsFrameRateCustom,
              _ => '$v',
            },
            // 点「自定义」不改值，只是提示用滑杆调；当前若是跟随屏幕则落到屏幕刷新率
            onChanged: (v) => onChanged(v == _custom ? sliderValue : v),
          ),
        ),
        SettingsSliderTile(
          title: l10n.settingsFrameRate,
          subtitle: l10n.settingsFrameRateSubtitle,
          value: sliderValue.toDouble(),
          min: AppearanceSettings.minFrameRateLimit.toDouble(),
          max: AppearanceSettings.maxFrameRateLimit.toDouble(),
          divisions:
              AppearanceSettings.maxFrameRateLimit -
              AppearanceSettings.minFrameRateLimit,
          labelOf: (v) => l10n.settingsFrameRateValue(v.round()),
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}
