import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import '../cache/cache_location.dart';

/// LRCLIB 补全歌词的本地缓存：`<目录>/<sha1(键)>.lrc`，同一首歌不再重复联网选词。
///
/// 只缓存选中的歌词原文（已对齐简繁）；「没找到」不落盘，下次启动会再试。
/// 普通读写失败静默；显式清理返回实际释放量和失败数。
class LyricsDiskCache {
  final Directory _directory;
  final Directory Function()? directoryProvider;
  final CacheLock lock;
  int generation = 0;
  Directory get directory => directoryProvider?.call() ?? _directory;

  LyricsDiskCache(this._directory, {this.directoryProvider, CacheLock? lock})
    : lock = lock ?? CacheLock();

  File _file(String key) => File(
    '${directory.path}${Platform.pathSeparator}${sha1.convert(utf8.encode(key))}.lrc',
  );

  Future<String?> read(String key) => lock.run(() async {
    try {
      final file = _file(key);
      return await file.exists() ? await file.readAsString() : null;
    } catch (_) {
      return null;
    }
  });

  Future<void> write(String key, String lrc, {int? expectedGeneration}) =>
      lock.run(() async {
        if (expectedGeneration != null && expectedGeneration != generation)
          return;
        try {
          await directory.create(recursive: true);
          await _file(key).writeAsString(lrc, flush: true);
        } catch (_) {}
      });

  Future<void> remove(String key) => lock.run(() async {
    generation++;
    try {
      final file = _file(key);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  });

  /// 已缓存的歌词份数。
  Future<int> count() async {
    try {
      if (!await directory.exists()) return 0;
      return await directory
          .list()
          .where((e) => e is File && e.path.endsWith('.lrc'))
          .length;
    } catch (_) {
      return 0;
    }
  }

  Future<CacheResult> clear({Future<CacheResult> Function()? clearFiles}) {
    generation++;
    return clearFiles != null
        ? clearFiles()
        : lock.run(() => CacheLocation.clearDirectory(directory.path));
  }
}
