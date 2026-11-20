import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 原生 Toast（Android 走系统 Toast，iOS / macOS 走自绘浮层，其它平台退回 Flutter 的 SnackBar）。
///
/// **为什么不用 SnackBar**：Android 上 WebView 是 PlatformView，在原生视图层级里
/// 盖在 Flutter 视图之上 —— Flutter 树里画出来的 SnackBar 会被 WebView 遮住，
/// 看起来就像「提示压根没弹出来」。系统 Toast 走独立窗口层，一定盖得住。
/// iOS / macOS 的 WKWebView 同理，而且这两端都没有系统 Toast，所以
/// `ios/Runner/AppDelegate.swift` 与 `macos/Runner/MainFlutterWindow.swift`
/// 里各自自绘了一个同款浮层。
class NativeToast {
  const NativeToast._();

  static const MethodChannel _channel = MethodChannel('km/toast');

  static Future<void> show(BuildContext context, String message) async {
    if (message.trim().isEmpty) return;

    final native = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (native) {
      try {
        await _channel.invokeMethod<void>('show', {'message': message});
        return;
      } catch (_) {
        // 通道不可用就退回下面
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
