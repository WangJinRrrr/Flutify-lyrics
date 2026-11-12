// 独立验证 TOTP（不依赖 Flutter，可直接 dart run）
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

String totp(List<int> secret, int timestampMs, {int period = 30, int digits = 6}) {
  final counter = timestampMs ~/ 1000 ~/ period;
  final msg = ByteData(8)..setUint64(0, counter, Endian.big);
  final h = Hmac(sha1, secret).convert(msg.buffer.asUint8List()).bytes;
  final off = h[h.length - 1] & 0x0F;
  final code = (ByteData.sublistView(Uint8List.fromList(h), off, off + 4).getUint32(0, Endian.big) & 0x7FFFFFFF) % 1000000;
  return code.toString().padLeft(digits, '0');
}

void main() {
  const obfuscated = ',7/*F("rLJ2oxaKL^f+E1xvP@N';
  final codes = <int>[];
  for (var i = 0; i < obfuscated.length; i++) {
    codes.add(obfuscated.codeUnitAt(i) ^ ((i % 33) + 9));
  }
  final secret = utf8.encode(codes.join());
  print('secret hex: ${secret.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
  print('Dart TOTP @1700000000 = ${totp(secret, 1700000000 * 1000)}');
  print('期望（Python）       = 371599');
}
