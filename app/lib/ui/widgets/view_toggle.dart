/// 顶栏右侧的「显示格式」切换按钮。
///
/// 背景：顶栏右侧原本放的是「设置」（跳到「我的」页）——
/// 但底部导航本来就有「我的」，顶栏再放一个跳页按钮就功能混乱。
/// 现在顶栏右侧**只有一个**图标，语义唯一：**网格 ⇄ 列表**。
///
/// 「最近」页和「小工具」页共用同一个 [ViewPrefs]，
/// 所以在任意一页切换，另一页也跟着变（同一份数据、同一套排版偏好）。
library;

import 'package:flutter/material.dart';

import '../../data/view_prefs.dart';
import 'paper_widgets.dart';

class ViewToggleButton extends StatelessWidget {
  const ViewToggleButton({
    super.key,
    required this.mode,
    required this.onToggle,
  });

  final ViewMode mode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final grid = mode == ViewMode.grid;
    return PaperIconButton(
      // 图标 = **当前**的排版（看得出现在是网格还是列表）
      icon: grid ? 'grid' : 'list',
      onPressed: onToggle,
      tooltip: grid ? '切换成列表' : '切换成卡片',
    );
  }
}

/// 网格 / 列表两种排版的通用小工具（给两个页面复用）。
class ViewModeIcon extends StatelessWidget {
  const ViewModeIcon({
    super.key,
    required this.mode,
    required this.color,
    this.size = 16,
  });

  final ViewMode mode;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final grid = mode == ViewMode.grid;
    return Icon(
      grid ? Icons.grid_view_rounded : Icons.view_agenda_outlined,
      size: size,
      color: color,
    );
  }
}
