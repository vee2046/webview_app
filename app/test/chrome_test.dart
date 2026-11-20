/// chrome 四档 —— 回归守卫。
///
/// 重点防两件事：
///  1. **不能拿 `webview.chrome.default` 判断当前工具是不是 auto 档** ——
///     它恒为 `minimal`，当初就是这么把 auto 档写废的（BUG #22）。
///  2. 沉浸式下默认不保留顶部进度条。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kmlab_toolbox/model/app_config.dart';
import 'package:kmlab_toolbox/webview/webview_host.dart';

AppConfig loadConfig() {
  final raw = File('../config/app.config.json').readAsStringSync();
  return AppConfig.parse(raw);
}

/// 造一个不挂载的 WebViewHost，只为读它的 getter
WebViewHost hostFor(AppConfig config, String toolId, {ChromeMode? chrome}) {
  final tool = config.toolById(toolId)!;
  return WebViewHost(
    tool: tool,
    config: config,
    chrome: chrome,
    onTitleChanged: (_) {},
    onSnapshot: (_) {},
    onBridgeMessage: (_) {},
    onScrollDirection: (_) {},
  );
}

void main() {
  final config = loadConfig();

  group('auto 档', () {
    test('全局默认档是 minimal —— 拿它判断会写废 auto', () {
      expect(config.webview.chrome.defaultMode, ChromeMode.minimal);
    });

    test('只有通往 AGI 之路是 auto 档', () {
      final auto = config.tools
          .where((t) => t.open.chrome == ChromeMode.auto)
          .map((t) => t.id)
          .toList();
      expect(auto, ['feishu']);
    });

    test('isAutoChrome 只对 auto 档为真', () {
      expect(config.toolById('feishu')!.open.isAutoChrome, isTrue);
      expect(config.toolById('checkin')!.open.isAutoChrome, isFalse);
      expect(config.toolById('mindx')!.open.isAutoChrome, isFalse);
    });

    test('其它工具不会被误判成 auto', () {
      for (final tool in config.tools) {
        if (tool.id == 'feishu') continue;
        expect(tool.open.isAutoChrome, isFalse, reason: '${tool.id} 不该是 auto');
      }
    });
  });

  group('immersive 档', () {
    test('脑力慢养是 immersive 档', () {
      expect(config.toolById('mindx')!.open.chrome, ChromeMode.immersive);
    });

    test('沉浸式默认不保留进度条', () {
      expect(hostFor(config, 'mindx').keepProgressBar, isFalse);
    });

    test('其它档位保留进度条', () {
      expect(hostFor(config, 'checkin').keepProgressBar, isTrue);
      expect(hostFor(config, 'feishu').keepProgressBar, isTrue);
    });

    test('运行时切到 immersive 后立刻不保留进度条', () {
      final host = hostFor(config, 'checkin', chrome: ChromeMode.immersive);
      expect(host.effectiveChrome, ChromeMode.immersive);
      expect(host.keepProgressBar, isFalse);
    });
  });

  group('chrome 配置本身', () {
    test('autoHideDelayMs 是正数（auto 档停手要自动收起）', () {
      expect(config.webview.chrome.autoHideDelayMs, greaterThan(0));
    });

    test('options 覆盖四档', () {
      final options = config.webview.chrome.options;
      expect(options, contains(ChromeMode.full));
      expect(options, contains(ChromeMode.auto));
      expect(options, contains(ChromeMode.minimal));
      expect(options, contains(ChromeMode.immersive));
    });
  });
}
