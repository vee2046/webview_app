/// 端上 UI 冒烟测试 —— 双端通用。
///
/// 跑法：
///   Android：`flutter test integration_test/app_smoke_test.dart -d emulator-5554`
///   iOS/macOS：`flutter drive --driver=test_driver/integration_test.dart \
///                              --target=integration_test/app_smoke_test.dart -d DEVICE
///
/// ⚠️ **Android 上千万别用 `flutter drive`** —— 没有 driver 消费者时
/// `binding.takeScreenshot()` 永远不会完成，整个测试会卡死（BUG #17）。
/// Android 用 `flutter test integration_test/...`。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 截图尽力而为 —— 绝不让它拖累断言（见 BUG #17）
  Future<void> shot(String name) async {
    try {
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
      }
      await binding.takeScreenshot(name).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[shot] $name 跳过：$e');
    }
  }

  /// 打印当前页面上所有可见文本，定位用
  void dumpTexts(WidgetTester tester, String tag) {
    final all = tester.widgetList<Text>(find.byType(Text));
    debugPrint('[$tag] ${all.map((t) => t.data).whereType<String>().toList()}');
  }

  testWidgets('① 首屏「最近」页能渲染', (WidgetTester tester) async {
    await tester.pumpAndSettle(const Duration(seconds: 3));
    dumpTexts(tester, 'recent');
    expect(find.text('最近'), findsWidgets);
    expect(find.text('小工具'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    await shot('01_recent');
  });

  testWidgets('② 小工具页能渲染出工具卡片', (WidgetTester tester) async {
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('小工具').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    dumpTexts(tester, 'tools');
    expect(find.text('kmlab'), findsWidgets);
    await shot('02_tools');
  });

  testWidgets('③ 点开工具 → WebView 加载远程 H5（不出兜底页）',
      (WidgetTester tester) async {
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('小工具').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 打开「打卡助手」（minimal chrome 的第一个工具）
    final target = find.text('打卡助手').first;
    expect(target, findsWidgets, reason: '小工具页里应有「打卡助手」卡片');
    await tester.tap(target);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 等 WebView 真实加载远程页面（LiveTestWidgetsFlutterBinding 是真异步）
    await tester.pumpAndSettle(const Duration(seconds: 20));

    dumpTexts(tester, 'tool');
    expect(
      find.text('这一页没打开'),
      findsNothing,
      reason: '不该出现兜底页 —— 说明 WebView 没加载到 kmlab.tech',
    );
    await shot('03_tool');
  });

  testWidgets('④ 顶栏返回 → 回到根页面', (WidgetTester tester) async {
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('小工具').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final target = find.text('打卡助手').first;
    await tester.tap(target);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 顶栏的返回按钮（读屏标签是「返回」）
    final back = find.bySemanticsLabel('返回');
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back.first);
    } else {
      await tester.tap(find.byType(Icon).first);
    }
    await tester.pumpAndSettle(const Duration(seconds: 2));

    dumpTexts(tester, 'back');
    expect(find.text('这一页没打开'), findsNothing);
    await shot('04_back');
  });
}
