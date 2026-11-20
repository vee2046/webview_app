/// 我的 —— 外观 / 配置 / 离线与数据 / 关于。
///
/// 这一屏也由配置驱动：远程配置地址、版本、签名开关、离线包状态
/// 全部从 AppConfig 读，用户改的是本地偏好。
library;

import 'package:flutter/material.dart';

import '../config/config_diff.dart';
import '../data/usage_store.dart';
import '../icons/doodle_icons.dart';
import '../model/app_config.dart';
import '../theme/paper_theme.dart';
import '../util/native_toast.dart';
import 'widgets/paper_widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.config,
    required this.usage,
    required this.darkMode,
    required this.onDarkModeChanged,
    this.onRefreshConfig,
    this.onExportAll,
    this.onImportAll,
    this.onClearAll,
    this.refreshing = false,
    this.lastRemoteAt,
    this.lastError,
    this.configDiff = const [],
    this.requireSignature = false,
    this.signatureLocked = false,
    this.onRequireSignatureChanged,
  });

  final AppConfig config;
  final UsageStore usage;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final Future<void> Function()? onRefreshConfig;
  final Future<void> Function()? onExportAll;
  final Future<void> Function()? onImportAll;
  final Future<void> Function()? onClearAll;
  final bool refreshing;
  final DateTime? lastRemoteAt;
  final String? lastError;

  /// 最近一次远端配置更新带来的差异清单（§4.4「让热更可审」）。
  final List<ConfigChange> configDiff;

  /// 实际生效的签名要求（配置强制 或 本机加严）。
  final bool requireSignature;

  /// 签名要求被配置强制锁定 → 本机开关不能关。
  final bool signatureLocked;

  final Future<bool> Function(bool value)? onRequireSignatureChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 打开/关闭本机「加严签名」开关。
  Future<void> _toggleSignature() async {
    final next = !widget.requireSignature;
    final ok = await widget.onRequireSignatureChanged?.call(next) ?? false;
    if (!mounted) return;
    if (!ok) {
      NativeToast.show(context, '远端配置强制要求签名，本机不能关闭');
      return;
    }
    NativeToast.show(
      context,
      next ? '已开启签名校验：远端配置对不上就拒绝' : '已关闭本机签名校验',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    final app = widget.config.app;
    final web = widget.config.webview;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我的',
                    style: TextStyle(
                      fontSize: 26,
                      height: 1.2,
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'settings · config · data',
                    style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                  ),
                ],
              ),
            ),
            PaperIconButton(
              icon: 'refresh',
              onPressed: widget.refreshing
                  ? null
                  : () => widget.onRefreshConfig?.call(),
              tooltip: '刷新配置',
              active: widget.refreshing,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── 外观 ──────────────────────────────────────────────
        SectionLabel('外观'),
        PaperSettingTile(
          icon: 'sun',
          title: '主题',
          description: '牛皮纸 / 深色 / 跟随系统',
          value: widget.darkMode ? '深色' : '牛皮纸',
          onTap: () => widget.onDarkModeChanged(!widget.darkMode),
          trailing: _Switch(on: widget.darkMode),
        ),
        PaperSettingTile(
          icon: 'grid',
          title: '首页布局',
          description: '${app.home.layout == 'grid' ? '卡片网格' : '紧凑列表'} · ${app.home.columns} 列',
          value: '${app.home.columns} 列',
        ),

        // ── 配置 ──────────────────────────────────────────────
        SectionLabel('配置'),
        PaperSettingTile(
          icon: 'link',
          title: '远程配置地址',
          description: '运行时静默刷新，失败自动回退',
          value: _shortUrl(widget.config.remote.configUrl),
        ),
        PaperSettingTile(
          icon: 'refresh',
          title: '配置版本',
          description: widget.lastRemoteAt == null
              ? '尚未同步远端'
              : '上次更新 ${_fmt(widget.lastRemoteAt!)}',
          value: widget.lastError != null
              ? '回退中'
              : 'v${widget.config.schemaVersion}',
        ),
        PaperSettingTile(
          icon: 'lock',
          title: '签名校验',
          description: widget.signatureLocked
              ? '远端配置强制开启，本机不能再关'
              : '拒绝被篡改的远端配置（HMAC-SHA256）',
          value: widget.requireSignature ? '已开' : '未开',
          trailing: _Switch(
            on: widget.requireSignature,
            onTap: widget.requireSignature ? null : _toggleSignature,
          ),
          onTap: widget.requireSignature ? null : _toggleSignature,
        ),
        if (widget.configDiff.isNotEmpty) _ConfigDiffPanel(diff: widget.configDiff),
        PaperSettingTile(
          icon: 'toolbox',
          title: '首屏',
          description: '打开 App 先看到哪一页',
          value: _firstTabLabel(),
        ),

        // ── 容器 ──────────────────────────────────────────────
        SectionLabel('容器'),
        PaperSettingTile(
          icon: 'fullscreen',
          title: '默认 chrome',
          description: '工具容器顶栏的默认档位',
          value: _chromeLabel(web.chrome.defaultMode),
        ),
        PaperSettingTile(
          icon: 'fullscreen',
          title: '全屏时隐藏系统栏',
          description: '沉浸模式连系统状态栏一起藏',
          value: web.chrome.hideSystemBars ? '已开' : '未开',
          trailing: _Switch(on: web.chrome.hideSystemBars),
        ),
        PaperSettingTile(
          icon: 'back',
          title: '返回键行为',
          description: '默认不接管页面内路由',
          value: web.routeBackEnabledDefault ? '接管' : '回根页面',
        ),

        // ── 离线与数据 ────────────────────────────────────────
        SectionLabel('离线与数据'),
        PaperSettingTile(
          icon: 'download',
          title: '离线包',
          description: '${widget.config.visibleTools.where((t) => t.offline.enabled).length} 个工具可离线',
          value: '远端优先',
        ),
        PaperSettingTile(
          icon: 'copy',
          title: '导出全部数据',
          description: '合并为一份 JSON，可换机',
          onTap: () => widget.onExportAll?.call(),
        ),
        PaperSettingTile(
          icon: 'upload',
          title: '导入数据',
          description: '选择备份文件恢复到本机',
          onTap: () => widget.onImportAll?.call(),
        ),
        PaperSettingTile(
          icon: 'trash',
          title: '清除全部数据',
          description: '清空最近记录、置顶与本地快照',
          onTap: () => widget.onClearAll?.call(),
        ),

        // ── 关于 ──────────────────────────────────────────────
        SectionLabel('关于'),
        PaperSettingTile(
          icon: 'star',
          title: '${app.appName} · v${widget.config.about.version}',
          description: widget.config.about.note,
          value: widget.config.about.site,
        ),
        PaperSettingTile(
          icon: 'info',
          title: '来源',
          description: '名称 / 图标 / 分类复用 kmlab_site',
          value: app.brandSource.entries['site'] ?? 'kmlab_site',
        ),
        const SizedBox(height: 10),
        _BrandSourceTable(entries: app.brandSource.entries),
      ],
    );
  }

  String _firstTabLabel() {
    final nav = widget.config.app.bottomNav;
    if (nav.isEmpty) return '最近';
    for (final item in nav) {
      if (item.id == 'recent') return item.title;
    }
    return nav.first.title;
  }

  String _chromeLabel(ChromeMode mode) => switch (mode) {
        ChromeMode.full => '完整',
        ChromeMode.auto => '自动隐藏',
        ChromeMode.minimal => '极简',
        ChromeMode.immersive => '沉浸',
        ChromeMode.none => '无',
      };

  static String _shortUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    return '${u.host}${u.path}';
  }

  static String _fmt(DateTime t) {
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    return '$mm-$dd $hh:$mi';
  }
}

/// 纸片开关
class _Switch extends StatelessWidget {
  const _Switch({required this.on, this.onTap});

  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 21,
        decoration: BoxDecoration(
          color: on ? p.crayonGreen : p.paperDeep,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: p.ink, width: 2),
        ),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        padding: const EdgeInsets.all(2),
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: p.paperCard,
            shape: BoxShape.circle,
            border: Border.all(color: p.ink, width: 1.6),
          ),
        ),
      ),
    );
  }
}


/// 品牌溯源表 —— 把 `app.brandSource` 的每一项都摊开给人看。
///
/// 配置里声明了「这一项是从 kmlab_site 的哪个文件抄来的」，
/// 那就应该真的展示出来，而不是只躺在 JSON 里。
class _BrandSourceTable extends StatelessWidget {
  const _BrandSourceTable({required this.entries});

  final Map<String, String> entries;

  static const Map<String, String> _labels = {
    'site': '站点',
    'siteName': '站点名',
    'brandSub': '副标题',
    'pageTitle': '页面标题',
    'icon': 'App 图标',
    'doodles': '线稿图标',
    'categories': '分类',
  };

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor, width: 1.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('品牌溯源', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final entry in entries.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(
                      _labels[entry.key] ?? entry.key,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


/// 配置差异面板 —— 把「远端配置这次改了什么」摊开给人看。
///
/// 这是「热更可审」的落地点（DESIGN.md §4.4）：远端配置可以在 App 不发版的
/// 情况下被改掉，如果不把差异摊开，用户遇到行为变化只会觉得「App 坏了」。
class _ConfigDiffPanel extends StatefulWidget {
  const _ConfigDiffPanel({required this.diff});

  final List<ConfigChange> diff;

  @override
  State<_ConfigDiffPanel> createState() => _ConfigDiffPanelState();
}

class _ConfigDiffPanelState extends State<_ConfigDiffPanel> {
  bool _expanded = false;

  static const int _maxShown = 20;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    final diff = widget.diff;
    final shown = diff.take(_maxShown).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: PaperCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UiIcon('refresh', size: 16, color: p.ink),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '本次更新的变更',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                ),
                Text(
                  ConfigDiff.summarize(diff),
                  style: TextStyle(fontSize: 12, color: p.inkSoft),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_expanded)
              for (final c in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    c.describe(),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: p.ink,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            if (diff.length > _maxShown)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '…还有 ${diff.length - _maxShown} 处未显示',
                  style: TextStyle(fontSize: 11, color: p.inkSoft),
                ),
              ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? '收起 ▲' : '展开看明细 ▼',
                style: TextStyle(
                  fontSize: 12,
                  color: p.crayonBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
