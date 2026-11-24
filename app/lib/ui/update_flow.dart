/// 自动更新的交互流程 —— 「发现新版本 → 确认 → 下载 → 拉起安装」。
///
/// 「我的 → 检查更新」和「启动时自动提示」共用这一段，避免两份逻辑。
library;

import 'package:flutter/material.dart';

import '../data/update_checker.dart';
import '../data/update_installer.dart';
import '../util/native_toast.dart';

/// 弹「发现新版本」对话框 → 用户点「立即更新」就下载并拉起系统安装界面。
///
/// 返回 true = 用户点了「立即更新」。
Future<bool> showUpdateFlow(BuildContext context, UpdateInfo info) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('发现新版本 ${info.versionName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info.note.isNotEmpty)
            Text(info.note, style: const TextStyle(fontSize: 13, height: 1.4)),
          if (info.sizeText.isNotEmpty)
            Text(
              '大小 ${info.sizeText}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
  if (go != true) return false;
  if (!context.mounted) return false;

  await downloadAndInstall(context, info);
  return true;
}

/// 下载 APK（带进度）→ 拉起系统安装界面。
Future<void> downloadAndInstall(BuildContext context, UpdateInfo info) async {
  final progress = ValueNotifier<double>(0);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('正在下载'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: value <= 0 ? null : value),
            const SizedBox(height: 10),
            Text(
              '${(value * 100).toStringAsFixed(0)}%'
              '${info.sizeText.isEmpty ? '' : ' · ${info.sizeText}'}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  try {
    final path = await UpdateInstaller.download(
      info,
      onProgress: (received, total) {
        if (total > 0) progress.value = received / total;
      },
    );
    if (!context.mounted) return;
    final ok = await UpdateInstaller.install(path);
    if (!context.mounted) return;
    await NativeToast.show(
      context,
      ok ? '下载完成，正在打开安装界面' : '下载完成，但当前平台不支持自动安装',
    );
  } catch (e) {
    if (!context.mounted) return;
    await NativeToast.show(context, '下载失败：$e');
  } finally {
    progress.dispose();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}
