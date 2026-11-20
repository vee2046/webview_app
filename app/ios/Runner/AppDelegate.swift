import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerToastChannel(engineBridge)
  }

  /// iOS 没有 Android 那样的系统 Toast，而 Flutter 的 SnackBar 在 WKWebView 旁边
  /// 会被原生视图盖住（同 Android BUG #12）—— 这里自绘一个浮层兜住。
  private func registerToastChannel(_ engineBridge: FlutterImplicitEngineBridge) {
    guard
      let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "km/toast")
    else { return }

    let channel = FlutterMethodChannel(
      name: "km/toast", binaryMessenger: registrar.messenger())

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "show" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let message = args["message"] as? String,
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(nil)
        return
      }
      self?.showPaperToast(message)
      result(nil)
    }
  }

  private func showPaperToast(_ message: String) {
    DispatchQueue.main.async {
      guard
        let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .flatMap({ $0.windows })
          .first(where: { $0.isKeyWindow })
      else { return }

      let label = UILabel()
      label.text = message
      label.font = .systemFont(ofSize: 14, weight: .medium)
      label.textColor = UIColor(red: 0.965, green: 0.945, blue: 0.894, alpha: 1)
      label.numberOfLines = 0
      label.textAlignment = .center
      label.backgroundColor = UIColor(red: 0.184, green: 0.165, blue: 0.141, alpha: 0.94)
      label.layer.cornerRadius = 12
      label.layer.masksToBounds = true
      label.translatesAutoresizingMaskIntoConstraints = false

      let container = UIView()
      container.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(label)
      window.addSubview(container)

      NSLayoutConstraint.activate([
        label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
        label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
        label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

        container.centerXAnchor.constraint(equalTo: window.centerXAnchor),
        container.leadingAnchor.constraint(
          greaterThanOrEqualTo: window.leadingAnchor, constant: 24),
        container.trailingAnchor.constraint(
          lessThanOrEqualTo: window.trailingAnchor, constant: -24),
        container.bottomAnchor.constraint(
          equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -72),
      ])

      container.alpha = 0
      UIView.animate(withDuration: 0.18) {
        container.alpha = 1
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        UIView.animate(
          withDuration: 0.25,
          animations: { container.alpha = 0 },
          completion: { _ in container.removeFromSuperview() }
        )
      }
    }
  }
}
