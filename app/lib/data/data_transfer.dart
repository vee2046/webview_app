/// App 级数据管理 —— 导出全部 / 导入 / 清除全部。
///
/// 与「单个工具的导出」是同一套落地方式（DESIGN §5.7）：
///   导出 → 生成 `.json` 文件 → 系统分享面板（剪贴板仅兜底）
///   导入 → FilePicker 选文件 → 校验 → 冲突确认 → mergeByKey 合并
///   清除 → 二次确认（写明影响范围 + 给「先导出备份」出口）
///
/// 与单工具导出的区别：
///   · 单工具导出的是**这个工具的 localStorage 快照**
///   · 这里导出的是**全部工具的快照 + 使用记录 + 置顶**（换机搬运用）
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../model/app_config.dart';
import '../theme/paper_theme.dart';
import '../util/native_toast.dart';
import 'usage_store.dart';

/// 导入后发生了什么，给调用方一个可读的结论。
class ImportSummary {
  const ImportSummary({
    required this.toolCount,
    required this.keyCount,
    required this.conflicts,
    required this.replaced,
  });

  final int toolCount;
  final int keyCount;
  final int conflicts;
  final bool replaced;

  String get text {
    final buf = StringBuffer();
    buf.write('导入 $toolCount 个工具、$keyCount 项数据');
    if (conflicts > 0) {
      buf.write(replaced ? '（覆盖了 $conflicts 项同名数据）' : '（合并了 $conflicts 项同名数据）');
    }
    return buf.toString();
  }
}

class AppDataTransfer {
  const AppDataTransfer._();

  /// 导出全部数据 → `.json` 文件 → 系统分享面板。
  static Future<void> exportAll(
    BuildContext context,
    UsageStore usage,
    AppConfig config,
  ) async {
    final payload = <String, dynamic>{
      'kind': 'app-wide',
      'app': config.app.name,
      'appName': config.app.appName,
      'version': config.about.version,
      'exportedAt': DateTime.now().toIso8601String(),
      ...usage.exportPayload(),
    };

    final dir = await getTemporaryDirectory();
    final name = 'km-all-backup-${_stamp(DateTime.now())}.json';
    final file = File('${dir.path}/$name');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );

    final share = config.webview.dataTransfer;
    if (!context.mounted) return;
    if (share.exportDelivery == 'share') {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          title: config.app.appName,
          text: '${config.app.appName} 的全部数据备份',
        ),
      );
    } else {
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
      );
      if (!context.mounted) return;
      await NativeToast.show(context, '数据已复制到剪贴板');
    }
  }

  /// 导入：选文件 → 校验 → 冲突确认 → 合并。返回 null 表示用户取消或文件无效。
  static Future<ImportSummary?> importAll(
    BuildContext context,
    UsageStore usage,
    AppConfig config,
  ) async {
    final dt = config.webview.dataTransfer;
    if (!dt.importEnabled) return null;

    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return null;

    final bytes = result.files.first.bytes;
    if (!context.mounted) return null;
    if (bytes == null) {
      await NativeToast.show(context, '读不到这个文件');
      return null;
    }
    if (bytes.length > dt.importMaxSizeMb * 1024 * 1024) {
      await NativeToast.show(context, '文件太大了（上限 ${dt.importMaxSizeMb} MB）');
      return null;
    }

    Object? decoded;
    String? bad;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      bad = '这不是一个有效的备份文件';
    }
    if (!context.mounted) return null;
    if (bad != null) {
      await NativeToast.show(context, bad);
      return null;
    }
    if (decoded is! Map) {
      await NativeToast.show(context, '备份文件格式不对');
      return null;
    }
    if (!context.mounted) return null;
    final payload = Map<String, dynamic>.from(decoded);

    // 单工具备份也可以整个导进来（结构不一样，这里做个兼容转换）
    final tools = payload['tools'];
    final singleStorage = payload['storage'];
    if (tools is! Map && singleStorage is Map) {
      payload['tools'] = {payload['toolId'] ?? 'unknown': singleStorage};
    }
    if (payload['tools'] is! Map) {
      await NativeToast.show(context, '备份文件里没有数据');
      return null;
    }
    if (!context.mounted) return null;

    // 冲突统计
    final incoming = (payload['tools'] as Map).cast<String, dynamic>();
    var conflicts = 0;
    var keyCount = 0;
    for (final entry in incoming.entries) {
      final v = entry.value;
      if (v is! Map) continue;
      final local = usage.snapshotOf(entry.key) ?? const <String, dynamic>{};
      for (final k in v.keys) {
        keyCount++;
        if (local.containsKey(k)) conflicts++;
      }
    }

    if (!context.mounted) return null;

    // 冲突策略（`importConflictPolicy: "confirm"`）
    var replaceAll = false;
    if (conflicts > 0 && dt.importConflictPolicy == 'confirm') {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('有同名的数据'),
          content: Text(
            '备份里有 $conflicts 项数据和这台设备上已有的同名。\n'
            '「合并」= 同名用备份覆盖、本地独有的保留（mergeByKey）；\n'
            '「完全覆盖」= 先清掉本地全部数据再导入。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('完全覆盖'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('合并'),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return null;
      if (!context.mounted) return null;
      replaceAll = choice == 'replace';
    }

    await usage.importPayload(payload, replaceAll: replaceAll);
    if (!context.mounted) return null;

    return ImportSummary(
      toolCount: incoming.length,
      keyCount: keyCount,
      conflicts: conflicts,
      replaced: replaceAll,
    );
  }

  /// 清除全部本地数据（使用记录 + 置顶 + 所有工具快照）。
  static Future<bool> clearAll(
    BuildContext context,
    UsageStore usage,
    AppConfig config,
  ) async {
    if (!context.mounted) return false;

    final ok = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final p = ctx.paper;
        return AlertDialog(
          title: const Text('清除这台设备上的全部数据？'),
          content: Text(
            '会清掉：\n'
            '· 所有工具的本地数据快照（${usage.snapshotIds.length} 个工具）\n'
            '· 使用记录与置顶\n\n'
            '只影响这台设备，不影响网页版上的数据。\n'
            '清掉之后就没法恢复了 —— 建议先「导出全部」。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'export'),
              child: const Text('先导出备份'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: p.crayonRed),
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );

    if (ok == 'export') {
      if (!context.mounted) return false;
      await exportAll(context, usage, config);
      return false;
    }
    if (ok != 'clear') return false;

    await usage.clearAllData();
    return true;
  }

  static String _stamp(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}';
  }
}
