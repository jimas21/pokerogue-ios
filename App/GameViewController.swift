import AVFoundation
import UIKit
import WebKit

/// Full-screen PokeRogue. The game runs in a web view from files inside the app (see `GameSchemeHandler`), so it
/// needs no connection. Links to outside sites (wiki, Discord) open in Safari.
final class GameViewController: UIViewController {
    private let saves = SaveStore()
    private var webView: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.setURLSchemeHandler(GameSchemeHandler(root: GameSchemeHandler.bundledGame),
                                   forURLScheme: GameSchemeHandler.scheme)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Look like mobile Safari, so the game picks its phone layout and touch controls.
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"

        let content = config.userContentController
        content.addUserScript(WKUserScript(source: PageScripts.bootstrap(restore: saves.restoreLiteral()),
                                           injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let relay = MessageRelay(self)
        content.add(relay, name: PageScripts.savesHandler)
        content.add(relay, name: PageScripts.downloadHandler)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        self.webView = webView
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Game sound follows the ring/silent switch and mixes with music already playing.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        webView.load(URLRequest(url: GameSchemeHandler.startURL))
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    /// Asks the page to send its saves now (the app is leaving the screen).
    func flushSaves() {
        let task = UIApplication.shared.beginBackgroundTask(withName: "pokerogue.saves")
        webView.evaluateJavaScript("window.__pokerogueFlushSaves && window.__pokerogueFlushSaves()") { _, _ in
            // The snapshot arrives as a message; give it a moment to be written before iOS suspends the app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                UIApplication.shared.endBackgroundTask(task)
            }
        }
    }

    fileprivate func received(_ message: WKScriptMessage) {
        switch message.name {
        case PageScripts.savesHandler:
            if let json = message.body as? String { saves.write(snapshot: json) }
        case PageScripts.downloadHandler:
            guard let body = message.body as? [String: Any],
                  let name = body["name"] as? String,
                  let base64 = body["base64"] as? String,
                  let data = Data(base64Encoded: base64)
            else { return }
            shareExport(named: name, data: data)
        default:
            break
        }
    }

    /// Keeps the exported file in the app's Documents/Exports (visible in the Files app under On My iPhone >
    /// PokéRogue) and opens the share sheet so it can be saved anywhere.
    private func shareExport(named name: String, data: Data) {
        let safeName = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exports = documents.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let file = exports.appendingPathComponent(safeName.isEmpty ? "pokerogue-export.prsv" : safeName)
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            showAlert("Couldn't save the exported file: \(error.localizedDescription)")
            return
        }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY,
                                                                 width: 1, height: 1)
        present(sheet, animated: true)
    }

    private func showAlert(_ text: String, confirm: Bool = false, done: @escaping (Bool) -> Void = { _ in }) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in done(true) })
        if confirm {
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
        }
        guard presentedViewController == nil else {
            done(false)
            return
        }
        present(alert, animated: true)
    }
}

extension GameViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        switch url.scheme?.lowercased() {
        case GameSchemeHandler.scheme, "about", "blob", "data":
            decisionHandler(.allow)
        default:
            // Wiki, Discord and other outside links: open in Safari, keep the game where it is.
            if navigationAction.targetFrame?.isMainFrame ?? true || navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iOS ended the page (usually memory pressure in the background). Saves are already on disk; reload.
        webView.load(URLRequest(url: GameSchemeHandler.startURL))
    }
}

extension GameViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // window.open(...) for outside links.
        if let url = navigationAction.request.url, url.scheme?.lowercased() != GameSchemeHandler.scheme {
            UIApplication.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        showAlert(message) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        showAlert(message, confirm: true, done: completionHandler)
    }
}

/// Holds the view controller weakly: WebKit keeps message handlers alive for as long as the web view exists.
private final class MessageRelay: NSObject, WKScriptMessageHandler {
    private weak var target: GameViewController?

    init(_ target: GameViewController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.received(message)
    }
}
