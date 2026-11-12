import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../providers/preferences_provider.dart';
import '../../../widgets/desktop_lyrics_buttons.dart';
import '../widgets/settings_section.dart';

/// 桌面歌词：开关和锁定。没有桌面歌词控制器（Android、测试）时不显示。
class DesktopLyricsSection extends StatelessWidget {
  const DesktopLyricsSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!DesktopLyricsButtons.available(context)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final preferences = context.watch<PreferencesProvider>();
    final prefs = preferences.prefs;
    return SettingsSection(
      title: l10n.desktopLyricsSection,
      children: [
        SettingsSwitchTile(
          title: l10n.desktopLyricsShow,
          subtitle: l10n.desktopLyricsShowSubtitle,
          value: prefs.desktopLyrics,
          onChanged: (value) => preferences.update(
            preferences.prefs.copyWith(desktopLyrics: value),
          ),
        ),
        if (prefs.desktopLyrics)
          SettingsSwitchTile(
            title: l10n.desktopLyricsLock,
            subtitle: l10n.desktopLyricsLockSubtitle,
            value: prefs.desktopLyricsLocked,
            onChanged: (value) => preferences.update(
              preferences.prefs.copyWith(desktopLyricsLocked: value),
            ),
          ),
      ],
    );
  }
}
