import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../model/app_config.dart';
import 'km_bridge.dart';

/// WebView 容器。
///
/// 负责：控制器生命周期、导航委托、Bridge 注入、localStorage 快照取回、
/// 加载失败兜底。**chrome（顶栏/底栏）的渲染在 `tool_detail_page.dart`**，
/// 这里只提供状态与能力。
class WebViewHost extends StatefulWidget {
  const WebViewHost({
    super.key,
    required this.tool,
    required this.config,
    required this.onTitleChanged,
    required this.onSnapshot,
    required this.onBridgeMessage,
    required this.onScrollDirection,
    this.onExternalLink,
    this.onDownloadRequested,
    this.controller,
    this.chrome,
  });

  final ToolConfig tool;
  final AppConfig config;

  /// H5 改了标题（`KM.setTitle`）时回调。
  final ValueChanged<String> onTitleChanged;

  /// 取回 localStorage 快照时回调（参数是解析后的 Map）。
  final ValueChanged<Map<String, dynamic>> onSnapshot;

  /// 收到 Bridge 消息时回调。
  final ValueChanged<KmHostMessage> onBridgeMessage;

  /// 页面滚动方向（`down` / `up`）—— 供 `auto` 档 chrome 淡入淡出。
  final ValueChanged<String> onScrollDirection;

  /// 页面要跳到站外 / 非 http 协议时回调（宿主负责用系统浏览器打开）。
  final ValueChanged<String>? onExternalLink;

  /// 页面点了「下载」时回调（参数是下载地址）。
  final ValueChanged<String>? onDownloadRequested;

  /// 外部可注入控制器（测试用）。
  final WebViewController? controller;

  /// 当前的 chrome 档位。
  ///
  /// 默认取 `tool.open.chrome`；运行时被「全屏浏览」切到 immersive 时，
  /// 由调用方把 `ChromeMode.immersive` 传进来（这样进度条要不要保留才能算对）。
  final ChromeMode? chrome;

  /// 实际生效的 chrome 档位。
  ChromeMode get effectiveChrome => chrome ?? tool.open.chrome;

  /// 沉浸式下要不要保留顶部进度条（`webview.chrome.keepProgressBarInImmersive`）。
  bool get keepProgressBar =>
      effectiveChrome != ChromeMode.immersive ||
      config.webview.chrome.keepProgressBarInImmersive;

  @override
  State<WebViewHost> createState() => WebViewHostState();
}

class WebViewHostState extends State<WebViewHost> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _failed = false;
  String? _failedUrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? WebViewController();
    _setup();
  }

  void _setup() {
    final cfg = widget.config.webview;
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_paperColor())
      ..addJavaScriptChannel(
        KmBridge.channelName,
        onMessageReceived: (JavaScriptMessage message) {
          final parsed = KmBridge.parse(message.message);
          if (parsed == null) return;
          if (parsed.action == 'scroll') {
            widget.onScrollDirection(parsed.payload['dir']?.toString() ?? 'down');
            return;
          }
          widget.onBridgeMessage(parsed);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (String url) {
            if (!mounted) return;
            setState(() {
              _failed = false;
              _ready = false;
            });
          },
          onPageFinished: (String url) async {
            if (!mounted) return;
            setState(() => _ready = true);
            await _injectBridge();
            await _takeSnapshot();
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null) _injectBridge();
          },
          onWebResourceError: (WebResourceError error) async {
            if (!mounted || error.isForMainFrame != true) return;
            final url = await _controller.currentUrl();
            if (!mounted) return;
            setState(() {
              _failed = true;
              _failedUrl = url;
            });
          },
          onNavigationRequest: (NavigationRequest request) async {
            final target = request.url;
            final cfg = widget.config.webview;

            // ① blob: / data: —— 页面内联资源或导出文件。
            //    不能让它进入导航栈（会把 WebView 导航到一段二进制 → 坏页）。
            if (target.startsWith('blob:') || target.startsWith('data:')) {
              if (cfg.interceptDownloads) {
                widget.onDownloadRequested?.call(target);
              }
              return NavigationDecision.prevent;
            }

            // ② 其它非 http(s) 协议：mailto / tel / sms / intent ……
            if (!target.startsWith('http://') && !target.startsWith('https://')) {
              widget.onExternalLink?.call(target);
              return NavigationDecision.prevent;
            }

            // ③ 站外链接交给系统浏览器，避免把 App 拖进别人的站点
            if (cfg.openExternalLinksInBrowser &&
                !target.startsWith(_originOf(widget.tool.url))) {
              widget.onExternalLink?.call(target);
              return NavigationDecision.prevent;
            }

            // ④ 同源但看起来是文件 → 当下载处理，别把 WebView 导航到二进制
            if (cfg.interceptDownloads && _looksLikeDownload(target)) {
              widget.onDownloadRequested?.call(target);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    final ua = cfg.userAgentSuffix;
    if (ua.isNotEmpty && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // setUserAgent 在 iOS 上不支持，调用会抛 UnsupportedError。
      _controller.setUserAgent(ua);
    }

    _controller.loadRequest(Uri.parse(widget.tool.url));
  }

  Color _paperColor() {
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark ? const Color(0xFF1B140E) : const Color(0xFFF6F1E4);
  }

  String _originOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return 'https://kmlab.tech';
    return '${uri.scheme}://${uri.host}';
  }

  /// 按扩展名判断这个链接是不是「文件」。
  bool _looksLikeDownload(String url) {
    final exts = widget.config.webview.downloadExtensions;
    if (exts.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final seg = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = seg.lastIndexOf('.');
    if (dot <= 0 || dot == seg.length - 1) return false;
    final ext = seg.substring(dot + 1).toLowerCase();
    return exts.contains(ext);
  }

  Future<void> _openExternally(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 拉不起系统浏览器就静默忽略，页面保持原样
    }
  }

  /// 注入 `window.KM` 壳对象 + 各类页面内监听。
  Future<void> _injectBridge() async {
    final bridge = widget.config.bridge;
    final chrome = widget.config.webview.chrome;
    try {
      if (bridge.enabled) {
        await _controller.runJavaScript(KmBridge.injectionScript(
          permissions: bridge.permissions,
          version: widget.config.about.version,
          theme: widget.config.app.theme,
        ));
      }
      // 「自动隐藏顶栏」档：必须由页面内上报滚动方向，顶栏才能随滚动淡出。
      // ⚠️ 判断必须用**当前工具**的档位（`tool.open.chrome`），
      // 不能用全局默认 `webview.chrome.default`（恒为 minimal）——
      // 那样 auto 档永远拿不到滚动脚本，顶栏就永远不会淡出（BUG #22）。
      if (widget.tool.open.isAutoChrome) {
        await _controller.runJavaScript(KmBridge.scrollScript);
      }
      await _controller.runJavaScript(KmBridge.edgeSwipeScript(
        chrome.immersiveTopHotZonePx,
      ));
      if (widget.tool.open.pullToRefresh) {
        await _controller.runJavaScript(KmBridge.pullToRefreshScript());
      }
      if (widget.config.webview.interceptDownloads) {
        await _controller.runJavaScript(KmBridge.downloadInterceptScript);
      }
      // 离线层：注册站内 Service Worker（origin 不变 → localStorage 依旧共享）
      await _controller.runJavaScript(KmBridge.serviceWorkerScript);
      if (bridge.enabled) {
        await _controller.runJavaScript(KmBridge.readyScript(widget.config.about.version));
      }
    } catch (_) {
      // 注入失败不影响 H5 本身（Bridge 是增强项）
    }
  }

  /// 取回 localStorage 快照 —— Dart 侧读不到 WebView 沙箱，只能通过 JS 取。
  Future<void> _takeSnapshot() async {
    if (!widget.tool.resume.enabled) return;
    if (widget.tool.resume.mode != ResumeMode.storage) return;
    try {
      final raw = await _controller.runJavaScriptReturningResult(KmBridge.snapshotScript);
      Object? decoded = raw;
      // Android 的 runJavaScriptReturningResult 会把 JS 的字符串返回值再 JSON 编码一层，
      // 于是这里要按「字符串 → 字符串 → Map」的顺序多解两次。
      if (decoded is String) {
        if (decoded.trim().isEmpty) return;
        decoded = jsonDecode(decoded);
        if (decoded is String) {
          if (decoded.trim().isEmpty) return;
          decoded = jsonDecode(decoded);
        }
      }
      if (decoded is Map) {
        widget.onSnapshot(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // 取不到就保持旧快照
    }
  }

  /// 手动触发一次快照取回（Bridge 收到 exportData 时用）。
  Future<void> refreshSnapshot() => _takeSnapshot();

  /// 页面里能不能再退一步。
  Future<bool> canGoBack() async {
    try {
      return await _controller.canGoBack();
    } catch (_) {
      return false;
    }
  }

  /// 退一步（只在 `routeBackEnabled` 打开时用）。
  Future<void> goBack() async {
    try {
      await _controller.goBack();
    } catch (_) {
      // 退不了就算了
    }
  }

  /// 在当前页面里跑一段 JS（失败静默）。
  ///
  /// 宿主（ToolDetailPage）拿不到 WebViewHost 内部的 controller，
  /// 所有「写 localStorage / 触发页面脚本」的动作都从这里走。
  Future<void> runScript(String script) async {
    try {
      await _controller.runJavaScript(script);
    } catch (_) {
      // 页面还没准备好就忽略
    }
  }

  Future<void> reload() async {
    if (mounted) setState(() => _failed = false);
    await _controller.reload();
  }

  @override
  void dispose() {
    _controller.clearCache();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _failed
              ? WebViewErrorView(
                  url: _failedUrl ?? widget.tool.url,
                  onRetry: reload,
                  onOpenBrowser: () => _openExternally(widget.tool.url),
                  allowRetry: widget.config.webview.errorRetryInWebview,
                )
              : WebViewWidget(controller: _controller),
        ),
        if (!_failed && _progress < 100 && widget.keepProgressBar)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress / 100,
              minHeight: 2.5,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation(Color(0xFFD9A441)),
            ),
          ),
        if (!_failed && !_ready && _progress == 0)
          const Positioned.fill(child: _LoadingPaper()),
      ],
    );
  }
}

/// 加载失败兜底页 —— 任何 chrome 档位下都必须存在，绝不白屏。
class WebViewErrorView extends StatelessWidget {
  const WebViewErrorView({
    super.key,
    required this.url,
    required this.onRetry,
    required this.onOpenBrowser,
    this.allowRetry = true,
  });

  final String url;
  final VoidCallback onRetry;
  final VoidCallback onOpenBrowser;

  /// `webview.errorRetryInWebview` 为 false 时不提供「重试」，只留「用浏览器打开」
  final bool allowRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 46, color: theme.colorScheme.outline),
            const SizedBox(height: 14),
            Text('这一页没打开', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              url,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (allowRetry) ...[
                  OutlinedButton(onPressed: onRetry, child: const Text('重试')),
                  const SizedBox(width: 10),
                ],
                FilledButton(onPressed: onOpenBrowser, child: const Text('用浏览器打开')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载中的牛皮纸骨架。
class _LoadingPaper extends StatelessWidget {
  const _LoadingPaper();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text('正在打开…', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// 沉浸模式顶部热区 —— iOS 没有硬件返回键，这是唯一的逃生通道。
class ImmersiveHotZone extends StatelessWidget {
  const ImmersiveHotZone({
    super.key,
    required this.height,
    this.onReveal,
    this.hintVisible = false,
  });

  final double height;
  final VoidCallback? onReveal;
  final bool hintVisible;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onReveal ?? () {},
      onVerticalDragEnd: (DragEndDetails details) {
        if ((details.primaryVelocity ?? 0) > 120) onReveal?.call();
      },
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.34),
              Theme.of(context).colorScheme.primary.withValues(alpha: 0),
            ],
          ),
        ),
        child: hintVisible
            ? Text(
                '↓ 下滑唤出工具栏',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : null,
      ),
    );
  }
}
