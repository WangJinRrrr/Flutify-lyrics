import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/protocol/audio_normalization.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造 Spotify 头里的 16 字节响度数据（4 个小端 float32）。
Uint8List _bytes(double trackGain, double trackPeak, [double albumGain = 0, double albumPeak = 1]) {
  final data = ByteData(AudioNormalization.byteLength)
    ..setFloat32(0, trackGain, Endian.little)
    ..setFloat32(4, trackPeak, Endian.little)
    ..setFloat32(8, albumGain, Endian.little)
    ..setFloat32(12, albumPeak, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  test('parse reads track gain and peak', () {
    final n = AudioNormalization.parse(_bytes(-6.5, 0.98))!;
    expect(n.trackGainDb, closeTo(-6.5, 1e-6));
    expect(n.trackPeak, closeTo(0.98, 1e-6));
  });

  test('parse rejects short or implausible data', () {
    expect(AudioNormalization.parse(Uint8List(8)), isNull);
    expect(AudioNormalization.parse(_bytes(double.nan, 1)), isNull);
    expect(AudioNormalization.parse(_bytes(-80, 1)), isNull);
    expect(AudioNormalization.parse(_bytes(-3, 0)), isNull);
  });

  test('volumeFactor attenuates loud tracks and never boosts', () {
    // -6.02 dB ≈ 0.5 倍
    expect(const AudioNormalization(trackGainDb: -6.0206, trackPeak: 0.9).volumeFactor, closeTo(0.5, 1e-3));
    // 正增益（偏轻的歌）：播放器音量不能超过 1
    expect(const AudioNormalization(trackGainDb: 4, trackPeak: 0.5).volumeFactor, 1.0);
    // 峰值限幅：增益 × 峰值 ≤ 1
    expect(const AudioNormalization(trackGainDb: -1, trackPeak: 1.6).volumeFactor, closeTo(1 / 1.6, 1e-6));
  });

  test('sidecar sits next to the audio file and round-trips', () async {
    final dir = await Directory.systemTemp.createTemp('flutify_norm_test');
    addTearDown(() => dir.delete(recursive: true));
    final audio = File('${dir.path}${Platform.pathSeparator}abc123.ogg');

    final sidecar = AudioNormalization.sidecarFor(audio);
    expect(sidecar.path, endsWith('abc123.norm'));
    expect(AudioNormalization.readSidecar(audio), isNull, reason: '旧缓存没有旁路文件');

    sidecar.writeAsBytesSync(_bytes(-2, 0.7));
    expect(AudioNormalization.readSidecar(audio)!.trackGainDb, closeTo(-2, 1e-6));
  });
}
