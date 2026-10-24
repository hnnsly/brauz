import Cocoa
import WebKit

final class TimingApp: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    let window: NSWindow
    let webView: WKWebView
    let targetURL: URL
    let totalRuns: Int
    var currentRun = 0
    var runsData: [[String: Double]] = []

    var submitTime: Double = 0
    var commitMs: Double = -1
    var layoutMs: Double = -1
    var finishMs: Double = -1
    var completedRun = false

    init(url: URL, runs: Int) {
        self.targetURL = url
        self.totalRuns = runs

        let rect = NSRect(x: 100, y: 100, width: 1180, height: 780)
        self.window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: NSRect(origin: .zero, size: rect.size), configuration: config)
        self.window.contentView = self.webView
        super.init()

        self.webView.navigationDelegate = self
        let observe = NSSelectorFromString("_setObservedRenderingProgressEvents:")
        if self.webView.responds(to: observe) {
            typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
            unsafeBitCast(self.webView.method(for: observe), to: Setter.self)(self.webView, observe, 1 << 1)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.orderBack(nil)
        startNextRun()
    }

    func startNextRun() {
        guard currentRun < totalRuns else {
            finishAll()
            return
        }
        currentRun += 1
        completedRun = false
        commitMs = -1
        layoutMs = -1
        finishMs = -1

        submitTime = CACurrentMediaTime()
        webView.load(URLRequest(url: targetURL))

        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            guard let self, !self.completedRun else { return }
            self.runFinished()
        }
    }

    func runFinished() {
        guard !completedRun else { return }
        completedRun = true
        runsData.append([
            "commit": commitMs,
            "layout": layoutMs,
            "finish": finishMs
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startNextRun()
        }
    }

    func finishAll() {
        let output: [String: Any] = [
            "url": targetURL.absoluteString,
            "runs": runsData
        ]
        if let data = try? JSONSerialization.data(withJSONObject: output, options: []),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
        NSApp.terminate(nil)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if commitMs < 0 {
            commitMs = (CACurrentMediaTime() - submitTime) * 1000
        }
    }

    @objc(_webView:renderingProgressDidChange:)
    func webView(_ webView: WKWebView, renderingProgressDidChange events: UInt) {
        if events & (1 << 1) != 0, layoutMs < 0 {
            layoutMs = (CACurrentMediaTime() - submitTime) * 1000
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if finishMs < 0 {
            finishMs = (CACurrentMediaTime() - submitTime) * 1000
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.runFinished()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if finishMs < 0 {
            finishMs = (CACurrentMediaTime() - submitTime) * 1000
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.runFinished()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if finishMs < 0 {
            finishMs = (CACurrentMediaTime() - submitTime) * 1000
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.runFinished()
        }
    }
}

let args = CommandLine.arguments
guard args.count > 1, let url = URL(string: args[1]) else {
    fputs("Usage: plainweb <url> [runs]\n", stderr)
    exit(1)
}
let runs = args.count > 2 ? (Int(args[2]) ?? 3) : 3

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = TimingApp(url: url, runs: runs)
app.delegate = delegate
app.run()
