/// 脑力慢养「上一局」摘要 —— `ExtractKind.lastGame`。
///
/// 真实结构（实测自线上 bundle）：
///   `bf_progress` = `{"gameId":"B","level":2,"qIndex":0,"score":82,"startedAt":...}`
///
/// 三个要点：
///  1. 游戏代码 → 中文名的映射在**配置**里，App 不硬编码
///  2. 有的游戏没有 `score` 只有 `moves` ⇒ 两级降级
///  3. localStorage 的值是**字符串**，要先解一层 JSON
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kmlab_toolbox/data/resume_reader.dart';
import 'package:kmlab_toolbox/model/app_config.dart';

AppConfig loadConfig() {
  final raw = File('../config/app.config.json').readAsStringSync();
  return AppConfig.parse(raw);
}

void main() {
  final config = loadConfig();
  final reader = ResumeReader();
  final tool = config.toolById('mindx')!;

  group('配置', () {
    test('脑力慢养改用 storage 模式', () {
      expect(tool.resume.mode, ResumeMode.storage);
    });

    test('extract 是 lastGame 且指向 bf_progress', () {
      expect(tool.resume.extract.kind, ExtractKind.lastGame);
      expect(tool.resume.extract.key, 'bf_progress');
    });

    test('游戏名映射放在配置里（5 个游戏）', () {
      final names = tool.resume.extract.names!;
      expect(names.length, 5);
      expect(names['A'], '找一找');
      expect(names['B'], '数口令');
      expect(names['C'], '配一对');
      expect(names['D'], '赶集');
      expect(names['E'], '数字找家');
    });
  });

  group('摘要', () {
    test('有分数 → 走主模板', () {
      final snapshot = {
        'bf_progress': jsonEncode({
          'gameId': 'B',
          'level': 2,
          'score': 82,
          'startedAt': 1795141226115,
        }),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.available, isTrue);
      expect(summary.text, contains('数口令'));
      expect(summary.text, contains('82'));
    });

    test('副标题优先显示关卡', () {
      final snapshot = {
        'bf_progress': jsonEncode({'gameId': 'B', 'level': 2, 'score': 82}),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.detail, contains('第 2 关'));
    });

    test('没有分数但有步数 → 走步数模板', () {
      final snapshot = {
        'bf_progress': jsonEncode({'gameId': 'C', 'level': 1, 'moves': 12}),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.available, isTrue);
      expect(summary.text, contains('配一对'));
      expect(summary.text, contains('12'));
      expect(summary.text, contains('步'));
    });

    test('既没分数也没步数 → 走 fallback 模板', () {
      final snapshot = {
        'bf_progress': jsonEncode({'gameId': 'D'}),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.available, isTrue);
      expect(summary.text, contains('赶集'));
    });

    test('未知游戏代码不崩', () {
      final snapshot = {
        'bf_progress': jsonEncode({'gameId': 'Z', 'level': 1, 'score': 5}),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.available, isTrue);
      expect(summary.text, contains('Z'));
    });

    test('字符串分数也能认', () {
      final snapshot = {
        'bf_progress': jsonEncode({'gameId': 'A', 'level': 3, 'score': '42'}),
      };
      final summary = reader.summarize(tool, snapshot);
      expect(summary.text, contains('42'));
    });

    test('没有 bf_progress → 不可用', () {
      final summary = reader.summarize(tool, const {'bf_flags': '{}'});
      expect(summary.available, isFalse);
    });

    test('空快照 → 不可用', () {
      final summary = reader.summarize(tool, const {});
      expect(summary.available, isFalse);
    });

    test('坏 JSON → 不崩', () {
      final summary = reader.summarize(tool, const {'bf_progress': '{not json'});
      expect(summary.available, isFalse);
    });

    test('没有 gameId → 不可用', () {
      final summary = reader.summarize(tool, const {'bf_progress': '{"level":1}'});
      expect(summary.available, isFalse);
    });
  });

  group('模型往返', () {
    test('ExtractConfig toJson / fromJson 保住新字段', () {
      final extract = tool.resume.extract;
      final json = extract.toJson();
      final back = ExtractConfig.fromJson(json);
      expect(back.kind, ExtractKind.lastGame);
      expect(back.gameField, extract.gameField);
      expect(back.scoreField, extract.scoreField);
      expect(back.movesField, extract.movesField);
      expect(back.levelField, extract.levelField);
      expect(back.names, extract.names);
      expect(back.templateMoves, extract.templateMoves);
      expect(back.templateFallback, extract.templateFallback);
    });

    test('extractKindFrom 认 lastGame', () {
      expect(extractKindFrom('lastGame'), ExtractKind.lastGame);
      expect(extractKindFrom('countDateMap'), ExtractKind.countDateMap);
      expect(extractKindFrom('unknown'), ExtractKind.none);
    });
  });
}
