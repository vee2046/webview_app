/// 分享长图 —— 纸片风的「工具报告」卡片。
///
/// 这个卡片是**被分享的那张长图本身**：Wrap 在 `RepaintBoundary` 里，
/// 渲染完用 `toImage()` 抓成 PNG，再交给系统分享面板。
///
/// 设计约束（沿用 kmlab_site 的手绘风）：
///   * 牛皮纸底 + 墨线描边 + 不规则圆角
///   * 颜色按**分类**取，不按工具取（和卡片页一致）
///   * 禁 emoji、禁渐变、禁霓虹
///   * 倾斜角固定小角度（±0.6°），长图上太斜会晃眼
library;

import 'package:flutter/material.dart';

import '../../icons/doodle_icons.dart';
import '../../theme/paper_theme.dart';
import 'app_logo.dart';

/// 长图里的一行：图标 + 标签 + 值。
class ShareRow {
  const ShareRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String icon;
  final String label;
  final String value;
  final Color? valueColor;
}

/// 一张可分享的长图卡片。
class ShareReportCard extends StatelessWidget {
  const ShareReportCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.accent,
    required this.rows,
    this.logoPath = 'assets/icon.svg',
    this.badge,
    this.footerNote,
    this.width = 340,
  });

  /// 品牌图标路径（配置的 `app.icon`）。
  final String logoPath;

  /// 大标题（工具名 / 「kmlab Toolbox」）
  final String title;

  /// 副标题（工具说明 / 报告日期）
  final String subtitle;

  /// doodle 图标名（9 个 kmlab 线稿之一）
  final String iconName;

  /// 强调色（分类色）
  final Color accent;

  /// 内容行
  final List<ShareRow> rows;

  /// 右上角小标签（例：「已连续 7 天」）
  final String? badge;

  /// 底部一句备注
  final String? footerNote;

  /// 长图宽度（逻辑像素）—— 固定，保证导出尺寸稳定
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: p.paperCard,
        borderRadius: paperBorderRadius(18, alternate: 10),
        border: Border.all(color: p.ink, width: p.lineWidth),
        boxShadow: p.shadowPaper,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            title: title,
            subtitle: subtitle,
            iconName: iconName,
            accent: accent,
            badge: badge,
          ),
          const SizedBox(height: 16),
          _DashedLine(color: p.ink.withValues(alpha: 0.35)),
          const SizedBox(height: 12),
          ...rows.map((r) => _Row(r)),
          if (footerNote != null) ...[
            const SizedBox(height: 14),
            _Footer(note: footerNote!),
          ],
          const SizedBox(height: 16),
          _BrandLine(logoPath: logoPath),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.accent,
    this.badge,
  });

  final String title;
  final String subtitle;
  final String iconName;
  final Color accent;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.ink, width: 1.8),
          ),
          alignment: Alignment.center,
          child: DoodleIcon(iconName, size: 28, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12.5, height: 1.35, color: p.inkSoft),
              ),
            ],
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent, width: 1.4),
            ),
            child: Text(
              badge!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.data);

  final ShareRow data;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: UiIcon(data.icon, size: 16, color: p.inkSoft),
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 74,
            child: Text(
              data.label,
              style: TextStyle(fontSize: 12.5, color: p.inkSoft),
            ),
          ),
          Expanded(
            child: Text(
              data.value,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: data.valueColor ?? p.ink,
                ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: p.paperDeep.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: p.inkSoft),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              note,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: p.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandLine extends StatelessWidget {
  const _BrandLine({required this.logoPath});

  /// 品牌图标路径（配置的 `app.icon`）。
  final String logoPath;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return Row(
      children: [
        AppLogo(path: logoPath, size: 22),
        const SizedBox(width: 7),
        // 窄屏上「kmlab Toolbox · handmade workspace」会顶掉右边的 kmlab.tech
        // → 用 ellipsis 优雅截断，而不是溢出。
        Expanded(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'kmlab Toolbox',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                TextSpan(
                  text: '  ·  handmade workspace',
                  style: TextStyle(fontSize: 11, color: p.inkSoft),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'kmlab.tech',
          style: TextStyle(fontSize: 11, color: p.inkSoft),
        ),
      ],
    );
  }
}

/// 手绘虚线分隔。
class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      width: double.infinity,
      child: CustomPaint(painter: _DashedPainter(color)),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const dash = 6.0;
    const gap = 5.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter old) => old.color != color;
}
