/// 配置差异 —— 「让远端热更可审」的算法测试。
///
/// ⚠️ 两层 API 要分清：
///   * `ConfigDiff.diffMaps` —— 纯 JSON 树差异（算法本体，什么都能比）
///   * `ConfigDiff.between`   —— 两份 **AppConfig** 的差异（跑在模型 toJson 上，
///                              所以模型不认识的字段天然看不见 —— 这是有意的）
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kmlab_toolbox/config/config_diff.dart';
import 'package:kmlab_toolbox/model/app_config.dart';

void main() {
  final raw = File('../config/app.config.json').readAsStringSync();
  final config = AppConfig.parse(raw);

  group('基本行为', () {
    test('同一份配置比出来没有差异', () {
      expect(ConfigDiff.between(config, config), isEmpty);
    });

    test('摘要：没有变化', () {
      expect(ConfigDiff.summarize(const []), '配置没有变化');
    });

    test('摘要：统计三类变化', () {
      final changes = [
        const ConfigChange(
            path: 'a', kind: ConfigChangeKind.changed, before: 1, after: 2),
        const ConfigChange(
            path: 'b', kind: ConfigChangeKind.added, after: 3),
        const ConfigChange(
            path: 'c', kind: ConfigChangeKind.removed, before: 4),
      ];
      expect(ConfigDiff.summarize(changes), '修改 1 处 · 新增 1 处 · 删除 1 处');
    });
  });

  group('字段级差异（diffMaps）', () {
    test('改一个顶层字段 → 一条 changed', () {
      final diff = ConfigDiff.diffMaps(
        {'app': {'name': 'kmlab'}},
        {'app': {'name': 'kmlab Toolbox'}},
        '',
      );
      expect(diff.length, 1);
      expect(diff.first.kind, ConfigChangeKind.changed);
      expect(diff.first.path, 'app.name');
      expect(diff.first.before, 'kmlab');
      expect(diff.first.after, 'kmlab Toolbox');
    });

    test('新增一个键 → added', () {
      final diff = ConfigDiff.diffMaps({'app': {}}, {'app': {'x': 1}}, '');
      expect(diff.length, 1);
      expect(diff.first.kind, ConfigChangeKind.added);
      expect(diff.first.path, 'app.x');
    });

    test('删掉一个键 → removed', () {
      final diff = ConfigDiff.diffMaps({
        'app': {'x': 1}
      }, {'app': {}}, '');
      expect(diff.length, 1);
      expect(diff.first.kind, ConfigChangeKind.removed);
      expect(diff.first.path, 'app.x');
    });

    test('嵌套三层也能定位到路径', () {
      final diff = ConfigDiff.diffMaps(
        {
          'app': {
            'a': {'b': {'c': 1}}
          }
        },
        {
          'app': {
            'a': {'b': {'c': 2}}
          }
        },
        '',
      );
      expect(diff.length, 1);
      expect(diff.first.path, 'app.a.b.c');
    });

    test('路径前缀会带上父路径', () {
      final diff = ConfigDiff.diffMaps({'a': 1}, {'a': 2}, 'root');
      expect(diff.first.path, 'root.a');
    });

    test('值相等但类型不同 → 算变化', () {
      final diff = ConfigDiff.diffMaps({'a': 1}, {'a': '1'}, '');
      expect(diff.length, 1);
    });
  });

  group('列表按 id 对齐', () {
    test('工具换顺序不算变化（按 id 对齐）', () {
      final diff = ConfigDiff.diffMaps(
        {
          'tools': [
            {'id': 'x', 'title': 'X'},
            {'id': 'y', 'title': 'Y'},
          ]
        },
        {
          'tools': [
            {'id': 'y', 'title': 'Y'},
            {'id': 'x', 'title': 'X'},
          ]
        },
        '',
      );
      expect(diff, isEmpty);
    });

    test('工具改名 → 一条 changed，路径带 id', () {
      final diff = ConfigDiff.diffMaps(
        {
          'tools': [
            {'id': 'x', 'title': 'X'}
          ]
        },
        {
          'tools': [
            {'id': 'x', 'title': 'X2'}
          ]
        },
        '',
      );
      expect(diff.length, 1);
      expect(diff.first.path, 'tools[x].title');
      expect(diff.first.before, 'X');
      expect(diff.first.after, 'X2');
    });

    test('工具新增 → added', () {
      final diff = ConfigDiff.diffMaps(
        {
          'tools': [
            {'id': 'x', 'title': 'X'}
          ]
        },
        {
          'tools': [
            {'id': 'x', 'title': 'X'},
            {'id': 'z', 'title': 'Z'},
          ]
        },
        '',
      );
      expect(diff.length, 1);
      expect(diff.first.kind, ConfigChangeKind.added);
      expect(diff.first.path, 'tools[z]');
    });

    test('工具下架 → removed', () {
      final diff = ConfigDiff.diffMaps(
        {
          'tools': [
            {'id': 'x', 'title': 'X'},
            {'id': 'z', 'title': 'Z'},
          ]
        },
        {
          'tools': [
            {'id': 'x', 'title': 'X'},
          ]
        },
        '',
      );
      expect(diff.length, 1);
      expect(diff.first.kind, ConfigChangeKind.removed);
      expect(diff.first.path, 'tools[z]');
    });

    test('没有 id 的列表按索引对齐', () {
      final diff = ConfigDiff.diffMaps({
        'list': [1, 2, 3]
      }, {
        'list': [1, 9, 3]
      }, '');
      expect(diff.length, 1);
      expect(diff.first.path, 'list[1]');
    });

    test('列表变长 → 末尾 added', () {
      final diff = ConfigDiff.diffMaps({
        'list': [1]
      }, {
        'list': [1, 2]
      }, '');
      expect(diff.length, 1);
      expect(diff.first.kind, ConfigChangeKind.added);
      expect(diff.first.path, 'list[1]');
    });
  });

  group('值的渲染', () {
    test('null / 空 / 布尔 / 长文本 / 列表', () {
      expect(ConfigChange.formatValue(null), '（无）');
      expect(ConfigChange.formatValue(''), '（空）');
      expect(ConfigChange.formatValue(true), '是');
      expect(ConfigChange.formatValue(false), '否');
      expect(ConfigChange.formatValue(42), '42');
      expect(ConfigChange.formatValue('短'), '短');
      expect(ConfigChange.formatValue('x' * 60).endsWith('…'), isTrue);
      expect(ConfigChange.formatValue([1, 2]), '[1, 2]');
      expect(ConfigChange.formatValue([1, 2, 3, 4]).contains('共 4 项'), isTrue);
      expect(ConfigChange.formatValue({'a': 1}), '{1 项}');
    });

    test('describe 三种类型', () {
      expect(
        const ConfigChange(
                path: 'a.b', kind: ConfigChangeKind.changed, before: 1, after: 2)
            .describe(),
        '修改  a.b：1 → 2',
      );
      expect(
        const ConfigChange(path: 'a.b', kind: ConfigChangeKind.added, after: 2)
            .describe(),
        '新增  a.b：2',
      );
      expect(
        const ConfigChange(path: 'a.b', kind: ConfigChangeKind.removed, before: 1)
            .describe(),
        '删除  a.b：1',
      );
    });
  });

  group('真实配置（模型层）', () {
    test('改一个工具标题能被抓到', () {
      final mutated = jsonDecode(raw) as Map<String, dynamic>;
      final tools = mutated['tools'] as List;
      (tools.first as Map<String, dynamic>)['title'] = '被改了';
      final other = AppConfig.fromJson(mutated);
      final diff = ConfigDiff.between(config, other);
      expect(diff, isNotEmpty);
      expect(diff.any((c) => c.path.startsWith('tools[')), isTrue);
      expect(diff.any((c) => c.after == '被改了'), isTrue);
    });

    test('模型不认识的字段不会出现在差异里（那是 JSON 层的活）', () {
      final mutated = jsonDecode(raw) as Map<String, dynamic>;
      mutated['someBrandNewField'] = 1;
      final other = AppConfig.fromJson(mutated);
      expect(ConfigDiff.between(config, other), isEmpty);
    });
  });
}
