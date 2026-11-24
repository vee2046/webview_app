import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kmlab_toolbox/version.dart';

void main() {
  test('version.dart 与 pubspec.yaml 的版本号一致', () {
    // 版本号有两个真相源会出事：pubspec（打进了安装包）和 version.dart（App 里显示的）。
    // 脚本每次出包前两个一起更新，但要是哪天漏了，用户看到的版本就骗人了。
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', multiLine: true)
        .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml 里找不到 version: x.y.z+N');

    expect(kAppVersion, m!.group(1));
    expect(kAppBuild, int.parse(m.group(2)!));
    expect(kAppVersionLabel, '${m.group(1)} (${m.group(2)})');
  });

  test('版本号格式合法（三个数字段 + 一个构建号）', () {
    expect(kAppVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(kAppBuild, greaterThan(0));
  });
}
