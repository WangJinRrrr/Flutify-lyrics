import 'package:flutify_app/services/lyrics/lrc_parser.dart';
import 'package:flutify_app/services/lyrics/translation_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// 双语对照 LRC 拆分：同时间点的原文 + 译文合并为「原文行 + translation」。
void main() {
  test('同时间点的对照行拆成原文 + 译文', () {
    const lrc =
        '[00:01.00]walking down the road\n[00:01.00]走在路上\n'
        '[00:03.00]under the sky\n[00:03.00]天空下面\n'
        '[00:05.00]all night long\n[00:05.00]整夜不停';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc));
    expect(merged, isNotNull);
    expect(merged!.map((l) => l.words), [
      'walking down the road',
      'under the sky',
      'all night long',
    ]);
    expect(merged.map((l) => l.translation), ['走在路上', '天空下面', '整夜不停']);
    expect(merged.map((l) => l.startTimeMs), [1000, 3000, 5000]);
  });

  test('译文时间戳略微滞后（0.5 秒内）也能配对', () {
    const lrc =
        '[00:01.00]walking down the road\n[00:01.10]走在路上\n'
        '[00:03.00]under the sky\n[00:03.10]天空下面\n'
        '[00:05.00]all night long\n[00:05.10]整夜不停';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc));
    expect(merged, isNotNull);
    expect(merged!.map((l) => l.translation), ['走在路上', '天空下面', '整夜不停']);
    expect(merged.map((l) => l.startTimeMs), [1000, 3000, 5000]);
  });

  test('间奏空行保留；翻译署名行剔除，不进歌词也不当译文', () {
    const lrc =
        '[00:00.00]中文翻译：某某\n'
        '[00:01.00]walking down the road\n[00:01.00]走在路上\n'
        '[00:02.00]\n'
        '[00:03.00]under the sky\n[00:03.00]天空下面\n'
        '[00:05.00]all night long\n[00:05.00]整夜不停';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc))!;
    expect(
      merged.any((l) => l.words.contains('翻译')),
      isFalse,
      reason: '署名行不进歌词',
    );
    expect(merged.any((l) => l.words.isEmpty), isTrue, reason: '间奏行保留');
    expect(merged.where((l) => l.words.isEmpty).single.startTimeMs, 2000);
  });

  test('日文 + 中文对照：原文判为日文而不是中文译文', () {
    const lrc =
        '[00:01.00]道を歩いて\n[00:01.00]走在路上\n'
        '[00:03.00]空の下で\n[00:03.00]天空下面\n'
        '[00:05.00]夜通しずっと\n[00:05.00]整夜不停';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc))!;
    expect(merged.map((l) => l.words), ['道を歩いて', '空の下で', '夜通しずっと']);
    expect(merged.map((l) => l.translation), ['走在路上', '天空下面', '整夜不停']);
  });

  test('译文在前（中文行先出现）也把外文判为原文', () {
    const lrc =
        '[00:01.00]走在路上\n[00:01.00]walking down the road\n'
        '[00:03.00]天空下面\n[00:03.00]under the sky\n'
        '[00:05.00]整夜不停\n[00:05.00]all night long';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc))!;
    expect(merged.map((l) => l.words), [
      'walking down the road',
      'under the sky',
      'all night long',
    ]);
    expect(merged.map((l) => l.translation), ['走在路上', '天空下面', '整夜不停']);
    expect(
      TranslationMerge.originalText(merged),
      isNot(contains('走在路上')),
      reason: '选词器只看原文，不能是中文',
    );
  });

  test('译文在前的日文对照也把日文判为原文', () {
    const lrc =
        '[00:01.00]走在路上\n[00:01.00]道を歩いて\n'
        '[00:03.00]天空下面\n[00:03.00]空の下で\n'
        '[00:05.00]整夜不停\n[00:05.00]夜通しずっと';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc))!;
    expect(merged.map((l) => l.words), ['道を歩いて', '空の下で', '夜通しずっと']);
  });

  test('相差 20ms 但跨过 0.5 秒整点的两行也能配对', () {
    // 旧的固定时间桶：1240 → 桶 2，1260 → 桶 3，被拆开
    const lrc =
        '[00:01.24]walking down the road\n[00:01.26]走在路上\n'
        '[00:03.24]under the sky\n[00:03.26]天空下面\n'
        '[00:05.24]all night long\n[00:05.26]整夜不停';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc))!;
    expect(merged.map((l) => l.words), [
      'walking down the road',
      'under the sky',
      'all night long',
    ]);
    expect(merged.map((l) => l.translation), ['走在路上', '天空下面', '整夜不停']);
  });

  test('0.5 秒内两句原文 + 两句译文：各自配对，不吞原文也不丢译文', () {
    const lrc =
        '[00:01.00]line one\n[00:01.20]line two\n[00:01.00]第一句\n[00:01.20]第二句\n'
        '[00:04.00]line three\n[00:04.00]第三句\n'
        '[00:06.00]line four\n[00:06.00]第四句';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc))!;
    expect(merged.map((l) => l.words), [
      'line one',
      'line two',
      'line three',
      'line four',
    ]);
    expect(merged.map((l) => l.translation), ['第一句', '第二句', '第三句', '第四句']);
  });

  test('只剔除署名格式的行；歌词正文里含 translation / 翻译等词照常保留', () {
    const lrc =
        '[00:00.00]Translated by someone\n'
        '[00:00.50]by: 某某\n'
        '[00:01.00]lost in translation\n[00:01.00]迷失在翻译里\n'
        '[00:03.00]under the sky\n[00:03.00]天空下面\n'
        '[00:05.00]all night long\n[00:05.00]整夜不停';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc))!;
    expect(merged.map((l) => l.words), [
      'lost in translation',
      'under the sky',
      'all night long',
    ]);
    expect(merged.first.translation, '迷失在翻译里');
  });

  test('快歌同文种连唱行不丢行（0.5 秒内的两句原文都保留）', () {
    const lrc =
        '[00:01.00]line one\n[00:01.00]第一句\n'
        '[00:02.30]quick a\n[00:02.60]quick b\n'
        '[00:04.00]line three\n[00:04.00]第三句\n'
        '[00:06.00]line four\n[00:06.00]第四句';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc))!;
    expect(
      merged.map((l) => l.words),
      containsAllInOrder(['quick a', 'quick b']),
      reason: '同文种相邻行不是对照，两句都要留下',
    );
    expect(
      merged.where((l) => l.words == 'quick a').single.translation,
      isEmpty,
    );
  });

  test('日文 + 中文对照里零星的英文句（0.5 秒内紧接日文）是真歌词，不吞进译文', () {
    const lrc =
        '[00:01.00]道を歩いて\n[00:01.00]走在路上\n[00:01.30]oh baby\n'
        '[00:03.00]空の下で\n[00:03.00]天空下面\n'
        '[00:05.00]夜通しずっと\n[00:05.00]整夜不停\n'
        '[00:07.00]君を待って\n[00:07.00]等着你';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc))!;
    expect(merged.map((l) => l.words), [
      '道を歩いて',
      'oh baby',
      '空の下で',
      '夜通しずっと',
      '君を待って',
    ]);
    expect(merged.map((l) => l.translation), [
      '走在路上',
      '',
      '天空下面',
      '整夜不停',
      '等着你',
    ]);
  });

  test('没有对照结构的普通歌词返回 null', () {
    const lrc =
        '[00:01.00]a line\n[00:03.00]b line\n[00:05.00]c line\n[00:07.00]d line';
    expect(TranslationMerge.tryMerge(LrcParser.parse(lrc)), isNull);
  });

  test('整首混排但逐句对不上（前后半各一种语言）返回 null', () {
    const lrc =
        '[00:01.00]first verse in english\n[00:03.00]second line here\n'
        '[00:05.00]第三句开始中文\n[00:07.00]第四句中文歌词\n'
        '[00:09.00]fifth english line\n[00:11.00]第六句又是中文';
    expect(TranslationMerge.tryMerge(LrcParser.parse(lrc)), isNull);
  });

  test('originalText 只拼接原文，不掺译文', () {
    const lrc =
        '[00:01.00]walking down the road\n[00:01.00]走在路上\n'
        '[00:03.00]under the sky\n[00:03.00]天空下面\n'
        '[00:05.00]all night long\n[00:05.00]整夜不停';
    final merged = TranslationMerge.tryMerge(LrcParser.parse(lrc))!;
    expect(
      TranslationMerge.originalText(merged),
      'walking down the road\nunder the sky\nall night long',
    );
  });
}
