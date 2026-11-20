/// 下载相关工具 —— data URL 解析 + 文件名消毒。
///
/// 文件名消毒有坑（BUG #21）：Dart 的 `\w` 只认 ASCII，
/// 用正则会把中文全换成 `_`。这里逐个盯住。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kmlab_toolbox/data/downloader.dart';

void main() {
  group('parseDataUrl', () {
    test('base64 内容能解出字节', () {
      final payload = AppDownloader.parseDataUrl(
        'data:text/plain;base64,${base64.encode(utf8.encode('hello'))}',
      );
      expect(payload, isNotNull);
      expect(utf8.decode(payload!.bytes), 'hello');
      expect(payload.mime, 'text/plain');
    });

    test('百分号编码也能解', () {
      final payload = AppDownloader.parseDataUrl('data:text/plain,hello%20world');
      expect(payload, isNotNull);
      expect(utf8.decode(payload!.bytes), 'hello world');
    });

    test('MIME 能推出文件名', () {
      final payload = AppDownloader.parseDataUrl(
        'data:application/pdf;base64,${base64.encode([1, 2, 3])}',
      );
      expect(payload!.name, endsWith('.pdf'));
    });

    test('不是 data URL → null', () {
      expect(AppDownloader.parseDataUrl('https://example.com/a.pdf'), isNull);
    });

    test('缺逗号 → null', () {
      expect(AppDownloader.parseDataUrl('data:text/plain;base64'), isNull);
    });

    test('空 body → null', () {
      expect(AppDownloader.parseDataUrl('data:text/plain;base64,'), isNull);
    });

    test('坏 base64 → null', () {
      expect(AppDownloader.parseDataUrl('data:text/plain;base64,!!!!'), isNull);
    });
  });

  group('sanitizeFileName', () {
    test('路径分隔符被剥掉', () {
      expect(AppDownloader.sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(AppDownloader.sanitizeFileName('a/b/c.txt'), 'c.txt');
    });

    test('危险字符换成下划线', () {
      final out = AppDownloader.sanitizeFileName('re;port<>?.pdf');
      expect(out, 're_port___.pdf');
      expect(out, isNot(contains(';')));
      expect(out, isNot(contains('<')));
    });

    test('中文名保留（BUG #21 回归守卫）', () {
      expect(AppDownloader.sanitizeFileName('月度报告.txt'), '月度报告.txt');
    });

    test('中英混排也保留中文', () {
      expect(AppDownloader.sanitizeFileName('报表 2026 Q1.pdf'), '报表 2026 Q1.pdf');
    });

    test('空名有兜底', () {
      final out = AppDownloader.sanitizeFileName('   ');
      expect(out.isNotEmpty, isTrue);
    });

    test('超长名被截断', () {
      final out = AppDownloader.sanitizeFileName('${'a' * 500}.txt');
      expect(out.length, lessThan(120));
    });
  });

  group('DownloadResult', () {
    test('有路径无错误 → ok', () {
      const r = DownloadResult(fileName: 'a.txt', filePath: '/tmp/a.txt', bytes: 3);
      expect(r.ok, isTrue);
    });

    test('有错误 → 不 ok', () {
      const r = DownloadResult(fileName: 'a.txt', bytes: 0, error: 'boom');
      expect(r.ok, isFalse);
    });

    test('没有路径 → 不 ok', () {
      const r = DownloadResult(fileName: 'a.txt', bytes: 0);
      expect(r.ok, isFalse);
    });
  });
}
