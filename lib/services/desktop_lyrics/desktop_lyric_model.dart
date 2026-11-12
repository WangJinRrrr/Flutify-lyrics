import '../../models/lyrics.dart';

/// 桌面歌词用的进度锚点。
///
/// 子窗口拿到一次「此刻的进度 + 墙钟」之后，自己按锚点往前走，
/// 不必每一帧都向主窗口要进度。暂停时进度停在锚点上。
class LyricProgressAnchor {
  final int positionMs;
  final int anchoredAtMs;
  final bool playing;

  const LyricProgressAnchor({
    required this.positionMs,
    required this.anchoredAtMs,
    required this.playing,
  });

  /// [nowMs] 与 [anchoredAtMs] 用同一套时钟（墙钟毫秒）。
  int positionAt(int nowMs) {
    if (!playing) return positionMs;
    final delta = nowMs - anchoredAtMs;
    if (delta <= 0) return positionMs;
    return positionMs + delta;
  }
}

/// 歌词查找时间。远程播放才加上设置里的提前量，本机播放不加。
int lyricLookupMs({
  required LyricProgressAnchor anchor,
  required int nowMs,
  required bool remote,
  required int leadMs,
}) {
  final position = anchor.positionAt(nowMs);
  if (!remote || leadMs == 0) return position;
  return position + leadMs;
}

/// 桌面歌词的简体默认文案，与 `app_zh.arb` 中同名条目一致。
class DesktopLyricCopy {
  static const loading = '正在载入歌词';
  static const empty = '暂无歌词';
  static const unsynced = '歌词未同步';
  static const interlude = '间奏';
}

/// 主窗口按当前界面语言填好，再发给桌面歌词窗口。
class DesktopLyricMessages {
  final String loading;
  final String empty;
  final String unsynced;
  final String interlude;

  const DesktopLyricMessages({
    this.loading = DesktopLyricCopy.loading,
    this.empty = DesktopLyricCopy.empty,
    this.unsynced = DesktopLyricCopy.unsynced,
    this.interlude = DesktopLyricCopy.interlude,
  });

  static const fallback = DesktopLyricMessages();

  Map<String, String> toMap() => {
    'loading': loading,
    'empty': empty,
    'unsynced': unsynced,
    'interlude': interlude,
  };

  factory DesktopLyricMessages.fromMap(Object? raw) {
    if (raw is! Map) return fallback;
    String pick(String key, String fallbackText) {
      final value = raw[key];
      return value is String && value.isNotEmpty ? value : fallbackText;
    }

    return DesktopLyricMessages(
      loading: pick('loading', DesktopLyricCopy.loading),
      empty: pick('empty', DesktopLyricCopy.empty),
      unsynced: pick('unsynced', DesktopLyricCopy.unsynced),
      interlude: pick('interlude', DesktopLyricCopy.interlude),
    );
  }
}

/// 桌面歌词只保留行首时间和整行正文。`LyricLine.syllables` 没有时间，不进入这里。
class DesktopLyricLineData {
  final int startTimeMs;
  final String words;
  final String translation;

  const DesktopLyricLineData({
    required this.startTimeMs,
    required this.words,
    this.translation = '',
  });

  factory DesktopLyricLineData.fromLine(LyricLine line) {
    return DesktopLyricLineData(
      startTimeMs: line.startTimeMs,
      words: line.words,
      translation: line.translation,
    );
  }

  /// 空行，或正文只有一个 ♪，都当成间奏。句子里夹着 ♪ 仍是歌词。
  bool get isInterlude {
    final text = words.trim();
    return text.isEmpty || text == '♪';
  }

  Map<String, Object> toMap() => {
    'startTimeMs': startTimeMs,
    'words': words,
    'translation': translation,
  };

  static DesktopLyricLineData? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final start = raw['startTimeMs'];
    final words = raw['words'];
    if (start is! int || words is! String) return null;
    final translation = raw['translation'];
    return DesktopLyricLineData(
      startTimeMs: start,
      words: words,
      translation: translation is String ? translation : '',
    );
  }
}

enum DesktopLyricPhase { loading, empty, unsynced, title, line, interlude }

class DesktopLyricPresentation {
  final DesktopLyricPhase phase;
  final String text;
  final String translation;

  /// 要画出来的发光单位。有歌词时恰好是整行原文，不会按字或按 syllable 切开。
  final List<String> units;
  final bool breathing;

  const DesktopLyricPresentation({
    required this.phase,
    required this.text,
    this.translation = '',
    required this.units,
    required this.breathing,
  });

  bool get lightsWholeLine =>
      (phase == DesktopLyricPhase.line ||
          phase == DesktopLyricPhase.title ||
          phase == DesktopLyricPhase.interlude) &&
      units.length == 1 &&
      units.single == text;
}

/// 一首歌在桌面歌词里的状态。切歌时先清空，再进入载入。
class DesktopLyricSession {
  String? trackId;
  String title = '';
  bool loading = false;
  bool loaded = false;
  String? syncType;
  List<DesktopLyricLineData> lines = const [];
  DesktopLyricMessages messages = DesktopLyricMessages.fallback;

  void changeTrack({required String? id, required String title}) {
    trackId = id;
    this.title = title;
    loading = id != null;
    loaded = false;
    syncType = null;
    lines = const [];
  }

  void setLyrics({
    required String syncType,
    required List<DesktopLyricLineData> lines,
  }) {
    loading = false;
    loaded = true;
    this.syncType = syncType;
    this.lines = List.unmodifiable(lines);
  }

  void setFromSpotify(SpotifyLyrics lyrics) {
    setLyrics(
      syncType: lyrics.syncType,
      lines: [
        for (final line in lyrics.lines) DesktopLyricLineData.fromLine(line),
      ],
    );
  }

  void fail() {
    loading = false;
    loaded = true;
    syncType = 'LINE_SYNCED';
    lines = const [];
  }

  DesktopLyricPresentation present({
    required int positionMs,
    required bool playing,
  }) {
    if (trackId == null) {
      return _status(DesktopLyricPhase.empty, messages.empty);
    }
    if (!loaded || loading) {
      return _status(DesktopLyricPhase.loading, messages.loading);
    }
    if (lines.isEmpty) {
      return _status(DesktopLyricPhase.empty, messages.empty);
    }
    if (syncType != 'LINE_SYNCED') {
      return _status(DesktopLyricPhase.unsynced, messages.unsynced);
    }

    final index = _indexAt(positionMs);
    if (index < 0) {
      final titleText = title.trim().isEmpty ? messages.empty : title.trim();
      return DesktopLyricPresentation(
        phase: DesktopLyricPhase.title,
        text: titleText,
        units: [titleText],
        breathing: playing,
      );
    }

    final line = lines[index];
    if (line.isInterlude) {
      return DesktopLyricPresentation(
        phase: DesktopLyricPhase.interlude,
        text: messages.interlude,
        units: [messages.interlude],
        breathing: playing,
      );
    }
    return DesktopLyricPresentation(
      phase: DesktopLyricPhase.line,
      text: line.words,
      translation: line.translation,
      units: [line.words],
      breathing: playing,
    );
  }

  DesktopLyricPresentation _status(DesktopLyricPhase phase, String text) {
    return DesktopLyricPresentation(
      phase: phase,
      text: text,
      units: const [],
      breathing: false,
    );
  }

  int _indexAt(int ms) {
    var lo = 0, hi = lines.length - 1, result = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].startTimeMs <= ms) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }

  Map<String, Object?> toSnapshot({
    required LyricProgressAnchor anchor,
    required bool remote,
    required int leadMs,
    required bool locked,
    required int accent,
  }) {
    return {
      'trackId': trackId,
      'title': title,
      'loading': loading,
      'loaded': loaded,
      'syncType': syncType,
      'lines': [for (final line in lines) line.toMap()],
      'positionMs': anchor.positionMs,
      'anchoredAtMs': anchor.anchoredAtMs,
      'playing': anchor.playing,
      'remote': remote,
      'leadMs': remote ? leadMs : 0,
      'locked': locked,
      'accent': accent,
      'copy': messages.toMap(),
    };
  }

  void applySnapshot(Map raw) {
    final track = raw['trackId'];
    trackId = track is String && track.isNotEmpty ? track : null;
    final nextTitle = raw['title'];
    title = nextTitle is String ? nextTitle : '';
    loading = raw['loading'] == true;
    loaded = raw['loaded'] == true;
    final sync = raw['syncType'];
    syncType = sync is String ? sync : null;
    final rawLines = raw['lines'];
    if (rawLines is List) {
      final parsed = <DesktopLyricLineData>[];
      for (final entry in rawLines) {
        final line = DesktopLyricLineData.fromMap(entry);
        if (line != null) parsed.add(line);
      }
      lines = List.unmodifiable(parsed);
    } else {
      lines = const [];
    }
    messages = DesktopLyricMessages.fromMap(raw['copy']);
  }
}

class DesktopLyricsSnapshotView {
  final DesktopLyricSession session;
  final LyricProgressAnchor anchor;
  final bool remote;
  final int leadMs;
  final bool locked;
  final int accent;

  const DesktopLyricsSnapshotView({
    required this.session,
    required this.anchor,
    required this.remote,
    required this.leadMs,
    required this.locked,
    required this.accent,
  });

  factory DesktopLyricsSnapshotView.decode(Map raw) {
    final session = DesktopLyricSession()..applySnapshot(raw);
    final position = raw['positionMs'];
    final anchoredAt = raw['anchoredAtMs'];
    final accent = raw['accent'];
    final lead = raw['leadMs'];
    return DesktopLyricsSnapshotView(
      session: session,
      anchor: LyricProgressAnchor(
        positionMs: position is int ? position : 0,
        anchoredAtMs: anchoredAt is int ? anchoredAt : 0,
        playing: raw['playing'] == true,
      ),
      remote: raw['remote'] == true,
      leadMs: lead is int ? lead : 0,
      locked: raw['locked'] == true,
      accent: accent is int ? accent : 0xFF1ED760,
    );
  }

  DesktopLyricPresentation presentAt(int nowMs) {
    return session.present(
      positionMs: lyricLookupMs(
        anchor: anchor,
        nowMs: nowMs,
        remote: remote,
        leadMs: leadMs,
      ),
      playing: anchor.playing,
    );
  }
}
