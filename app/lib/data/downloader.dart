import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 下载结果。
class DownloadResult {
  const DownloadResult({
    required this.fileName,
    this.filePath,
    this.bytes = 0,
    this.error,
  });

  /// 建议的文件名（已去掉路径分隔符）。
  final String fileName;

  /// 落盘后的绝对路径；失败时为 null。
  final String? filePath;

  /// 文件字节数。
  final int bytes;

  /// 失败原因；成功时为 null。
  final String? error;

  bool get ok => filePath != null && error == null;
}

/// 把 WebView 里点开的「下载」真的存成文件。
///
/// 三种来源：
/// - 普通 http(s) URL —— 直接下载（Dart 侧发起，绕开 WebView 的二进制导航）
/// - `data:` URL —— 页面内联资源（base64）
/// - `blob:` URL —— 只能由页面自己读（见 `KmBridge.blobToDataUrlScript`），
///   Dart 侧拿不到 blob 的字节，所以先让页面转成 data URL 再解码
class AppDownloader {
  const AppDownloader._();

  /// 从 http(s) 地址下载。
  static Future<DownloadResult> downloadFromUrl(
    String url, {
    String? suggestedName,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return const DownloadResult(fileName: '', error: '下载地址不对');
    }
    try {
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        return DownloadResult(
          fileName: suggestedName ?? _nameFromUri(uri),
          error: '下载失败（HTTP ${response.statusCode}）',
        );
      }
      final name = suggestedName ?? _nameFromUri(uri, fallbackExt: 'bin');
      final saved = await _save(name, response.bodyBytes);
      return DownloadResult(fileName: name, filePath: saved, bytes: response.bodyBytes.length);
    } catch (e) {
      return DownloadResult(
        fileName: suggestedName ?? 'download',
        error: '下载失败（$e）',
      );
    }
  }

  /// 从 `data:` URL 下载（base64 内联资源）。
  static Future<DownloadResult> downloadFromDataUrl(
    String dataUrl, {
    String? suggestedName,
  }) async {
    final parsed = parseDataUrl(dataUrl);
    if (parsed == null) {
      return const DownloadResult(fileName: '', error: '这个文件读不出来');
    }
    final name = suggestedName ?? parsed.name;
    try {
      final saved = await _save(name, parsed.bytes);
      return DownloadResult(fileName: name, filePath: saved, bytes: parsed.bytes.length);
    } catch (e) {
      return DownloadResult(fileName: name, error: '保存失败（$e）');
    }
  }

  /// 解析 `data:` URL，返回字节与建议文件名。
  static DataUrlPayload? parseDataUrl(String dataUrl) {
    if (!dataUrl.startsWith('data:')) return null;
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    final meta = dataUrl.substring(5, comma);
    final body = dataUrl.substring(comma + 1);
    final isBase64 = meta.endsWith(';base64');
    final mime = isBase64 ? meta.substring(0, meta.length - 7) : meta;
    final bytes = isBase64
        ? (() {
            try {
              return base64Decode(body);
            } catch (_) {
              return <int>[];
            }
          })()
        : utf8.encode(Uri.decodeComponent(body));
    if (bytes.isEmpty) return null;
    final name = _fileNameFromMime(mime);
    return DataUrlPayload(bytes: bytes, mime: mime, name: name);
  }

  /// 把字节写到临时目录。
  static Future<String> _save(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final safe = sanitizeFileName(name);
    final file = File('${dir.path}/$safe');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 去掉路径分隔符与危险字符。
  ///
  /// ⚠️ 不能直接用 `[^\w.\- ]` —— Dart 的 `\w` 只认 ASCII 词字符，
  /// 中文会被整片替换成 `_`（「报告.txt」→「报告_.txt」就没了）。
  /// 所以改成按 code point 判断：非 ASCII（>= 0x80）一律保留。
  static String sanitizeFileName(String raw) {
    final base = raw.split('/').last.split('\\').last.trim();
    final buf = StringBuffer();
    for (final rune in base.runes) {
      final ch = String.fromCharCode(rune);
      if (rune > 0x7f || _safeFileChars.hasMatch(ch)) {
        buf.write(ch);
      } else {
        buf.write('_');
      }
    }
    final trimmed = buf.toString().trim();
    if (trimmed.isEmpty) return 'download';
    final chars = trimmed.runes.toList();
    if (chars.length > 96) {
      return String.fromCharCodes(chars.sublist(chars.length - 96));
    }
    return trimmed;
  }

  /// 文件名里允许的 ASCII 字符。
  static final RegExp _safeFileChars = RegExp(r'^[A-Za-z0-9._\- ]$');

  /// 从 URL 猜文件名。
  static String _nameFromUri(Uri uri, {String fallbackExt = 'bin'}) {
    final seg = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (seg.isEmpty) {
      final host = uri.host.replaceAll(RegExp(r'[^\w.\-]'), '_');
      return '$host.$fallbackExt';
    }
    return sanitizeFileName(seg);
  }

  /// 按 MIME 猜扩展名。
  static String _fileNameFromMime(String mime) {
    const map = <String, String>{
      'text/plain': 'download.txt',
      'text/html': 'download.html',
      'text/csv': 'download.csv',
      'application/json': 'download.json',
      'application/pdf': 'download.pdf',
      'application/zip': 'download.zip',
      'image/png': 'download.png',
      'image/jpeg': 'download.jpg',
      'image/gif': 'download.gif',
      'image/svg+xml': 'download.svg',
      'video/mp4': 'download.mp4',
      'audio/mpeg': 'download.mp3',
    };
    return map[mime.toLowerCase()] ?? 'download.bin';
  }
}

/// `data:` URL 解析结果。
class DataUrlPayload {
  const DataUrlPayload({
    required this.bytes,
    required this.mime,
    required this.name,
  });

  final List<int> bytes;
  final String mime;
  final String name;
}
