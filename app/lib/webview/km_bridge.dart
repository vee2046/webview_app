import 'dart:convert';

/// H5 ⇄ 原生的桥接层。
///
/// 设计原则（见 DESIGN.md D4）：**增强而非依赖**。
/// 每个 H5 在没有 App 的普通浏览器里必须原样可用，
/// 因此 Bridge 只在「检测到原生宿主」时注入，注入失败也绝不影响 H5 本身。
///
/// 通信方式：
/// - H5 → 原生：`window.KmHost.postMessage(json)` （JavaScriptChannel）
/// - 原生 → H5：`controller.runJavaScript(...)` 注入 `window.KM` 壳对象
class KmBridge {
  const KmBridge._();

  /// JavaScriptChannel 名称，H5 侧通过 `window.KmHost.postMessage` 调用。
  static const String channelName = 'KmHost';

  /// Bridge 命名空间，H5 侧通过 `window.KM` 调用。
  static const String namespace = 'KM';

  /// H5 发给原生的一条消息。
  static KmHostMessage? parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final action = decoded['action'];
      if (action is! String || action.isEmpty) return null;
      final payload = <String, dynamic>{};
      decoded.forEach((key, value) {
        if (key != 'action') payload['$key'] = value;
      });
      return KmHostMessage(action: action, payload: payload);
    } catch (_) {
      return null;
    }
  }

  /// 生成注入 `window.KM` 的脚本。
  ///
  /// [permissions] 来自 `config.bridge.permissions`，只有白名单内的能力才暴露。
  /// [version] 是 App 版本，会被 H5 读到。
  /// [theme] 当前主题，供 H5 适配深浅色。
  static String injectionScript({
    required List<String> permissions,
    String version = '0.1.0',
    String theme = 'paper',
  }) {
    final perms = jsonEncode(permissions);
    return '''
(function () {
  if (window.$namespace && window.$namespace.__kmInstalled) { return; }
  var P = $perms;
  function allowed(p) { return P.indexOf(p) >= 0; }
  function send(action, payload) {
    try {
      var host = window.$channelName;
      if (host && host.postMessage) {
        host.postMessage(JSON.stringify(Object.assign({ action: action }, payload || {})));
      }
    } catch (e) { /* 宿主不存在时静默降级 */ }
  }
  var KM = {
    __kmInstalled: true,
    version: '$version',
    has: function (p) { return allowed(p); },
    openTool: function (id) { if (allowed('navigate')) send('openTool', { id: String(id) }); },
    setTitle: function (t) { if (allowed('title')) send('setTitle', { title: String(t) }); },
    setResumeState: function (s) {
      if (!allowed('storage')) return;
      var summary = (typeof s === 'string') ? s : ((s && s.summary) || '');
      send('setResumeState', { summary: String(summary) });
    },
    toast: function (m) { if (allowed('toast')) send('toast', { message: String(m) }); },
    share: function (u, t) {
      if (!allowed('share')) return;
      send('share', { url: String(u || location.href), title: String(t || document.title) });
    },
    exportData: function () { if (allowed('storage')) send('exportData', {}); },
    importData: function () { if (allowed('storage')) send('importData', {}); },
    vibrate: function (ms) { if (allowed('vibrate')) send('vibrate', { ms: ms || 20 }); },
    theme: function () { return window.__kmTheme || '$theme'; }
  };
  window.$namespace = KM;
  window.__kmTheme = '$theme';
})();
''';
  }

  /// 通知 H5 宿主已就绪（页面脚本跑完之后调用）。
  static String readyScript([String version = '0.1.0']) {
    return '''
(function () {
  try {
    document.dispatchEvent(new CustomEvent('km-ready', { detail: { version: '$version' } }));
  } catch (e) {}
})();
''';
  }

  /// 滚动方向监听 —— 供 `auto` 档 chrome 判断何时淡出/淡回顶栏。
  static const String scrollScript = '''
(function () {
  if (window.__kmScrollBound) { return; }
  window.__kmScrollBound = true;
  var last = window.scrollY || 0;
  var timer = null;
  function report() {
    var y = window.scrollY || 0;
    var dy = y - last;
    if (Math.abs(dy) > 4) {
      last = y;
      try {
        var host = window.$channelName;
        if (host && host.postMessage) {
          host.postMessage(JSON.stringify({ action: 'scroll', dir: dy > 0 ? 'down' : 'up' }));
        }
      } catch (e) {}
    }
  }
  window.addEventListener('scroll', report, { passive: true });
})();
''';

  /// 顶部边缘下滑手势（在页面里监听）—— 沉浸式档唤出工具栏的主通道。
  ///
  /// 为什么必须放在 JS 里而不是 Flutter 的 GestureDetector？
  /// Android 上 WebView 是 PlatformView，它在原生视图层级里盖住 Flutter 视图，
  /// 叠在它上面的 Flutter 手势层收不到落在 WebView 区域的触摸。
  /// 所以边缘手势只能由页面自己监听，再通过 JS Channel 回传给宿主。
  static String edgeSwipeScript([double zone = 28]) {
    return '''
(function () {
  if (window.__kmEdgeBound) { return; }
  window.__kmEdgeBound = true;
  var zone = $zone;
  var startY = 0;
  var tracking = false;
  function firstY(e) {
    var t = e.touches && e.touches[0];
    return t ? t.clientY : -1;
  }
  function onStart(e) {
    var y = firstY(e);
    if (y < 0 || y > zone) { tracking = false; return; }
    tracking = true;
    startY = y;
  }
  function onMove(e) {
    if (!tracking) { return; }
    var y = firstY(e);
    if (y < 0) { return; }
    if (y - startY > 36) {
      tracking = false;
      try {
        var host = window.$channelName;
        if (host && host.postMessage) {
          host.postMessage(JSON.stringify({ action: 'edgeSwipe' }));
        }
      } catch (err) {}
    }
  }
  function onEnd() { tracking = false; }
  document.addEventListener('touchstart', onStart, { passive: true });
  document.addEventListener('touchmove', onMove, { passive: true });
  document.addEventListener('touchend', onEnd, { passive: true });
  document.addEventListener('touchcancel', onEnd, { passive: true });
})();
''';
  }

  /// 下拉刷新 —— 在页面里监听「顶部继续下拉」的手势。
  ///
  /// 同样因为 PlatformView 遮挡，Flutter 收不到 WebView 区域的手势，
  /// 所以这个手势也必须由页面自己监听，再回传给宿主决定要不要 reload。
  /// 只有页面已经滚到最顶部（scrollY <= 0）时才响应，避免和页面内滚动打架。
  static String pullToRefreshScript() {
    return '''
(function () {
  if (window.__kmPullBound) { return; }
  window.__kmPullBound = true;
  var THRESHOLD = 68;
  var startY = 0, pulling = false, maxPull = 0;

  var box = null;
  function indicator() {
    if (box) { return box; }
    box = document.createElement('div');
    box.style.cssText = [
      'position:fixed', 'left:50%', 'top:10px', 'z-index:2147483647',
      'transform:translate(-50%,-40px)', 'opacity:0',
      'padding:6px 14px', 'border-radius:14px',
      'background:#fbf7ec', 'color:#2f2a24',
      'border:2px solid #2f2a24', 'box-shadow:3px 4px 0 rgba(47,42,36,.16)',
      'font:600 13px/1.4 -apple-system,"PingFang SC","Microsoft YaHei",sans-serif',
      'transition:transform .16s ease,opacity .16s ease',
      'pointer-events:none'
    ].join(';');
    (document.body || document.documentElement).appendChild(box);
    return box;
  }
  function paint(pull, ready) {
    var el = indicator();
    el.textContent = ready ? '松手刷新' : '下拉刷新';
    el.style.transform = 'translate(-50%,' + Math.min(pull, THRESHOLD) * 0.55 + 'px)';
    el.style.opacity = String(Math.min(1, pull / 26));
  }
  function hide() {
    if (!box) { return; }
    box.style.transform = 'translate(-50%,-40px)';
    box.style.opacity = '0';
  }
  function firstY(e) {
    var t = e.touches && e.touches[0];
    return t ? t.clientY : -1;
  }
  function onStart(e) {
    if ((window.scrollY || 0) > 0) { pulling = false; return; }
    var y = firstY(e);
    if (y < 0) { pulling = false; return; }
    pulling = true; maxPull = 0; startY = y;
  }
  function onMove(e) {
    if (!pulling) { return; }
    var y = firstY(e);
    if (y < 0) { return; }
    var pull = y - startY;
    if (pull <= 0) { hide(); return; }
    if (pull > maxPull) { maxPull = pull; }
    // 已经在顶部还继续下拉 → 阻止原生滚动/回弹，只留我们的指示器
    if (e.cancelable) { e.preventDefault(); }
    paint(pull, pull >= THRESHOLD);
  }
  function onEnd() {
    if (!pulling) { return; }
    pulling = false;
    var ready = maxPull >= THRESHOLD;
    hide();
    if (!ready) { return; }
    try {
      var host = window.$channelName;
      if (host && host.postMessage) {
        host.postMessage(JSON.stringify({ action: 'pullToRefresh' }));
      }
    } catch (err) {}
  }
  document.addEventListener('touchstart', onStart, { passive: true });
  document.addEventListener('touchmove', onMove, { passive: false });
  document.addEventListener('touchend', onEnd, { passive: true });
  document.addEventListener('touchcancel', onEnd, { passive: true });
})();
''';
  }

  /// 注册 Service Worker —— 让 H5 在断网时仍能从缓存打开（**origin 不变**，
  /// 所以 localStorage 与网页版依旧共享）。
  ///
  /// SW 文件由 kmlab_site 托管在站点根目录 `/sw.js`（作用域 `/`），
  /// 站内其它资源一律不接管，只缓存 `/h5_tools/**`。
  /// 注册失败（站点还没部署 SW）时静默忽略 —— 离线能力是增强项，不是依赖。
  static const String serviceWorkerScript = '''
(function () {
  if (window.__kmSwBound) { return; }
  window.__kmSwBound = true;
  function say(action, extra) {
    try {
      var host = window.$channelName;
      if (host && host.postMessage) {
        var payload = { action: action };
        if (extra) { for (var k in extra) { payload[k] = extra[k]; } }
        host.postMessage(JSON.stringify(payload));
      }
    } catch (e) {}
  }
  try {
    if (!('serviceWorker' in navigator)) {
      // iOS ≤13 根本不支持；iOS 14+ 还要 Info.plist 里配了 WKAppBoundDomains
      say('swUnavailable', { reason: 'navigator.serviceWorker 不存在' });
      return;
    }
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).then(function (reg) {
      say('swReady', { scope: reg.scope });
    }).catch(function (err) {
      say('swUnavailable', { reason: String(err && err.message || err) });
    });
  } catch (e) {
    say('swUnavailable', { reason: String(e) });
  }
})();
''';

  /// 拦截 `<a download="文件名">` 这种「明确是下载」的链接。
  ///
  /// 导航层拿不到 `download` 属性里的文件名（只有 URL），
  /// 所以在页面里点一下、把 URL 和文件名一起报给宿主。
  /// 这里 `preventDefault()` 掉默认行为 —— 避免宿主和导航层各处理一次。
  static const String downloadInterceptScript = '''
(function () {
  if (window.__kmDownloadBound) { return; }
  window.__kmDownloadBound = true;
  document.addEventListener('click', function (e) {
    try {
      var el = e.target;
      var a = el && el.closest ? el.closest('a[download]') : null;
      if (!a) { return; }
      var href = a.href || a.getAttribute('href') || '';
      if (!href) { return; }
      var name = a.getAttribute('download') || '';
      e.preventDefault();
      window.$channelName.postMessage(JSON.stringify({
        action: 'downloadLink', url: href, name: name
      }));
    } catch (err) {}
  }, true);
})();
''';

  /// 把页面里的 `blob:` URL 转成 `data:` URL。
  ///
  /// Dart 侧拿不到 blob 的字节（blob 只在页面自己的作用域里有），
  /// 所以要让页面自己读出来、编码成 base64，再由 Dart 解码落盘。
  /// 返回 `data:<mime>;base64,<payload>`。
  static String blobToDataUrlScript(String blobUrl) {
    final encoded = Uri.encodeComponent(blobUrl);
    return '''
(function () {
  try {
    var u = decodeURIComponent('$encoded');
    fetch(u).then(function (r) { return r.blob(); }).then(function (b) {
      return new Promise(function (resolve, reject) {
        var fr = new FileReader();
        fr.onload = function () { resolve(fr.result); };
        fr.onerror = reject;
        fr.readAsDataURL(b);
      });
    }).then(function (dataUrl) {
      return window.$channelName.postMessage(JSON.stringify({
        action: 'blobData', dataUrl: dataUrl, size: dataUrl.length
      }));
    }).catch(function (e) {
      return window.$channelName.postMessage(JSON.stringify({
        action: 'blobData', error: String(e)
      }));
    });
  } catch (e) {
    window.$channelName.postMessage(JSON.stringify({ action: 'blobData', error: String(e) }));
  }
})();
''';
  }

  /// 取回当前页面的 localStorage 快照（Dart 侧读不到 WebView 沙箱，只能这样取）。
  ///
  /// 返回的是一个 JSON 字符串，形如 `{"key":"value", ...}`。
  static const String snapshotScript = '''
(function () {
  try {
    var out = {};
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      out[k] = localStorage.getItem(k);
    }
    return JSON.stringify(out);
  } catch (e) {
    return JSON.stringify({});
  }
})();
''';
}

/// 一条 H5 → 原生的消息。
class KmHostMessage {
  const KmHostMessage({required this.action, required this.payload});

  final String action;
  final Map<String, dynamic> payload;

  String get id => (payload['id'] ?? '').toString();
  String get title => (payload['title'] ?? '').toString();
  String get message => (payload['message'] ?? '').toString();
  String get summary => (payload['summary'] ?? '').toString();
  String get url => (payload['url'] ?? '').toString();
  int get ms => int.tryParse((payload['ms'] ?? '20').toString()) ?? 20;

  @override
  String toString() => 'KmHostMessage($action, $payload)';
}
