/// 自动更新 —— 检查远端清单，比版本号。
///
/// 清单长这样（`scripts/publish-update.sh` 生成）：
/// ```json
/// {
///   "versionCode": 9,
///   "versionName": "0.1.8",
///   "url": "https://kmlab.tech/download/kmlab-toolbox.apk",
///   "size": 55653964,
///   "note": "分类同步 + 修复若干问题",
///   "publishedAt": "2026-11-24T05:24:45Z"
/// }
/// ```
///
/// **本地版本号从 `version.dart` 来**（出包脚本自动生成，跟 pubspec 一致），
/// 所以「远端 versionCode > 本地 kAppBuild」就是有新版。
///
/// ⚠️ APK 本体**不由 App 托管** —— 清单里的 `url` 指向哪里由发布方决定
///    （站点静态目录 / 对象存储 / 网盘直链都行）。App 只负责「查 → 提示 → 装」。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../model/app_config.dart';
import '../version.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
    this.size = 0,
    this.note = '',
    this.publishedAt,
  });

  final int versionCode;
  final String versionName;
  final String url;
  final int size;
  final String note;
  final DateTime? publishedAt;

  /// 本机是不是比这个旧。
  bool get isNewerThanLocal => versionCode > kAppBuild;

  /// 人类可读的大小，如 `53.1 MB`。
  String get sizeText {
    if (size <= 0) return '';
    final mb = size / 1024 / 1024;
    return mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${(size / 1024).round()} KB';
  }

  static UpdateInfo? fromJson(Map<String, dynamic> json) {
    final code = json['versionCode'];
    final url = json['url'];
    if (code is! int || url is! String || url.isEmpty) return null;
    return UpdateInfo(
      versionCode: code,
      versionName: (json['versionName'] as String?) ?? '未知版本',
      url: url,
      size: (json['size'] as num?)?.toInt() ?? 0,
      note: (json['note'] as String?) ?? '',
      publishedAt: DateTime.tryParse((json['publishedAt'] as String?) ?? ''),
    );
  }
}

class UpdateChecker {
  UpdateChecker({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 本机当前版本号（跟安装包里的一致）。
  int get localVersionCode => kAppBuild;

  /// 拉清单。返回 null 表示「没有可用更新」或「拉取失败」。
  ///
  /// ⚠️ 拉不到**不是错误** —— 离线、地址没配、404 都归到这里，
  ///    静默失败即可，不该打扰用户。
  Future<UpdateInfo?> check(RemoteConfig remote) async {
    final url = remote.updateUrl;
    debugPrint('[UpdateChecker] 检查更新：$url');
    if (url == null || url.isEmpty) return null;
    try {
      final res = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = res.body.trimLeft();
      if (!body.startsWith('{')) return null; // SPA 兜底返回 HTML
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final info = UpdateInfo.fromJson(decoded);
      if (info == null || !info.isNewerThanLocal) {
        debugPrint('[UpdateChecker] 没有可用更新（远端 $decoded）');
        return null;
      }
      debugPrint('[UpdateChecker] 发现新版本 ${info.versionName} (${info.versionCode})');
      return info;
    } catch (e) {
      debugPrint('[UpdateChecker] 检查失败：$e');
      return null;
    }
  }

  void dispose() => _client.close();
}

/// 自动更新的状态（ChangeNotifier）—— 让「我的」页能显示「可更新」。
class UpdateStore extends ChangeNotifier {
  UpdateStore(this._checker);

  final UpdateChecker _checker;

  /// 发现的新版本；null = 没有可用更新。
  UpdateInfo? available;

  /// 正在检查 / 正在下载。
  bool busy = false;

  /// 上次检查时间。
  DateTime? lastCheckedAt;

  /// 上次「提示」时间 —— 避免每次启动都弹同样的提示。
  DateTime? lastPromptAt;

  bool get hasUpdate => available != null;

  /// 检查有没有新版。
  ///
  /// [silent] = true 时不打扰用户（只在「我的」页那行显示）。
  Future<void> check(RemoteConfig remote, {bool silent = true}) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      available = await _checker.check(remote);
      lastCheckedAt = DateTime.now();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 用户点了「稍后」→ 记一次，避免反复提示。
  void dismiss() {
    lastPromptAt = DateTime.now();
    available = null;
    notifyListeners();
  }
}
