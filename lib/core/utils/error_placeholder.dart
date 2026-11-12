import 'package:flutter/material.dart';

/// 全局兜底：替换 Flutter 默认的红屏 / 灰块 ErrorWidget。
///
/// 某个组件构建失败时，只在它原本的位置显示一个低调的占位块，
/// 页面其余部分照常可用；异常本身仍会通过 FlutterError.onError 打印到控制台，
/// 不影响排查问题。
///
/// 约束：ErrorWidget 可能出现在 MaterialApp / Directionality / Theme / Overlay 之外，
/// 因此这里不能依赖任何 InheritedWidget（包括 Tooltip），颜色与方向都需写死。
void installErrorPlaceholder() {
  ErrorWidget.builder = (_) => const _ErrorPlaceholder();
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    // 无界约束下（如横向列表、Column 内）限制尺寸，避免再次触发布局异常
    return LimitedBox(
      maxWidth: 160,
      maxHeight: 96,
      child: SizedBox.expand(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: const Center(
              child: Icon(Icons.hide_image_outlined, color: Color(0x66FFFFFF), size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
