import Flutter
import UIKit
import WebKit

/// Tortib yangilash (pull-to-refresh): iOS'ning o'z `UIRefreshControl`i WKWebView'ning scrollView'iga ulanadi.
/// Butun sahifa qayta yuklanmaydi: saytdagi `window.__oftobRefresh()` joriy ekranni yumshoq (pjax) yangilaydi,
/// aylanuvchi belgi shu tugagach (yoki 10 soniyadan keyin) to'xtaydi. Sayt javob bermasa — oddiy reload.
final class WebRefresh: NSObject {
  static let shared = WebRefresh()

  private weak var attached: WKWebView?
  private var busy = false
  private var timer: Timer?

  func start() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
      self?.attachIfNeeded()
    }
  }

  private func findWebView(in view: UIView) -> WKWebView? {
    if let web = view as? WKWebView { return web }
    for sub in view.subviews {
      if let web = findWebView(in: sub) { return web }
    }
    return nil
  }

  private func attachIfNeeded() {
    var window: UIWindow?
    for scene in UIApplication.shared.connectedScenes {
      if let ws = scene as? UIWindowScene {
        window = ws.windows.first(where: { $0.isKeyWindow }) ?? ws.windows.first
        if window != nil { break }
      }
    }
    guard let root = window, let web = findWebView(in: root) else { return }
    if web === attached && web.scrollView.refreshControl != nil { return }
    let control = UIRefreshControl()
    control.addTarget(self, action: #selector(onRefresh(_:)), for: .valueChanged)
    web.scrollView.refreshControl = control
    web.scrollView.bounces = true
    web.scrollView.alwaysBounceVertical = true
    attached = web
  }

  private final class Gate {
    var done = false
  }

  @objc private func onRefresh(_ sender: UIRefreshControl) {
    guard let web = attached else {
      sender.endRefreshing()
      return
    }
    if busy {
      sender.endRefreshing()
      return
    }
    busy = true
    let gate = Gate()
    let finish: () -> Void = { [weak self, weak sender] in
      DispatchQueue.main.async {
        if gate.done { return }
        gate.done = true
        sender?.endRefreshing()
        self?.busy = false
      }
    }
    // spinner hech qachon cheksiz aylanmasligi uchun
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { finish() }
    let body = "return window.__oftobRefresh ? await window.__oftobRefresh() : 'none'"
    web.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { result in
      DispatchQueue.main.async {
        switch result {
        case .success(let value):
          if let text = value as? String, text == "none" { web.reload() }
        case .failure:
          web.reload()
        }
        finish()
      }
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    WebRefresh.shared.start()
    return ok
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
