import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kmlab_toolbox/data/update_checker.dart';
import 'package:kmlab_toolbox/model/app_config.dart';
import 'package:kmlab_toolbox/version.dart';

RemoteConfig remoteWith(String? updateUrl) => RemoteConfig(
      enabled: true,
      configUrl: 'https://example.com/app.json',
      updateUrl: updateUrl,
      timeoutMs: 8000,
      refreshOnLaunch: true,
      hotReload: false,
      requireSignature: false,
    );

void main() {
  group('UpdateChecker · 自动更新', () {
    test('远端版本号更大 → 有可用更新', () async {
      final checker = UpdateChecker(client: MockClient((req) async {
        return http.Response(
          jsonEncode({
            'versionCode': kAppBuild + 1,
            'versionName': '9.9.9',
            'url': 'https://example.com/a.apk',
            'size': 12345,
            'note': '测试',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }));

      final info = await checker.check(remoteWith('https://example.com/u.json'));
      expect(info, isNotNull);
      expect(info!.versionCode, kAppBuild + 1);
      expect(info.versionName, '9.9.9');
      expect(info.note, '测试');
      expect(info.sizeText, contains('KB'));
    });

    test('远端版本号 == 或 < 本机 → 没有更新', () async {
      for (final code in [kAppBuild, kAppBuild - 1]) {
        final checker = UpdateChecker(client: MockClient((req) async {
          return http.Response(
            jsonEncode({'versionCode': code, 'url': 'https://example.com/a.apk'}),
            200,
          );
        }));
        expect(await checker.check(remoteWith('https://example.com/u.json')), isNull);
      }
    });

    test('没配 updateUrl → 不检查', () async {
      final checker = UpdateChecker(client: MockClient((_) async => http.Response('{}', 200)));
      expect(await checker.check(remoteWith(null)), isNull);
      expect(await checker.check(remoteWith('')), isNull);
    });

    test('返回 HTML（SPA 兜底）→ 当作没有更新，不崩', () async {
      final checker = UpdateChecker(client: MockClient((_) async {
        return http.Response('<!doctype html><html></html>', 200);
      }));
      expect(await checker.check(remoteWith('https://example.com/u.json')), isNull);
    });

    test('HTTP 500 / 网络异常 → 静默失败', () async {
      final bad = UpdateChecker(client: MockClient((_) async => http.Response('x', 500)));
      expect(await bad.check(remoteWith('https://example.com/u.json')), isNull);

      final boom = UpdateChecker(client: MockClient((_) async => throw Exception('boom')));
      expect(await boom.check(remoteWith('https://example.com/u.json')), isNull);
    });

    test('清单缺 url / versionCode → 当作没有更新', () async {
      for (final body in [
        jsonEncode({'versionCode': kAppBuild + 1}),
        jsonEncode({'url': 'https://example.com/a.apk'}),
      ]) {
        final checker = UpdateChecker(client: MockClient((_) async => http.Response(body, 200)));
        expect(await checker.check(remoteWith('https://example.com/u.json')), isNull);
      }
    });

    test('本机版本号就是安装包里的那个', () {
      expect(UpdateChecker().localVersionCode, kAppBuild);
    });
  });
}
