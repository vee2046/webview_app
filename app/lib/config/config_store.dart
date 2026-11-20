/// 配置状态容器 —— 持有当前生效的 `AppConfig`，负责三层来源的编排与原子替换。
///
/// 流程（DESIGN.md §5「冷启动时序」）：
///   1. 读内置快照 → 立刻出首屏
///   2. 后台拉远端 → 校验 → 原子替换 → 有差异才通知 UI
///   3. 远端失败 → 沿用 last-good → 再沿用内置快照
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/app_config.dart';
import 'config_loader.dart';

class ConfigStore extends ChangeNotifier {
  ConfigStore({ConfigLoader? loader}) : _loader = loader ?? ConfigLoader();

  static const String _lastGoodKey = 'km.config.lastGood';
  static const String _lastRemoteKey = 'km.config.lastRemoteAt';

  final ConfigLoader _loader;

  AppConfig? _config;
  bool _loading = true;
  bool _refreshing = false;
  String? _lastError;
  DateTime? _lastRemoteAt;

  AppConfig? get config => _config;
  bool get loading => _loading;
  bool get refreshing => _refreshing;
  String? get lastError => _lastError;
  DateTime? get lastRemoteAt => _lastRemoteAt;

  /// 首屏用：拿不到就是 null，UI 走骨架屏
  AppConfig? get current => _config;

  Future<void> bootstrap() async {
    _loading = true;
    notifyListeners();

    // ── 第 1 层：内置快照 ──
    final bundled = await _loader.loadBundled();
    if (bundled != null) {
      _config = bundled;
      _loading = false;
      notifyListeners();
    }

    // ── 第 3 层：上次可用配置（远端失败时兜底）──
    if (_config == null) {
      final lastGood = await _readLastGood();
      if (lastGood != null) {
        _config = lastGood;
        _loading = false;
        notifyListeners();
      }
    }

    // ── 第 2 层：远端 ──
    final remoteCfg = _config?.remote ?? RemoteConfig.fallback;
    if (remoteCfg.enabled && remoteCfg.refreshOnLaunch) {
      await refresh();
    }

    _loading = _config == null;
    notifyListeners();
  }

  /// 手动/后台刷新远端配置。成功则原子替换 + 持久化 last-good。
  Future<bool> refresh() async {
    final remoteCfg = _config?.remote ?? RemoteConfig.fallback;
    if (!remoteCfg.enabled || remoteCfg.configUrl.isEmpty) {
      _lastError = '未配置远端地址';
      notifyListeners();
      return false;
    }

    _refreshing = true;
    _lastError = null;
    notifyListeners();

    final incoming = await _loader.loadRemote(remoteCfg);

    _refreshing = false;
    if (incoming == null) {
      _lastError = '远端配置不可用，继续使用本地配置';
      notifyListeners();
      return false;
    }

    // 新鲜度保护：远端配置不能比当前生效的配置旧
    final stale = staleReason(incoming, _config);
    if (stale != null) {
      debugPrint('[ConfigStore] $stale');
      _lastError = stale;
      notifyListeners();
      return false;
    }

    // 原子替换：要么整体生效，要么整体不生效
    final changed = !_sameConfig(_config, incoming);
    _config = incoming;
    _lastRemoteAt = DateTime.now();

    await _writeLastGood(incoming);
    await _writeLastRemoteAt(_lastRemoteAt!);

    notifyListeners();
    return changed;
  }

  /// 远端配置比当前生效的配置旧？返回原因字符串，null 表示没问题。
  ///
  /// 场景（真实踩过）：App 发版内置了新配置，但线上 `data/app.json` 还没更新
  /// → 旧配置把新配置覆盖掉 → App 里的修复被悄悄回滚。
  ///
  /// 规则：远端配置的 `generatedAt` 必须 **>=** 当前配置的；
  /// 远端缺 `generatedAt`（手改 / 老版本）→ 也拒绝，沿用本地。
  static String? staleReason(AppConfig incoming, AppConfig? current) {
    if (current == null) return null;
    final currentAt = current.generatedAt;
    if (currentAt == null) return null; // 当前配置没有时间戳 → 无法判断，放行

    final incomingAt = incoming.generatedAt;
    if (incomingAt == null) {
      return '远端配置缺少 generatedAt（可能是旧版本或手工改动），已沿用本地配置';
    }
    if (incomingAt.isBefore(currentAt)) {
      return '远端配置比本地配置旧（$incomingAt < $currentAt），已沿用本地配置';
    }
    return null;
  }

  Future<AppConfig?> _readLastGood() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastGoodKey);
      if (raw == null || raw.isEmpty) return null;
      return _loader.parseAndValidate(raw);
    } catch (e) {
      debugPrint('[ConfigStore] 读取 last-good 失败: $e');
      return null;
    }
  }

  Future<void> _writeLastGood(AppConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastGoodKey, encodeConfig(config));
    } catch (e) {
      debugPrint('[ConfigStore] 写入 last-good 失败: $e');
    }
  }

  Future<void> _writeLastRemoteAt(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRemoteKey, at.millisecondsSinceEpoch.toString());
    } catch (e) {
      debugPrint('[ConfigStore] 写入刷新时间失败: $e');
    }
  }

  /// 粗略比较：只比会影响到界面的部分，避免无意义重建
  bool _sameConfig(AppConfig? a, AppConfig? b) {
    if (a == null || b == null) return a != b;
    if (a.schemaVersion != b.schemaVersion) return false;
    if (a.tools.length != b.tools.length) return false;
    if (a.app.tabs.length != b.app.tabs.length) return false;
    for (var i = 0; i < a.tools.length; i++) {
      final x = a.tools[i];
      final y = b.tools[i];
      if (x.id != y.id ||
          x.title != y.title ||
          x.icon != y.icon ||
          x.color != y.color ||
          x.tab != y.tab ||
          x.enabled != y.enabled ||
          x.sort != y.sort ||
          x.url != y.url ||
          x.open.chrome != y.open.chrome) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }
}
