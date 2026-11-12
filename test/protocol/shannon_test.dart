import 'dart:typed_data';

import 'package:flutify_app/services/protocol/ap_codec.dart';
import 'package:flutify_app/services/protocol/shannon.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String hexOf(Uint8List data) =>
    data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // 黄金向量由独立的 Python 移植（同源于 despotify / shannon crate）生成并自检通过。
  const keyHex = 'f1e2d3c4b5a69788796a5b4c3d2e1f00';
  const ptHex = 'a20d90a8e46cd854b052527cfe0c417ac95ed19c0d46d056808b56d1828b';

  group('Shannon（协议加密通道）', () {
    test('加密 + MAC 黄金向量（nonce=7）', () {
      final shannon = Shannon(hex(keyHex));
      shannon.nonceU32(7);
      final data = hex(ptHex);
      shannon.encrypt(data);
      expect(hexOf(data), '68dd29ea34198a2328e3b0ac64aa2e84601dafc77cbb4a3b5e9fc239f06a');
      expect(hexOf(shannon.finish(4)), '72a47775');
    });

    test('解密 + MAC 黄金向量（nonce=7）', () {
      final shannon = Shannon(hex(keyHex));
      shannon.nonceU32(7);
      final data = hex('68dd29ea34198a2328e3b0ac64aa2e84601dafc77cbb4a3b5e9fc239f06a');
      shannon.decrypt(data);
      expect(hexOf(data), ptHex);
      expect(hexOf(shannon.finish(4)), '72a47775');
    });

    test('分包续传（3 字节头 + 载荷）黄金向量（nonce=0）', () {
      final shannon = Shannon(hex(keyHex));
      shannon.nonceU32(0);
      final header = hex('0c0024');
      shannon.encrypt(header);
      expect(hexOf(header), 'df42b5');
      final payload = hex(ptHex);
      shannon.encrypt(payload);
      expect(hexOf(payload), '30fe46ab823ff84de8838bde5429066e16d50f58a2935d8c3df322a3e27d');
      expect(hexOf(shannon.finish(4)), 'ca143ce1');
    });

    test('解密侧分包续传可还原（nonce=0）', () {
      final shannon = Shannon(hex(keyHex));
      shannon.nonceU32(0);
      final header = hex('df42b5');
      shannon.decrypt(header);
      expect(hexOf(header), '0c0024');
      final payload = hex('30fe46ab823ff84de8838bde5429066e16d50f58a2935d8c3df322a3e27d');
      shannon.decrypt(payload);
      expect(hexOf(payload), ptHex);
      expect(hexOf(shannon.finish(4)), 'ca143ce1');
    });

    test('每包重新播种（nonce 递增）', () {
      final enc = Shannon(hex(keyHex));
      final dec = Shannon(hex(keyHex));
      for (var nonce = 0; nonce < 3; nonce++) {
        enc.nonceU32(nonce);
        dec.nonceU32(nonce);
        final data = Uint8List.fromList(hex(ptHex));
        enc.encrypt(data);
        expect(hexOf(data), isNot(ptHex));
        dec.decrypt(data);
        expect(hexOf(data), ptHex);
        expect(hexOf(enc.finish(4)), hexOf(dec.finish(4)));
      }
    });
  });

  group('ApCodec（包编解码）', () {
    test('encode → nextPacket 往返（含 MAC 校验）', () {
      final sendKey = hex('00112233445566778899aabbccddeeff');
      final recvKey = hex('ffeeddccbbaa99887766554433221100');
      final sender = ApCodec(sendKey, recvKey);
      final receiver = ApCodec(recvKey, sendKey); // 收发密钥互换

      final payloads = [
        Uint8List.fromList([1, 2, 3, 4]),
        Uint8List(0),
        Uint8List.fromList(List.generate(42, (i) => i)),
        Uint8List.fromList(List.generate(255, (i) => 255 - i)),
      ];

      final wire = <int>[];
      for (var cmd = 0; cmd < payloads.length; cmd++) {
        wire.addAll(sender.encode(0x0c + cmd, payloads[cmd]));
      }

      // 按任意分片喂入（模拟 TCP 粘包/拆包）
      var offset = 0;
      final packets = <ApPacket>[];
      while (offset < wire.length) {
        final end = (offset + 5).clamp(0, wire.length);
        receiver.addIncoming(Uint8List.fromList(wire.sublist(offset, end)));
        offset = end;
        ApPacket? packet;
        while ((packet = receiver.nextPacket()) != null) {
          packets.add(packet!);
        }
      }

      expect(packets.length, payloads.length);
      for (var i = 0; i < payloads.length; i++) {
        expect(packets[i].cmd, 0x0c + i);
        expect(hexOf(packets[i].payload), hexOf(payloads[i]));
      }
    });

    test('MAC 篡改会被拒收', () {
      final sendKey = hex('00112233445566778899aabbccddeeff');
      final recvKey = hex('ffeeddccbbaa99887766554433221100');
      final sender = ApCodec(sendKey, recvKey);
      final receiver = ApCodec(recvKey, sendKey);

      final wire = sender.encode(0x0c, Uint8List.fromList([1, 2, 3, 4]));
      wire[wire.length - 1] ^= 0x01; // 翻转 MAC 一位
      receiver.addIncoming(wire);
      expect(() => receiver.nextPacket(), throwsStateError);
    });
  });
}
