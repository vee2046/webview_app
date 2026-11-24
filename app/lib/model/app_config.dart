/// App 配置模型 —— 与 `config/app.config.json` 严格一一对应。
///
/// 设计原则：
///   * 每个字段都有默认值，缺字段不崩（见 DESIGN.md §4.4「接受」规则）
///   * 模型不可变，ConfigLoader 负责原子替换
///   * 未知字段一律忽略
library;

import 'dart:convert';

/// 顶栏 chrome 档位
enum ChromeMode { full, auto, minimal, immersive, none }

ChromeMode chromeModeFrom(String? raw) => switch (raw) {
      'full' => ChromeMode.full,
      'auto' => ChromeMode.auto,
      'immersive' => ChromeMode.immersive,
      'none' => ChromeMode.none,
      _ => ChromeMode.minimal,
    };

/// 工具打开方式
// ⚠️ 这里原本有个 `OpenMode{webview, external, browser}` ——
//    `external` 会让「点工具卡片」的行为因工具而异（有的弹「用别的 App 打开」）。
//    用户明确要求「不做特例」，已连同配置里的 `open.mode` 一起删掉（D18）：
//    **所有工具一律在 App 内的 WebView 里打开配置里的 url。**



/// 返回键不接管路由时的回退目标
enum BackFallback { home, exit }

BackFallback backFallbackFrom(String? raw) =>
    raw == 'exit' ? BackFallback.exit : BackFallback.home;

/// 续接卡摘要的读取方式
enum ResumeMode { storage, bridge, none }

ResumeMode resumeModeFrom(String? raw) => switch (raw) {
      'storage' => ResumeMode.storage,
      'bridge' => ResumeMode.bridge,
      _ => ResumeMode.none,
    };

/// 摘要算法
///
/// - `countToday`  记录数组里数「今天」的条数（喝水）
/// - `count`       数数组长度（药品 / 待办 / 分期）
/// - `countDateMap` **按日期分组的对象**里数「今天」的条数（打卡助手）
/// - `field`       读某个字段值
/// - `none`        不算
enum ExtractKind { countToday, count, countDateMap, field, lastGame, none }

ExtractKind extractKindFrom(String? raw) => switch (raw) {
      'countToday' => ExtractKind.countToday,
      'count' => ExtractKind.count,
      'countDateMap' => ExtractKind.countDateMap,
      'field' => ExtractKind.field,
      'lastGame' => ExtractKind.lastGame,
      _ => ExtractKind.none,
    };

// ─────────────────────────────────────────────────────────────
// 基础小部件
// ─────────────────────────────────────────────────────────────

class TabConfig {
  const TabConfig({
    required this.id,
    required this.title,
    required this.icon,
    this.color,
  });

  final String id;
  final String title;
  final String icon;
  final String? color;

  factory TabConfig.fromJson(Map<String, dynamic> json) => TabConfig(
        id: json['id'] as String? ?? 'all',
        title: json['title'] as String? ?? '',
        icon: json['icon'] as String? ?? 'box',
        color: json['color'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'icon': icon,
        if (color != null) 'color': color,
      };
}

class BottomNavItem {
  const BottomNavItem({
    required this.id,
    required this.title,
    required this.icon,
  });

  final String id;
  final String title;
  final String icon;

  factory BottomNavItem.fromJson(Map<String, dynamic> json) => BottomNavItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        icon: json['icon'] as String? ?? 'box',
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'icon': icon};
}

class RemoteConfig {
  const RemoteConfig({
    required this.enabled,
    required this.configUrl,
    this.updateUrl,
    required this.timeoutMs,
    required this.refreshOnLaunch,
    required this.hotReload,
    required this.requireSignature,
    this.canaryUrl = '',
    this.rolloutPercent = 0,
  });

  final bool enabled;
  final String configUrl;

  /// 自动更新清单地址（可选）。为空 = 不检查更新。
  ///
  /// 清单内容见 `lib/data/update_checker.dart`。
  final String? updateUrl;

  final int timeoutMs;
  final bool refreshOnLaunch;
  final bool hotReload;
  final bool requireSignature;

  /// 灰度配置地址（可选）。为空 = 没开灰度。
  ///
  /// ⚠️ 为什么必须是**两个 URL** 而不是「一份配置 + 一个百分比」：
  /// 百分比得写在**稳定版**那份配置里（因为决定「我拉哪个地址」的是稳定版）。
  /// 如果把它写在灰度版里，不在灰度组的设备永远看不到它，也就永远升不到 100%。
  final String canaryUrl;

  /// 灰度流量比例（0~100）。`bucket < rolloutPercent` 的设备拉灰度版。
  final int rolloutPercent;

  /// 有没有开灰度。
  bool get hasCanary => canaryUrl.isNotEmpty && rolloutPercent > 0;

  static const RemoteConfig fallback = RemoteConfig(
    enabled: false,
    configUrl: '',
    timeoutMs: 8000,
    refreshOnLaunch: false,
    hotReload: false,
    requireSignature: false,
    canaryUrl: '',
    rolloutPercent: 0,
  );

  factory RemoteConfig.fromJson(Map<String, dynamic> json) => RemoteConfig(
        enabled: json['enabled'] as bool? ?? false,
        configUrl: json['configUrl'] as String? ?? '',

        updateUrl: json['updateUrl'] as String?,
        timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 8000,
        refreshOnLaunch: json['refreshOnLaunch'] as bool? ?? false,
        hotReload: json['hotReload'] as bool? ?? false,
        requireSignature: json['requireSignature'] as bool? ?? false,
        canaryUrl: json['canaryUrl'] as String? ?? '',
        rolloutPercent: ((json['rolloutPercent'] as num?)?.toInt() ?? 0)
            .clamp(0, 100),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'configUrl': configUrl,

        'updateUrl': updateUrl,
        'timeoutMs': timeoutMs,
        'refreshOnLaunch': refreshOnLaunch,
        'hotReload': hotReload,
        'requireSignature': requireSignature,
        'canaryUrl': canaryUrl,
        'rolloutPercent': rolloutPercent,
      };

  RemoteConfig copyWith({
    bool? enabled,
    String? configUrl,
    int? timeoutMs,
    bool? refreshOnLaunch,
    bool? hotReload,
    bool? requireSignature,
    String? canaryUrl,
    int? rolloutPercent,
  }) =>
      RemoteConfig(
        enabled: enabled ?? this.enabled,
        configUrl: configUrl ?? this.configUrl,
        timeoutMs: timeoutMs ?? this.timeoutMs,
        refreshOnLaunch: refreshOnLaunch ?? this.refreshOnLaunch,
        hotReload: hotReload ?? this.hotReload,
        requireSignature: requireSignature ?? this.requireSignature,
        canaryUrl: canaryUrl ?? this.canaryUrl,
        rolloutPercent: rolloutPercent ?? this.rolloutPercent,
      );
}

class OfflineConfig {
  const OfflineConfig({required this.enabled, this.path, this.size});

  final bool enabled;
  final String? path;
  final String? size;

  factory OfflineConfig.fromJson(Map<String, dynamic> json) => OfflineConfig(
        enabled: json['enabled'] as bool? ?? false,
        path: json['path'] as String?,
        size: json['size'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (path != null) 'path': path,
        if (size != null) 'size': size,
      };
}

class OpenConfig {
  const OpenConfig({
    required this.titleBar,
    required this.pullToRefresh,
    required this.chrome,
    required this.routeBackEnabled,
    required this.backFallback,
    required this.overflowItems,
  });

  final bool titleBar;
  final bool pullToRefresh;
  final ChromeMode chrome;
  final bool routeBackEnabled;
  final BackFallback backFallback;

  /// ⋯ 溢出菜单项 —— 既是白名单也是显示顺序
  final List<String> overflowItems;

  factory OpenConfig.fromJson(Map<String, dynamic> json, {
    ChromeMode defaultChrome = ChromeMode.minimal,
    bool defaultRouteBack = false,
    BackFallback defaultFallback = BackFallback.home,
    List<String> defaultOverflow = const [],
  }) =>
      OpenConfig(
        titleBar: json['titleBar'] as bool? ?? true,
        pullToRefresh: json['pullToRefresh'] as bool? ?? true,
        chrome: json['chrome'] == null
            ? defaultChrome
            : chromeModeFrom(json['chrome'] as String?),
        routeBackEnabled:
            json['routeBackEnabled'] as bool? ?? defaultRouteBack,
        backFallback: json['backFallback'] == null
            ? defaultFallback
            : backFallbackFrom(json['backFallback'] as String?),
        overflowItems: (json['overflowItems'] as List?)?.cast<String>() ??
            defaultOverflow,
      );

  Map<String, dynamic> toJson() => {
        'titleBar': titleBar,
        'pullToRefresh': pullToRefresh,
        'chrome': chrome.name,
        'routeBackEnabled': routeBackEnabled,
        'backFallback': backFallback.name,
        'overflowItems': overflowItems,
      };
}

class ExtractConfig {
  const ExtractConfig({
    required this.kind,
    this.key,
    this.dateField,
    this.goalKey,
    this.path,
    this.unit,
    this.template,
    this.gameField,
    this.scoreField,
    this.movesField,
    this.levelField,
    this.names,
    this.templateMoves,
    this.templateFallback,
  });

  final ExtractKind kind;
  final String? key;

  /// `countToday` 用：记录里哪个字段是时间戳
  final String? dateField;

  /// `countToday` 用：目标值存在哪个 key
  final String? goalKey;

  /// `count` 用：点路径，如 `meds` / `tasks` / `installments`
  final String? path;
  final String? unit;
  final String? template;

  // ── `lastGame` 用（脑力慢养）────────────────────────────────
  //
  // 脑力慢养的 `bf_progress` 存的是「今天还没打完的那一局」：
  //   `{gameId:"B", level:3, qIndex:7, score:82, startedAt:1764...}`
  // `gameId` 是一串字母代码（A~E），真实游戏名在 `names` 里配置 ——
  // **H5 的知识放在配置里，App 不硬编码**。

  /// 哪一个字段是游戏代码（默认 `gameId`）
  final String? gameField;

  /// 哪一个字段是分数（默认 `score`）
  final String? scoreField;

  /// 哪一个字段是步数（默认 `moves`，部分游戏没有分数只有步数）
  final String? movesField;

  /// 哪一个字段是关卡（默认 `level`）
  final String? levelField;

  /// 游戏代码 → 中文名，如 `{"B":"数口令"}`
  final Map<String, String>? names;

  /// 没有分数但有步数时用的模板
  final String? templateMoves;

  /// 既没分数也没步数时用的模板
  final String? templateFallback;

  factory ExtractConfig.fromJson(Map<String, dynamic> json) => ExtractConfig(
        kind: extractKindFrom(json['kind'] as String?),
        key: json['key'] as String?,
        dateField: json['dateField'] as String?,
        goalKey: json['goalKey'] as String?,
        path: json['path'] as String?,
        unit: json['unit'] as String?,
        template: json['template'] as String?,
        gameField: json['gameField'] as String?,
        scoreField: json['scoreField'] as String?,
        movesField: json['movesField'] as String?,
        levelField: json['levelField'] as String?,
        names: _stringMap(json['names']),
        templateMoves: json['templateMoves'] as String?,
        templateFallback: json['templateFallback'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (key != null) 'key': key,
        if (dateField != null) 'dateField': dateField,
        if (goalKey != null) 'goalKey': goalKey,
        if (path != null) 'path': path,
        if (unit != null) 'unit': unit,
        if (template != null) 'template': template,
        if (gameField != null) 'gameField': gameField,
        if (scoreField != null) 'scoreField': scoreField,
        if (movesField != null) 'movesField': movesField,
        if (levelField != null) 'levelField': levelField,
        if (names != null) 'names': names,
        if (templateMoves != null) 'templateMoves': templateMoves,
        if (templateFallback != null) 'templateFallback': templateFallback,
      };

  /// 配置里的 `names` 可能是 `Map`，也可能是 `Map<String, dynamic>`
  static Map<String, String>? _stringMap(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v != null) out[k] = '$v';
    });
    return out.isEmpty ? null : out;
  }
}

class IdbRef {
  const IdbRef({required this.name, required this.store});

  final String name;
  final String store;

  factory IdbRef.fromJson(Map<String, dynamic> json) => IdbRef(
        name: json['name'] as String? ?? '',
        store: json['store'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'store': store};
}

class ResumeConfig {
  const ResumeConfig({
    required this.enabled,
    required this.mode,
    required this.storageKeys,
    required this.extract,
    required this.summary,
    this.idb,
    this.note,
  });

  final bool enabled;
  final ResumeMode mode;
  final List<String> storageKeys;
  final ExtractConfig extract;
  final String summary;
  final IdbRef? idb;
  final String? note;

  factory ResumeConfig.fromJson(Map<String, dynamic> json) => ResumeConfig(
        enabled: json['enabled'] as bool? ?? false,
        mode: resumeModeFrom(json['mode'] as String?),
        storageKeys: (json['storageKeys'] as List?)?.cast<String>() ?? const [],
        extract: json['extract'] is Map<String, dynamic>
            ? ExtractConfig.fromJson(json['extract'] as Map<String, dynamic>)
            : const ExtractConfig(kind: ExtractKind.none),
        summary: json['summary'] as String? ?? '',
        idb: json['idb'] is Map<String, dynamic>
            ? IdbRef.fromJson(json['idb'] as Map<String, dynamic>)
            : null,
        note: json['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'mode': mode.name,
        'storageKeys': storageKeys,
        'extract': extract.toJson(),
        'summary': summary,
        if (idb != null) 'idb': idb!.toJson(),
        if (note != null) 'note': note,
      };
}

// ─────────────────────────────────────────────────────────────
// 容器配置
// ─────────────────────────────────────────────────────────────

class ChromeConfig {
  const ChromeConfig({
    required this.defaultMode,
    required this.options,
    required this.immersiveRevealGesture,
    required this.immersiveTopHotZonePx,
    required this.immersiveFallbackButton,
    required this.hideSystemBars,
    required this.keepProgressBarInImmersive,
  });

  final ChromeMode defaultMode;
  final List<ChromeMode> options;
  final String immersiveRevealGesture;
  final double immersiveTopHotZonePx;
  final bool immersiveFallbackButton;
  final bool hideSystemBars;
  final bool keepProgressBarInImmersive;

  factory ChromeConfig.fromJson(Map<String, dynamic> json) => ChromeConfig(
        defaultMode:
            chromeModeFrom(json['default'] as String? ?? 'minimal'),
        options: ((json['options'] as List?)?.cast<String>() ?? const [])
            .map(chromeModeFrom)
            .toList(growable: false),
        immersiveRevealGesture:
            json['immersiveRevealGesture'] as String? ?? 'edge-swipe-down',
        immersiveTopHotZonePx:
            ((json['immersiveTopHotZonePx'] as num?)?.toDouble() ?? 28),
        immersiveFallbackButton:
            json['immersiveFallbackButton'] as bool? ?? true,
        hideSystemBars: json['hideSystemBars'] as bool? ?? false,
        keepProgressBarInImmersive:
            json['keepProgressBarInImmersive'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'default': defaultMode.name,
        'options': options.map((e) => e.name).toList(),
        'immersiveRevealGesture': immersiveRevealGesture,
        'immersiveTopHotZonePx': immersiveTopHotZonePx,
        'immersiveFallbackButton': immersiveFallbackButton,
        'hideSystemBars': hideSystemBars,
        'keepProgressBarInImmersive': keepProgressBarInImmersive,
      };
}

class OverflowConfig {
  const OverflowConfig({
    required this.sheetStyle,
    required this.confirmDanger,
    required this.defaultItems,
  });

  final String sheetStyle;
  final bool confirmDanger;
  final List<String> defaultItems;

  factory OverflowConfig.fromJson(Map<String, dynamic> json) => OverflowConfig(
        sheetStyle: json['sheetStyle'] as String? ?? 'grouped',
        confirmDanger: json['confirmDanger'] as bool? ?? true,
        defaultItems:
            (json['defaultItems'] as List?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'sheetStyle': sheetStyle,
        'confirmDanger': confirmDanger,
        'defaultItems': defaultItems,
      };
}

class DataTransferConfig {
  const DataTransferConfig({
    required this.exportFormat,
    required this.exportFileName,
    required this.exportDelivery,
    required this.clipboardFallback,
    required this.importEnabled,
    required this.importMaxSizeMb,
    required this.importConflictPolicy,
    required this.importMergeStrategy,
  });

  final String exportFormat;
  final String exportFileName;
  final String exportDelivery;
  final bool clipboardFallback;
  final bool importEnabled;
  final int importMaxSizeMb;
  final String importConflictPolicy;
  final String importMergeStrategy;

  factory DataTransferConfig.fromJson(Map<String, dynamic> json) =>
      DataTransferConfig(
        exportFormat: json['exportFormat'] as String? ?? 'json',
        exportFileName: json['exportFileName'] as String? ??
            'km-{toolId}-backup-{yyyyMMdd}.json',
        exportDelivery: json['exportDelivery'] as String? ?? 'share',
        clipboardFallback: json['clipboardFallback'] as bool? ?? true,
        importEnabled: json['importEnabled'] as bool? ?? true,
        importMaxSizeMb: (json['importMaxSizeMb'] as num?)?.toInt() ?? 10,
        importConflictPolicy:
            json['importConflictPolicy'] as String? ?? 'confirm',
        importMergeStrategy:
            json['importMergeStrategy'] as String? ?? 'mergeByKey',
      );

  Map<String, dynamic> toJson() => {
        'exportFormat': exportFormat,
        'exportFileName': exportFileName,
        'exportDelivery': exportDelivery,
        'clipboardFallback': clipboardFallback,
        'importEnabled': importEnabled,
        'importMaxSizeMb': importMaxSizeMb,
        'importConflictPolicy': importConflictPolicy,
        'importMergeStrategy': importMergeStrategy,
      };

  /// 把 `{toolId}` / `{yyyyMMdd}` 占位符填上
  String fileNameFor(String toolId, DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return exportFileName
        .replaceAll('{toolId}', toolId)
        .replaceAll('{yyyyMMdd}', '$y$m$d');
  }
}

/// 默认识别为「下载」的扩展名。
///
/// 刻意**不含** html / json —— 那两类多半是页面导航而不是文件。
const List<String> defaultDownloadExtensions = <String>[
  'pdf', 'zip', 'apk', 'ipa', 'dmg', 'exe', 'csv', 'xls', 'xlsx', 'doc', 'docx',
  'ppt', 'pptx', 'txt', 'md', 'rtf', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg',
  'mp3', 'wav', 'm4a', 'mp4', 'mov', 'webm', 'epub',
];

class WebViewConfig {
  const WebViewConfig({
    required this.userAgentSuffix,
    required this.openExternalLinksInBrowser,
    required this.interceptDownloads,
    required this.downloadExtensions,
    required this.handleHardwareBack,
    required this.routeBackEnabledDefault,
    required this.backFallbackDefault,
    required this.errorRetryInWebview,
    required this.chrome,
    required this.overflow,
    required this.dataTransfer,
  });

  final String userAgentSuffix;
  final bool openExternalLinksInBrowser;
  final bool interceptDownloads;

  /// 命中这些扩展名的链接按「下载」处理（不当作页面导航）。
  final List<String> downloadExtensions;
  final bool handleHardwareBack;
  final bool routeBackEnabledDefault;
  final BackFallback backFallbackDefault;
  final bool errorRetryInWebview;
  final ChromeConfig chrome;
  final OverflowConfig overflow;
  final DataTransferConfig dataTransfer;

  factory WebViewConfig.fromJson(Map<String, dynamic> json) => WebViewConfig(
        userAgentSuffix: json['userAgentSuffix'] as String? ?? '',
        openExternalLinksInBrowser:
            json['openExternalLinksInBrowser'] as bool? ?? true,
        interceptDownloads: json['interceptDownloads'] as bool? ?? true,
        downloadExtensions: json['downloadExtensions'] is List
            ? (json['downloadExtensions'] as List)
                .map((e) => e.toString().toLowerCase())
                .where((e) => e.isNotEmpty)
                .toList()
            : defaultDownloadExtensions,
        handleHardwareBack: json['handleHardwareBack'] as bool? ?? true,
        routeBackEnabledDefault:
            json['routeBackEnabledDefault'] as bool? ?? false,
        backFallbackDefault: backFallbackFrom(json['backFallbackDefault'] as String?),
        errorRetryInWebview: json['errorRetryInWebview'] as bool? ?? true,
        chrome: json['chrome'] is Map<String, dynamic>
            ? ChromeConfig.fromJson(json['chrome'] as Map<String, dynamic>)
            : const ChromeConfig(
                defaultMode: ChromeMode.minimal,
                options: [],
                immersiveRevealGesture: 'edge-swipe-down',
                immersiveTopHotZonePx: 28,
                immersiveFallbackButton: true,
                hideSystemBars: false,
                keepProgressBarInImmersive: false,
              ),
        overflow: json['overflow'] is Map<String, dynamic>
            ? OverflowConfig.fromJson(json['overflow'] as Map<String, dynamic>)
            : const OverflowConfig(
                sheetStyle: 'grouped',
                confirmDanger: true,
                defaultItems: [],
              ),
        dataTransfer: json['dataTransfer'] is Map<String, dynamic>
            ? DataTransferConfig.fromJson(
                json['dataTransfer'] as Map<String, dynamic>)
            : const DataTransferConfig(
                exportFormat: 'json',
                exportFileName: 'km-{toolId}-backup-{yyyyMMdd}.json',
                exportDelivery: 'share',
                clipboardFallback: true,
                importEnabled: true,
                importMaxSizeMb: 10,
                importConflictPolicy: 'confirm',
                importMergeStrategy: 'mergeByKey',
              ),
      );

  Map<String, dynamic> toJson() => {
        'userAgentSuffix': userAgentSuffix,
        'openExternalLinksInBrowser': openExternalLinksInBrowser,
        'interceptDownloads': interceptDownloads,
        'downloadExtensions': downloadExtensions,
        'handleHardwareBack': handleHardwareBack,
        'routeBackEnabledDefault': routeBackEnabledDefault,
        'backFallbackDefault': backFallbackDefault.name,
        'errorRetryInWebview': errorRetryInWebview,
        'chrome': chrome.toJson(),
        'overflow': overflow.toJson(),
        'dataTransfer': dataTransfer.toJson(),
      };
}

class BridgeConfig {
  const BridgeConfig({
    required this.enabled,
    required this.namespace,
    required this.timeoutMs,
    required this.permissions,
  });

  final bool enabled;
  final String namespace;
  final int timeoutMs;
  final List<String> permissions;

  factory BridgeConfig.fromJson(Map<String, dynamic> json) => BridgeConfig(
        enabled: json['enabled'] as bool? ?? true,
        namespace: json['namespace'] as String? ?? 'KM',
        timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 1500,
        permissions:
            (json['permissions'] as List?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'namespace': namespace,
        'timeoutMs': timeoutMs,
        'permissions': permissions,
      };
}

class AboutConfig {
  const AboutConfig({
    required this.repo,
    required this.site,
    required this.note,
  });

  final String repo;
  final String site;
  final String note;

  factory AboutConfig.fromJson(Map<String, dynamic> json) => AboutConfig(
        repo: json['repo'] as String? ?? '',
        site: json['site'] as String? ?? '',
        note: json['note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'repo': repo,
        'site': site,
        'note': note,
      };
}

// ─────────────────────────────────────────────────────────────
// 工具
// ─────────────────────────────────────────────────────────────

class ToolConfig {
  const ToolConfig({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.tab,
    required this.url,
    required this.offline,
    required this.open,
    required this.featured,
    required this.sort,
    required this.enabled,
    required this.resume,
    this.badge,
  });

  final String id;
  final String title;
  final String subtitle;
  final String icon;
  final String color;
  final String tab;
  final String url;
  final OfflineConfig offline;
  final OpenConfig open;
  final bool featured;
  final int sort;
  final bool enabled;
  final ResumeConfig resume;
  final String? badge;

  factory ToolConfig.fromJson(Map<String, dynamic> json, {
    ChromeMode defaultChrome = ChromeMode.minimal,
    bool defaultRouteBack = false,
    BackFallback defaultFallback = BackFallback.home,
    List<String> defaultOverflow = const [],
  }) =>
      ToolConfig(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        icon: json['icon'] as String? ?? 'box',
        color: json['color'] as String? ?? '#6b6256',
        tab: json['tab'] as String? ?? 'all',
        url: json['url'] as String? ?? '',
        offline: json['offline'] is Map<String, dynamic>
            ? OfflineConfig.fromJson(json['offline'] as Map<String, dynamic>)
            : const OfflineConfig(enabled: false),
        open: OpenConfig.fromJson(
          json['open'] is Map<String, dynamic>
              ? json['open'] as Map<String, dynamic>
              : const {},
          defaultChrome: defaultChrome,
          defaultRouteBack: defaultRouteBack,
          defaultFallback: defaultFallback,
          defaultOverflow: defaultOverflow,
        ),
        featured: json['featured'] as bool? ?? false,
        sort: (json['sort'] as num?)?.toInt() ?? 100,
        enabled: json['enabled'] as bool? ?? true,
        resume: json['resume'] is Map<String, dynamic>
            ? ResumeConfig.fromJson(json['resume'] as Map<String, dynamic>)
            : const ResumeConfig(
                enabled: false,
                mode: ResumeMode.none,
                storageKeys: [],
                extract: ExtractConfig(kind: ExtractKind.none),
                summary: '',
              ),
        badge: json['badge'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'icon': icon,
        'color': color,
        'tab': tab,
        'url': url,
        'offline': offline.toJson(),
        'open': open.toJson(),
        'featured': featured,
        'sort': sort,
        'enabled': enabled,
        'resume': resume.toJson(),
        if (badge != null) 'badge': badge,
      };
}

// ─────────────────────────────────────────────────────────────
// App 元信息
// ─────────────────────────────────────────────────────────────

class RecentEmptyState {
  const RecentEmptyState({
    required this.showSuggested,
    required this.suggestFrom,
    required this.showLinkToTools,
  });

  final bool showSuggested;
  final String suggestFrom;
  final bool showLinkToTools;

  factory RecentEmptyState.fromJson(Map<String, dynamic> json) =>
      RecentEmptyState(
        showSuggested: json['showSuggested'] as bool? ?? true,
        suggestFrom: json['suggestFrom'] as String? ?? 'featured',
        showLinkToTools: json['showLinkToTools'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'showSuggested': showSuggested,
        'suggestFrom': suggestFrom,
        'showLinkToTools': showLinkToTools,
      };
}

class RecentConfig {
  const RecentConfig({
    required this.isDefaultTab,
    required this.showGreeting,
    required this.showTodayCount,
    required this.showPinned,
    required this.showResumeCard,
    required this.showTimeline,
    required this.timelineGroups,
    required this.maxTimelineItems,
    required this.emptyState,
  });

  final bool isDefaultTab;
  final bool showGreeting;
  final bool showTodayCount;
  final bool showPinned;
  final bool showResumeCard;
  final bool showTimeline;
  final List<String> timelineGroups;
  final int maxTimelineItems;
  final RecentEmptyState emptyState;

  factory RecentConfig.fromJson(Map<String, dynamic> json) => RecentConfig(
        isDefaultTab: json['isDefaultTab'] as bool? ?? true,
        showGreeting: json['showGreeting'] as bool? ?? true,
        showTodayCount: json['showTodayCount'] as bool? ?? true,
        showPinned: json['showPinned'] as bool? ?? true,
        showResumeCard: json['showResumeCard'] as bool? ?? true,
        showTimeline: json['showTimeline'] as bool? ?? true,
        timelineGroups:
            (json['timelineGroups'] as List?)?.cast<String>() ?? const [],
        maxTimelineItems: (json['maxTimelineItems'] as num?)?.toInt() ?? 30,
        emptyState: json['emptyState'] is Map<String, dynamic>
            ? RecentEmptyState.fromJson(
                json['emptyState'] as Map<String, dynamic>)
            : const RecentEmptyState(
                showSuggested: true,
                suggestFrom: 'featured',
                showLinkToTools: true,
              ),
      );

  Map<String, dynamic> toJson() => {
        'isDefaultTab': isDefaultTab,
        'showGreeting': showGreeting,
        'showTodayCount': showTodayCount,
        'showPinned': showPinned,
        'showResumeCard': showResumeCard,
        'showTimeline': showTimeline,
        'timelineGroups': timelineGroups,
        'maxTimelineItems': maxTimelineItems,
        'emptyState': emptyState.toJson(),
      };
}

class HomeConfig {
  const HomeConfig({
    required this.layout,
    required this.columns,
    required this.showHero,
    required this.showSearch,
    required this.showRecent,
    required this.showOfflineBadge,
    required this.newBadgeDays,
  });

  final String layout;
  final int columns;
  final bool showHero;
  final bool showSearch;
  final bool showRecent;
  final bool showOfflineBadge;
  final int newBadgeDays;

  factory HomeConfig.fromJson(Map<String, dynamic> json) => HomeConfig(
        layout: json['layout'] as String? ?? 'grid',
        columns: (json['columns'] as num?)?.toInt() ?? 2,
        showHero: json['showHero'] as bool? ?? false,
        showSearch: json['showSearch'] as bool? ?? true,
        showRecent: json['showRecent'] as bool? ?? false,
        showOfflineBadge: json['showOfflineBadge'] as bool? ?? true,
        newBadgeDays: (json['newBadgeDays'] as num?)?.toInt() ?? 7,
      );

  Map<String, dynamic> toJson() => {
        'layout': layout,
        'columns': columns,
        'showHero': showHero,
        'showSearch': showSearch,
        'showRecent': showRecent,
        'showOfflineBadge': showOfflineBadge,
        'newBadgeDays': newBadgeDays,
      };
}

class BrandSource {
  const BrandSource(this.entries);

  /// key → kmlab_site 出处
  final Map<String, String> entries;

  factory BrandSource.fromJson(Map<String, dynamic> json) => BrandSource({
        for (final e in json.entries) e.key: e.value as String? ?? '',
      });

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(entries);
}

class IconsManifest {
  const IconsManifest({
    required this.source,
    required this.names,
    required this.defaultIcon,
  });

  final String source;
  final List<String> names;
  final String defaultIcon;

  factory IconsManifest.fromJson(Map<String, dynamic> json) => IconsManifest(
        source: json['source'] as String? ?? '',
        names: (json['names'] as List?)?.cast<String>() ?? const [],
        defaultIcon: json['default'] as String? ?? 'box',
      );

  Map<String, dynamic> toJson() => {
        'source': source,
        'names': names,
        'default': defaultIcon,
      };
}

class AppMeta {
  const AppMeta({
    required this.id,
    required this.name,
    required this.appName,
    required this.brandSub,
    required this.pageTitle,
    required this.icon,
    required this.brand,
    required this.tagline,
    required this.theme,
    required this.allowThemeOverride,
    required this.bottomNav,
    required this.recent,
    required this.home,
    required this.brandSource,
    required this.icons,
    required this.tabs,
    required this.storageManifest,
  });

  final String id;
  final String name;
  final String appName;
  final String brandSub;
  final String pageTitle;
  final String icon;
  final String brand;
  final String tagline;
  final String theme;
  final bool allowThemeOverride;
  final List<BottomNavItem> bottomNav;
  final RecentConfig recent;
  final HomeConfig home;
  final BrandSource brandSource;
  final IconsManifest icons;
  final List<TabConfig> tabs;
  final String storageManifest;

  factory AppMeta.fromJson(Map<String, dynamic> json) => AppMeta(
        id: json['id'] as String? ?? 'kmlab-toolbox',
        name: json['name'] as String? ?? 'kmlab',
        appName: json['appName'] as String? ?? 'kmlab Toolbox',
        brandSub: json['brandSub'] as String? ?? '',
        pageTitle: json['pageTitle'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        brand: json['brand'] as String? ?? '',
        tagline: json['tagline'] as String? ?? '',
        theme: json['theme'] as String? ?? 'paper',
        allowThemeOverride: json['allowThemeOverride'] as bool? ?? true,
        bottomNav: ((json['bottomNav'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BottomNavItem.fromJson)
            .toList(growable: false),
        recent: json['recent'] is Map<String, dynamic>
            ? RecentConfig.fromJson(json['recent'] as Map<String, dynamic>)
            : const RecentConfig(
                isDefaultTab: true,
                showGreeting: true,
                showTodayCount: true,
                showPinned: true,
                showResumeCard: true,
                showTimeline: true,
                timelineGroups: [],
                maxTimelineItems: 30,
                emptyState: RecentEmptyState(
                  showSuggested: true,
                  suggestFrom: 'featured',
                  showLinkToTools: true,
                ),
              ),
        home: json['home'] is Map<String, dynamic>
            ? HomeConfig.fromJson(json['home'] as Map<String, dynamic>)
            : const HomeConfig(
                layout: 'grid',
                columns: 2,
                showHero: false,
                showSearch: true,
                showRecent: false,
                showOfflineBadge: true,
                newBadgeDays: 7,
              ),
        brandSource: json['brandSource'] is Map<String, dynamic>
            ? BrandSource.fromJson(json['brandSource'] as Map<String, dynamic>)
            : const BrandSource({}),
        icons: json['icons'] is Map<String, dynamic>
            ? IconsManifest.fromJson(json['icons'] as Map<String, dynamic>)
            : const IconsManifest(source: '', names: [], defaultIcon: 'box'),
        tabs: ((json['tabs'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TabConfig.fromJson)
            .toList(growable: false),
        storageManifest: json['storageManifest'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'appName': appName,
        'brandSub': brandSub,
        'pageTitle': pageTitle,
        'icon': icon,
        'brand': brand,
        'tagline': tagline,
        'theme': theme,
        'allowThemeOverride': allowThemeOverride,
        'bottomNav': bottomNav.map((e) => e.toJson()).toList(),
        'recent': recent.toJson(),
        'home': home.toJson(),
        'brandSource': brandSource.toJson(),
        'icons': icons.toJson(),
        'tabs': tabs.map((e) => e.toJson()).toList(),
        'storageManifest': storageManifest,
      };
}

// ─────────────────────────────────────────────────────────────
// 顶层
// ─────────────────────────────────────────────────────────────

class AppConfig {
  const AppConfig({
    required this.schemaVersion,
    required this.app,
    required this.remote,
    required this.tools,
    required this.webview,
    required this.bridge,
    required this.about,
    this.generatedAt,
  });

  final int schemaVersion;
  final AppMeta app;
  final RemoteConfig remote;
  final List<ToolConfig> tools;
  final WebViewConfig webview;
  final BridgeConfig bridge;
  final AboutConfig about;

  /// **这份配置是什么时候生成的**（ISO 8601）。
  ///
  /// 用来判断远端配置比 App 内置快照「新」还是「旧」——
  /// 线上忘了更新时，旧配置不能覆盖 App 里更新的那一份。
  final DateTime? generatedAt;

  /// 上架的工具（按 sort 升序）
  List<ToolConfig> get visibleTools {
    final list = tools.where((t) => t.enabled).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    return list;
  }

  ToolConfig? toolById(String id) {
    for (final t in tools) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 按分类页签过滤
  List<ToolConfig> toolsOfTab(String tabId) =>
      visibleTools.where((t) => t.tab == tabId).toList(growable: false);

  /// 分类页签 → 该分类下的工具
  List<ToolConfig> toolsOfTabConfig(TabConfig tab) =>
      tab.id == 'all' ? visibleTools : toolsOfTab(tab.id);

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final webviewJson = json['webview'] is Map<String, dynamic>
        ? json['webview'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final chrome = webviewJson['chrome'] is Map<String, dynamic>
        ? ChromeConfig.fromJson(webviewJson['chrome'] as Map<String, dynamic>)
        : const ChromeConfig(
            defaultMode: ChromeMode.minimal,
            options: [],
            immersiveRevealGesture: 'edge-swipe-down',
            immersiveTopHotZonePx: 28,
            immersiveFallbackButton: true,
            hideSystemBars: false,
            keepProgressBarInImmersive: false,
          );

    final overflow = webviewJson['overflow'] is Map<String, dynamic>
        ? OverflowConfig.fromJson(webviewJson['overflow'] as Map<String, dynamic>)
        : const OverflowConfig(
            sheetStyle: 'grouped',
            confirmDanger: true,
            defaultItems: [],
          );

    return AppConfig(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      app: json['app'] is Map<String, dynamic>
          ? AppMeta.fromJson(json['app'] as Map<String, dynamic>)
          : const AppMeta(
              id: 'kmlab-toolbox',
              name: 'kmlab',
              appName: 'kmlab Toolbox',
              brandSub: '',
              pageTitle: '',
              icon: '',
              brand: '',
              tagline: '',
              theme: 'paper',
              allowThemeOverride: true,
              bottomNav: [],
              recent: RecentConfig(
                isDefaultTab: true,
                showGreeting: true,
                showTodayCount: true,
                showPinned: true,
                showResumeCard: true,
                showTimeline: true,
                timelineGroups: [],
                maxTimelineItems: 30,
                emptyState: RecentEmptyState(
                  showSuggested: true,
                  suggestFrom: 'featured',
                  showLinkToTools: true,
                ),
              ),
              home: HomeConfig(
                layout: 'grid',
                columns: 2,
                showHero: false,
                showSearch: true,
                showRecent: false,
                showOfflineBadge: true,
                newBadgeDays: 7,
              ),
              brandSource: BrandSource({}),
              icons: IconsManifest(source: '', names: [], defaultIcon: 'box'),
              tabs: [],
              storageManifest: '',
            ),
      remote: json['remote'] is Map<String, dynamic>
          ? RemoteConfig.fromJson(json['remote'] as Map<String, dynamic>)
          : RemoteConfig.fallback,
      tools: ((json['tools'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((t) => ToolConfig.fromJson(
                t,
                defaultChrome: chrome.defaultMode,
                defaultRouteBack:
                    webviewJson['routeBackEnabledDefault'] as bool? ?? false,
                defaultFallback: backFallbackFrom(
                    webviewJson['backFallbackDefault'] as String?),
                defaultOverflow: overflow.defaultItems,
              ))
          .toList(growable: false),
      webview: WebViewConfig.fromJson(webviewJson),
      bridge: json['bridge'] is Map<String, dynamic>
          ? BridgeConfig.fromJson(json['bridge'] as Map<String, dynamic>)
          : const BridgeConfig(
              enabled: true,
              namespace: 'KM',
              timeoutMs: 1500,
              permissions: [],
            ),
      about: json['about'] is Map<String, dynamic>
          ? AboutConfig.fromJson(json['about'] as Map<String, dynamic>)
          : const AboutConfig(
              repo: '',
              site: '',
              note: '',
            ),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        if (generatedAt != null) 'generatedAt': generatedAt!.toIso8601String(),
        'app': app.toJson(),
        'remote': remote.toJson(),
        'tools': tools.map((e) => e.toJson()).toList(),
        'webview': webview.toJson(),
        'bridge': bridge.toJson(),
        'about': about.toJson(),
      };

  /// 解析失败时抛出，交由 ConfigLoader 处理降级
  static AppConfig parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('配置根节点不是对象');
    }
    return AppConfig.fromJson(decoded);
  }
}
