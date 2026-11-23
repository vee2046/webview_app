/// 最近页 —— App 首屏。
///
/// 三个区块（顺序即优先级）：
///   1. 续接卡  —— 上次干到哪儿（唯一「能立刻继续干活」的地方）
///   2. 常用    —— 用户手动置顶
///   3. 时间线  —— 今天 / 昨天 / 本周 / 更早
///
/// 首次安装时首屏是空的 → 走空状态（推荐工具 + 去工具箱的出口），绝不留白。
library;

import 'package:flutter/material.dart';

import '../data/resume_reader.dart';
import '../data/usage_store.dart';
import '../data/view_prefs.dart';
import '../icons/doodle_icons.dart';
import '../model/app_config.dart';
import '../theme/paper_theme.dart';
import 'widgets/paper_widgets.dart';
import 'widgets/view_toggle.dart';

class RecentPage extends StatelessWidget {
  const RecentPage({
    super.key,
    required this.config,
    required this.usage,
    required this.viewPrefs,
    this.resumeReader,
    this.onOpenTool,
    this.onOpenTools,
  });

  final AppConfig config;
  final UsageStore usage;
  final ViewPrefs viewPrefs;
  final ResumeReader? resumeReader;
  final void Function(ToolConfig tool)? onOpenTool;
  final VoidCallback? onOpenTools;

  @override
  Widget build(BuildContext context) {
    final recent = config.app.recent;
    final tools = config.visibleTools;


    // ── 续接卡：最近一个「有摘要」的工具 ─────────────────────────
    ToolConfig? resumeTool;
    ResumeSummary? resumeSummary;
    for (final id in usage.recentToolIds) {
      final tool = config.toolById(id);
      if (tool == null || !tool.resume.enabled) continue;
      final summary = (resumeReader ?? ResumeReader())
          .summarize(tool, usage.snapshotOf(id));
      if (summary.available) {
        resumeTool = tool;
        resumeSummary = summary;
        break;
      }
      resumeTool ??= tool;
      resumeSummary ??= summary;
    }
    final ToolConfig? resume = resumeTool;

    // ── 常用 ────────────────────────────────────────────────────
    final pinned = <ToolConfig>[
      for (final id in usage.pinned)
        if (config.toolById(id) != null) config.toolById(id)!,
    ];

    final timeline = recent.showTimeline
        ? usage.timelineByGroups(recent.timelineGroups)
        : const <String, List<UsageRecord>>{};

    final isEmpty = usage.history.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _RecentAppBar(
          app: config.app,
          showGreeting: recent.showGreeting,
          mode: viewPrefs.mode,
          onToggleView: () => viewPrefs.toggle(),
        ),
        if (recent.showTodayCount) ...[
          const SizedBox(height: 6),
          _TodayCount(usage: usage),
        ],
        if (isEmpty)
          _EmptyRecent(
            app: config.app,
            config: config,
            tools: tools,
            onOpenTool: onOpenTool,
            onOpenTools: onOpenTools,
          )
        else ...[
          if (recent.showResumeCard && resume != null) ...[
            const SizedBox(height: 16),
            SectionLabel('接着干'),
            _ResumeCard(
              tool: resume,
              summary: resumeSummary,
              color: tabColorOf(config, resume.tab, context.paper.crayonAmber),
              onTap: () => onOpenTool?.call(resume),
            ),
          ],
          if (recent.showPinned && pinned.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionLabel('常用'),
            _PinnedRow(
              tools: pinned,
              colorOf: (t) => tabColorOf(config, t.tab, context.paper.crayonAmber),
              onOpenTool: onOpenTool,
            ),
          ],
          if (recent.showTimeline) ...[
            const SizedBox(height: 18),
            for (final entry in timeline.entries)
              if (entry.value.isNotEmpty) ...[
                SectionLabel(entry.key),
                if (viewPrefs.isGrid)
                  _timelineGrid(
                    config,
                    entry.value.take(recent.maxTimelineItems).toList(),
                    onOpenTool,
                    context.paper.crayonAmber,
                  )
                else
                  for (final record in entry.value.take(recent.maxTimelineItems))
                    _TimelineRow(
                      tool: config.toolById(record.toolId),
                      color: tabColorOf(
                        config,
                        config.toolById(record.toolId)?.tab,
                        context.paper.crayonAmber,
                      ),
                      record: record,
                      onTap: onOpenTool == null
                          ? null
                          : () {
                              final t = config.toolById(record.toolId);
                              if (t != null) onOpenTool!(t);
                            },
                    ),
              ],
          ],
        ],
      ],
    );
  }

  /// 时间线在「卡片」排版下的样子 —— 每组两张一行。
  Widget _timelineGrid(
    AppConfig config,
    List<UsageRecord> records,
    void Function(ToolConfig tool)? onOpenTool,
    Color fallback,
  ) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.12,
      children: [
        for (final record in records)
          _TimelineCard(
            tool: config.toolById(record.toolId),
            color: tabColorOf(
              config,
              config.toolById(record.toolId)?.tab,
              fallback,
            ),
            record: record,
            onTap: onOpenTool == null
                ? null
                : () {
                    final t = config.toolById(record.toolId);
                    if (t != null) onOpenTool(t);
                  },
          ),
      ],
    );
  }
}

// ── 顶部栏 ────────────────────────────────────────────────────

class _RecentAppBar extends StatelessWidget {
  const _RecentAppBar({
    required this.app,
    required this.showGreeting,
    required this.mode,
    required this.onToggleView,
  });

  final AppMeta app;
  final bool showGreeting;
  final ViewMode mode;
  final VoidCallback onToggleView;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了';
    if (h < 11) return '早上好';
    if (h < 14) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }


  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                showGreeting ? _greeting : app.name,
                style: TextStyle(
                  fontSize: 26,
                  height: 1.2,
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                showGreeting ? app.brandSub : app.appName,
                style: TextStyle(fontSize: 12.5, color: p.inkSoft),
              ),
            ],
          ),
        ),
        // 顶栏右侧**只有一个**图标：网格 ⇄ 列表。
        // （原来这里是「设置」跳到「我的」页 —— 底部导航本来就有「我的」，功能重复。）
        ViewToggleButton(mode: mode, onToggle: onToggleView),
      ],
    );
  }
}

// ── 今日统计 ──────────────────────────────────────────────────

class _TodayCount extends StatelessWidget {
  const _TodayCount({required this.usage});

  final UsageStore usage;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    final streak = usage.streakDays;
    return Row(
      children: [
        Text(
          '今天打开过 ${usage.todayCount} 个工具',
          style: TextStyle(fontSize: 12.5, color: p.inkSoft),
        ),
        if (streak > 0) ...[
          Text(' · ', style: TextStyle(fontSize: 12.5, color: p.inkSoft)),
          Text(
            '已连续使用 $streak 天',
            style: TextStyle(fontSize: 12.5, color: p.crayonAmber),
          ),
        ],
      ],
    );
  }
}

// ── 续接卡 ────────────────────────────────────────────────────

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.tool,
    required this.summary,
    required this.color,
    this.onTap,
  });

  final ToolConfig tool;
  final ResumeSummary? summary;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return PaperCard(
      onTap: onTap,
      tiltSeed: tool.id,
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.ink, width: 2),
            ),
            alignment: Alignment.center,
            child: DoodleIcon(tool.icon, size: 26, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tool.title,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.25,
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary?.available == true
                      ? (summary!.detail ?? summary!.text)
                      : '还没开始',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: summary?.available == true ? p.inkSoft : p.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: p.inkSoft),
        ],
      ),
    );
  }
}

// ── 常用 ──────────────────────────────────────────────────────

class _PinnedRow extends StatelessWidget {
  const _PinnedRow({
    required this.tools,
    required this.colorOf,
    this.onOpenTool,
  });

  final List<ToolConfig> tools;
  final Color Function(ToolConfig tool) colorOf;
  final void Function(ToolConfig tool)? onOpenTool;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tools.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final tool = tools[i];
          final color = colorOf(tool);
          return InkWell(
            onTap: onOpenTool == null ? null : () => onOpenTool!(tool),
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 62,
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.paper.ink, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: DoodleIcon(tool.icon, size: 26, color: color),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    tool.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.paper.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── 时间线 ────────────────────────────────────────────────────

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.tool,
    required this.color,
    required this.record,
    this.onTap,
  });

  final ToolConfig? tool;
  final Color color;
  final UsageRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    if (tool == null) return const SizedBox.shrink();
    final hh = record.at.hour.toString().padLeft(2, '0');
    final mm = record.at.minute.toString().padLeft(2, '0');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.ink, width: 1.8),
              ),
              alignment: Alignment.center,
              child: DoodleIcon(tool!.icon, size: 17, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tool!.title,
                    style: TextStyle(fontSize: 13.5, color: p.ink),
                  ),
                  if (record.summary != null && record.summary!.isNotEmpty)
                    Text(
                      record.summary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: p.inkSoft),
                    ),
                ],
              ),
            ),
            Text(
              '$hh:$mm',
              style: TextStyle(
                fontSize: 11,
                color: p.inkSoft,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 空状态 ────────────────────────────────────────────────────

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent({
    required this.app,
    required this.config,
    required this.tools,
    this.onOpenTool,
    this.onOpenTools,
  });

  final AppMeta app;
  final AppConfig config;
  final List<ToolConfig> tools;
  final void Function(ToolConfig tool)? onOpenTool;
  final VoidCallback? onOpenTools;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    final suggested = <ToolConfig>[
      for (final t in tools)
        if (t.featured) t,
    ];
    final list = suggested.isEmpty ? tools.take(4).toList() : suggested.take(4).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: p.inkSoft.withValues(alpha: 0.5),
                width: 2.2,
              ),
            ),
            alignment: Alignment.center,
            child: DoodleIcon('box', size: 52, color: p.inkSoft),
          ),
          const SizedBox(height: 18),
          Text(
            '还没有使用记录',
            style: TextStyle(fontSize: 17, color: p.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '挑一个开始吧\n之后这里会记住你干到哪儿',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.6, color: p.inkSoft),
          ),
          if (list.isNotEmpty) ...[
            const SizedBox(height: 22),
            _PinnedRow(
              tools: list,
              colorOf: (t) => tabColorOf(config, t.tab, context.paper.crayonAmber),
              onOpenTool: onOpenTool,
            ),
          ],
          if (onOpenTools != null) ...[
            const SizedBox(height: 18),
            PaperButton(
              label: '去工具箱逛逛 ›',
              onPressed: onOpenTools,
              icon: 'grid',
              fill: p.paperCard,
            ),
          ],
        ],
      ),
    );
  }
}

// ── 工具 ──────────────────────────────────────────────────────

/// 分类色 —— 与小工具页保持一致：**按分类取色，不按工具取色**。
/// 找不到分类时退回琥珀色。
Color tabColorOf(AppConfig config, String? tabId, Color fallback) {
  if (tabId == null) return fallback;
  for (final tab in config.app.tabs) {
    if (tab.id == tabId) {
      return parseHexColor(tab.color) ?? fallback;
    }
  }
  return fallback;
}

/// `#6f9264` / `#6F9264` → Color
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
    s = s.split('').map((c) => '$c$c').join();
  }
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}


/// 时间线在「卡片」排版下的样子（[\_TimelineRow] 的竖版）。
class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.tool,
    required this.color,
    required this.record,
    this.onTap,
  });

  final ToolConfig? tool;
  final Color color;
  final UsageRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    if (tool == null) return const SizedBox.shrink();
    final hh = record.at.hour.toString().padLeft(2, '0');
    final mm = record.at.minute.toString().padLeft(2, '0');

    return PaperCard(
      onTap: onTap,
      tiltSeed: '${tool!.id}-${record.at.millisecondsSinceEpoch}',
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: p.ink, width: 1.8),
            ),
            alignment: Alignment.center,
            child: DoodleIcon(tool!.icon, size: 19, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            tool!.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.2,
              color: p.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (record.summary != null && record.summary!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              record.summary!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: p.inkSoft),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '$hh:$mm',
            style: TextStyle(
              fontSize: 10.5,
              color: p.inkSoft,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
