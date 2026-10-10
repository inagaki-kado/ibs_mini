import UIKit
import WebKit

/// ネイティブのカメラプレビューの上に、透過させた WKWebView（score.html）を重ねる。
/// score.html とは JS ブリッジ（messageHandlers.beyNative / window.onNativeCamera）でやり取りする。
final class HUDViewController: UIViewController, WKScriptMessageHandler {
    private let camera = CameraController()
    private let previewView = CameraPreviewView()
    private lazy var replay = ReplayPlayer(recorder: camera.recorder)
    private var webView: WKWebView!

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .black
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        camera.attach(previewLayer: previewView.previewLayer)
        view.addSubview(previewView)
        view.addSubview(replay.view) // カメラ映像の上・HUD(WebView)の下

        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(self), name: "beyNative")
        // 描画前に透過用クラスを付け、起動時に背景色が一瞬映るのを防ぐ
        contentController.addUserScript(WKUserScript(
            source: "document.documentElement.classList.add('native-cam');",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        webView.isInspectable = true // Mac の Safari「開発」メニューからデバッグ可能にする
        #endif
        view.addSubview(webView)

        camera.onStateChange = { [weak self] state in
            self?.callJS("onNativeCamera", state.json)
        }
        camera.onMeasuredFPS = { [weak self] fps in
            self?.callJS("onNativeCameraFps", ["fps": fps])
        }
        replay.onStateChange = { [weak self] state in
            self?.callJS("onNativeReplay", state)
        }

        if let url = Bundle.main.url(forResource: "score", withExtension: "html", subdirectory: "web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // previewView は transform を持つため frame ではなく bounds/center で配置する
        previewView.bounds = view.bounds
        previewView.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        replay.view.bounds = view.bounds
        replay.view.center = previewView.center
        webView.frame = view.bounds
    }

    // MARK: - JS → Native

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "cameraStart":
            camera.start()
        case "cameraCycle":
            camera.cycleFPS()
        case "transform":
            applyTransform(body)
        case "replayStart":
            replay.start()
        case "replayStop":
            replay.stop()
        case "replayPlay":
            replay.play(rate: (body["rate"] as? NSNumber)?.floatValue)
        case "replayPause":
            replay.pause()
        case "replayRate":
            if let r = body["rate"] as? NSNumber { replay.setRate(r.floatValue) }
        case "replaySeek":
            if let t = body["t"] as? NSNumber { replay.seek(to: t.doubleValue) }
        case "replayStep":
            replay.step((body["dir"] as? NSNumber)?.intValue ?? 1)
        case "replayFlush":
            camera.recorder.flush()
        default:
            break
        }
    }

    /// score.html の CSS transform `rotate(r) scale(s) translate(tx,ty)` と同じ変形をかける。
    /// カメラは中心基準、リプレイは 2x ズーム用に transform-origin（ox%, oy%）を反映する。
    private func applyTransform(_ body: [String: Any]) {
        func num(_ key: String, _ fallback: Double) -> CGFloat {
            CGFloat((body[key] as? NSNumber)?.doubleValue ?? fallback)
        }
        let rot = num("rot", 0) * .pi / 180
        let tx = num("tx", 0), ty = num("ty", 0)
        func cssTransform(scale: CGFloat) -> CGAffineTransform {
            CGAffineTransform(rotationAngle: rot).scaledBy(x: scale, y: scale).translatedBy(x: tx, y: ty)
        }
        let scale = num("scale", 1)
        previewView.transform = cssTransform(scale: scale)

        // UIView の transform は中心基準なので、origin までのずれ d を挟んで p' = d + T(p - d) にする
        let size = view.bounds.size
        let d = CGPoint(x: (num("ox", 50) / 100 - 0.5) * size.width, y: (num("oy", 50) / 100 - 0.5) * size.height)
        replay.view.transform = CGAffineTransform(translationX: -d.x, y: -d.y)
            .concatenating(cssTransform(scale: num("rscale", Double(scale))))
            .concatenating(CGAffineTransform(translationX: d.x, y: d.y))
    }

    // MARK: - Native → JS

    private func callJS(_ function: String, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.\(function) && window.\(function)(\(json));", completionHandler: nil)
    }
}

/// WKUserContentController が handler を強参照するため、循環参照を避ける中継
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}
