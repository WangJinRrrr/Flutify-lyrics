// 播客服务探针：验证 PodcastService 对 open.spotify.com 节目页 / 单集页的解析。
//
// 用法：dart run tool/podcast_probe.dart [showId]
import 'dart:io';

import 'package:flutify_app/services/podcast/podcast_service.dart';

Future<void> main(List<String> args) async {
  final showId = args.isNotEmpty ? args.first : '4zmKf7s1X6WY1rF2GdyHSy';
  final service = PodcastService();
  try {
    PodcastService.debugHtml = (html) {
      stdout.writeln('html ${html.length} chars, initialState 出现: ${html.contains('initialState')}');
      final i = html.indexOf('initialState');
      if (i >= 0) stdout.writeln(html.substring(i - 80, i + 120));
    };
    final show = await service.fetchShow(showId);
    stdout.writeln('节目: ${show.name} — ${show.publisher}');
    stdout.writeln('封面: ${show.coverUrl.isEmpty ? '(无)' : show.coverUrl}');
    stdout.writeln('简介: ${show.description.length} 字');
    stdout.writeln('单集: ${show.episodes.length} 集');
    for (final ep in show.episodes.take(3)) {
      stdout.writeln('  - ${ep.name} | ${ep.durationMs}ms | ${ep.releaseDate} | 预览:${ep.previewUrl.isNotEmpty} | 播至 ${ep.resumeMs}ms');
    }
    if (show.episodes.isNotEmpty) {
      final ep = await service.fetchEpisode(show.episodes.first.id);
      stdout.writeln('单集页解析: ${ep.name} @ ${ep.showName} (${ep.showUri})');
    }
  } finally {
    // PodcastService 不持有长连接，直接退出即可
  }
}
