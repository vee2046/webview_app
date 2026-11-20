/// 「配置即契约」守卫。
///
/// 规则：**配置里出现的每一个字段名，都必须有人在 `app/lib` 里读过。**
///
/// 这条测试是自动化的 —— 它把「配置里声明了、代码里从没用过」这种假开关
/// 变成必然报红的失败，而不是等到用户去改配置才发现没反应。
///
/// 背景：实测揪出 8 个假开关（`javascriptEnabled` / `cacheMode` 等），
/// 对应平台根本没有 API —— 假开关比没有开关更糟，运营会以为改它有用。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kmlab_toolbox/model/app_config.dart';

/// 自由格式子树：内容是「人写的说明 / 映射表」，不是机器消费的字段。
/// 用**路径**判定（不是 key 名），免得和正常字段撞名。
const List<String> _freeFormPaths = [
  'app.brandSource', // 品牌溯源表：site / siteName / brandSub / …
  'tools.[].resume.extract.names', // 游戏代码 → 中文名（A~E）
];

/// 路径是否落在某个自由格式子树里
bool isFreeForm(List<String> path) {
  for (final root in _freeFormPaths) {
    final parts = root.split('.');
    if (path.length < parts.length) continue;
    var match = true;
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] == '[]') {
        if (!path[i].startsWith('[')) {
          match = false;
          break;
        }
      } else if (parts[i] != path[i]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

void main() {
  final raw = File('../config/app.config.json').readAsStringSync();
  final config = AppConfig.parse(raw);
  final decoded = jsonDecode(raw) as Map<String, dynamic>;

  late final String dartSource;
  setUpAll(() {
    final buf = StringBuffer();
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        buf.writeln(entity.readAsStringSync());
      }
    }
    dartSource = buf.toString();
  });

  /// 收集配置里所有「机器消费」的叶子字段名
  List<String> collectMachineFieldNames(Object? node) {
    final out = <String>[];
    void walk(Object? n, List<String> path) {
      if (isFreeForm(path)) return;
      if (n is Map) {
        n.forEach((k, v) => walk(v, [...path, k.toString()]));
      } else if (n is List) {
        if (n.isNotEmpty && n.every((e) => e is String || e is num)) {
          out.add(path.last);
        } else {
          for (final v in n) {
            walk(v, [...path, '[i]']);
          }
        }
      } else if (n != null) {
        out.add(path.last);
      }
    }

    walk(decoded, const []);
    return out;
  }

  test('配置里没有任何孤儿字段', () {
    final names = collectMachineFieldNames(decoded).toSet();
    final orphans = <String>[];
    for (final name in names) {
      if (!dartSource.contains("json['$name']")) {
        orphans.add(name);
      }
    }
    expect(
      orphans,
      isEmpty,
      reason: '以下配置字段在 app/lib 里没有任何读取点：\n'
          '${orphans.join('\n')}\n'
          '要么实现它，要么从配置里删掉 —— 假开关比没有开关更糟。',
    );
  });

  test('8 个假开关确实已删干净', () {
    const removed = [
      'javascriptEnabled',
      'domStorageEnabled',
      'databaseEnabled',
      'allowFileAccess',
      'allowContentAccess',
      'allowUniversalAccessFromFileUrls',
      'mediaPlaybackRequiresUserGesture',
      'cacheMode',
    ];
    final webviewJson = config.webview.toJson();
    for (final name in removed) {
      expect(
        webviewJson.containsKey(name),
        isFalse,
        reason: '$name 应该是假开关，不该存在于模型里',
      );
    }
  });

  test('两个真开关确有读取点', () {
    expect(dartSource.contains("json['handleHardwareBack']"), isTrue);
    expect(dartSource.contains("json['errorRetryInWebview']"), isTrue);
    expect(config.webview.handleHardwareBack, isTrue);
    expect(config.webview.errorRetryInWebview, isTrue);
  });

  test('品牌溯源 7 项齐全', () {
    final entries = config.app.brandSource.entries;
    for (final key in const [
      'site',
      'siteName',
      'brandSub',
      'pageTitle',
      'icon',
      'doodles',
      'categories',
    ]) {
      expect(entries.containsKey(key), isTrue, reason: '缺 $key');
    }
  });

  test('App 正式名是纯英文（防中英混排回归）', () {
    expect(config.app.appName, 'kmlab Toolbox');
    expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(config.app.appName), isFalse);
  });
}
