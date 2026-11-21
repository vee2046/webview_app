/// 分享长图的预览弹窗 —— 先给用户看一眼，再决定分不分享。
///
/// 为什么要预览：长图是**App 自己画的一张海报**（不是网页截图），
/// 用户有权在发出去之前看一眼它长什么样。
///
/// 抓图的技术细节：
///   * `RepaintBoundary` 必须包住整张卡片（不是滚动视口），
///     否则抓到的只有可见那一屏
///   * 卡片宽度取 `min(340, 视口宽)` —— 小屏（320dp）上不能溢出
library;

import 'package:flutter/material.dart';

import '../data/share_image.dart';
import '../theme/paper_theme.dart';
import '../util/native_toast.dart';
import 'widgets/paper_widgets.dart';

/// 弹出分享长图预览。
///
/// 返回 true = 用户点了「分享」且已交给系统分享面板。
Future<bool> showSharePreview(
  BuildContext context, {
  required Widget Function(double width) cardBuilder,
  required String fileName,
  String? text,
  String? hint,
}) async {
  final key = GlobalKey();

  /// 导出长图的固定宽度（逻辑像素）—— 固定值，导出尺寸才稳定。
  const double cardWidth = 340;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    // 横向可滚动：卡片固定 340 逻辑宽，小屏（320dp）上能左右滑，
                    // 而不是把长图挤成一窄条。
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: RepaintBoundary(
                        key: key,
                        child: cardBuilder(cardWidth),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PaperButton(
                    label: '取消',
                    expand: false,
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                  const SizedBox(width: 10),
                  PaperButton(
                    label: '分享长图',
                    icon: 'share',
                    expand: false,
                    onPressed: () async {
                      // 等一帧，确保 RepaintBoundary 已经画出来
                      await Future<void>.delayed(const Duration(milliseconds: 60));
                      final bytes = await ShareImage.capture(key);
                      if (bytes == null || bytes.isEmpty) {
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop(false);
                          NativeToast.show(ctx, '长图生成失败');
                        }
                        return;
                      }
                      final ok = await ShareImage.sharePng(
                        bytes,
                        fileName: fileName,
                        text: text,
                      );
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop(ok);
                        if (!ok) NativeToast.show(ctx, '分享失败');
                      }
                    },
                  ),
                ],
              ),
              if (hint != null) ...[
                const SizedBox(height: 10),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: ctx.paper.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  return result ?? false;
}
