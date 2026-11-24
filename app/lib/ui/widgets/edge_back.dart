/// 左边缘右滑 = 返回手势。
///
/// 行为（跟主流 App 一致）：
///   - 在「小工具」/「我的」页 → 切回「最近」页
///   - 在「最近」页          → 第一次提示「再划一次退出」，再划一次才真的退出
///
/// ## 为什么用「祖先 GestureDetector」而不是 Listener
///
/// `Listener` 拿得到原始指针事件，但它**不参与手势竞技场** —— 页面里的
/// 横向滚动容器（比如小工具页的分类页签）会跟着一起动，出现
/// 「想滑回第一个页签，却把 App 滑回上一页」的误触。
///
/// `GestureDetector` 会参与竞技场：手指落在横向滚动容器上时，
/// **容器先胜出**（竞技场按深度优先派发），我们的手势根本不会触发；
/// 落在普通区域时纵向 ListView 不接受横向拖拽，于是我们胜出。
/// ⇒ 页签那一小条区域滑不动返回是刻意的，其余地方都能滑。
library;

import 'package:flutter/material.dart';

class EdgeBackGesture extends StatefulWidget {
  const EdgeBackGesture({
    super.key,
    required this.child,
    required this.onBack,
    this.edgeWidth = 22,
    this.triggerDx = 72,
  });

  final Widget child;

  /// 触发了「返回」时的回调。
  final VoidCallback onBack;

  /// 左边多少像素算「边缘」。
  final double edgeWidth;

  /// 从边缘往右累计滑多少像素才算一次返回。
  final double triggerDx;

  @override
  State<EdgeBackGesture> createState() => _EdgeBackGestureState();
}

class _EdgeBackGestureState extends State<EdgeBackGesture> {
  /// 手指按下的横坐标；null = 本次触摸还没开始。
  double? _downX;

  /// 从边缘往右累计的位移。
  double _accDx = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // translucent：既接住自己的手势，又让子节点照常收到事件（纵向滚动不受影响）
      behavior: HitTestBehavior.translucent,
      onHorizontalDragDown: (d) {
        _downX = d.globalPosition.dx;
        _accDx = 0;
      },
      onHorizontalDragUpdate: (d) {
        _accDx += d.delta.dx;
      },
      onHorizontalDragEnd: (d) {
        final fromEdge = (_downX ?? double.infinity) <= widget.edgeWidth;
        if (fromEdge && _accDx >= widget.triggerDx) {
          widget.onBack();
        }
        _downX = null;
        _accDx = 0;
      },
      onHorizontalDragCancel: () {
        _downX = null;
        _accDx = 0;
      },
      child: widget.child,
    );
  }
}
