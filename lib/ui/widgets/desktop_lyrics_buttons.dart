import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/preferences_provider.dart';
import '../../services/desktop_lyrics/desktop_lyrics_host.dart';
import '../screens/player/lyrics/glass_icon_button.dart';

/// 歌词面板上的桌面歌词开关和锁定。Android 没有控制器时不占位置。
class DesktopLyricsButtons extends StatelessWidget {
  final double size;

  const DesktopLyricsButtons({super.key, this.size = 36});

  static bool available(BuildContext context) {
    try {
      return context.read<DesktopLyricsController?>() != null;
    } on ProviderNotFoundException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!available(context)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final preferences = context.watch<PreferencesProvider>();
    final enabled = preferences.prefs.desktopLyrics;
    final locked = preferences.prefs.desktopLyricsLocked;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassIconButton(
            icon: Icons.lyrics_rounded,
            size: size,
            selected: enabled,
            tooltip: l10n.desktopLyricsToggle,
            onPressed: () => preferences.update(
              preferences.prefs.copyWith(desktopLyrics: !enabled),
            ),
          ),
          const SizedBox(width: 8),
          GlassIconButton(
            icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: size,
            selected: locked,
            tooltip: locked ? l10n.desktopLyricsUnlock : l10n.desktopLyricsLock,
            onPressed: enabled
                ? () => preferences.update(
                    preferences.prefs.copyWith(desktopLyricsLocked: !locked),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
