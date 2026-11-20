/// 配置加载器 —— 实现 DESIGN.md §4.1「三层来源」与 §4.4「校验规则」。
///
/// 铁律：
///   1. 首屏永远有内容（内置快照同步读出）
///   2. 远端配置要么整体生效，要么整体不生效（原子替换）
///   3. 任何一步失败都静默降级，用户无感
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../model/app_config.dart';
import 'config_signature.dart';

class ConfigLoadReport {
  const ConfigLoadReport({
    required this.source,
    required this.ok,
    this.warning,
  });

  /// `bundle` / `lastGood` / `remote`
  final String source;
  final bool ok;
  final String? warning;
}

/// 纯逻辑的加载器（不持有状态，便于单测）
class ConfigLoader {
  ConfigLoader({
    http.Client? httpClient,
    this.bundlePath = 'assets/app.config.json',
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String bundlePath;

  /// 当前 App 支持的配置格式版本。远端 schemaVersion 高于此值 → 拒绝。
  static const int supportedSchemaVersion = 1;

  /// 从包内读取内置快照。
  Future<AppConfig?> loadBundled() async {
    try {
      final raw = await rootBundle.loadString(bundlePath);
      return AppConfig.parse(raw);
    } catch (e) {
      debugPrint('[ConfigLoader] 内置快照读取失败: $e');
      return null;
    }
  }

  /// 拉取远端配置。超时 / 解析失败 / schema 不兼容 / tools 为空 → 全部返回 null。
  Future<AppConfig?> loadRemote(RemoteConfig remote) async {
    if (!remote.enabled || remote.configUrl.isEmpty) return null;

    try {
      final res = await _http
          .get(Uri.parse(remote.configUrl))
          .timeout(Duration(milliseconds: remote.timeoutMs));
      if (res.statusCode != 200) {
        debugPrint('[ConfigLoader] 远端配置 HTTP ${res.statusCode}');
        return null;
      }
      // ⚠️ 静态托管的 SPA 对任何不存在的路径都返回 200 + index.html，
      // 所以「200」不等于「拿到了配置」。必须再验一次内容形态。
      if (!looksLikeJson(res.body)) {
        debugPrint('[ConfigLoader] 远端返回的不是 JSON（多半是 SPA 的 index.html 兜底），'
            '静默沿用内置快照');
        return null;
      }
      // ⚠️ `requireSignature` 取自**本地**配置（`remote` 来自当前生效的配置），
      // 不能取自远端自己 —— 否则远端把开关关掉就等于免检了。
      return parseAndValidate(res.body,
          requireSignature: remote.requireSignature);
    } catch (e) {
      debugPrint('[ConfigLoader] 远端配置拉取失败: $e');
      return null;
    }
  }

  /// 解析 + 校验。返回 null 表示「这份配置不生效」。
  ///
  /// 拒绝规则见 DESIGN.md §4.4：
  ///   * schemaVersion 高于当前支持版本
  ///   * JSON 解析失败
  ///   * tools 为空数组（防止误清空首页）
  ///   * 签名不匹配（开启校验时）
  AppConfig? parseAndValidate(String raw, {bool requireSignature = false}) {
    AppConfig config;
    Map<String, dynamic> rawMap;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('[ConfigLoader] 配置根节点不是对象');
        return null;
      }
      rawMap = decoded;
      config = AppConfig.fromJson(rawMap);
    } catch (e) {
      debugPrint('[ConfigLoader] 配置解析失败: $e');
      return null;
    }

    if (config.schemaVersion > supportedSchemaVersion) {
      debugPrint('[ConfigLoader] schemaVersion ${config.schemaVersion} '
          '高于当前支持的 $supportedSchemaVersion，拒绝');
      return null;
    }

    if (config.tools.isEmpty) {
      debugPrint('[ConfigLoader] tools 为空，拒绝（防止误清空首页）');
      return null;
    }

    if (requireSignature) {
      // 签名校验（DESIGN.md §4.4）：远端配置的 HMAC-SHA256 对不上 → 拒绝。
      //
      // ⚠️ 校验的是**原始 JSON**（不是模型）—— 模型会丢掉没读过的字段，
      //    用模型算出来的签名与签发时算的必然不一致。
      if (!ConfigSignature.verify(rawMap)) {
        debugPrint('[ConfigLoader] 远端配置签名校验不通过，已拒绝并沿用本地配置');
        return null;
      }
      debugPrint('[ConfigLoader] 远端配置签名校验通过');
    }

    // id 去重：后者覆盖前者（并保留一个可告警的信号）
    final seen = <String>{};
    for (final tool in config.tools) {
      if (!seen.add(tool.id)) {
        debugPrint('[ConfigLoader] 工具 id 重复: ${tool.id}');
      }
    }

    return config;
  }

  void dispose() => _http.close();
}

/// 序列化工具，供持久化 last-good 用
String encodeConfig(AppConfig config) => jsonEncode(config.toJson());

/// 判断响应体是否「长得像 JSON 配置」。
///
/// 背景：`kmlab.tech` 是静态托管的 Vue SPA，访问任何不存在的路径都会
/// **返回 HTTP 200 + index.html**（前端路由兜底）。如果只看状态码，
/// 远端配置就永远不会失败，也永远不会生效 —— 但日志会刷一片解析错误。
/// 这里做一次内容嗅探：首字符必须是 `{`（我们的配置是对象）才继续。
bool looksLikeJson(String body) {
  final trimmed = body.trimLeft();
  return trimmed.startsWith('{');
}
