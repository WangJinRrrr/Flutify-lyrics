import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/lyrics_query.dart';
import '../../models/track.dart';
import '../../providers/appearance_provider.dart';
import '../../providers/connect_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/spotify_provider.dart';
import '../../services/desktop_lyrics/desktop_lyric_model.dart';
import '../../services/desktop_lyrics/desktop_lyrics_host.dart';
import '../../services/desktop_lyrics/desktop_lyrics_smoke.dart';

/// 把正在播放的曲目、歌词和进度交给桌面歌词窗口。
///
/// 进度沿用 [PlaybackProvider] 或 Connect 的远程进度，歌词沿用 [SpotifyProvider.fetchLyrics]。
/// 子窗口按锚点自己往前走；这里只在播放状态变化、拖动进度或大约每秒校正一次。
/// 没有注入控制器（Android、测试）时原样返回 [child]。
class DesktopLyricsBinding extends StatefulWidget {
  final Widget child;

  const DesktopLyricsBinding({super.key, required this.child});

  @override
  State<DesktopLyricsBinding> createState() => _DesktopLyricsBindingState();
}

class _DesktopLyricsBindingState extends State<DesktopLyricsBinding> {
  DesktopLyricsController? _controller;
  PlaybackProvider? _playback;
  ConnectProvider? _connect;
  PreferencesProvider? _preferences;
  AppearanceProvider? _appearance;
  SpotifyProvider? _spotify;
  StreamSubscription<String>? _lyricsCached;

  final DesktopLyricSession _session = DesktopLyricSession();
  LyricProgressAnchor _anchor = const LyricProgressAnchor(
    positionMs: 0,
    anchoredAtMs: 0,
    playing: false,
  );
  int _generation = 0;
  String? _trackId;
  bool _remote = false;
  int _leadMs = 0;
  int _lastSentMs = 0;
  bool _smokeGaveUp = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<DesktopLyricsController?>();
    _controller = controller;
    if (controller == null) return;
    controller
      ..onLockChanged = _setLocked
      ..onClose = _close
      ..onOpenFailed = _openFailed;
    _playback = context.read<PlaybackProvider>();
    _connect = context.read<ConnectProvider>();
    _preferences = context.read<PreferencesProvider>();
    _appearance = context.read<AppearanceProvider>();
    _spotify = context.read<SpotifyProvider>();
    _playback!.addListener(_onSource);
    _playback!.positionNotifier.addListener(_onPosition);
    _connect!.addListener(_onSource);
    _connect!.position.addListener(_onPosition);
    _preferences!.addListener(_onSource);
    _appearance!.addListener(_onSource);
    _lyricsCached = _spotify!.lyricsCached.listen(_onLyricsCached);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onSource();
    });
  }

  @override
  void dispose() {
    _playback?.removeListener(_onSource);
    _playback?.positionNotifier.removeListener(_onPosition);
    _connect?.removeListener(_onSource);
    _connect?.position.removeListener(_onPosition);
    _preferences?.removeListener(_onSource);
    _appearance?.removeListener(_onSource);
    unawaited(_lyricsCached?.cancel());
    final controller = _controller;
    if (controller != null) {
      controller
        ..onLockChanged = null
        ..onClose = null
        ..onOpenFailed = null;
    }
    super.dispose();
  }

  void _setLocked(bool locked) {
    final preferences = _preferences;
    if (preferences == null) return;
    if (preferences.prefs.desktopLyricsLocked == locked) return;
    preferences.update(
      preferences.prefs.copyWith(desktopLyricsLocked: locked),
    );
  }

  void _close() {
    final preferences = _preferences;
    if (preferences == null || !preferences.prefs.desktopLyrics) return;
    preferences.update(preferences.prefs.copyWith(desktopLyrics: false));
  }

  void _openFailed(Object error) {
    _smokeGaveUp = true;
    debugPrint('[desktop-lyrics] 已把桌面歌词开关复位: $error');
    final preferences = _preferences;
    if (preferences == null || !preferences.prefs.desktopLyrics) return;
    preferences.update(preferences.prefs.copyWith(desktopLyrics: false));
  }

  bool _isRemote() {
    final connect = _connect!;
    final playback = _playback!;
    return connect.controlsRemote(
      localPlaying: playback.isPlaying,
      localHasTrack: playback.currentTrack != null,
    );
  }

  int _readPosition() {
    if (_isRemote()) return _connect!.position.value.inMilliseconds;
    return _playback!.position.inMilliseconds;
  }

  bool _readPlaying() {
    if (_isRemote()) return _connect!.player.isAudible;
    return _playback!.isPlaying;
  }

  void _onLyricsCached(String trackId) {
    if (trackId != _trackId) return;
    final cached = _spotify?.cachedLyrics(trackId);
    if (cached == null) return;
    _session.setFromSpotify(cached);
    _push();
  }

  void _onPosition() {
    if (!mounted || _controller == null) return;
    final preferences = _preferences;
    if (preferences == null || !preferences.prefs.desktopLyrics) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final position = _readPosition();
    final playing = _readPlaying();
    final expected = _anchor.positionAt(now);
    final jump = (position - expected).abs() > 400;
    final playingChanged = playing != _anchor.playing;
    if (!playingChanged && !jump && now - _lastSentMs < 1000) return;
    _anchor = LyricProgressAnchor(
      positionMs: position,
      anchoredAtMs: now,
      playing: playing,
    );
    _remote = _isRemote();
    _leadMs = _remote ? preferences.prefs.remoteLyricsLeadMs : 0;
    _push();
  }

  void _onSource() {
    if (!mounted || _controller == null) return;
    final preferences = _preferences!;
    if (desktopLyricsSmokeRequested &&
        !_smokeGaveUp &&
        !preferences.prefs.desktopLyrics) {
      preferences.update(preferences.prefs.copyWith(desktopLyrics: true));
      return;
    }
    final enabled = preferences.prefs.desktopLyrics;
    if (!enabled) {
      unawaited(_controller!.hide());
      return;
    }

    final remote = _isRemote();
    final track = remote ? _connect!.displayTrack : _playback!.currentTrack;
    final playing = remote ? _connect!.player.isAudible : _playback!.isPlaying;
    _remote = remote;
    _leadMs = remote ? preferences.prefs.remoteLyricsLeadMs : 0;
    _session.messages = DesktopLyricMessages(
      loading: context.l10n.desktopLyricsLoading,
      empty: context.l10n.desktopLyricsEmpty,
      unsynced: context.l10n.desktopLyricsUnsynced,
      interlude: context.l10n.desktopLyricsInterlude,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    _anchor = LyricProgressAnchor(
      positionMs: _readPosition(),
      anchoredAtMs: now,
      playing: playing,
    );

    if (desktopLyricsSmokeRequested) {
      _trackId = 'desktop-lyrics-smoke';
      _session
        ..changeTrack(id: 'desktop-lyrics-smoke', title: 'Sample')
        ..setLyrics(
          syncType: 'LINE_SYNCED',
          lines: const [
            DesktopLyricLineData(startTimeMs: 0, words: '星が落ちる'),
          ],
        );
      _push();
      return;
    }

    final id = track?.id;
    if (id != _trackId) {
      _trackId = id;
      final generation = ++_generation;
      // 切歌先清空，再去取新歌词，避免上一首的句子留在窗口上。
      _session.changeTrack(id: id, title: track?.name ?? '');
      _push();
      if (track != null) unawaited(_load(track, generation));
      return;
    }
    _push();
  }

  Future<void> _load(SpotifyTrack track, int generation) async {
    final spotify = _spotify;
    if (spotify == null) return;
    final cached = spotify.cachedLyrics(track.id);
    if (cached != null) {
      if (!mounted || generation != _generation) return;
      _session.setFromSpotify(cached);
      _push();
      return;
    }
    try {
      final lyrics = await spotify.fetchLyrics(LyricsQuery.fromTrack(track));
      if (!mounted || generation != _generation) return;
      _session.setFromSpotify(lyrics);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _session.fail();
    }
    _push();
  }

  void _push() {
    final controller = _controller;
    final preferences = _preferences;
    final appearance = _appearance;
    if (controller == null || preferences == null || appearance == null) return;
    if (!preferences.prefs.desktopLyrics) {
      unawaited(controller.hide());
      return;
    }
    _lastSentMs = DateTime.now().millisecondsSinceEpoch;
    final snapshot = _session.toSnapshot(
      anchor: _anchor,
      remote: _remote,
      leadMs: _leadMs,
      locked: preferences.prefs.desktopLyricsLocked,
      accent: appearance.accent.toARGB32(),
    );
    final l10n = context.l10n;
    snapshot['tooltips'] = {
      'lock': l10n.desktopLyricsLock,
      'close': l10n.commonClose,
    };
    unawaited(controller.show(snapshot));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
