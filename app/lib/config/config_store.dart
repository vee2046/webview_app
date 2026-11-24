/// 配置状态容器 —— 持有当前生效的 `AppConfig`，负责三层来源的编排与原子替换。
///
/// 流程（DESIGN.md §5「冷启动时序」）：
///   1. 读内置快照 → 立刻出首屏
///   2. 后台拉远端 → 校验 → 原子替换 → 有差异才通知 UI
///   3. 远端失败 → 沿用 last-good → 再沿用内置快照
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/device_bucket.dart';
import '../model/app_config.dart';
import 'config_diff.dart';
import 'config_loader.dart';

class ConfigStore extends ChangeNotifier {
  ConfigStore({ConfigLoader? loader}) : _loader = loader ?? ConfigLoader();

  static const String _lastGoodKey = 'km.config.lastGood';
  static const String _lastRemoteKey = 'km.config.lastRemoteAt';
  static const String _sigOverrideKey = 'km.config.requireSignature';

  final ConfigLoader _loader;

  AppConfig? _config;
  bool _loading = true;
  bool _refreshing = false;
  String? _lastError;
  DateTime? _lastRemoteAt;
  List<ConfigChange> _lastDiff = const [];
  int _deviceBucket = 0;
  String _channel = 'stable';
  bool _localRequireSignature = false;

  AppConfig? get config => _config;
  bool get loading => _loading;
  bool get refreshing => _refreshing;
  String? get lastError => _lastError;
  DateTime? get lastRemoteAt => _lastRemoteAt;

  /// 本机分桶号（0~99），灰度用。
  int get deviceBucket => _deviceBucket;

  /// 当前走的是哪条通道：`stable`（稳定版）/ `canary`（灰度版）。
  String get channel => _channel;

  /// 最近一次远端配置更新带来的差异清单（空 = 没有变更）。
  ///
  /// 让热更「可审」：运营改了什么，用户在「我的 → 配置」里看得见（§4.4）。
  List<ConfigChange> get lastDiff => _lastDiff;

  /// 有没有待查看的变更。
  bool get hasDiff => _lastDiff.isNotEmpty;

  /// 清掉差异清单（用户看过了就不再提示）。
  void clearDiff() {
    if (_lastDiff.isEmpty) return;
    _lastDiff = const [];
    notifyListeners();
  }

  /// 远端配置是否**强制**要求签名（来自配置本身，运营说了算）。
  bool get signatureRequiredByConfig => _config?.remote.requireSignature ?? false;

  /// 本机是否额外要求签名（用户手动加严）。
  bool get localRequireSignature => _localRequireSignature;

  /// 实际生效的签名要求。
  ///
  /// ⚠️ 只能**加严**不能放松：配置里写着「必须签名」时，本机开关不能把它关掉 ——
  ///    否则「关掉校验」就成了绕过校验的后门。
  bool get requireSignature =>
      signatureRequiredByConfig || _localRequireSignature;

  /// 本机加严开关。返回 false 表示「配置已强制，不能关闭」。
  Future<bool> setLocalRequireSignature(bool value) async {
    if (!value && signatureRequiredByConfig) return false;
    if (value == _localRequireSignature) return true;
    _localRequireSignature = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sigOverrideKey, value);
    } catch (e) {
      debugPrint('[ConfigStore] 写入签名开关失败: $e');
    }
    notifyListeners();
    return true;
  }

  /// 首屏用：拿不到就是 null，UI 走骨架屏
  AppConfig? get current => _config;

  Future<void> bootstrap() async {
    _loading = true;
    notifyListeners();

    // 本机「加严签名」开关（跨启动保留）
    try {
      final prefs = await SharedPreferences.getInstance();
      _localRequireSignature = prefs.getBool(_sigOverrideKey) ?? false;
    } catch (e) {
      debugPrint('[ConfigStore] 读取签名开关失败: $e');
    }

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

    // 灰度分流：本机落在灰度组就拉灰度版地址，否则拉稳定版。
    //
    // ⚠️ `rolloutPercent` 取自**当前生效（稳定版）配置** —— 决定「我拉哪个地址」
    // 的必须是稳定版，否则不在灰度组的设备永远看不到灰度配置，也就永远升不到 100%。
    _deviceBucket = await DeviceBucket.bucket();
    final useCanary = remoteCfg.hasCanary &&
        DeviceBucket.isInCanary(_deviceBucket, remoteCfg.rolloutPercent);
    _channel = useCanary ? 'canary' : 'stable';
    final effectiveUrl = useCanary ? remoteCfg.canaryUrl : remoteCfg.configUrl;
    debugPrint('[ConfigStore] 分桶 $_deviceBucket/100 · 走 $_channel 通道 · $effectiveUrl');

    final incoming = await _loader.loadRemote(
      remoteCfg.copyWith(
        requireSignature: requireSignature,
        configUrl: effectiveUrl,
      ),
    );

    _refreshing = false;
    if (incoming == null) {
      _lastError = '远端配置不可用，已沿用本地';
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
    final previous = _config;
    final changed = !_sameConfig(_config, incoming);
    _config = incoming;
    _lastRemoteAt = DateTime.now();

    // 算差异：即使「界面可见部分没变」（changed == false），
    // 也不代表 JSON 完全一样 —— 那就只留界面级的变化，别刷屏。
    if (previous != null) {
      final diff = ConfigDiff.between(previous, incoming);
      _lastDiff = diff;
      if (diff.isNotEmpty) {
        debugPrint('[ConfigStore] 远端配置有变化：${ConfigDiff.summarize(diff)}');
        for (final c in diff.take(8)) {
          debugPrint('  · ${c.describe()}');
        }
      }
    } else {
      _lastDiff = const [];
    }

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
      // ⚠️ 这些消息会**直接显示在「我的 → 配置状态」里**，所以要短。
      //    细节（两个时间戳是多少）留在 debugPrint 里。
      return '远端配置缺少版本时间戳，已沿用本地';
    }
    if (incomingAt.isBefore(currentAt)) {
      debugPrint('[ConfigStore] 远端 generatedAt=\$incomingTs < 本地 \$currentTs');
      return '远端配置比本地旧，已沿用本地';
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
