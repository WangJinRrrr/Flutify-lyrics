import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/file.dart' show File;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;

import 'cache_location.dart';

/// Keeps library downloads and metadata writes outside directory maintenance.
/// A cancelled image subscription still drains its download before moving files.
class ArtworkCache implements BaseCacheManager {
  /// Export the old platform repository (SQLite on Android, JSON on Windows)
  /// beside its files before replacing the application's default cache manager.
  static Future<void> prepareLegacy(String directory) async {
    if (!await io.Directory(directory).exists()) return;
    final repo = Config(DefaultCacheManager.key).repo;
    await repo.open();
    try {
      final index = io.File(p.join(directory, 'index.json'));
      final merged = {
        for (final item in await CacheLocation.readArtworkIndex(index))
          item.key: item,
      };
      for (final item in await repo.getAllObjects()) {
        merged.putIfAbsent(item.key, () => item);
      }
      await CacheLocation.writeArtworkIndex(index, merged.values);
    } finally {
      await repo.close();
    }
    await repo.deleteDataFile();
  }

  final CacheLocation location;
  Future<void> _barrier = Future.value();
  final Set<Future<void>> _active = {};
  Timer? _trimTimer;
  bool _disposed = false;
  late CacheManager _manager;
  ArtworkCache(this.location) {
    _open();
    _trimTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      unawaited(_exclusive(_trim).catchError((Object _) {}));
    });
  }

  void _open() {
    final directory = location.imageDirectory.path;
    _manager = CacheManager(
      Config(
        'flutify_artwork',
        fileSystem: _ArtworkFileSystem(directory),
        repo: _ArtworkRepository(io.File(p.join(directory, 'index.json'))),
        maxNrOfCacheObjects: 500,
      ),
    );
  }

  // Admit concurrent downloads immediately; maintenance waits for the admitted
  // batch and prevents new requests entering the manager until it has reopened.
  Future<T> _run<T>(Future<T> Function(CacheManager) action) {
    if (_disposed) return Future.error(StateError('Artwork cache is disposed'));
    final result = _barrier.then((_) => action(_manager));
    late Future<void> settled;
    settled = result
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _active.remove(settled));
    _active.add(settled);
    return result;
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = Future.wait([_barrier, ..._active]).then((_) => action());
    _barrier = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _trim() async {
    if (!_disposed) {
      final objects = await _manager.config.repo.getAllObjects();
      objects.sort(
        (a, b) => (a.touched ?? DateTime(1970)).compareTo(
          b.touched ?? DateTime(1970),
        ),
      );
      for (final item in objects.take(
        (objects.length - 500).clamp(0, objects.length),
      )) {
        await _manager.removeFile(item.key);
      }
    }
  }

  Future<CacheResult> maintain(Future<CacheResult> Function() action) =>
      _exclusive(() async {
        await _manager.dispose();
        try {
          return await action();
        } finally {
          await location.imageDirectory.create(recursive: true);
          _open();
        }
      });

  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) =>
      _run((manager) => manager.getSingleFile(url, key: key, headers: headers));

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    final output = StreamController<FileResponse>();
    var cancelled = false;
    output.onCancel = () {
      cancelled = true;
    };
    output.onListen = () {
      _run((manager) async {
        await for (final event in manager.getFileStream(
          url,
          key: key,
          headers: headers,
          withProgress: withProgress,
        )) {
          if (!cancelled) output.add(event);
        }
      }).then(
        (_) {
          output.close();
        },
        onError: (Object e, StackTrace stack) {
          if (!cancelled) output.addError(e, stack);
          output.close();
        },
      );
    };
    return output.stream;
  }

  @override
  Stream<FileInfo> getFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) => getFileStream(
    url,
    key: key,
    headers: headers,
  ).where((event) => event is FileInfo).cast<FileInfo>();
  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) => _run(
    (manager) => manager.downloadFile(
      url,
      key: key,
      authHeaders: authHeaders,
      force: force,
    ),
  );
  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) => _run(
    (manager) => manager.getFileFromCache(key, ignoreMemCache: ignoreMemCache),
  );
  @override
  Future<FileInfo?> getFileFromMemory(String key) =>
      _run((manager) => manager.getFileFromMemory(key));
  @override
  Future<File> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) => _run(
    (manager) => manager.putFile(
      url,
      fileBytes,
      key: key,
      eTag: eTag,
      maxAge: maxAge,
      fileExtension: fileExtension,
    ),
  );
  @override
  Future<File> putFileStream(
    String url,
    Stream<List<int>> source, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) => _run(
    (manager) => manager.putFileStream(
      url,
      source,
      key: key,
      eTag: eTag,
      maxAge: maxAge,
      fileExtension: fileExtension,
    ),
  );
  @override
  Future<void> removeFile(String key) =>
      _run((manager) => manager.removeFile(key));
  @override
  Future<void> emptyCache() => _run((manager) => manager.emptyCache());
  @override
  Future<void> dispose() {
    _disposed = true;
    _trimTimer?.cancel();
    return _exclusive(() => _manager.dispose());
  }
}

class _ArtworkFileSystem implements FileSystem {
  final String directory;
  _ArtworkFileSystem(this.directory);
  @override
  Future<File> createFile(String name) async {
    if (p.basename(name) != name || name == '.' || name == '..') {
      throw const FormatException('Invalid artwork cache filename');
    }
    final root = const LocalFileSystem().directory(directory);
    await root.create(recursive: true);
    return root.childFile(name);
  }
}

/// The library's delayed cleanup timer outlives dispose. Trim under our lock
/// instead, so that a retired manager cannot delete or recreate migrated data.
class _ArtworkRepository extends JsonCacheInfoRepository {
  _ArtworkRepository(super.file) : super.withFile();
  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) async => [];
  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) async => [];
}
