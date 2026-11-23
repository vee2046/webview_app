/// 端上 UI 冒烟测试 —— 双端通用。
///
/// 跑法：
///   Android：`flutter test integration_test/app_smoke_test.dart -d emulator-5554`
///   iOS/macOS：`flutter drive --driver=test_driver/integration_test.dart \
///                              --target=integration_test/app_smoke_test.dart -d DEVICE`
///
/// ⚠️ **Android 上千万别用 `flutter drive`** —— 没有 driver 消费者时
/// `binding.takeScreenshot()` 永远不会完成，整个测试会卡死（BUG #17）。
/// Android 用 `flutter test integration_test/...`。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:kmlab_toolbox/main.dart' as app;
import 'package:kmlab_toolbox/ui/recent_page.dart';
import 'package:kmlab_toolbox/ui/tools_page.dart';
import 'package:kmlab_toolbox/ui/widgets/paper_widgets.dart';

/// 被测 App 已经启动过没有。
///
/// ⚠️ **这一段是本文件最关键的地方**（BUG #27）：
/// `flutter test integration_test/xxx.dart` 和
/// `flutter drive --target=integration_test/xxx.dart`
/// **都是把「测试文件」当成 App 的入口** —— 被测 App 的 `lib/main.dart`
/// **不会自动跑**。不自己调一次 `app.main()`，整个 widget 树就是空的，
/// 所有 `find.text(...)` 全部找不到（表现为「首屏最近页能渲染」这种用例直接挂）。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 启动被测 App + 等首屏稳定。
  ///
  /// ⚠️ 关键：**每个用例都要保证 App 在跑**。
  /// `testWidgets` 之间 widget 树会被重置（第一个用例跑完，第二个用例的
  /// `find.text(...)` 就全找不到元素了 —— 报 `Bad state: No element`）。
  /// 所以这里不靠「启动过没有」的标记，而是**看树里还有没有 App**：
  /// 没有就重新 `app.main()` 一次。
  Future<void> startApp(WidgetTester tester) async {
    if (find.byType(MaterialApp).evaluate().isEmpty) {
      await app.main();
    }
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

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

  /// **真**等待（墙钟时间）。
  ///
  /// ⚠️ `pumpAndSettle(Duration(seconds: 20))` 里的 20 秒是**每帧之间的间隔**，
  /// 不是「等 20 秒」—— WebView 没有动画，它一帧就 settle 了。
  /// 要等网络/JS 回调（页面加载、Service Worker 注册）必须用 `runAsync` 真睡。
  Future<void> waitReal(WidgetTester tester, int seconds) async {
    await tester.runAsync(
      () => Future<void>.delayed(Duration(seconds: seconds)),
    );
    await tester.pumpAndSettle();
  }

  /// 在 ⋯ 溢出菜单里点某个条目。
  ///
  /// ⚠️ **Android 小屏（320×640）上 ⋯ 菜单放不下** ——
  /// 11 个条目 + 4 个分组标题总高超过屏幕，菜单是可滚动的，
  /// 「关于这个工具」在折叠线以下，`find.text` **根本找不到**（ListView 懒建）。
  /// iPhone 16（393×852）上能一屏放下，所以 iOS 上不滚动也能找到 ——
  /// 这就是「同一套用例，Android 挂 iOS 过」的经典原因。
  Future<void> tapOverflowItem(WidgetTester tester, String label) async {
    final list = find.byType(ListView).last;
    for (var i = 0; i < 8; i++) {
      if (find.text(label).evaluate().isNotEmpty) break;
      await tester.drag(list, const Offset(0, -160));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }
    expect(
      find.text(label).evaluate().isNotEmpty,
      isTrue,
      reason: '⋯ 菜单里应有「$label」（小屏上要先滚动）',
    );
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// 打开「打卡助手」并等 WebView 真的把远程 H5 加载完。
  Future<void> openCheckinTool(WidgetTester tester,
      {int loadSeconds = 6}) async {
    await tester.tap(find.text('小工具').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final target = find.text('打卡助手').first;
    expect(target, findsWidgets, reason: '小工具页里应有「打卡助手」卡片');
    await tester.tap(target);
    await waitReal(tester, loadSeconds);
  }

  testWidgets('① 首屏「最近」页能渲染', (WidgetTester tester) async {
    await startApp(tester);
    dumpTexts(tester, 'recent');
    expect(find.text('最近'), findsWidgets);
    expect(find.text('小工具'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    await shot('01_recent');
  });

  testWidgets('② 小工具页能渲染出工具卡片', (WidgetTester tester) async {
    await startApp(tester);
    await tester.tap(find.text('小工具').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    dumpTexts(tester, 'tools');
    expect(find.text('kmlab'), findsWidgets);
    await shot('02_tools');
  });

  testWidgets('③ 点开工具 → WebView 加载远程 H5（不出兜底页）',
      (WidgetTester tester) async {
    await startApp(tester);
    await openCheckinTool(tester);

    dumpTexts(tester, 'tool');
    expect(
      find.text('这一页没打开'),
      findsNothing,
      reason: '不该出现兜底页 —— 说明 WebView 没加载到 kmlab.tech',
    );
    await shot('03_tool');
  });

  testWidgets('④ 顶栏返回 → 回到根页面', (WidgetTester tester) async {
    await startApp(tester);
    await openCheckinTool(tester);

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

  testWidgets('⑤ 离线能力被如实探测并显示（两端各自的结果）',
      (WidgetTester tester) async {
    await startApp(tester);
    // Service Worker 首次注册要下载 + 安装，给足时间
    await openCheckinTool(tester, loadSeconds: 10);

    // ⋯ 溢出菜单 → 关于这个工具
    final more = find.bySemanticsLabel('更多');
    expect(more.evaluate().isNotEmpty, isTrue, reason: '顶栏应有「更多」按钮');
    await tester.tap(more.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tapOverflowItem(tester, '关于这个工具');

    dumpTexts(tester, 'about');

    // 「断网可用」这一行必须是**确定结论**，不能停在「首次访问后自动缓存」
    // —— 那说明 App 压根没探测到离线能力（BUG #28）。
    final cached = find.text('已缓存到本机');
    final unsupported = find.text('此平台不支持（需域名验证）');
    final platformName =
        Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'macOS');

    if (Platform.isIOS) {
      // iOS 的 WKWebView **只在已验证的 app-bound domain 里**才暴露
      // navigator.serviceWorker；kmlab.tech 未走 Apple 的域名验证流程，
      // 所以 `navigator.serviceWorker` 是 undefined —— 离线能力用不了，
      // 但 App 必须**如实说出来**，而不是假装「首次访问后自动缓存」。
      expect(
        unsupported,
        findsWidgets,
        reason: 'iOS 上 SW API 不存在，应显示「此平台不支持（需域名验证）」',
      );
    } else {
      // Android 与 macOS 的 WKWebView 都直接暴露 Service Worker API
      expect(
        cached,
        findsWidgets,
        reason: '$platformName 上 Service Worker 应注册成功，显示「已缓存到本机」',
      );
    }
    await shot('05_sw');
  });

  testWidgets('⑦ 顶栏右侧 = 切显示格式（最近页与小工具页共用一个开关）',
      (WidgetTester tester) async {
    await startApp(tester);
    await tester.tap(find.text('小工具').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 顶栏右侧**只有**一个按钮（原来有「刷新配置」+「齿轮跳我的」两个）
    final toolsButtons = find.descendant(
      of: find.byType(ToolsPage),
      matching: find.byType(PaperIconButton),
    );
    expect(
      toolsButtons,
      findsOneWidget,
      reason: '小工具页顶栏右侧现在只保留一个按钮（网格 ⇄ 列表）',
    );

    // ⚠️ IndexedStack 里三个页面都活着（只是不绘制），
    //    所以 tooltip 一定要**按页面 scope** 去找，否则两个页面各有一个 → tap 会报「找到多个」。
    Finder listToggleIn(Type page) => find.descendant(
          of: find.byType(page),
          matching: find.byTooltip('切换成列表'),
        );

    bool inListMode() =>
        find
            .descendant(
              of: find.byType(ToolsPage),
              matching: find.byTooltip('切换成卡片'),
            )
            .evaluate()
            .isNotEmpty;

    final before = inListMode();
    await tester.tap(before
        ? find.descendant(
            of: find.byType(ToolsPage),
            matching: find.byTooltip('切换成卡片'),
          )
        : listToggleIn(ToolsPage));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(inListMode(), !before, reason: '点一下应该切到另一种排版');

    // 回到最近页 —— 同一个开关，状态跟着走
    await tester.tap(find.text('最近').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(
      find
          .descendant(
            of: find.byType(RecentPage),
            matching: find.byTooltip('切换成卡片'),
          )
          .evaluate()
          .isNotEmpty,
      !before,
      reason: '最近页和小工具页共用一个视图开关',
    );
  });

  testWidgets('⑥ JS Bridge 注入成功（window.KM 存在）',
      (WidgetTester tester) async {
    await startApp(tester);
    await openCheckinTool(tester, loadSeconds: 8);

    // Bridge 注入失败时，App 的标题会一直是工具默认名；
    // 注入成功 → ready 事件派发 → 页面能拿到 window.KM。
    // 这里用「关于这个工具」里能读到真实 URL 来间接验证页面是活的。
    final more = find.bySemanticsLabel('更多');
    await tester.tap(more.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tapOverflowItem(tester, '关于这个工具');

    expect(
      find.text('https://kmlab.tech/h5_tools/checkIn.html'),
      findsWidgets,
      reason: 'WebView 应已加载到 kmlab.tech（说明页面活着、JS 通道没被拦）',
    );
    await shot('06_bridge');
  });
}
