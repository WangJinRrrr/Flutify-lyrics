import 'dart:io';

import 'package:flutify_app/models/app_preferences.dart';
import 'package:flutify_app/models/lyrics.dart';
import 'package:flutify_app/services/desktop_lyrics/desktop_lyric_model.dart';
import 'package:flutify_app/services/desktop_lyrics/desktop_lyric_motion.dart';
import 'package:flutify_app/services/desktop_lyrics/desktop_lyrics_bounds.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('进度按锚点插值，时钟倒退时不回退', () {
    const anchor = LyricProgressAnchor(
      positionMs: 1000,
      anchoredAtMs: 5000,
      playing: true,
    );
    expect(anchor.positionAt(5000), 1000);
    expect(anchor.positionAt(6500), 2500);
    expect(anchor.positionAt(4200), 1000);
  });

  test('暂停时进度停住，远程播放才加上提前量', () {
    const playing = LyricProgressAnchor(
      positionMs: 1000,
      anchoredAtMs: 5000,
      playing: true,
    );
    const paused = LyricProgressAnchor(
      positionMs: 1000,
      anchoredAtMs: 5000,
      playing: false,
    );

    expect(paused.positionAt(9000), 1000);
    expect(
      lyricLookupMs(anchor: playing, nowMs: 5600, remote: false, leadMs: 400),
      1600,
    );
    expect(
      lyricLookupMs(anchor: playing, nowMs: 5600, remote: true, leadMs: 400),
      2000,
    );
    expect(
      lyricLookupMs(anchor: paused, nowMs: 9000, remote: true, leadMs: 250),
      1250,
    );
    expect(
      lyricLookupMs(anchor: paused, nowMs: 9000, remote: false, leadMs: 250),
      1000,
    );
  });

  test('整行点亮，不按字或 syllable 拆开', () {
    const line = LyricLine(
      startTimeMs: 0,
      words: 'hello world 今天',
      syllables: ['hel', 'lo', 'world', '今', '天'],
    );
    final data = DesktopLyricLineData.fromLine(line);
    expect(data.words, 'hello world 今天');
    expect(data.toMap().containsKey('syllables'), isFalse);

    final session = DesktopLyricSession()
      ..changeTrack(id: 'track', title: '歌')
      ..setLyrics(syncType: 'LINE_SYNCED', lines: [data]);
    final presentation = session.present(positionMs: 10, playing: true);

    expect(presentation.phase, DesktopLyricPhase.line);
    expect(presentation.units, ['hello world 今天']);
    expect(presentation.lightsWholeLine, isTrue);
    expect(glyphPosesFor(presentation), [GlyphPose.active]);
    expect(glyphPosesFor(presentation).length, 1);
  });

  test('空行和 ♪ 显示为间奏，句子里的 ♪ 仍是歌词', () {
    final session = DesktopLyricSession()
      ..changeTrack(id: 'track', title: '歌')
      ..setLyrics(
        syncType: 'LINE_SYNCED',
        lines: const [
          DesktopLyricLineData(startTimeMs: 0, words: ''),
          DesktopLyricLineData(startTimeMs: 1000, words: '  ♪  '),
          DesktopLyricLineData(startTimeMs: 2000, words: 'la ♪ la'),
        ],
      );

    expect(
      session.present(positionMs: 0, playing: true).text,
      DesktopLyricCopy.interlude,
    );
    expect(
      session.present(positionMs: 1000, playing: false).phase,
      DesktopLyricPhase.interlude,
    );
    final sung = session.present(positionMs: 2000, playing: true);
    expect(sung.text, 'la ♪ la');
    expect(sung.units, ['la ♪ la']);
  });

  test('第一句之前显示歌名', () {
    final session = DesktopLyricSession()
      ..changeTrack(id: 'track', title: '  夜航  ')
      ..setLyrics(
        syncType: 'LINE_SYNCED',
        lines: const [
          DesktopLyricLineData(startTimeMs: 8000, words: '第一句'),
        ],
      );
    final title = session.present(positionMs: 1200, playing: true);
    expect(title.phase, DesktopLyricPhase.title);
    expect(title.text, '夜航');
    expect(title.units, ['夜航']);
    expect(title.lightsWholeLine, isTrue);
  });

  test('载入中、无歌词、未同步各有提示，未同步不假装切行', () {
    final loading = DesktopLyricSession()
      ..changeTrack(id: 'track', title: '歌');
    expect(
      loading.present(positionMs: 0, playing: true).text,
      DesktopLyricCopy.loading,
    );

    final empty = DesktopLyricSession()
      ..changeTrack(id: 'track', title: '歌')
      ..fail();
    expect(
      empty.present(positionMs: 0, playing: true).text,
      DesktopLyricCopy.empty,
    );

    final unsynced = DesktopLyricSession()
      ..changeTrack(id: 'track', title: '歌')
      ..setLyrics(
        syncType: 'UNSYNCED',
        lines: const [
          DesktopLyricLineData(startTimeMs: 0, words: '一行'),
          DesktopLyricLineData(startTimeMs: 4000, words: '另一行'),
        ],
      );
    final presentation = unsynced.present(positionMs: 4500, playing: true);
    expect(presentation.phase, DesktopLyricPhase.unsynced);
    expect(presentation.text, DesktopLyricCopy.unsynced);
    expect(presentation.units, isEmpty);
    expect(glyphPosesFor(presentation), isEmpty);
  });

  test('暂停时呼吸停住，切歌先清空上一句', () {
    final session = DesktopLyricSession()
      ..changeTrack(id: 'a', title: '甲')
      ..setLyrics(
        syncType: 'LINE_SYNCED',
        lines: const [DesktopLyricLineData(startTimeMs: 0, words: '上一句')],
      );
    expect(session.present(positionMs: 10, playing: true).breathing, isTrue);
    expect(session.present(positionMs: 10, playing: false).breathing, isFalse);
    expect(session.present(positionMs: 10, playing: false).text, '上一句');

    session.changeTrack(id: 'b', title: '乙');
    final cleared = session.present(positionMs: 10, playing: true);
    expect(cleared.phase, DesktopLyricPhase.loading);
    expect(cleared.text, DesktopLyricCopy.loading);
    expect(cleared.text, isNot('上一句'));
    expect(cleared.units, isEmpty);
  });

  test('窗口位置写入 ui_desktop_lyrics_bounds，坏数据丢弃', () {
    expect(DesktopLyricsBounds.storageKey, 'ui_desktop_lyrics_bounds');
    const bounds = DesktopLyricsBounds(
      x: 12,
      y: 34,
      width: 860,
      height: 220,
    );
    expect(DesktopLyricsBounds.decode(bounds.encode()), bounds);
    expect(DesktopLyricsBounds.decode(''), isNull);
    expect(DesktopLyricsBounds.decode('{'), isNull);
    expect(
      DesktopLyricsBounds.decode('{"x":1,"y":2,"w":10,"h":10}'),
      isNull,
    );
    expect(
      DesktopLyricsBounds.decode('{"x":"a","y":2,"w":400,"h":200}'),
      isNull,
    );
  });

  test('文案与简体 arb 一致，快照不带逐字轴', () {
    expect(DesktopLyricCopy.loading, '正在载入歌词');
    expect(DesktopLyricCopy.empty, '暂无歌词');
    expect(DesktopLyricCopy.unsynced, '歌词未同步');
    expect(DesktopLyricCopy.interlude, '间奏');

    final arb = File('lib/l10n/app_zh.arb').readAsStringSync();
    expect(arb, contains('"desktopLyricsLoading": "正在载入歌词"'));
    expect(arb, contains('"desktopLyricsEmpty": "暂无歌词"'));
    expect(arb, contains('"desktopLyricsUnsynced": "歌词未同步"'));
    expect(arb, contains('"desktopLyricsInterlude": "间奏"'));
    expect(arb, contains('"desktopLyricsSection": "桌面歌词"'));

    final session = DesktopLyricSession()
      ..changeTrack(id: 'track', title: '歌')
      ..setFromSpotify(
        const SpotifyLyrics(
          syncType: 'LINE_SYNCED',
          lines: [
            LyricLine(
              startTimeMs: 0,
              words: '整行',
              translation: '译文',
              syllables: ['整', '行'],
            ),
          ],
        ),
      );
    final raw = session.toSnapshot(
      anchor: const LyricProgressAnchor(
        positionMs: 0,
        anchoredAtMs: 10,
        playing: false,
      ),
      remote: true,
      leadMs: 300,
      locked: true,
      accent: 0xFF1ED760,
    );
    final line = (raw['lines'] as List).single as Map;
    expect(line.keys, ['startTimeMs', 'words', 'translation']);
    expect(raw['leadMs'], 300);
    expect(raw['locked'], isTrue);

    final decoded = DesktopLyricsSnapshotView.decode(raw);
    final presentation = decoded.presentAt(10);
    expect(presentation.text, '整行');
    expect(presentation.translation, '译文');
    expect(presentation.units, ['整行']);
    expect(presentation.breathing, isFalse);
  });

  test('呼吸约 6.4 秒，入场离场含淡入缩放模糊，强调色双层光晕加深色投影', () {
    expect(LyricMotion.breathPeriod, const Duration(milliseconds: 6400));
    expect(LyricMotion.breathOffsetY(0), 0);
    expect(LyricMotion.breathOffsetY(0.25).abs(), LyricMotion.breathAmplitude);
    expect(LyricMotion.lineEnterPose.opacity, lessThan(1));
    expect(LyricMotion.lineEnterPose.scale, lessThan(1));
    expect(LyricMotion.lineEnterPose.blur, greaterThan(0));
    expect(LyricMotion.lineExitPose.opacity, lessThan(1));
    expect(LyricMotion.lineExitPose.scale, greaterThan(1));
    expect(LyricMotion.lineExitPose.blur, greaterThan(0));

    const emphasis = Color(0xFF1ED760);
    final shadows = lyricGlowShadows(emphasis);
    expect(shadows, hasLength(3));
    expect(shadows[0].blurRadius, isNot(shadows[1].blurRadius));
    expect(shadows[0].color.withAlpha(255), emphasis);
    expect(shadows[1].color.withAlpha(255), emphasis);
    expect(shadows[2].color.r, 0);
    expect(shadows[2].color.g, 0);
    expect(shadows[2].color.b, 0);
    expect(shadows[2].offset, isNot(Offset.zero));
  });

  test('桌面歌词开关和锁定可以随偏好保存', () {
    expect(AppPreferences.defaults.desktopLyrics, isFalse);
    expect(AppPreferences.defaults.desktopLyricsLocked, isFalse);
    final prefs = AppPreferences.defaults.copyWith(
      desktopLyrics: true,
      desktopLyricsLocked: true,
    );
    final decoded = AppPreferences.decode(prefs.encode());
    expect(decoded.desktopLyrics, isTrue);
    expect(decoded.desktopLyricsLocked, isTrue);
    expect(AppPreferences.fromJson({}).desktopLyrics, isFalse);
    expect(
      AppPreferences.fromJson({'desktopLyricsLocked': 'yes'}).desktopLyricsLocked,
      isFalse,
    );
  });
}
