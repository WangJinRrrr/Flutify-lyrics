// LRCLIB 选词探针：用 App 的真实查询与选词逻辑复现一首歌的补全过程。
//
// 用法：dart run tool/lrclib_probe.dart [曲名 [歌手 [时长ms]]]
// 默认复现「My Way / OAO / 130s」（纯音乐被误配 Sinatra 歌词的案例）。
import 'dart:io';

import 'package:flutify_app/models/lyrics_query.dart';
import 'package:flutify_app/services/lyrics/lrclib_candidate.dart';
import 'package:flutify_app/services/lyrics/lrclib_client.dart';
import 'package:flutify_app/services/lyrics/lrclib_selector.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final title = args.isNotEmpty ? args[0] : 'My Way';
  final artist = args.length > 1 ? args[1] : 'OAO';
  final durationMs = args.length > 2 ? int.parse(args[2]) : 130000;
  stdout.writeln('args: $args');
  final query = LyricsQuery(trackId: 'probe', title: title, artist: artist, durationMs: durationMs);
  stdout.writeln('查询: title="$title" artist="$artist" durationMs=$durationMs');

  final client = LrclibClient(http.Client());
  final candidates = <LrclibCandidate>[];

  Future<void> add(String label, Future<LrclibResponse> Function() request) async {
    final res = await request();
    stdout.writeln('--- $label: ${res.candidates.length} 条（网络错误: ${res.networkError}）');
    candidates.addAll(res.candidates);
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  // 与 LrclibLyricsSource.find 相同的查询顺序
  await add(
    '精确 get',
    () => client.get(track: title, artist: artist, album: 'My Way', durationSec: durationMs ~/ 1000),
  );
  await add('曲名+主唱搜索', () => client.search(track: title, artist: artist));
  if (candidates.length < 4) await add('只按曲名搜', () => client.search(track: title));
  if (candidates.length < 3) {
    await add('全文搜索', () => client.search(q: '$title $artist'));
  }

  stdout.writeln('\n=== 候选（共 ${candidates.length} 条）===');
  for (final c in candidates) {
    stdout.writeln(
      '  "${c.trackName}" by "${c.artistName}" | ${c.duration}s | '
      'instrumental=${c.instrumental} | 有词=${c.lines.isNotEmpty}',
    );
  }

  final selection = LrclibSelector.select(candidates, query);
  if (selection == null) {
    stdout.writeln('\n选词结果：无（不上歌词）');
  } else {
    final firstLine = selection.synced.split('\n').firstWhere((l) => l.length > 12, orElse: () => '');
    stdout.writeln('\n选词结果：${selection.lang}，首行: $firstLine');
  }
}
