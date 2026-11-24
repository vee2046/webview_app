/// 下载 APK + 拉起系统安装界面。
///
/// 分工：
///   - **下载**在 Dart 侧做（已有 `http` 依赖，不需要额外插件）
///   - **拉起安装界面**必须走原生（`content://` URI + `FLAG_GRANT_READ_URI_PERMISSION`，
///     `url_launcher` 给不了这个授权）→ MethodChannel `km/install`
///
/// 只做 Android；其它平台直接返回「不支持」。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_checker.dart';

class UpdateInstaller {
  static const MethodChannel _channel = MethodChannel('km/install');

  /// 下载到 App 缓存目录（`FileProvider` 授权的那棵子树里）。
  static Future<String> download(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final file = File('${dir.path}/kmlab-toolbox-${info.versionCode}.apk');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(info.url))
        ..followRedirects = true;
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw Exception('下载失败：HTTP ${res.statusCode}');
      }
      final total = res.contentLength ?? info.size;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        received += chunk.length;
        onProgress?.call(received, total);
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      return file.path;
    } finally {
      client.close();
    }
  }

  /// 拉起系统安装界面。返回 false 表示「当前平台不支持」。
  static Future<bool> install(String apkPath) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('installApk', {'path': apkPath});
      return ok == true;
    } on PlatformException catch (e) {
      debugPrint('[UpdateInstaller] 安装失败：${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
