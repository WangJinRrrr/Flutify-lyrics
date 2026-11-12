// 歌手比对探针：验证短歌手名（如 OAO）的判定。
import 'dart:io';

import 'package:flutify_app/services/lyrics/artist_match.dart';
import 'package:flutify_app/services/lyrics/lyric_script.dart';

void main() {
  stdout.writeln("detectLang('OAO') = ${detectLang('OAO')}");
  stdout.writeln("compare('OAO', 'Frank Sinatra') = ${ArtistMatcher.compare('OAO', 'Frank Sinatra')}");
  stdout.writeln("compare('OAO', 'Calvin Harris') = ${ArtistMatcher.compare('OAO', 'Calvin Harris')}");
  stdout.writeln("compare('OAO', 'OAO') = ${ArtistMatcher.compare('OAO', 'OAO')}");
}
