import 'package:flutify_app/core/utils/byte_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ByteSize picks KB / MB / GB with 1024 steps', () {
    expect(ByteSize.format(0), '0 KB');
    expect(ByteSize.format(1536), '2 KB');
    expect(ByteSize.format(ByteSize.mb), '1 MB');
    expect(ByteSize.format(300 * ByteSize.mb + 400 * ByteSize.kb), '300 MB');
    expect(ByteSize.format(2 * ByteSize.gb), '2 GB');
    expect(ByteSize.format(ByteSize.gb + ByteSize.gb ~/ 2), '1.5 GB');
  });
}
