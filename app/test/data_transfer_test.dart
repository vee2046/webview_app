/// App 级数据管理 —— 导出 / 导入 / 清除。
///
/// 只测 `UsageStore` 那一层（纯逻辑，不碰 UI 与文件选择器）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmlab_toolbox/data/usage_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<UsageStore> freshStore() async {
    final usage = UsageStore();
    await usage.load();
    return usage;
  }

  test('exportPayload 含全部工具快照 + 使用记录 + 置顶', () async {
    final usage = await freshStore();
    await usage.saveSnapshot('checkin', {'checkin_records': '{"a":1}'});
    await usage.saveSnapshot('mindx', {'bf_progress': '{"gameId":"B"}'});
    await usage.recordOpen('checkin');
    await usage.togglePin('checkin');

    final payload = usage.exportPayload();
    final tools = payload['tools'] as Map;
    expect(tools.keys.toSet(), {'checkin', 'mindx'});

    final usagePart = payload['usage'] as Map;
    expect((usagePart['history'] as List).length, 1);
    expect((usagePart['pinned'] as List), contains('checkin'));
  });

  test('exportPayload 能 jsonEncode / jsonDecode 往返', () async {
    final usage = await freshStore();
    await usage.saveSnapshot('checkin', {'checkin_records': '{"a":1}'});
    final raw = jsonEncode(usage.exportPayload());
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect((decoded['tools'] as Map).length, 1);
  });

  test('mergeByKey：同名 key 覆盖 + 本地独有保留 + 新工具新增', () async {
    final usage = await freshStore();
    await usage.saveSnapshot('checkin', {'k': '旧值', 'onlyLocal': '本地'});
    await usage.saveSnapshot('water', {'w': '本地独有'});

    await usage.importPayload({
      'tools': {
        'checkin': {'k': '新值'},
        'mindx': {'m': '新工具'},
      },
    });

    final checkin = usage.snapshotOf('checkin')!;
    expect(checkin['k'], '新值');
    expect(checkin['onlyLocal'], '本地');
    expect(usage.snapshotOf('water'), isNotNull);
    expect(usage.snapshotOf('mindx')!['m'], '新工具');
  });

  test('完全覆盖：先清本地再写导入的', () async {
    final usage = await freshStore();
    await usage.saveSnapshot('water', {'w': '本地独有'});
    await usage.importPayload({
      'tools': {
        'checkin': {'k': '新值'},
      },
    }, replaceAll: true);

    expect(usage.snapshotOf('water'), isNull);
    expect(usage.snapshotOf('checkin')!['k'], '新值');
  });

  test('使用记录按 toolId 去重取较新 + 置顶取并集', () async {
    final usage = await freshStore();
    await usage.recordOpen('checkin');
    await usage.togglePin('water');

    final now = DateTime.now();
    await usage.importPayload({
      'tools': <String, dynamic>{},
      'usage': {
        'history': [
          {'toolId': 'checkin', 'at': now.millisecondsSinceEpoch},
          {'toolId': 'mindx', 'at': now.millisecondsSinceEpoch},
        ],
        'pinned': ['checkin'],
      },
    });

    expect(usage.history.where((r) => r.toolId == 'checkin').length, 1);
    expect(usage.history.any((r) => r.toolId == 'mindx'), isTrue);
    expect(usage.pinned.toSet(), {'water', 'checkin'});
  });

  test('导入后持久化，冷启动能读回', () async {
    final usage = await freshStore();
    await usage.importPayload({
      'tools': {
        'checkin': {'k': 'v'},
      },
    });

    final again = await freshStore();
    expect(again.snapshotOf('checkin')!['k'], 'v');
  });

  test('clearAllData 清干净且持久化也抹掉', () async {
    final usage = await freshStore();
    await usage.saveSnapshot('checkin', {'k': 'v'});
    await usage.recordOpen('checkin');
    await usage.togglePin('checkin');

    await usage.clearAllData();
    expect(usage.snapshotOf('checkin'), isNull);
    expect(usage.history, isEmpty);
    expect(usage.pinned, isEmpty);

    final again = await freshStore();
    expect(again.snapshotOf('checkin'), isNull);
    expect(again.history, isEmpty);
  });
}
