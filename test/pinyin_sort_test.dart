import 'package:flutify_app/core/utils/pinyin_sort.dart';
import 'package:flutter_test/flutter_test.dart';

/// 音乐库「按字母顺序」的中文排序：汉字按拼音，数字 / 字母混排时行为稳定可预期。
void main() {
  test('汉字按拼音排序，不是按 Unicode 码点', () {
    final titles = ['周杰伦', '阿杜', '北京欢迎你', '光良', '爱'];
    final sorted = sortByPinyin(titles, (t) => t);
    expect(sorted, ['阿杜', '爱', '北京欢迎你', '光良', '周杰伦']); // a-du / ai / bei-jing / guang / zhou
  });

  test('英文、数字与中文混排：按各自读法的字典序', () {
    final titles = ['你好', 'Apple', '2046', 'banana'];
    final sorted = sortByPinyin(titles, (t) => t);
    expect(sorted, ['2046', 'Apple', 'banana', '你好']); // 2… / apple / banana / ni-hao
  });

  test('大小写不敏感，同音 / 相同标题回退到原串比较', () {
    expect(compareByPinyin('abc', 'ABC'), 0);
    expect(compareByPinyin('李', '里'), isNonZero, reason: '同音字不返回 0，排序稳定');
    expect(compareByPinyin('', 'a'), lessThan(0));
  });

  test('不改动入参列表', () {
    final titles = ['周', '爱'];
    sortByPinyin(titles, (t) => t);
    expect(titles, ['周', '爱']);
  });
}
