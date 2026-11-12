import 'package:flutter/material.dart';

import 'accent_colors.dart';

/// Material 3 Expressive (MD3E) Color Tokens
/// Combining Spotify's signature vibrancy with Google Material 3 Expressive tonal surface hierarchy.
class MD3EColors {
  MD3EColors._();

  // Signature Spotify Vibrancy
  static const Color spotifyGreen = Color(0xFF1ED760);
  static const Color spotifyGreenDark = Color(0xFF1DB954);
  static const Color spotifyBlack = Color(0xFF121212);

  // M3 Expressive Dark Surface Hierarchy
  static const Color surfaceDim = Color(0xFF0F1014);
  static const Color surface = Color(0xFF121318);
  static const Color surfaceBright = Color(0xFF2E2F38);
  static const Color surfaceContainerLowest = Color(0xFF0A0B0E);
  static const Color surfaceContainerLow = Color(0xFF16171E);
  static const Color surfaceContainer = Color(0xFF1C1D26);
  static const Color surfaceContainerHigh = Color(0xFF23242F);
  static const Color surfaceContainerHighest = Color(0xFF2C2D3B);

  // On Surface & Text
  static const Color onSurface = Color(0xFFE4E1E9);
  static const Color onSurfaceVariant = Color(0xFFA5A4B2);
  static const Color outline = Color(0xFF494A57);
  static const Color outlineVariant = Color(0xFF32333E);

  // 浅色表面层级：语义与深色一致——Lowest 是窗口最底层（面板之间的缝隙、播放栏），
  // surface 是内容面板本身，Container 系列逐级加深用于卡片 / 输入框 / 悬停。
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceDim = Color(0xFFDCDDE3);
  static const Color lightSurfaceBright = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLowest = Color(0xFFEBECF0);
  static const Color lightSurfaceContainerLow = Color(0xFFF6F6F9);
  static const Color lightSurfaceContainer = Color(0xFFF0F0F4);
  static const Color lightSurfaceContainerHigh = Color(0xFFE9E9EF);
  static const Color lightSurfaceContainerHighest = Color(0xFFE1E2E9);
  static const Color lightOnSurface = Color(0xFF15161B);
  static const Color lightOnSurfaceVariant = Color(0xFF5C5D69);
  static const Color lightOutline = Color(0xFF8D8E9A);
  static const Color lightOutlineVariant = Color(0xFFD5D6DE);

  /// 浅色背景上的品牌绿：原色 #1ED760 在白底上对比度不足 2:1，文字 / 图标改用加深版。
  static const Color spotifyGreenOnLight = Color(0xFF12A04A);

  // Expressive Accent Accents (For Genres, Moods, Playlists)
  static const Color accentViolet = Color(0xFF9E54FF);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color accentPink = Color(0xFFFF4081);
  static const Color accentOrange = Color(0xFFFF6E40);
  static const Color accentAmber = Color(0xFFFFB74D);
  static const Color accentBlue = Color(0xFF2979FF);
  static const Color accentEmerald = Color(0xFF00E676);
  static const Color accentRose = Color(0xFFE91E63);

  // 纯黑（OLED）表面层级：底色纯黑，容器只做极轻的提亮，保留卡片 / 悬停的层次。
  static const Color oledSurfaceContainerLow = Color(0xFF0B0B0D);
  static const Color oledSurfaceContainer = Color(0xFF121214);
  static const Color oledSurfaceContainerHigh = Color(0xFF1A1A1E);
  static const Color oledSurfaceContainerHighest = Color(0xFF242428);

  /// 生成配色。[primary] 为用户的强调色（任意颜色），这里保证它作为文字 / 图标时在对应背景上可读：
  /// 深色下过暗会提亮，浅色下过亮会加深（Spotify 绿在浅色下即为 [spotifyGreenOnLight] 附近的深绿）。
  static ColorScheme createColorScheme({
    Color primary = spotifyGreen,
    Brightness brightness = Brightness.dark,
    bool pureBlack = false,
  }) {
    if (brightness == Brightness.dark) {
      final darkPrimary = AccentColors.readableOn(primary, surface);
      return ColorScheme(
        brightness: Brightness.dark,
        primary: darkPrimary,
        onPrimary: AccentColors.onAccent(darkPrimary),
        primaryContainer: darkPrimary.withAlpha(55),
        onPrimaryContainer: Colors.white,
        secondary: const Color(0xFF72D572),
        onSecondary: Colors.black,
        secondaryContainer: const Color(0xFF274E27),
        onSecondaryContainer: const Color(0xFFB5F2B5),
        tertiary: accentViolet,
        onTertiary: Colors.black,
        tertiaryContainer: accentViolet.withAlpha(55),
        onTertiaryContainer: const Color(0xFFEADBFF),
        error: const Color(0xFFFFB4AB),
        onError: const Color(0xFF690005),
        errorContainer: const Color(0xFF93000A),
        onErrorContainer: const Color(0xFFFFDAD6),
        surface: pureBlack ? Colors.black : surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
        surfaceContainerLowest: pureBlack ? Colors.black : surfaceContainerLowest,
        surfaceContainerLow: pureBlack ? oledSurfaceContainerLow : surfaceContainerLow,
        surfaceContainer: pureBlack ? oledSurfaceContainer : surfaceContainer,
        surfaceContainerHigh: pureBlack ? oledSurfaceContainerHigh : surfaceContainerHigh,
        surfaceContainerHighest: pureBlack ? oledSurfaceContainerHighest : surfaceContainerHighest,
        inverseSurface: const Color(0xFFE4E1E9),
        onInverseSurface: const Color(0xFF2F3036),
        inversePrimary: spotifyGreenDark,
        shadow: Colors.black,
      );
    } else {
      final lightPrimary = primary == spotifyGreen ? spotifyGreenOnLight : AccentColors.readableOn(primary, lightSurface);
      return ColorScheme(
        brightness: Brightness.light,
        primary: lightPrimary,
        onPrimary: AccentColors.onAccent(lightPrimary),
        primaryContainer: lightPrimary.withAlpha(40),
        onPrimaryContainer: const Color(0xFF00391A),
        secondary: const Color(0xFF2E7D32),
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFD7F5D9),
        onSecondaryContainer: const Color(0xFF0B3D10),
        tertiary: const Color(0xFF7A3FE0),
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFEBDDFF),
        onTertiaryContainer: const Color(0xFF2A0A5E),
        error: const Color(0xFFBA1A1A),
        onError: Colors.white,
        errorContainer: const Color(0xFFFFDAD6),
        onErrorContainer: const Color(0xFF410002),
        surface: lightSurface,
        onSurface: lightOnSurface,
        onSurfaceVariant: lightOnSurfaceVariant,
        outline: lightOutline,
        outlineVariant: lightOutlineVariant,
        surfaceDim: lightSurfaceDim,
        surfaceBright: lightSurfaceBright,
        surfaceContainerLowest: lightSurfaceContainerLowest,
        surfaceContainerLow: lightSurfaceContainerLow,
        surfaceContainer: lightSurfaceContainer,
        surfaceContainerHigh: lightSurfaceContainerHigh,
        surfaceContainerHighest: lightSurfaceContainerHighest,
        inverseSurface: const Color(0xFF2F3036),
        onInverseSurface: const Color(0xFFF2F0F7),
        inversePrimary: spotifyGreen,
        shadow: Colors.black,
      );
    }
  }
}
