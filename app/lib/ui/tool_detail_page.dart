/// 工具容器页 —— 承载 H5 的 WebView 壳。
///
/// 职责：
///   · chrome 四档（full / auto / minimal / immersive）—— 见 DESIGN §5.3
///   · 顶栏右侧只留一个 ⋯，12 个动作收进分组 Action Sheet —— 见 DESIGN §5.6
///   · 导出 = .json 文件 → 系统分享面板 —— 见 DESIGN §5.7
///   · 返回键默认不接管页面内路由 —— 见 DESIGN §5.5
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/downloader.dart';
import '../data/resume_reader.dart';
import '../data/share_image.dart';
import '../data/usage_store.dart';
import '../icons/doodle_icons.dart';
import '../model/app_config.dart';
import '../theme/paper_theme.dart';
import '../util/native_toast.dart';
import '../webview/km_bridge.dart';
import '../webview/webview_host.dart';
import 'recent_page.dart';
import 'share_preview_dialog.dart';
import 'widgets/share_card.dart';

class ToolDetailPage extends StatefulWidget {
  const ToolDetailPage({
    super.key,
    required this.tool,
    required this.config,
    required this.usage,
    this.onOpenTool,
    this.onExitTool,
    this.onHome,
  });

  final ToolConfig tool;
  final AppConfig config;
  final UsageStore usage;

  /// 从 H5 里 KM.openTool(id) 跳到另一个工具
  final void Function(ToolConfig tool)? onOpenTool;

  /// 返回键的最终落点（routeBackEnabled=false 时走这里）
  final VoidCallback? onExitTool;

  /// 「回工具箱」按钮
  final VoidCallback? onHome;

  @override
  State<ToolDetailPage> createState() => _ToolDetailPageState();
}

class _ToolDetailPageState extends State<ToolDetailPage>
    with WidgetsBindingObserver {
  late ChromeMode _chrome;
  late bool _immersiveRevealed = false;
  String _title = '';
  bool _barVisible = true;
  bool _chromePinned = false;

  /// 「自动隐藏」档的顶栏自动收起定时器（见 `autoHideDelayMs`）。
  Timer? _autoHideTimer;

  /// 站内 Service Worker 是否已注册成功（= 这个工具已经能离线打开）
  bool _offlineReady = false;

  /// 这个平台压根没有 Service Worker API（iOS 未验证 app-bound 域名时）。
  ///
  /// ⚠️ 与「注册失败」是两回事：iOS 的 WKWebView 只在 app-bound domain 里
  ///    才暴露 `navigator.serviceWorker`，没验证过就是 undefined，
  ///    离线能力**根本用不了**，重试多少次都没用。
  bool _offlineUnsupported = false;

  // ⚠️ 不要在这里存 WebViewController —— 控制器归 WebViewHost 所有，
  //    这里存一份只会拿到 null（曾经导致「刷新 / 导入 / 清除」全部静默失效）。
  //    要操作 WebView 一律走 _hostKey.currentState。

  ChromeMode get _effectiveChrome => _chromePinned ? ChromeMode.immersive : _chrome;

  /// 用来从外部拿到 WebViewHostState（退出前重采快照）。
  final GlobalKey<WebViewHostState> _hostKey = GlobalKey<WebViewHostState>();

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    _chrome = widget.tool.open.chrome;
    _title = widget.tool.title;
    _barVisible = _chrome != ChromeMode.immersive;
    // 自动隐藏档：顶栏不会一直压着内容，停手一会儿就自己收起来。
    if (_chrome == ChromeMode.auto) _scheduleAutoHide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoHideTimer?.cancel();
    _restoreSystemBars();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台时 WebView 还活着 —— 这是「用户操作完但还没退出工具」时唯一可靠的采集时机。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _captureSnapshot();
    }
  }

  // ── chrome 切换 ──────────────────────────────────────────────

  void _toggleFullscreen() {
    setState(() {
      _chromePinned = !_chromePinned;
      if (_chromePinned) {
        _immersiveRevealed = true;
      }
    });
    _applySystemBars();
  }

  void _applySystemBars() {
    final hide = _effectiveChrome == ChromeMode.immersive &&
        widget.config.webview.chrome.hideSystemBars;
    SystemChrome.setEnabledSystemUIMode(
      hide ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _restoreSystemBars() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ── 返回键 ────────────────────────────────────────────────────

  /// `routeBackEnabled=false`（默认）→ 直接回 App 根页面，不碰 H5 路由。
  Future<void> _handleBack() async {
    final open = widget.tool.open;
    if (open.routeBackEnabled) {
      final host = _hostKey.currentState;
      if (host != null && await host.canGoBack()) {
        await host.goBack();
        return;
      }
    }
    // 离开前重采一次 localStorage 快照（否则续接卡永远停在打开时那一刻的状态）。
    await _captureSnapshot();
    if (open.backFallback == BackFallback.exit) {
      widget.onExitTool?.call();
      return;
    }
    widget.onHome?.call();
  }

  /// 重新采集该工具的 localStorage 快照。
  Future<void> _captureSnapshot() async {
    try {
      // 必须加超时：WebView 异常时不能让「返回键」卡住不动。
      await _hostKey.currentState
          ?.refreshSnapshot()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // 采集失败不影响用户操作，静默忽略。
    }
  }

  /// 「回最近」入口（沉浸式工具栏的主页按钮）。
  Future<void> _leaveHome() async {
    await _captureSnapshot();
    widget.onHome?.call();
  }

  // ── 快照 ──────────────────────────────────────────────────────

  void _onSnapshot(Map<String, dynamic> snapshot) {
    widget.usage.saveSnapshot(widget.tool.id, snapshot);
  }

  /// 下拉刷新：重新加载当前页。
  void _reloadPage() {
    if (!mounted) return;
    NativeToast.show(context, '正在刷新…');
    _hostKey.currentState?.reload();
  }

  /// Service Worker 状态（从页面直读，不依赖 JS channel）。
  void _onServiceWorkerState(String state) {
    final ready = state.startsWith('ready');
    final unsupported = state == 'unsupported';
    debugPrint('[SW] 状态=$state');
    if (mounted && (ready != _offlineReady || unsupported != _offlineUnsupported)) {
      setState(() {
        _offlineReady = ready;
        _offlineUnsupported = unsupported;
      });
    }
  }

  void _onBridgeMessage(KmHostMessage msg) {
    switch (msg.action) {
      case 'setTitle':
        if (msg.title.isNotEmpty) {
          setState(() => _title = msg.title);
        }
      case 'openTool':
        final target = widget.config.toolById(msg.id);
        if (target != null) widget.onOpenTool?.call(target);
      case 'edgeSwipe':
        // 沉浸式档：页面里检测到「顶部边缘下滑」→ 唤出工具栏。
        if (mounted && widget.tool.open.chrome == ChromeMode.immersive) {
          setState(() => _immersiveRevealed = true);
        }
      case 'pullToRefresh':
        // 页面里检测到「下拉刷新」手势 → 重新加载当前页
        _reloadPage();
      case 'swReady':
        // 站内 Service Worker 注册成功 → 这个工具已经能离线打开
        debugPrint('[SW] 注册成功 scope=${msg.payload['scope']}');
        if (mounted) {
          setState(() => _offlineReady = true);
        }
      case 'swUnavailable':
        // 注册失败 —— 常见于 iOS：WKWebView 只在「已验证的 app-bound domain」
        // 里才暴露 Service Worker API，没验证过就是 undefined。
        debugPrint('[SW] 注册失败：${msg.payload['reason']}');
        if (mounted) {
          setState(() => _offlineUnsupported = true);
        }
      case 'toast':
        final m = msg.message;
        if (m.isNotEmpty) {
          _toast(m);
        }
      case 'share':
        _shareText(msg.url.isEmpty ? widget.tool.url : msg.url,
            msg.title.isEmpty ? widget.tool.title : msg.title);
      case 'vibrate':
        HapticFeedback.lightImpact();
      case 'exportData':
        _exportToolData();
      case 'importData':
        _importToolData();
      case 'downloadLink':
        // 页面里点了 <a download="文件名"> → 走下载流程（带文件名）
        final dlUrl = msg.payload['url']?.toString() ?? '';
        if (dlUrl.isEmpty) break;
        final dlName = msg.payload['name']?.toString() ?? '';
        _startDownload(dlUrl, suggestedName: dlName.isEmpty ? null : dlName);
      case 'blobData':
        _handleBlobData(msg);
      case 'setResumeState':
        final s = msg.summary;
        if (s.isNotEmpty) {
          widget.usage.updateSummary(widget.tool.id, s);
        }
    }
  }

  void _onScrollDirection(String dir) {
    if (_chrome != ChromeMode.auto) return;
    _autoHideTimer?.cancel();
    final want = dir == 'up';
    if (want != _barVisible && mounted) setState(() => _barVisible = want);
    // 「自动隐藏」档：顶栏不能一直压着内容 —— 停止滚动 autoHideDelayMs 后自己收起来。
    if (_barVisible) _scheduleAutoHide();
  }

  /// 安排顶栏在 `autoHideDelayMs` 之后自动隐藏。
  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    final delay = widget.config.webview.chrome.autoHideDelayMs;
    if (delay <= 0) return;
    _autoHideTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      if (_chrome == ChromeMode.auto && _barVisible) {
        setState(() => _barVisible = false);
      }
    });
  }

  // ── ⋯ 溢出菜单 ───────────────────────────────────────────────

  List<_OverflowAction> get _actions {
    final all = <_OverflowAction>[
      _OverflowAction('reload', '刷新页面', 'refresh', _groupPage),
      _OverflowAction('copyLink', '复制链接', 'copy', _groupPage),
      _OverflowAction('openInBrowser', '在浏览器中打开', 'globe', _groupPage),
      _OverflowAction('share', '分享', 'share', _groupPage),
      _OverflowAction('fullscreen', '全屏浏览', 'fullscreen', _groupDisplay),
      _OverflowAction('shareCard', '生成分享长图', 'image', _groupDisplay),
      _OverflowAction('pin', '固定到常用', 'pin', _groupDisplay),
      _OverflowAction('exportData', '导出这个工具的数据', 'download', _groupData),
      _OverflowAction('importData', '导入数据', 'upload', _groupData),
      _OverflowAction('clearData', '清除这个工具的数据', 'trash', _groupData,
          danger: true),
      _OverflowAction('about', '关于这个工具', 'info', null),
      _OverflowAction('feedback', '反馈问题', 'mail', null),
    ];
    final allowed = widget.tool.open.overflowItems;
    if (allowed.isEmpty) return all;
    return all.where((a) => allowed.contains(a.id)).toList();
  }

  static const _groupPage = '页面';
  static const _groupDisplay = '显示';
  static const _groupData = '数据';

  Future<void> _showOverflow() async {
    final actions = _actions;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.86,
      ),
      builder: (_) => _OverflowSheet(
        tool: widget.tool,
        actions: actions,
        pinned: widget.usage.isPinned(widget.tool.id),
      ),
    );
    if (picked == null || !mounted) return;
    await _runAction(picked);
  }

  Future<void> _runAction(String id) async {
    switch (id) {
      case 'reload':
        await _hostKey.currentState?.reload();
      case 'copyLink':
        await Clipboard.setData(ClipboardData(text: widget.tool.url));
        _toast('链接已复制');
      case 'openInBrowser':
        await _openExternally(widget.tool.url);
      case 'share':
        await _shareText(widget.tool.url, _title);
      case 'fullscreen':
        _toggleFullscreen();
      case 'shareCard':
        await _shareToolCard();
      case 'pin':
        await widget.usage.togglePin(widget.tool.id);
        if (mounted) {
          setState(() {});
          _toast(widget.usage.isPinned(widget.tool.id) ? '已固定到常用' : '已取消固定');
        }
      case 'exportData':
        await _exportToolData();
      case 'importData':
        await _importToolData();
      case 'clearData':
        await _confirmClearData();
      case 'about':
        await _showAbout();
      case 'feedback':
        await _openExternally(
          '${widget.config.about.repo}/issues/new?title=${Uri.encodeComponent(widget.tool.title)}',
        );
    }
  }

  /// 生成分享长图：把这个工具的摘要做成一张纸片海报。
  ///
  /// ⚠️ 长图里画的是 **App 自己知道的数据**（摘要 / 分类 / 存储位置），
  /// 不是网页截图 —— WebView 是 PlatformView，系统截图抓不到 H5 内容。
  Future<void> _shareToolCard() async {
    if (!mounted) return;
    final tool = widget.tool;
    final color = tabColorOf(widget.config, tool.tab, context.paper.crayonBlue);
    final summary = ResumeReader()
        .summarize(tool, widget.usage.snapshotOf(tool.id));
    final tab = widget.config.app.tabs
        .where((t) => t.id == tool.tab)
        .map((t) => t.title)
        .firstOrNull;
    final streak = widget.usage.streakDays;

    final ok = await showSharePreview(
      context,
      fileName: ShareImage.fileName('tool-${tool.id}', DateTime.now()),
      text: '${tool.title} · kmlab Toolbox',
      hint: '长图里是 App 侧的数据摘要（网页内容不会被截图）',
      cardBuilder: (w) => ShareReportCard(
        width: w,
        logoPath: widget.config.app.icon,
        title: tool.title,
        subtitle: tool.subtitle,
        iconName: tool.icon,
        accent: color,
        badge: streak > 0 ? '连续 $streak 天' : null,
        rows: [
          ShareRow(icon: 'clock', label: '最近进度', value: summary.text),
          ShareRow(icon: 'grid', label: '分类', value: tab ?? '未分类'),
          ShareRow(
            icon: 'lock',
            label: '数据存储',
            value: '本机 · 与网页版同源',
          ),
          ShareRow(
            icon: 'wifi',
            label: '离线可用',
            value: _offlineReady ? '断网也能打开' : '需要联网',
            valueColor: _offlineReady ? context.paper.crayonGreen : null,
          ),
          ShareRow(icon: 'link', label: '地址', value: tool.url),
        ],
        footerNote: '数据存在这台设备的浏览器存储里，与网页版共享同一份。'
            '换机可在「我的 → 离线与数据」导出备份。',
      ),
    );
    if (!ok && mounted) _toast('已取消分享');
  }

  void _toast(String msg) {
    if (!mounted) return;
    // 用系统 Toast 而不是 SnackBar —— WebView 是 PlatformView，会把 Flutter 的
    // SnackBar 整个盖住，看起来就像「提示压根没弹出来」。
    NativeToast.show(context, msg);
  }

  Future<void> _openExternally(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('没有找到能打开它的 App');
    }
  }

  /// 站外链接 / 非 http 协议 → 交给系统处理，并给用户一个明确反馈。
  ///
  /// 没有反馈的话，用户点了链接看到「页面没动」会以为 App 卡了。
  Future<void> _handleExternalLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) {
      _toast('没有找到能打开它的 App');
      return;
    }
    final host = uri.host.isEmpty ? '' : uri.host;
    _toast(host.isEmpty ? '已交给系统打开' : '已用浏览器打开 $host');
  }

  /// 页面点了「下载」→ 真的把文件存下来，再走系统分享面板。
  /// blob 下载要绕一圈（页面转 data URL 再回来），先把文件名存着。
  String? _pendingDownloadName;

  Future<void> _startDownload(String url, {String? suggestedName}) async {
    _pendingDownloadName = suggestedName;
    if (!mounted) return;
    if (url.startsWith('data:')) {
      await _downloadDataUrl(url, suggestedName: suggestedName);
      return;
    }
    if (url.startsWith('blob:')) {
      // blob 的字节只有页面自己读得到 → 让页面转成 data URL 再回来
      _toast('正在准备文件…');
      try {
        await _hostKey.currentState?.runScript(KmBridge.blobToDataUrlScript(url));
      } catch (_) {
        _toast('这个文件读不出来');
      }
      return;
    }
    _toast('正在下载…');
    final result = await AppDownloader.downloadFromUrl(url, suggestedName: suggestedName);
    if (!mounted) return;
    await _afterDownload(result);
  }

  /// 页面把 blob 转成 data URL 之后的回调。
  Future<void> _handleBlobData(KmHostMessage msg) async {
    final err = msg.payload['error']?.toString();
    final dataUrl = msg.payload['dataUrl']?.toString();
    if (err != null && err.isNotEmpty) {
      _toast('这个文件读不出来');
      return;
    }
    if (dataUrl == null || dataUrl.isEmpty) return;
    final result = await AppDownloader.downloadFromDataUrl(
      dataUrl,
      suggestedName: _pendingDownloadName,
    );
    _pendingDownloadName = null;
    if (!mounted) return;
    await _afterDownload(result);
  }

  Future<void> _downloadDataUrl(String dataUrl, {String? suggestedName}) async {
    final result = await AppDownloader.downloadFromDataUrl(dataUrl, suggestedName: suggestedName);
    if (!mounted) return;
    await _afterDownload(result);
  }

  Future<void> _afterDownload(DownloadResult result) async {
    if (!mounted) return;
    if (!result.ok) {
      _toast(result.error ?? '下载失败');
      return;
    }
    _toast('已下载 ${result.fileName}');
    final path = result.filePath;
    if (path == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        title: widget.tool.title,
        text: '${widget.tool.title} 下载的文件',
      ),
    );
  }

  Future<void> _shareText(String url, String title) async {
    await SharePlus.instance.share(
      ShareParams(text: '$title\n$url', subject: title, title: title),
    );
  }

  // ── 导出 / 导入 / 清除 ────────────────────────────────────────

  Future<void> _exportToolData() async {
    final snapshot = widget.usage.snapshotOf(widget.tool.id);
    if (snapshot == null) {
      _toast('还没有数据可以导出');
      return;
    }
    final payload = <String, dynamic>{
      'toolId': widget.tool.id,
      'title': widget.tool.title,
      'version': widget.config.about.version,
      'exportedAt': DateTime.now().toIso8601String(),
      'storage': snapshot,
    };
    final dir = await getTemporaryDirectory();
    final name = widget.config.webview.dataTransfer
        .fileNameFor(widget.tool.id, DateTime.now());
    final file = File('${dir.path}/$name');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );

    final share = widget.config.webview.dataTransfer;
    if (share.exportDelivery == 'share') {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          title: widget.tool.title,
          text: '${widget.tool.title} 的数据备份',
        ),
      );
    } else {
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
      );
      _toast('数据已复制到剪贴板');
    }
  }

  Future<void> _importToolData() async {
    final dt = widget.config.webview.dataTransfer;
    if (!dt.importEnabled) return;
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      _toast('读不到这个文件');
      return;
    }
    if (bytes.length > dt.importMaxSizeMb * 1024 * 1024) {
      _toast('文件太大了（上限 ${dt.importMaxSizeMb} MB）');
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      _toast('这不是一个有效的备份文件');
      return;
    }
    if (decoded is! Map) {
      _toast('备份文件格式不对');
      return;
    }
    final storage = (decoded['storage'] as Map?)?.cast<String, dynamic>();
    if (storage == null) {
      _toast('备份文件里没有数据');
      return;
    }
    // 冲突策略
    final existing = widget.usage.snapshotOf(widget.tool.id) ?? <String, dynamic>{};
    final conflict = storage.keys.where(existing.containsKey).toList();
    if (conflict.isNotEmpty && dt.importConflictPolicy == 'confirm') {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('有冲突的数据'),
          content: Text(
            '${conflict.length} 项已存在的数据会被覆盖：\n${conflict.join('\n')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('覆盖'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await widget.usage.saveSnapshot(widget.tool.id, storage);
    // 同步回 WebView 的 localStorage（Dart 侧读不到 WebView 沙箱，只能让页面自己写）
    final host = _hostKey.currentState;
    for (final entry in storage.entries) {
      await host?.runScript(
        'localStorage.setItem(${jsonEncode(entry.key)}, ${jsonEncode(jsonEncode(entry.value))});',
      );
    }
    await host?.reload();
    _toast('数据已导入');
  }

  Future<void> _confirmClearData() async {
    final name = widget.tool.title;
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('清除「$name」的数据'),
        content: Text(
          '只清除 $name 这个工具的数据，不影响其它工具。\n\n'
          '建议先导出一份备份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'export'),
            child: const Text('先导出备份'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'clear'),
            child: Text(
              '清除',
              style: TextStyle(color: context.paper.crayonRed),
            ),
          ),
        ],
      ),
    );
    if (choice == 'export') {
      await _exportToolData();
      return;
    }
    if (choice != 'clear' || !mounted) return;

    // ⚠️ 所有工具共用同一个 origin（kmlab.tech），
    //    所以绝对不能用 localStorage.clear() —— 只能按 key 精确删除。
    final keys = widget.tool.resume.storageKeys;
    if (keys.isNotEmpty) {
      final js = keys
          .map((k) => 'localStorage.removeItem(${jsonEncode(k)});')
          .join('\n');
      await _hostKey.currentState?.runScript(js);
    }
    await widget.usage.clearSnapshot(widget.tool.id);
    await widget.usage.updateSummary(widget.tool.id, '');
    await _hostKey.currentState?.reload();
    _toast('已清除「$name」的数据');
  }

  Future<void> _showAbout() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AboutSheet(
        tool: widget.tool,
        config: widget.config,
        offlineReady: _offlineReady,
        offlineUnsupported: _offlineUnsupported,
      ),
    );
  }

  // ── 构建 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    final chrome = _effectiveChrome;

    // `webview.handleHardwareBack` = false ⇒ **不接管**返回键，
    // 交给系统默认行为（弹掉路由回到上一个页面）；
    // true ⇒ App 接管，走 `backFallback`（home / exit）。
    return PopScope(
      canPop: !widget.config.webview.handleHardwareBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: p.paper,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (chrome == ChromeMode.full)
                _FullTopBar(
                  title: _title,
                  url: widget.tool.url,
                  onBack: _handleBack,
                  onOverflow: _showOverflow,
                ),
              if (chrome == ChromeMode.minimal)
                _MinimalTopBar(
                  onBack: _handleBack,
                  onOverflow: _showOverflow,
                ),
              if (chrome == ChromeMode.auto)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: _barVisible ? 44 : 0,
                  child: _barVisible
                      ? _FullTopBar(
                          title: _title,
                          url: widget.tool.url,
                          onBack: _handleBack,
                          onOverflow: _showOverflow,
                          compact: true,
                        )
                      : const SizedBox.shrink(),
                ),
              // immersive 档：工具栏必须「浮在 WebView 之上」，
              // 绝不能作为 Column 的直接子节点 —— Column 子节点高度无界，
              // 内部 Stack 会拿到 constraints.biggest = Size(w, infinity)，
              // 断言失败把整棵布局炸掉（WebView 变成 0x0 → 整页白屏）。
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: WebViewHost(
                        key: _hostKey,
                        tool: widget.tool,
                        config: widget.config,
                        chrome: _effectiveChrome,
                        onTitleChanged: (t) {
                          if (t.isNotEmpty && mounted) {
                            setState(() => _title = t);
                          }
                        },
                        onSnapshot: _onSnapshot,
                        onBridgeMessage: _onBridgeMessage,
                        onServiceWorkerState: _onServiceWorkerState,
                        onScrollDirection: _onScrollDirection,
                        onExternalLink: _handleExternalLink,
                        onDownloadRequested: _startDownload,
                      ),
                    ),
                    if (chrome == ChromeMode.immersive)
                      Positioned.fill(
                        child: _ImmersiveLayer(
                          revealed: _immersiveRevealed,
                          hotZoneHeight: widget
                              .config.webview.chrome.immersiveTopHotZonePx,
                          onReveal: () => setState(() => _immersiveRevealed = true),
                          onHide: () => setState(() => _immersiveRevealed = false),
                          onBack: _handleBack,
                          onOverflow: _showOverflow,
                          title: _title,
                        ),
                      ),
                  ],
                ),
              ),
              if (chrome == ChromeMode.full)
                _FullBottomBar(
                  onReload: () => _hostKey.currentState?.reload(),
                  onShare: () => _shareText(widget.tool.url, _title),
                  onHome: _leaveHome,
                  onBrowser: () => _openExternally(widget.tool.url),
                  onOverflow: _showOverflow,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 顶栏 ──────────────────────────────────────────────────────

class _MinimalTopBar extends StatelessWidget {
  const _MinimalTopBar({required this.onBack, required this.onOverflow});

  final VoidCallback onBack;
  final VoidCallback onOverflow;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.ink, width: 2.5)),
      ),
      child: Row(
        children: [
          _CircleButton(icon: 'back', onTap: onBack),
          const Spacer(),
          _CircleButton(icon: 'more', onTap: onOverflow),
        ],
      ),
    );
  }
}

class _FullTopBar extends StatelessWidget {
  const _FullTopBar({
    required this.title,
    required this.url,
    required this.onBack,
    required this.onOverflow,
    this.compact = false,
  });

  final String title;
  final String url;
  final VoidCallback onBack;
  final VoidCallback onOverflow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return Container(
      height: compact ? 44 : 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.ink, width: 2.5)),
      ),
      child: Row(
        children: [
          _CircleButton(icon: 'back', onTap: onBack),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.2,
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!compact)
                  Text(
                    url.replaceFirst('https://', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: p.inkSoft),
                  ),
              ],
            ),
          ),
          _CircleButton(icon: 'more', onTap: onOverflow),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  /// 图标是纯 SVG 线稿，没有可读文字 → 补一条无障碍标签，读屏软件才念得出来。
  static const Map<String, String> _labels = {
    'back': '返回',
    'more': '更多',
    'close': '关闭',
    'home': '回最近页',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return Semantics(
      button: true,
      label: _labels[icon] ?? icon,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.paperCard,
            border: Border.all(color: p.ink, width: 2),
          ),
          alignment: Alignment.center,
          child: UiIcon(icon, size: 15, color: p.ink),
        ),
      ),
    );
  }
}

// ── immersive 层 ──────────────────────────────────────────────

class _ImmersiveLayer extends StatelessWidget {
  const _ImmersiveLayer({
    required this.revealed,
    required this.hotZoneHeight,
    required this.onReveal,
    required this.onHide,
    required this.onBack,
    required this.onOverflow,
    required this.title,
  });

  final bool revealed;

  /// 顶部热区高度（来自 `webview.chrome.immersiveTopHotZonePx`）。
  final double hotZoneHeight;
  final VoidCallback onReveal;
  final VoidCallback onHide;
  final VoidCallback onBack;
  final VoidCallback onOverflow;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return Stack(
      children: [
        // 顶部热区 —— iOS 没有硬件返回键，这是唯一的逃生通道
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ImmersiveHotZone(
            height: hotZoneHeight,
            hintVisible: !revealed,
            onReveal: revealed ? null : onReveal,
          ),
        ),
        if (revealed)
          Positioned(
            top: 34,
            left: 0,
            right: 0,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: p.paper.withValues(alpha: 0.96),
              child: Row(
                children: [
                  _CircleButton(icon: 'back', onTap: onBack),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: p.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _CircleButton(icon: 'more', onTap: onOverflow),
                  _CircleButton(icon: 'close', onTap: onHide),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── 底部条（full 档） ──────────────────────────────────────────

class _FullBottomBar extends StatelessWidget {
  const _FullBottomBar({
    required this.onReload,
    required this.onShare,
    required this.onHome,
    required this.onBrowser,
    required this.onOverflow,
  });

  final VoidCallback onReload;
  final VoidCallback onShare;
  final VoidCallback? onHome;
  final VoidCallback onBrowser;
  final VoidCallback onOverflow;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    Widget item(String icon, String label, VoidCallback? onTap) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiIcon(icon, size: 19, color: p.ink),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 10.5, color: p.inkSoft),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.ink, width: 2),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          item('refresh', '刷新', onReload),
          item('share', '分享', onShare),
          item('home', '回最近', onHome),
          item('globe', '浏览器', onBrowser),
          item('more', '更多', onOverflow),
        ],
      ),
    );
  }
}

// ── ⋯ 溢出菜单 ─────────────────────────────────────────────────

class _OverflowAction {
  const _OverflowAction(
    this.id,
    this.label,
    this.icon,
    this.group, {
    this.danger = false,
  });

  final String id;
  final String label;
  final String icon;
  final String? group;
  final bool danger;
}

class _OverflowSheet extends StatelessWidget {
  const _OverflowSheet({
    required this.tool,
    required this.actions,
    required this.pinned,
  });

  final ToolConfig tool;
  final List<_OverflowAction> actions;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    // 按分组归拢，保留顺序；无分组的单独成组（不显示标题）
    final grouped = <String?, List<_OverflowAction>>{};
    for (final a in actions) {
      grouped.putIfAbsent(a.group, () => <_OverflowAction>[]).add(a);
    }

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: p.paperCard,
          borderRadius: paperBorderRadius(20, alternate: 12),
          border: Border.all(color: p.ink, width: 2.5),
          boxShadow: p.shadowHover,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.title,
                    style: TextStyle(
                      fontSize: 15,
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    tool.url.replaceFirst('https://', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: p.inkSoft),
                  ),
                ],
              ),
            ),
            Divider(color: p.ink.withValues(alpha: 0.25), height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  for (final entry in grouped.entries) ...[
                    if (entry.key != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                        child: Text(
                          entry.key!,
                          style: TextStyle(
                            fontSize: 11,
                            color: p.inkSoft,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    for (final a in entry.value)
                      _OverflowRow(action: a, pinned: pinned),
                  ],
                ],
              ),
            ),
            Divider(color: p.ink.withValues(alpha: 0.25), height: 1),
            InkWell(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Center(
                  child: Text(
                    '取消',
                    style: TextStyle(fontSize: 14, color: p.inkSoft),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverflowRow extends StatelessWidget {
  const _OverflowRow({required this.action, required this.pinned});

  final _OverflowAction action;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    final color = action.danger ? p.crayonRed : p.ink;
    var label = action.label;
    if (action.id == 'pin') label = pinned ? '取消固定' : '固定到常用';
    return InkWell(
      onTap: () => Navigator.pop(context, action.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            UiIcon(action.icon, size: 17, color: color),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 关于这个工具 ──────────────────────────────────────────────

class _AboutSheet extends StatelessWidget {
  const _AboutSheet({
    required this.tool,
    required this.config,
    this.offlineReady = false,
    this.offlineUnsupported = false,
  });

  final ToolConfig tool;
  final AppConfig config;

  /// 站内 Service Worker 是否已就绪（= 断网也能打开）
  final bool offlineReady;

  /// 本平台没有 Service Worker API（iOS 的平台限制：需 Apple 域名验证）。
  final bool offlineUnsupported;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 74,
              child: Text(label, style: TextStyle(fontSize: 12.5, color: p.inkSoft)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(fontSize: 12.5, color: p.ink),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        decoration: BoxDecoration(
          color: p.paperCard,
          borderRadius: paperBorderRadius(20, alternate: 12),
          border: Border.all(color: p.ink, width: 2.5),
          boxShadow: p.shadowHover,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DoodleIcon(tool.icon, size: 30, color: p.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.title,
                        style: TextStyle(
                          fontSize: 16,
                          color: p.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (tool.subtitle.isNotEmpty)
                        Text(
                          tool.subtitle,
                          style: TextStyle(fontSize: 12, color: p.inkSoft),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            row('加载方式', '远端优先（与网页版同源）'),
            row('离线副本',
                tool.offline.enabled ? (tool.offline.size ?? '已缓存') : '无'),
            row('断网可用', offlineReady
                ? '已缓存到本机'
                : (offlineUnsupported ? '此平台不支持（需域名验证）' : '首次访问后自动缓存')),
            row('数据存储', '本机 · 与网页版共享'),
            row('来源', tool.url),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
