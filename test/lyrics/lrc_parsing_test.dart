import 'package:flutify_app/services/lyrics/lrc_parser.dart';
import 'package:flutify_app/services/lyrics/lyric_script.dart';
import 'package:flutify_app/services/lyrics/zh_script.dart';
import 'package:flutter_test/flutter_test.dart';

/// LRC 解析、文种识别、简繁转换（全部为合成文本）。
void main() {
  group('LrcParser', () {
    test('解析时间标签、忽略元信息、按时间排序', () {
      final lines = LrcParser.parse('[ar:Someone]\n[00:02.50]second\r\n[00:01.00]first\nplain text\n[01:00]minute');
      expect(lines.map((l) => l.startTimeMs), [1000, 2500, 60000]);
      expect(lines.map((l) => l.words), ['first', 'second', 'minute']);
    });

    test('一行多个时间标签展开为多行，空行保留为间奏', () {
      final lines = LrcParser.parse('[00:01.00][00:05.00]chorus\n[00:03.00]');
      expect(lines.map((l) => (l.startTimeMs, l.words)), [(1000, 'chorus'), (3000, ''), (5000, 'chorus')]);
    });

    test('同一时间点保持原有先后', () {
      final lines = LrcParser.parse('[00:01.00]a\n[00:01.00]b');
      expect(lines.map((l) => l.words), ['a', 'b']);
    });

    test('空文本返回空列表', () => expect(LrcParser.parse(''), isEmpty));
  });

  group('文种识别', () {
    test('detectLang 区分中日韩与拉丁', () {
      expect(detectLang('今天天气很好我们出去走走'), LyricLang.zh);
      expect(detectLang('きょうはいいてんきですね'), LyricLang.ja);
      expect(detectLang('오늘은 날씨가 좋네요'), LyricLang.ko);
      expect(detectLang('hello there my friend'), LyricLang.latin);
      expect(detectLang('привет мой друг'), LyricLang.cyrillic);
    });

    test('含少量假名的汉字歌词判为日语', () {
      expect(lyricLang('[00:01.00]夢の中で\n[00:02.00]君を見た\n[00:03.00]遠い空'), LyricLang.ja);
    });

    test('lineFamily：中日韩 / 拉丁 / 西里尔', () {
      expect(lineFamily('你好世界'), 0);
      expect(lineFamily('hello world'), 1);
      expect(lineFamily('привет'), 2);
    });
  });

  group('ZhScript', () {
    test('统计繁简专用字', () {
      expect(ZhScript.countTraditional('這裡會說話'), greaterThan(0));
      expect(ZhScript.countSimplified('这里会说话'), greaterThan(0));
      expect(ZhScript.countTraditional('hello'), 0);
    });

    test('繁简互转', () {
      expect(ZhScript.convert('這裡會說話', toSimplified: true), '这里会说话');
      // 一对多的字（里 → 裡 / 裏 / 里）不在对照表里，这里只用一一对应的字
      expect(ZhScript.convert('这会说话', toSimplified: false), '這會說話');
      expect(ZhScript.convert('abc 123', toSimplified: true), 'abc 123');
    });
  });
}
