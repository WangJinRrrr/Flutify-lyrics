import 'dart:typed_data';

import 'package:flutify_app/services/protocol/ap_crypto.dart';
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
  group('apComputeKeys（握手密钥推导，HMAC-SHA1 链）', () {
    // 黄金向量由 Python hmac 独立计算生成。
    final shared = hex('c3a5' * 24);
    final packets = hex('0004${'11' * 38}');

    test('challenge / send_key / recv_key', () {
      final keys = apComputeKeys(shared, packets);
      expect(hexOf(keys.challenge), '0fee68ecd08aa430a621123f6f0aa18a8afdf7aa');
      expect(hexOf(keys.sendKey), 'd8947260e647236b706bd310e01b69c72f91efcbf44056ff5ca445e0836fad99');
      expect(hexOf(keys.recvKey), '8503147c08360c29aec41443f6e0edfbb34853e3cacc6ae5935aad0a946953d3');
    });

    test('收发密钥互不相同且均为 32 字节', () {
      final keys = apComputeKeys(shared, packets);
      expect(keys.sendKey.length, 32);
      expect(keys.recvKey.length, 32);
      expect(hexOf(keys.sendKey), isNot(hexOf(keys.recvKey)));
    });
  });

  group('DhLocalKeys', () {
    test('双方独立计算共享密钥一致', () {
      final a = DhLocalKeys.random();
      final b = DhLocalKeys.random();
      final sharedA = a.sharedSecret(b.publicKey);
      final sharedB = b.sharedSecret(a.publicKey);
      expect(hexOf(sharedA), hexOf(sharedB));
    });

    test('不同私钥得到不同共享密钥', () {
      final a = DhLocalKeys.random();
      final b = DhLocalKeys.random();
      final c = DhLocalKeys.random();
      expect(hexOf(a.sharedSecret(b.publicKey)), isNot(hexOf(a.sharedSecret(c.publicKey))));
    });
  });

  group('rsaVerifyPkcs1Sha1', () {
    test('伪造签名无法通过验证', () {
      final modulus = Uint8List.fromList(List.generate(256, (i) => i));
      final signature = Uint8List.fromList(List.generate(256, (i) => 255 - i));
      final message = Uint8List.fromList([1, 2, 3]);
      expect(
        rsaVerifyPkcs1Sha1(modulus: modulus, signature: signature, message: message),
        isFalse,
      );
    });
  });
}
