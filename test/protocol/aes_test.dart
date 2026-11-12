import 'dart:typed_data';

import 'package:flutify_app/services/protocol/aes.dart';
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
  group('AesCipher (FIPS-197 附录 C 测试向量)', () {
    const pt = '00112233445566778899aabbccddeeff';

    test('AES-128', () {
      final cipher = AesCipher(hex('000102030405060708090a0b0c0d0e0f'));
      expect(hexOf(cipher.encryptBlock(hex(pt))), '69c4e0d86a7b0430d8cdb78070b4c55a');
    });

    test('AES-192', () {
      final cipher =
          AesCipher(hex('000102030405060708090a0b0c0d0e0f1011121314151617'));
      expect(hexOf(cipher.encryptBlock(hex(pt))), 'dda97ca4864cdfe06eaf70a0ec0d7191');
    });

    test('AES-256', () {
      final cipher = AesCipher(hex(
          '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'));
      expect(hexOf(cipher.encryptBlock(hex(pt))), '8ea2b7ca516745bfeafc49904b496089');
    });

    test('非法密钥长度抛异常', () {
      expect(() => AesCipher(Uint8List(15)), throwsArgumentError);
    });
  });

  group('AesCtr（SP 800-38A F.5.1 测试向量）', () {
    test('整段加解密', () {
      final key = hex('2b7e151628aed2a6abf7158809cf4f3c');
      final iv = hex('f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff');
      final pt = hex('6bc1bee22e409f96e93d7e117393172a'
          'ae2d8a571e03ac9c9eb76fac45af8e51'
          '30c81c46a35ce411e5fbc1191a0a52ef');
      final expected = hex('874d6191b620e3261bef6864990db6ce'
          '9806f66b7970fdff8617187bb9fffdff'
          '5ae4df3edbd5d35e5b4f09020db03eab');

      final data = Uint8List.fromList(pt);
      AesCtr(key, iv).process(data);
      expect(hexOf(data), hexOf(expected));

      AesCtr(key, iv).process(data); // CTR 对称：再处理一次还原
      expect(hexOf(data), hexOf(pt));
    });

    test('随机向量 + 任意分块与整段等价', () {
      final key = hex('f8e18cf61b5ee520660e33a6d725c0d7');
      final iv = hex('e652d95733c05b6d69ef66a42786509d');
      final pt = hex('efd5e4b417e84433cf28a2ce1a7ebf247c56636c11601e973ef5954cfa13097a8abd487c39ffcbcfdfc5a350be2cab3a8f52fc98b1a6e0114e372302a68b5aedb45a8347debd9b9668184bc9425cef7084dd74e18aea5c76966cfb125b9100aebea29e93');
      final expected = hex('18bfc8ef4584e47f589abb70438a82eba1d54079dde41cf16c5af8fa5d5244569cf608d1a639c55e1f4944c732db9adc1d9e2213b11f010601710cf3bfd52be54aadef7c935b8d1f08554a2b37de5964dcb14c5ca48deba8539bc774a368e287576f47d2');

      final oneShot = Uint8List.fromList(pt);
      AesCtr(key, iv).process(oneShot);
      expect(hexOf(oneShot), hexOf(expected));

      // 分块（含跨块边界与非 16 倍数长度）
      final chunked = Uint8List.fromList(pt);
      final cipher = AesCtr(key, iv);
      var offset = 0;
      for (final size in [1, 15, 16, 17, 33, 38]) {
        if (offset >= chunked.length) break;
        final end = (offset + size).clamp(0, chunked.length);
        cipher.process(Uint8List.sublistView(chunked, offset, end));
        offset = end;
      }
      if (offset < chunked.length) {
        cipher.process(Uint8List.sublistView(chunked, offset));
      }
      expect(hexOf(chunked), hexOf(expected));
    });

    test('atOffset 从任意偏移开始，与从头处理到该位置等价（断点续传）', () {
      final key = hex('f8e18cf61b5ee520660e33a6d725c0d7');
      // 计数器低字节接近溢出，覆盖跨字节进位
      final iv = hex('e652d95733c05b6d69ef66a427ffffff');
      final pt = Uint8List.fromList(List.generate(1000, (i) => (i * 7 + 3) & 0xff));
      final full = Uint8List.fromList(pt);
      AesCtr(key, iv).process(full);

      for (final offset in [0, 1, 15, 16, 17, 255, 256, 513, 999]) {
        final tail = Uint8List.fromList(pt.sublist(offset));
        final cipher = AesCtr.atOffset(key, iv, offset);
        cipher.process(tail);
        expect(hexOf(tail), hexOf(Uint8List.sublistView(full, offset)), reason: 'offset $offset');
        expect(cipher.offset, pt.length);
      }
    });
  });
}
