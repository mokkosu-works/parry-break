import UIKit
import WebKit

// ゲーム本体 (リポジトリ直下の index.html) を全画面の WKWebView で動かす画面
final class GameViewController: UIViewController {
    private var webView: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(
            WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(HapticHandler(), name: "haptic")

        let webView = WKWebView(frame: .zero, configuration: config)
        let background = UIColor(named: "LaunchBackground")
        webView.isOpaque = false
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        webView.navigationDelegate = self
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }   // Mac の Safari から Web インスペクタで調べられる
        #endif
        self.webView = webView
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: BundleSchemeHandler.startURL))
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    // 画面端のスワイプでホームに戻ってしまわないよう、システムのジェスチャーを一段遅らせる
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    // ページ側から使うネイティブ機能
    // - navigator.standalone: ホーム画面のアプリ扱いにして「ホーム画面に追加」の案内や全画面の要求を出さない
    // - navigator.vibrate: iOS の WebView にはないので、触覚フィードバックにつなぐ (パターンの間隔はここで刻む)
    private static let bridgeScript = """
    (() => {
      try { Object.defineProperty(navigator, 'standalone', { value: true }); } catch (e) {}
      const post = ms => { try { webkit.messageHandlers.haptic.postMessage(ms); } catch (e) {} };
      let timers = [];
      navigator.vibrate = p => {
        timers.forEach(clearTimeout); timers = [];
        let t = 0;
        (Array.isArray(p) ? p : [p]).forEach((v, i) => {
          const ms = Math.max(0, Number(v) || 0);
          if (i % 2 === 0 && ms > 0) { if (t === 0) post(ms); else timers.push(setTimeout(() => post(ms), t)); }
          t += ms;
        });
        return true;
      };
    })();
    """
}

extension GameViewController: WKNavigationDelegate {
    // アプリ内のファイル以外 (外部リンク) は Safari で開く
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.scheme != BundleSchemeHandler.scheme else {
            decisionHandler(.allow)
            return
        }
        if navigationAction.targetFrame?.isMainFrame ?? true { UIApplication.shared.open(url) }
        decisionHandler(.cancel)
    }


    // メモリ不足などで描画プロセスが落ちたら読み込み直す
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.load(URLRequest(url: BundleSchemeHandler.startURL))
    }
}

// navigator.vibrate(ms) の長さに応じて触覚フィードバックの強さを選ぶ
private final class HapticHandler: NSObject, WKScriptMessageHandler {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let ms = (message.body as? NSNumber)?.doubleValue, ms > 0 else { return }
        switch ms {
        case ..<12: light.impactOccurred()
        case ..<40: medium.impactOccurred()
        case ..<150: heavy.impactOccurred()
        default: notification.notificationOccurred(.error)   // ゲームオーバー
        }
    }
}
