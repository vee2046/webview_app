import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kmlab_toolbox/data/view_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViewPrefs · 视图偏好（网格 ⇄ 列表）', () {
    test('默认是网格', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = ViewPrefs();
      await prefs.load();
      expect(prefs.mode, ViewMode.grid);
      expect(prefs.isGrid, isTrue);
      expect(prefs.isList, isFalse);
      expect(prefs.hasUserChoice, isFalse);
    });

    test('toggle 在网格 / 列表之间来回切', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = ViewPrefs();
      await prefs.load();

      await prefs.toggle();
      expect(prefs.mode, ViewMode.list);

      await prefs.toggle();
      expect(prefs.mode, ViewMode.grid);
    });

    test('切换后持久化，冷启动读回来还是同一个', () async {
      SharedPreferences.setMockInitialValues({});
      final a = ViewPrefs();
      await a.load();
      await a.toggle();

      // 换一个实例 = 模拟冷启动
      final b = ViewPrefs();
      await b.load();
      expect(b.mode, ViewMode.list);
      expect(b.hasUserChoice, isTrue);
    });

    test('持久化的 key 就是约定的那个', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = ViewPrefs();
      await prefs.load();
      await prefs.toggle();

      final raw = await SharedPreferences.getInstance();
      expect(raw.getString(ViewPrefs.key), 'list');
    });

    test('setMode 同一个值不会重复通知', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = ViewPrefs();
      await prefs.load();

      var notified = 0;
      prefs.addListener(() => notified++);

      await prefs.setMode(ViewMode.grid); // 已经是 grid
      expect(notified, 0);

      await prefs.setMode(ViewMode.list);
      expect(notified, 1);
    });

    test('ViewMode.fromName 容错', () {
      expect(ViewMode.fromName('list'), ViewMode.list);
      expect(ViewMode.fromName('grid'), ViewMode.grid);
      expect(ViewMode.fromName(null), ViewMode.grid);
      expect(ViewMode.fromName('乱写'), ViewMode.grid);
    });

    group('配置默认值 vs 用户选择', () {
      test('没手动选过时跟随配置', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = ViewPrefs();
        await prefs.load();

        prefs.setConfigDefault(ViewMode.list);
        expect(prefs.mode, ViewMode.list);
        expect(prefs.hasUserChoice, isFalse);
      });

      test('手动选过之后不再被配置覆盖', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = ViewPrefs();
        await prefs.load();

        await prefs.toggle(); // 用户选了 list
        prefs.setConfigDefault(ViewMode.grid);
        expect(prefs.mode, ViewMode.list);

        prefs.setConfigDefault(ViewMode.list);
        expect(prefs.mode, ViewMode.list);
      });
    });
  });
}
