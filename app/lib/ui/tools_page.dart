import 'package:flutter/material.dart';

import '../data/usage_store.dart';
import '../data/view_prefs.dart';
import '../icons/doodle_icons.dart';
import '../model/app_config.dart';
import '../theme/paper_theme.dart';
import 'widgets/app_logo.dart';
import 'widgets/paper_widgets.dart';
import 'widgets/view_toggle.dart';

/// 小工具页 —— 完整清单，纯配置渲染。
///
/// 卡片数量 / 顺序 / 名称 / 图标 / 底色 / 角标全部来自
/// `config.app.tabs[]` 与 `config.tools[]`。
class ToolsPage extends StatefulWidget {
  const ToolsPage({
    super.key,
    required this.config,
    required this.usage,
    required this.viewPrefs,
    required this.onOpenTool,
  });

  final AppConfig config;
  final UsageStore usage;
  final ViewPrefs viewPrefs;
  final ValueChanged<ToolConfig> onOpenTool;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  String _tabId = 'all';
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ToolConfig> _visibleTools() {
    final all = widget.config.visibleTools;
    final byTab = _tabId == 'all'
        ? all
        : all.where((t) => t.tab == _tabId).toList();
    if (_query.trim().isEmpty) return byTab;
    final q = _query.trim().toLowerCase();
    return byTab
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.subtitle.toLowerCase().contains(q) ||
            t.id.toLowerCase().contains(q))
        .toList();
  }

  Color _colorOf(ToolConfig tool) {
    for (final tab in widget.config.app.tabs) {
      if (tab.id == tool.tab && tab.color != null) {
        return _parseHex(tab.color!);
      }
    }
    return context.paper.ink;
  }

  static Color _parseHex(String hex) {
    var v = hex.replaceAll('#', '').trim();
    if (v.length == 6) v = 'FF$v';
    final n = int.tryParse(v, radix: 16);
    return n == null ? const Color(0xFF2F2A24) : Color(n);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    final app = widget.config.app;
    final tools = _visibleTools();

    return Column(
      children: [
        _ToolsAppBar(
          title: app.name,
          subtitle: app.brandSub,
          logoPath: app.icon,
          mode: widget.viewPrefs.mode,
          onToggleView: () => widget.viewPrefs.toggle(),
        ),
        if (app.home.showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: _PaperSearchField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        _FilterTabs(
          tabs: app.tabs,
          selected: _tabId,
          onSelect: (id) => setState(() => _tabId = id),
        ),
        Expanded(
          child: tools.isEmpty
              ? _EmptyTools(query: _query)
              : (widget.viewPrefs.isGrid ? _grid(tools) : _list(tools)),
        ),
        if (t.isDark) const SizedBox.shrink(),
      ],
    );
  }

  /// 卡片（网格）排版。
  Widget _grid(List<ToolConfig> tools) {
    final app = widget.config.app;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: app.home.columns.clamp(1, 3),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.86,
      ),
      itemCount: tools.length,
      itemBuilder: (context, index) {
        final tool = tools[index];
        return _ToolCard(
          tool: tool,
          color: _colorOf(tool),
          onTap: () => widget.onOpenTool(tool),
          onLongPress: () => _showToolSheet(context, tool, _colorOf(tool)),
        );
      },
    );
  }

  /// 列表排版 —— 每行一个工具。
  Widget _list(List<ToolConfig> tools) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
      itemCount: tools.length,
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, index) {
        final tool = tools[index];
        return _ToolRow(
          tool: tool,
          color: _colorOf(tool),
          onTap: () => widget.onOpenTool(tool),
          onLongPress: () => _showToolSheet(context, tool, _colorOf(tool)),
        );
      },
    );
  }

  void _showToolSheet(BuildContext context, ToolConfig tool, Color color) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => _ToolSheet(tool: tool, color: color),
    );
  }
}

class _ToolsAppBar extends StatelessWidget {
  const _ToolsAppBar({
    required this.title,
    required this.subtitle,
    required this.logoPath,
    required this.mode,
    required this.onToggleView,
  });

  final String title;
  final String subtitle;

  /// 品牌图标路径（配置的 `app.icon`）。
  final String logoPath;
  final ViewMode mode;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Row(
        children: [
          // 品牌图标 —— 与桌面图标同一张 favicon（路径来自配置）
          AppLogo(path: logoPath, size: 32),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.15,
                    color: context.paper.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    color: context.paper.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          // 顶栏右侧**只有一个**图标：网格 ⇄ 列表。
          // （原来这里是「刷新配置」+「设置」，而「设置」会跳到「我的」页 ——
          //   底部导航本来就有「我的」，功能重复且混乱。）
          ViewToggleButton(mode: mode, onToggle: onToggleView),
        ],
      ),
    );
  }
}

class _PaperSearchField extends StatelessWidget {
  const _PaperSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    return Container(
      decoration: BoxDecoration(
        color: t.paperCard,
        border: Border.all(color: t.ink, width: t.lineWidth),
        borderRadius: BorderRadius.circular(16),
        boxShadow: t.shadowPaper,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          UiIcon('search', size: 16, color: t.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: 14, color: t.ink),
              cursorColor: t.ink,
              decoration: InputDecoration(
                isDense: true,
                // 外层已经有一圈墨线矩形边框（见上方 Container），
                // 这里必须把所有边框都关掉 —— 否则 enabledBorder / focusedBorder
                // 仍会从主题的 InputDecorationTheme 里补上来，外层就会出现两圈边。
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: '搜工具，比如「喝水」',
                hintStyle: TextStyle(fontSize: 13, color: t.inkSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<TabConfig> tabs;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 6),
              child: GestureDetector(
                onTap: () => onSelect(tab.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: tab.id == selected ? t.paperCard : Colors.transparent,
                    border: Border.all(
                      color: tab.id == selected ? t.ink : Colors.transparent,
                      width: t.lineWidth,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: tab.id == selected ? t.shadowPaper : null,
                  ),
                  child: Text(
                    tab.title,
                    style: TextStyle(
                      fontSize: 13,
                      color: tab.id == selected ? t.ink : t.inkSoft,
                      fontWeight: tab.id == selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.tool,
    required this.color,
    required this.onTap,
    required this.onLongPress,
  });

  final ToolConfig tool;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    final badge = tool.badge ??
        (tool.featured ? '推荐' : (tool.offline.enabled ? '离线' : null));

    return PaperCard(
      onTap: onTap,
      onLongPress: onLongPress,
      tiltSeed: tool.id,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  border: Border.all(color: t.ink, width: t.lineWidth),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: DoodleIcon(tool.icon, size: 24, color: color),
              ),
              if (badge != null)
                Positioned(
                  top: -8,
                  right: -10,
                  child: PaperBadge(
                    badge,
                    color: tool.featured ? t.crayonAmber : t.crayonGreen,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            tool.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              height: 1.25,
              color: t.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Text(
              tool.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 1.4, color: t.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTools extends StatelessWidget {
  const _EmptyTools({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UiIcon('toolbox', size: 40, color: t.inkSoft),
          const SizedBox(height: 12),
          Text(
            query.isEmpty ? '这一类还没有工具' : '没找到「$query」',
            style: TextStyle(fontSize: 15, color: t.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '换个分类，或去「最近」看看',
            style: TextStyle(fontSize: 12, color: t.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// 长按卡片 → 详情抽屉（来源 / 离线 / 数据归属 / 备份 / 收藏）。
class _ToolSheet extends StatelessWidget {
  const _ToolSheet({required this.tool, required this.color});

  final ToolConfig tool;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                color: t.inkSoft.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    border: Border.all(color: t.ink, width: t.lineWidth),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: DoodleIcon(tool.icon, size: 23, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.title,
                        style: TextStyle(
                          fontSize: 17,
                          color: t.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        tool.subtitle,
                        style: TextStyle(fontSize: 12, color: t.inkSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SheetRow(icon: 'wifi', label: '加载方式', value: '远端优先'),
          _SheetRow(
            icon: 'download',
            label: '离线副本',
            value: tool.offline.enabled ? '已缓存 ${tool.offline.size ?? ''}' : '无',
          ),
          _SheetRow(icon: 'lock', label: '数据存储', value: '本机 · 与网页版同源'),
          _SheetRow(icon: 'copy', label: '备份数据', value: '导出为 JSON'),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
            child: PaperButton(
              label: '加入常用',
              icon: 'pin',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.icon, required this.label, required this.value});

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x22000000))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      child: Row(
        children: [
          UiIcon(icon, size: 15, color: t.inkSoft),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: t.ink)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: t.inkSoft,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}


/// 列表排版的一行 —— 与 [\_ToolCard] 同一套视觉语言，只是横着排。
class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.tool,
    required this.color,
    required this.onTap,
    required this.onLongPress,
  });

  final ToolConfig tool;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.paper;
    final badge = tool.badge ??
        (tool.featured ? '推荐' : (tool.offline.enabled ? '离线' : null));

    return PaperCard(
      onTap: onTap,
      onLongPress: onLongPress,
      tiltSeed: tool.id,
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: t.ink, width: t.lineWidth),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: DoodleIcon(tool.icon, size: 22, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tool.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.2,
                    color: t.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tool.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, height: 1.3, color: t.inkSoft),
                ),
              ],
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            PaperBadge(
              badge,
              color: tool.featured ? t.crayonAmber : t.crayonGreen,
            ),
          ],
        ],
      ),
    );
  }
}
