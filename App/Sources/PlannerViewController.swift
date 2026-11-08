import UIKit
import WebKit
import UniformTypeIdentifiers

/// Shows the planner (Web/index.html) full screen and answers its storage requests.
///
/// The page calls `window.webkit.messageHandlers.pencilled.postMessage({cmd: ...})`, which
/// returns a Promise. Each command is answered by `DocumentStore` on a background queue.
final class PlannerViewController: UIViewController, WKScriptMessageHandlerWithReply, WKNavigationDelegate, UIDocumentPickerDelegate {
    private var webView: WKWebView!
    private let store = DocumentStore()
    private let queue = DispatchQueue(label: "pencilledin.store", qos: .userInitiated)
    private var pendingPick: ((Any?, String?) -> Void)?

    private static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x0E / 255, green: 0x11 / 255, blue: 0x16 / 255, alpha: 1)
            : UIColor(red: 0xF4 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1)
    }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "pencilled")
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = Self.background
        webView.scrollView.backgroundColor = Self.background
        // The page lays itself out to exactly fit the screen and scrolls its own week grid.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillResign), name: UIApplication.willResignActiveNotification, object: nil)
    }

    @objc private func appBecameActive() { sendEvent("active") }
    @objc private func appWillResign() { sendEvent("inactive") }

    private func sendEvent(_ type: String) {
        webView.evaluateJavaScript("window.__pencilledNative && window.__pencilledNative.event('\(type)')", completionHandler: nil)
    }

    // MARK: - Messages from the page

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
            replyHandler(nil, "Unknown message")
            return
        }
        let name = body["name"] as? String
        let text = body["text"] as? String
        let resolve = body["resolve"] as? Bool ?? false

        if cmd == "cloud.pick" {
            presentFolderPicker(reply: replyHandler)
            return
        }

        let store = self.store
        queue.async {
            var value: Any?
            var failure: String?
            do {
                switch cmd {
                case "local.readAll": value = store.localReadAll()
                case "local.write": try store.localWrite(name, text); value = true
                case "cloud.status": value = store.status()
                case "cloud.unlink": value = store.unlink()
                case "cloud.list": value = try store.cloudList()
                case "cloud.read": value = try store.cloudRead(name)
                case "cloud.write": value = try store.cloudWrite(name, text, resolve: resolve)
                default: failure = "Unknown command \(cmd)"
                }
            } catch {
                failure = error.localizedDescription
            }
            // Copy into constants: a `var` captured by the @Sendable main-queue closure does not compile.
            let result = value ?? NSNull()
            let failureMessage = failure
            DispatchQueue.main.async {
                if let failureMessage = failureMessage { replyHandler(nil, failureMessage) } else { replyHandler(result, nil) }
            }
        }
    }

    // MARK: - Choosing the iCloud folder

    private func presentFolderPicker(reply: @escaping (Any?, String?) -> Void) {
        // present(_:) silently does nothing while something else is shown, which would leave the
        // page's Promise waiting forever.
        guard presentedViewController == nil else {
            reply(nil, "Another window is already open.")
            return
        }
        pendingPick?(NSNull(), nil)
        pendingPick = reply
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.directoryURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let reply = pendingPick else { return }
        pendingPick = nil
        guard let url = urls.first else { reply(NSNull(), nil); return }
        let store = self.store
        queue.async {
            do {
                let status = try store.setFolder(url)
                DispatchQueue.main.async { reply(status, nil) }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { reply(nil, message) }
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingPick?(NSNull(), nil)
        pendingPick = nil
    }

    // MARK: - Links open in Safari, not inside the planner

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme == "http" || url.scheme == "https" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
