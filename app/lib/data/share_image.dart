/// 分享长图 —— 把 Flutter 界面抓成 PNG，交给系统分享面板。
///
/// 为什么自己抓而不是用系统截图：
///   * WebView 是 PlatformView，**系统截图不会包含 H5 内容**
///     （Android 的 `convertFlutterSurfaceToImage` 也不含 PlatformView）
///   * 所以长图里画的是 **App 自己知道的数据**（工具摘要、使用统计），
///     不是「网页长截图」
///
/// 流程：RepaintBoundary → toImage → PNG 字节 → 临时文件 → SharePlus。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ShareImage {
  const ShareImage._();

  /// 抓取 [key] 指向的 RepaintBoundary，输出 PNG 字节。
  ///
  /// 失败（没挂载 / 不是 RepaintBoundary / 尺寸为 0）时返回 null，**不抛异常** ——
  /// 分享是锦上添花，不该把用户卡住。
  static Future<Uint8List?> capture(
    GlobalKey key, {
    double pixelRatio = 3.0,
  }) async {
    try {
      final context = key.currentContext;
      if (context == null) return null;
      final object = context.findRenderObject();
      if (object is! RenderRepaintBoundary) return null;
      if (!object.hasSize || object.size.isEmpty) return null;

      final image = await object.toImage(pixelRatio: pixelRatio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return null;
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// PNG 字节写到临时目录，返回文件。
  static Future<File?> savePng(Uint8List bytes, String fileName) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// 把 PNG 写到临时文件并弹出系统分享面板。
  static Future<bool> sharePng(
    Uint8List bytes, {
    required String fileName,
    String? text,
  }) async {
    final file = await savePng(bytes, fileName);
    if (file == null) return false;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: text,
        ),
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (_) {
      return false;
    }
  }

  /// 生成一个带日期的文件名：`km-share-20261121-1032.png`
  static String fileName(String prefix, DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'km-$prefix-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.png';
  }
}
