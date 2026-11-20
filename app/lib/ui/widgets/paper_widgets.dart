/// 「牛皮纸」通用组件 —— 手绘边框、纸片阴影、稳定倾斜角。
library;

import 'package:flutter/material.dart';

import '../../icons/doodle_icons.dart';
import '../../theme/paper_theme.dart';

/// 手绘边框纸片
class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(12),
    this.radius = 18,
    this.background,
    this.tiltSeed,
    this.tilt = 0,
    this.hoverShadow = false,
    this.borderColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final double radius;
  final Color? background;
  final String? tiltSeed;
  final double tilt;

  /// 悬停时用更深的纸片阴影
  final bool hoverShadow;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    final angle = tiltSeed != null ? seededTilt(tiltSeed!) : tilt;

    return Transform.rotate(
      angle: tiltToRadians(angle),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: paperBorderRadius(radius),
          child: Ink(
            decoration: BoxDecoration(
              color: background ?? t.paperCard,
              borderRadius: paperBorderRadius(radius),
              border: Border.all(
                color: borderColor ?? t.ink,
                width: t.lineWidth,
              ),
              boxShadow: hoverShadow ? t.shadowHover : t.shadowPaper,
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// 主操作按钮
class PaperButton extends StatelessWidget {
  const PaperButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.danger = false,
    this.fill,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final bool danger;
  final Color? fill;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    final bg = danger
        ? t.crayonRed.withValues(alpha: 0.14)
        : (fill ?? t.crayonAmber);
    final fg = danger ? t.crayonRed : t.ink;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          UiIcon(icon!, size: 16, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
          ),
        ),
      ],
    );

    return Transform.rotate(
      angle: tiltToRadians(seededTilt(label)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: paperBorderRadius(14),
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: paperBorderRadius(14),
              border: Border.all(color: t.ink, width: t.lineWidth),
              boxShadow: t.shadowPaper,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形图标按钮
class PaperIconButton extends StatelessWidget {
  const PaperIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 32,
    this.iconSize = 18,
    this.tooltip,
    this.active = false,
  });

  final String icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active ? t.crayonAmber.withValues(alpha: 0.35) : t.paperCard,
            shape: BoxShape.circle,
            border: Border.all(color: t.ink, width: t.lineWidth * 0.85),
            boxShadow: [
              BoxShadow(
                color: t.ink.withValues(alpha: 0.16),
                offset: const Offset(1.5, 2),
              ),
            ],
          ),
          child: Center(
            child: UiIcon(icon, size: iconSize, color: t.ink),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 虚线分隔的小节标题
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: t.inkSoft, fontSize: 13.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CustomPaint(
              painter: _DashedLinePainter(color: t.ink.withValues(alpha: 0.22)),
              size: const Size(double.infinity, 2),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 6.0;
    const gap = 5.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

/// 小角标
class PaperBadge extends StatelessWidget {
  const PaperBadge(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    final c = color ?? t.crayonAmber;
    return Transform.rotate(
      angle: 0.12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: t.ink, width: 1.6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            height: 1.5,
            fontWeight: FontWeight.w700,
            color: t.isDark ? t.ink : t.paper,
          ),
        ),
      ),
    );
  }
}

/// 「胶带」装饰
class TapeStrip extends StatelessWidget {
  const TapeStrip({super.key, this.width = 46, this.angle = -0.06});

  final double width;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: width,
        height: 16,
        decoration: BoxDecoration(
          color: t.crayonAmber.withValues(alpha: t.isDark ? 0.22 : 0.35),
          boxShadow: [
            BoxShadow(
              color: t.ink.withValues(alpha: 0.14),
              offset: const Offset(0, 1),
              blurRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置项行
class PaperSettingTile extends StatelessWidget {
  const PaperSettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.value,
    this.onTap,
    this.trailing,
  });

  final String icon;
  final String title;
  final String? description;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: paperBorderRadius(14),
          child: Ink(
            decoration: BoxDecoration(
              color: t.paperCard,
              borderRadius: paperBorderRadius(14),
              border: Border.all(color: t.ink, width: t.lineWidth),
              boxShadow: [
                BoxShadow(
                  color: t.ink.withValues(alpha: 0.13),
                  offset: const Offset(2, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  UiIcon(icon, size: 17, color: t.inkSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (description != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              description!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (value != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        value!,
                        textAlign: TextAlign.right,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 11.5),
                      ),
                    ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
