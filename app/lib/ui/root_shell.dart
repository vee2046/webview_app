/// 根外壳 —— 底部导航（最近 / 小工具 / 我的）。
///
/// 首屏落在「最近」；工具详情用 push 路由，进入后 chrome 由工具自己决定。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/config_store.dart';
import '../data/data_transfer.dart';
import '../config/config_diff.dart';
import '../data/usage_store.dart';
import '../data/view_prefs.dart';
import '../icons/doodle_icons.dart';
import '../model/app_config.dart';
import '../theme/paper_theme.dart';
import '../util/native_toast.dart';
import 'recent_page.dart';
import 'settings_page.dart';
import 'tool_detail_page.dart';
import 'tools_page.dart';
import 'widgets/edge_back.dart';

class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.configStore,
    required this.usage,
    required this.viewPrefs,
    required this.darkMode,
    required this.onDarkModeChanged,
  });

  final ConfigStore configStore;
  final UsageStore usage;
  final ViewPrefs viewPrefs;
  final bool darkMode;
  final void Function(bool dark) onDarkModeChanged;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late int _index;

  /// 「再划一次退出」：第一次边缘滑动后置位，第二次滑动才真的退出。
  bool _exitArmed = false;
  Timer? _exitTimer;

  /// 边缘返回手势的提示窗口（秒）。
  static const int _exitConfirmWindow = 3;

  /// 已经喂给 [ViewPrefs] 的配置默认值（避免重复喂）。
  String? _appliedLayout;

  /// 配置和视图偏好都要能触发重建 —— 合成一个 Listenable 一起听。
  late final Listenable _listenable;

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _listenable = Listenable.merge([widget.configStore, widget.viewPrefs]);
    _exitTimer = null;
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
      listenable: _listenable,
      builder: (context, _) {
        final config = widget.configStore.config;
        if (config == null) {
          return Scaffold(
            backgroundColor: context.paper.paper,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final nav = config.app.bottomNav;

        // 配置里的 `app.home.layout` 是**默认值**；
        // 用户在顶栏手动切过就以用户的选择为准。
        // ⚠️ 不能在这里直接 setConfigDefault —— 它会 notifyListeners，
        //    在 build 期间通知会触发「setState during build」。
        //    所以丢到下一帧。
        final layout = config.app.home.layout;
        if (layout != _appliedLayout) {
          _appliedLayout = layout;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.viewPrefs.setConfigDefault(ViewMode.fromName(layout));
          });
        }

        return Scaffold(
          backgroundColor: context.paper.paper,
          body: SafeArea(
            bottom: false,
            // 左边缘右滑 = 返回（小工具/我的 → 最近；最近 → 再划一次退出）
            child: EdgeBackGesture(
              onBack: () => _handleEdgeBack(config),
              child: IndexedStack(
              index: _index.clamp(0, nav.isEmpty ? 0 : nav.length - 1),
              children: [
                RecentPage(
                  config: config,
                  usage: widget.usage,
                  viewPrefs: widget.viewPrefs,
                  onOpenTool: _openTool,
                  onOpenTools: () => _selectTab(config, 'tools'),
                ),
                ToolsPage(
                  config: config,
                  usage: widget.usage,
                  viewPrefs: widget.viewPrefs,
                  onOpenTool: _openTool,
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

  /// 左边缘右滑 = 返回。
  ///
  /// - 不在「最近」页 → 切回「最近」页
  /// - 已在「最近」页 → 第一次提示「再划一次退出」，3 秒内再划一次才退出 App
  void _handleEdgeBack(AppConfig config) {
    final nav = config.app.bottomNav;
    final recentId =
        config.app.recent.isDefaultTab == true ? 'recent' : 'tools';
    final recentIndex = _indexOf(nav, recentId);

    if (_index != recentIndex) {
      setState(() => _index = recentIndex);
      return;
    }

    if (_exitArmed) {
      _exitArmed = false;
      _exitTimer?.cancel();
      SystemNavigator.pop();
      return;
    }

    _exitArmed = true;
    _exitTimer?.cancel();
    _exitTimer = Timer(
      const Duration(seconds: _exitConfirmWindow),
      () => _exitArmed = false,
    );
    NativeToast.show(context, '再划一次退出');
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

