/// 续接卡摘要算法 —— 端到端跑真实配置 + 真实算法。
///
/// 用的是仓库根目录的 `config/app.config.json`（唯一真相源），
/// 所以配置一改，这里的期望值就会红 —— 正好起到「配置即契约」的作用。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmlab_toolbox/data/resume_reader.dart';
import 'package:kmlab_toolbox/data/usage_store.dart';
import 'package:kmlab_toolbox/model/app_config.dart';

AppConfig loadConfig() {
  final raw = File('../config/app.config.json').readAsStringSync();
  return AppConfig.parse(raw);
}

void main() {
  final config = loadConfig();
  final reader = ResumeReader();

  group('配置本身', () {
    test('9 个工具', () {
      expect(config.tools.length, 9);
    });

    test('app.tabs 是分类的唯一真相源', () {
      final ids = config.app.tabs.map((t) => t.id).toList();
      expect(ids, containsAll(<String>['all', 'life', 'productivity', 'knowledge', 'misc']));
      // 每个工具引用的 tab 都必须在 app.tabs 里
      for (final tool in config.tools) {
        expect(ids, contains(tool.tab));
      }
    });

    test('打卡助手用 countDateMap 算法', () {
      final checkin = config.toolById('checkin');
      expect(checkin, isNotNull);
      expect(checkin!.resume.extract.kind, ExtractKind.countDateMap);
      expect(checkin.resume.extract.key, 'checkin_records');
    });
  });

  group('打卡助手（countDateMap）', () {
    final tool = config.toolById('checkin')!;

    test('今天 2 次 → 「今天 2 次打卡」', () {
      final today = ResumeReader.dateKey(DateTime.now());
      final snapshot = {
        'checkin_records': jsonEncode({
          today: [
            {'t': 'in', 'time': '08:38:21'},
            {'t': 'in', 'time': '08:40:19'},
          ],
        }),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.available, isTrue);
      expect(summary.text, contains('2'));
      expect(summary.text, contains('打卡'));
    });

    test('今天没有但历史有 → 提示累计', () {
      final snapshot = {
        'checkin_records': jsonEncode({
          '2020-01-01': [
            {'t': 'in', 'time': '08:00:00'},
          ],
        }),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.text, contains('1'));
    });

    test('完全没有数据 → 「还没开始」', () {
      final summary = reader.summarize(tool, const {});
      expect(summary.available, isFalse);
      expect(summary.text, '还没开始');
    });

    test('null 快照 → 「还没开始」', () {
      final summary = reader.summarize(tool, null);
      expect(summary.available, isFalse);
      expect(summary.text, '还没开始');
    });
  });

  group('其它工具的摘要', () {
    test('药品管家：数 meds 数组', () {
      final tool = config.toolById('medicine')!;
      final snapshot = {
        'medicine_tracker_v1': jsonEncode({
          'meds': [
            {'name': '维生素'},
            {'name': '钙片'},
          ],
        }),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.available, isTrue);
      expect(summary.text, contains('2'));
    });

    test('任务管理：数 tasks 数组', () {
      final tool = config.toolById('list')!;
      final snapshot = {
        'todo-h5:v1': jsonEncode({
          'tasks': [
            {'id': 1},
          ],
        }),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.available, isTrue);
      expect(summary.text, contains('1'));
    });

    test('宝盒月光：数 installments 数组', () {
      final tool = config.toolById('whereismoney')!;
      final snapshot = {
        'baobox.v1': jsonEncode({
          'installments': [
            {'name': '手机'},
            {'name': '耳机'},
            {'name': '显示器'},
          ],
        }),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.available, isTrue);
      expect(summary.text, contains('3'));
    });

    test('每日喝水：数今天的记录并带目标', () {
      final tool = config.toolById('water')!;
      final today = DateTime.now();
      final snapshot = {
        'waterIntakeRecords': jsonEncode([
          {'id': 1, 'timestamp': today.toIso8601String()},
          {'id': 2, 'timestamp': today.toIso8601String()},
          {'id': 3, 'timestamp': today.toIso8601String()},
        ]),
        'waterIntakeGoal': '8',
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.available, isTrue);
      expect(summary.text, contains('3'));
    });

    test('每日喝水：今天还没喝 → 不可用', () {
      final tool = config.toolById('water')!;
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final snapshot = {
        'waterIntakeRecords': jsonEncode([
          {'id': 1, 'timestamp': yesterday.toIso8601String()},
        ]),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.available, isFalse);
    });
  });

  group('UsageStore 快照往返', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('保存后能读回', () async {
      final usage = UsageStore();
      await usage.load();
      await usage.saveSnapshot('checkin', {'checkin_records': '{"2026-11-19":[]}'});
      expect(usage.snapshotOf('checkin'), isNotNull);
      expect(usage.snapshotOf('checkin')!['checkin_records'], '{"2026-11-19":[]}');
    });

    test('冷启动后仍能读回（load 必须调 loadSnapshots）', () async {
      final first = UsageStore();
      await first.load();
      await first.saveSnapshot('mindx', {'bf_progress': '{"gameId":"B"}'});

      final second = UsageStore();
      await second.load();
      expect(second.snapshotOf('mindx'), isNotNull);
      expect(second.snapshotOf('mindx')!['bf_progress'], '{"gameId":"B"}');
    });

    test('快照能算出今天的打卡摘要', () async {
      final usage = UsageStore();
      await usage.load();
      final today = ResumeReader.dateKey(DateTime.now());
      await usage.saveSnapshot('checkin', {
        'checkin_records': jsonEncode({
          today: [
            {'t': 'in', 'time': '08:00:00'},
          ],
        }),
      });
      final tool = config.toolById('checkin')!;
      final summary = reader.summarize(tool, usage.snapshotOf('checkin'));
      expect(summary.available, isTrue);
      expect(summary.text, contains('1'));
    });
  });

  group('maybeDecode', () {
    test('JSON 对象字符串会被解开', () {
      final v = ResumeReader.maybeDecode('{"a":1}');
      expect(v, isA<Map<String, dynamic>>());
    });

    test('JSON 数组字符串会被解开', () {
      final v = ResumeReader.maybeDecode('[1,2]');
      expect(v, isA<List<dynamic>>());
    });

    test('普通字符串原样返回', () {
      expect(ResumeReader.maybeDecode('hello'), 'hello');
    });

    test('空串返回 null', () {
      expect(ResumeReader.maybeDecode(''), isNull);
    });

    test('坏 JSON 原样返回', () {
      expect(ResumeReader.maybeDecode('{not json'), '{not json');
    });

    test('null 原样返回', () {
      expect(ResumeReader.maybeDecode(null), isNull);
    });
  });
}
