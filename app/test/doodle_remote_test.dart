import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kmlab_toolbox/icons/doodle_icons.dart';
import 'package:kmlab_toolbox/model/app_config.dart';

void main() {
  final raw = File('../config/app.config.json').readAsStringSync();
  final config = AppConfig.parse(raw);

  group('doodle 图标外置（数据分离）', () {
    test('配置里每个图标名都有对应的 SVG 路径', () {
      for (final name in config.app.icons.names) {
        expect(
          config.app.icons.paths.containsKey(name),
          isTrue,
          reason: '图标「$name」没有 paths 里的 SVG 片段 —— '
              '站点新增图标时 App 会显示不出来',
        );
        expect(config.app.icons.paths[name]!.trim(), isNotEmpty);
        expect(config.app.icons.paths[name], contains('<'));
      }
    });

    test('paths 是纯数据（配置里能改，App 不用重新打包）', () {
      // 模拟「站点新增一种 doodle」：往 paths 里塞一条，看 App 能不能画出来。
      const fake = 'podcast-remote';
      DoodleIcons.install({
        ...config.app.icons.paths,
        fake: '<circle cx="32" cy="32" r="20"/>',
      });

      final svg = doodleSvg(fake, color: const Color(0xFF2F2A24));
      expect(svg, contains('<circle cx="32" cy="32" r="20"/>'),
          reason: '远端新增的图标应该直接被画出来');
      expect(svg, contains('viewBox="0 0 64 64"'),
          reason: '外层 SVG 的 viewBox 还得是 64×64（doodle 的坐标系）');
    });

    test('远端没有这个图标时回退到内置表', () {
      DoodleIcons.install(const {});
      final svg = doodleSvg('note', color: const Color(0xFF2F2A24));
      expect(svg, isNotEmpty);
      expect(svg, contains('<svg'));
    });

    test('远端和内置的 doodle 数量对得上（漏了会静默 fallback）', () {
      expect(config.app.icons.paths.length,
          greaterThanOrEqualTo(config.app.icons.names.length));
    });
  });
}
