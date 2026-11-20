/// 根外壳 —— 底部导航（最近 / 小工具 / 我的）。
///
/// 首屏落在「最近」；工具详情用 push 路由，进入后 chrome 由工具自己决定。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/config_store.dart';
import '../data/data_transfer.dart';
import '../config/config_diff.dart';
import '../data/usage_store.dart';
import '../icons/doodle_icons.dart';
import '../model/app_config.dart';
import '../theme/paper_theme.dart';
import '../util/native_toast.dart';
import 'recent_page.dart';
import 'settings_page.dart';
import 'tool_detail_page.dart';
import 'tools_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.configStore,
    required this.usage,
    required this.darkMode,
    required this.onDarkModeChanged,
  });

  final ConfigStore configStore;
  final UsageStore usage;
  final bool darkMode;
  final void Function(bool dark) onDarkModeChanged;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    final nav = widget.configStore.config?.app.bottomNav;
    final recentId = widget.configStore.config?.app.recent.isDefaultTab == true
        ? 'recent'
        : 'tools';
    _index = _indexOf(nav, recentId);
  }

  int _indexOf(List<BottomNavItem>? nav, String id) {
    if (nav == null || nav.isEmpty) return 0;
    final i = nav.indexWhere((e) => e.id == id);
    return i < 0 ? 0 : i;
  }

  // ── 打开工具 ──────────────────────────────────────────────────

  Future<void> _openTool(ToolConfig tool) async {
    final config = widget.configStore.config;
    if (config == null) return;

    // 外部 App / 浏览器
    if (tool.open.mode == OpenMode.external || tool.open.mode == OpenMode.browser) {
      await showDialog<void>(
        context: context,
        builder: (_) => _ExternalToolSheet(tool: tool),
      );
      return;
    }

    await widget.usage.recordOpen(tool.id);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ToolDetailPage(
          tool: tool,
          config: config,
          usage: widget.usage,
          onOpenTool: (next) {
            // KM.openTool → 替换当前页，避免栈越叠越深
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => ToolDetailPage(
                  tool: next,
                  config: config,
                  usage: widget.usage,
                  onOpenTool: (n2) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => ToolDetailPage(
                          tool: n2,
                          config: config,
                          usage: widget.usage,
                          onOpenTool: null,
                          onExitTool: () => _exitApp(),
                          onHome: () => _goHome(),
                        ),
                      ),
                    );
                  },
                  onExitTool: () => _exitApp(),
                  onHome: () => _goHome(),
                ),
              ),
            );
          },
          onExitTool: () => _exitApp(),
          onHome: () => _goHome(),
        ),
      ),
    );
  }

  /// 回到 App 根页面，并把底部导航切回「最近」——`backFallback: "home"` 的语义。
  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    final nav = widget.configStore.config?.app.bottomNav;
    final recentId = widget.configStore.config?.app.recent.isDefaultTab == true
        ? 'recent'
        : 'tools';
    final target = _indexOf(nav, recentId);
    if (target != _index && mounted) {
      setState(() => _index = target);
    }
  }

  /// `backFallback: "exit"` 的语义：直接退出 App。
  void _exitApp() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    SystemNavigator.pop();
  }

  // ── 页面 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.configStore,
      builder: (context, _) {
        final config = widget.configStore.config;
        if (config == null) {
          return Scaffold(
            backgroundColor: context.paper.paper,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final nav = config.app.bottomNav;

        return Scaffold(
          backgroundColor: context.paper.paper,
          body: SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _index.clamp(0, nav.isEmpty ? 0 : nav.length - 1),
              children: [
                RecentPage(
                  config: config,
                  usage: widget.usage,
                  onOpenTool: _openTool,
                  onOpenSettings: () => _selectTab(config, 'me'),
                  onOpenTools: () => _selectTab(config, 'tools'),
                ),
                ToolsPage(
                  config: config,
                  usage: widget.usage,
                  onOpenTool: _openTool,
                  onOpenSettings: () => _selectTab(config, 'me'),
                  onRefreshConfig: () => _refreshConfig(config),
                ),
                SettingsPage(
                  config: config,
                  usage: widget.usage,
                  darkMode: widget.darkMode,
                  onDarkModeChanged: widget.onDarkModeChanged,
                  refreshing: widget.configStore.refreshing,
                  lastRemoteAt: widget.configStore.lastRemoteAt,
                  lastError: widget.configStore.lastError,
                  onExportAll: () => _exportAll(config),
                  onImportAll: () => _importAll(config),
                  onClearAll: () => _clearAll(config),
                  onRefreshConfig: () => _refreshConfig(config),
                  configDiff: widget.configStore.lastDiff,
                  requireSignature: widget.configStore.requireSignature,
                  signatureLocked:
                      widget.configStore.signatureRequiredByConfig,
                  onRequireSignatureChanged: (v) =>
                      widget.configStore.setLocalRequireSignature(v),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _PaperNavBar(
            items: nav,
            index: _index,
            onTap: (i) => setState(() => _index = i),
          ),
        );
      },
    );
  }

  void _selectTab(AppConfig config, String id) {
    final i = config.app.bottomNav.indexWhere((e) => e.id == id);
    if (i >= 0) setState(() => _index = i);
  }

  // ── App 级数据管理 ────────────────────────────────────────────

  /// 导出全部数据 → `.json` → 系统分享面板。
  /// 刷新远端配置，并把**差异**摊开给用户看。
  ///
  /// 「配置已更新」四个字对用户没有任何信息量 —— 他真正想知道的是
  /// 「改了什么」：工具下架了？签名算法换了？推荐位动了？
  Future<void> _refreshConfig(AppConfig config) async {
    final changed = await widget.configStore.refresh();
    if (!mounted) return;

    final diff = widget.configStore.lastDiff;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    if (diff.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(changed ? '配置已更新' : '配置没有变化')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置已更新'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ConfigDiff.summarize(diff)),
                const SizedBox(height: 10),
                for (final c in diff.take(20))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      c.describe(),
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                if (diff.length > 20)
                  Text('…还有 ${diff.length - 20} 处未显示',
                      style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    widget.configStore.clearDiff();
  }

  Future<void> _exportAll(AppConfig config) async {
    try {
      await AppDataTransfer.exportAll(context, widget.usage, config);
    } catch (e) {
      if (!mounted) return;
      await NativeToast.show(context, '导出失败：$e');
    }
  }

  /// 导入备份（选文件 → 校验 → 冲突确认 → 合并）。
  Future<void> _importAll(AppConfig config) async {
    try {
      final summary = await AppDataTransfer.importAll(
        context,
        widget.usage,
        config,
      );
      if (!mounted) return;
      if (summary != null) {
        await NativeToast.show(context, summary.text);
      }
    } catch (e) {
      if (!mounted) return;
      await NativeToast.show(context, '导入失败：$e');
    }
  }

  /// 清除这台设备上的全部数据（二次确认）。
  Future<void> _clearAll(AppConfig config) async {
    try {
      final done = await AppDataTransfer.clearAll(
        context,
        widget.usage,
        config,
      );
      if (!mounted || !done) return;
      await NativeToast.show(context, '已清除本机数据');
    } catch (e) {
      if (!mounted) return;
      await NativeToast.show(context, '清除失败：$e');
    }
  }
}

// ── 底部导航 ──────────────────────────────────────────────────

class _PaperNavBar extends StatelessWidget {
  const _PaperNavBar({
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<BottomNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.ink.withValues(alpha: 0.35), width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            _NavItem(
              item: items[i],
              active: i == index,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final BottomNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UiIcon(
              item.icon,
              size: 21,
              color: active ? p.ink : p.inkSoft,
              strokeWidth: active ? 2.4 : 1.8,
            ),
            const SizedBox(height: 1),
            Text(
              item.title,
              style: TextStyle(
                fontSize: 11,
                color: active ? p.ink : p.inkSoft,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 外部工具提示 ──────────────────────────────────────────────

class _ExternalToolSheet extends StatelessWidget {
  const _ExternalToolSheet({required this.tool});

  final ToolConfig tool;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        decoration: BoxDecoration(
          color: p.paperCard,
          borderRadius: paperBorderRadius(20, alternate: 12),
          border: Border.all(color: p.ink, width: 2.5),
          boxShadow: p.shadowHover,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DoodleIcon(tool.icon, size: 40, color: p.ink),
            const SizedBox(height: 10),
            Text(
              tool.title,
              style: TextStyle(
                fontSize: 16,
                color: p.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tool.open.mode == OpenMode.external
                  ? '这个工具是另一个 App，会用系统方式打开。'
                  : '这个工具会在浏览器里打开。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: p.inkSoft),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('知道了'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('打开'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
