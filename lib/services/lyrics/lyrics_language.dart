import 'lyric_script.dart';
import 'zh_script.dart';

/// Language tags retain Chinese script; an unqualified `zh` matches both scripts
/// only when used as an exclusion. Unknown Latin text is not assumed English.
class LyricsLanguage {
  LyricsLanguage._();

  static String normalize(String tag) {
    final parts = tag.trim().replaceAll('_', '-').toLowerCase().split('-');
    if (parts.first != 'zh') return parts.first;
    if (parts.contains('hant')) return 'zh-Hant';
    if (parts.contains('hans')) return 'zh-Hans';
    if (parts.any(const ['tw', 'hk', 'mo'].contains)) return 'zh-Hant';
    if (parts.any(const ['cn', 'sg', 'my'].contains)) return 'zh-Hans';
    return 'zh';
  }

  static String of(String tag, String text) {
    final code = normalize(tag);
    if (code == 'zh') return chineseScript(text);
    if (code.isNotEmpty && code != 'und') return code;
    return switch (lyricLang(text)) {
      LyricLang.zh => chineseScript(text),
      LyricLang.ja => 'ja',
      LyricLang.ko => 'ko',
      _ => 'und',
    };
  }

  static String chineseScript(String text) {
    final traditional = ZhScript.countTraditional(text);
    final simplified = ZhScript.countSimplified(text);
    if (traditional > simplified) return 'zh-Hant';
    if (simplified > traditional) return 'zh-Hans';
    return 'zh';
  }

  static bool excluded(String source, String exclusion) {
    final code = normalize(exclusion);
    return source == code ||
        (code == 'zh' && source.startsWith('zh')) ||
        (source == 'zh' && code.startsWith('zh'));
  }

  static bool matches(String code, String target) =>
      code == target || (code == 'zh' && target.startsWith('zh'));
}
