import Cocoa
import FlutterMacOS

/// kmlab Toolbox · macOS 宿主窗口
///
/// 只做两件事：
///  1. 按 Flutter 模板创建 `FlutterViewController` 并注册插件；
///  2. 把引擎的 binaryMessenger 挂到 `km/toast` 通道，自绘一个「纸片风」原生
///     Toast —— 因为 macOS 没有系统 Toast，而 Flutter 的 SnackBar 会被
///     PlatformView（WebView）整个盖住（见 DESIGN.md BUG #12，与 Android 同根因）。
///
/// ⚠️ **模板结构不能删**：`RegisterGeneratedPlugins(registry:)` 是所有插件
///    （webview_flutter_wkwebview / shared_preferences / path_provider …）在
///    macOS 上生效的唯一入口 —— 少了它，WebView 会一直是空白。
class MainFlutterWindow: NSWindow {

    /// Toast 文案
    private var toastLabel: NSTextField?

    override func awakeFromNib() {
        // ── 模板原样：创建视图控制器 + 注册插件 ──────────────────
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)

        RegisterGeneratedPlugins(registry: flutterViewController)

        // ── 本项目新增：km/toast 通道 ───────────────────────────
        // `FlutterViewController.engine` 是 non-null（视图控制器会隐式创建引擎），
        // 所以这里可以安全地拿它的 binaryMessenger。
        let channel = FlutterMethodChannel(
            name: "km/toast",
            binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "show" else {
                result(FlutterMethodNotImplemented)
                return
            }
            let args = call.arguments as? [String: Any]
            let message = args?["message"] as? String ?? ""
            // MethodChannel 的回调已经跑在主线程
            self?.showPaperToast(message)
            result(nil)
        }

        super.awakeFromNib()
    }

    // MARK: - 纸片风 Toast

    private func makeToastLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor(red: 0xF6 / 255.0, green: 0xF1 / 255.0, blue: 0xE4 / 255.0, alpha: 1.0)
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 12
        label.layer?.backgroundColor = NSColor(
            red: 0x2F / 255.0, green: 0x2A / 255.0, blue: 0x24 / 255.0, alpha: 0.94
        ).cgColor
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.cell?.wraps = true
        label.alphaValue = 0
        label.isHidden = true
        contentView?.addSubview(label, positioned: .above, relativeTo: nil)
        return label
    }

    private func showPaperToast(_ message: String) {
        guard !message.isEmpty else { return }
        let label = toastLabel ?? makeToastLabel()
        toastLabel = label

        label.stringValue = message
        label.isHidden = false
        label.alphaValue = 0

        let fitting = label.sizeThatFits(NSSize(width: 320, height: 1000))
        let width = min(fitting.width + 28, 360)
        let height = fitting.height + 14
        label.frame = NSRect(
            x: (frame.width - width) / 2,
            y: 48,
            width: width,
            height: height
        )

        // 淡入
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            label.animator().alphaValue = 1
        }, completionHandler: nil)

        // 2 秒后淡出
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak label] in
            guard let label = label else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                label.animator().alphaValue = 0
            }, completionHandler: {
                label.isHidden = true
            })
        }
    }
}
