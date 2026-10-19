import UIKit
import WebKit

/// ネイティブのカメラプレビューの上に、透過させた WKWebView（score.html）を重ねる。
/// score.html とは JS ブリッジ（messageHandlers.beyNative / window.onNativeCamera）でやり取りする。
final class HUDViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private let camera = CameraController()
    private let previewView = CameraPreviewView()
    private lazy var replay = ReplayPlayer(recorder: camera.recorder)
    private var webView: WKWebView!
    /// カメラ・リプレイ・HUD を載せる 16:9 の領域。HDMI 接続中だけ画面の中央に 16:9 で収める（左右に黒帯）。
    /// 未接続のときは画面いっぱい（従来どおり）。
    private let stageView = UIView()
    private var externalConnected = false
    private var transform = HUDTransform()

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
        stageView.clipsToBounds = true // ズームした映像が黒帯にはみ出さないようにする
        view.addSubview(stageView)
        stageView.addSubview(previewView)
        #if DEBUG
        DebugGridView.attach(to: previewView)
        #endif
        stageView.addSubview(replay.view) // カメラ映像の上・HUD(WebView)の下

        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(self), name: "beyNative")
        // HDMI 側へ画面の変化を送る（HDMI 接続中だけ有効になる。score.html 自体は変えない）
        contentController.add(WeakScriptMessageHandler(self), name: "beyMirror")
        contentController.addUserScript(WKUserScript(
            source: MirrorScripts.leader, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        // 描画前に透過用クラスを付け、起動時に背景色が一瞬映るのを防ぐ
        contentController.addUserScript(WKUserScript(
            source: "document.documentElement.classList.add('native-cam');",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        webView.isInspectable = true // Mac の Safari「開発」メニューからデバッグ可能にする
        #endif
        stageView.addSubview(webView)

        camera.onStateChange = { [weak self] state in
            self?.callJS("onNativeCamera", state.json)
        }
        camera.onMeasuredFPS = { [weak self] fps in
            self?.callJS("onNativeCameraFps", ["fps": fps])
        }
        replay.onStateChange = { [weak self] state in
            self?.callJS("onNativeReplay", state)
        }

        if var url = Bundle.main.url(forResource: "score", withExtension: "html", subdirectory: "web") {
            let base = url.deletingLastPathComponent()
            #if DEBUG
            // シミュレータ確認用: 起動引数 -BeyPeerCode 9981 で接続コードを変える（実機の本番コード 0511 を奪わないため）
            if let code = UserDefaults.standard.string(forKey: "BeyPeerCode"),
               var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                comps.queryItems = [URLQueryItem(name: "peer", value: code)]
                if let u = comps.url { url = u }
            }
            #endif
            webView.loadFileURL(url, allowingReadAccessTo: base)
        }
        DisplayCoordinator.shared.register(main: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // HDMI 接続中は 16:9 に収めて、HDMI 側とレイアウトを一致させる
        stageView.frame = externalConnected ? Stage.fit(in: view.bounds) : view.bounds
        let local = CGRect(origin: .zero, size: stageView.bounds.size)
        // previewView は transform を持つため frame ではなく bounds/center で配置する
        previewView.bounds = local
        previewView.center = CGPoint(x: local.midX, y: local.midY)
        replay.view.bounds = local
        replay.view.center = previewView.center
        webView.frame = local
        applyCurrentTransform()
        DisplayCoordinator.shared.mainStageChanged(stageView.bounds.size)
    }

    #if DEBUG
    // シミュレータ確認用: 起動引数 -BeyMirrorDebug YES を付けると、HDMI 側の画面を実物の代わりに
    // スマホ画面の右上へ小さく重ねて表示する（HUD の複製・ズームの同期を目で見て確かめるため）。本番ビルドには入らない。
    //   -BeyMirrorDebugDetachAfter 秒   … その秒数後に HDMI を抜いた状況にする（スマホ側が全画面に戻るか）
    //   -BeyMirrorDebugReattachAfter 秒 … 取り外しのさらにその秒数後に、もう一度つなぐ（再接続できるか）
    private var debugExternal: ExternalHUDViewController?
    private var debugStarted = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ProcessInfo.processInfo.arguments.contains("-BeyMirrorDebug"), !debugStarted else { return }
        debugStarted = true
        let defaults = UserDefaults.standard
        let detachAfter = defaults.double(forKey: "BeyMirrorDebugDetachAfter")
        let reattachAfter = defaults.double(forKey: "BeyMirrorDebugReattachAfter")
        NSLog("[Mirror] debug detachAfter=%.1f reattachAfter=%.1f", detachAfter, reattachAfter)
        debugAttach()
        guard detachAfter > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + detachAfter) { [weak self] in
            NSLog("[Mirror] debug detach now")
            self?.debugDetach()
            guard reattachAfter > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + reattachAfter) { [weak self] in
                NSLog("[Mirror] debug reattach now")
                self?.debugAttach()
            }
        }
    }

    private func debugAttach() {
        guard debugExternal == nil else { return }
        let ext = ExternalHUDViewController()
        addChild(ext)
        let w = view.bounds.width * 0.5
        ext.view.frame = CGRect(x: view.bounds.width - w - 4, y: 4, width: w, height: w / Stage.aspect)
        ext.view.layer.borderColor = UIColor.yellow.cgColor
        ext.view.layer.borderWidth = 2
        view.addSubview(ext.view)
        ext.didMove(toParent: self)
        debugExternal = ext
        DisplayCoordinator.shared.externalConnected(ext)
    }

    private func debugDetach() {
        guard let ext = debugExternal else { return }
        DisplayCoordinator.shared.externalDisconnected(ext)
        ext.willMove(toParent: nil)
        ext.view.removeFromSuperview()
        ext.removeFromParent()
        debugExternal = nil
    }
    #endif

    // MARK: - HDMI（外部ディスプレイ）

    /// HDMI 側の画面ができた。スマホ側も 16:9 に収め、カメラ・リプレイを HDMI 側にも映す
    func attachExternal(_ ext: ExternalHUDViewController) {
        externalConnected = true
        ext.loadViewIfNeeded()
        camera.addPreviewLayer(ext.previewView.previewLayer)
        replay.addExtraView(ext.replayView)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        ext.relayout()
        if ext.isReady { startMirror() }
    }

    func detachExternal(_ ext: ExternalHUDViewController) {
        externalConnected = false
        camera.removePreviewLayer(ext.previewView.previewLayer)
        replay.removeExtraView(ext.replayView)
        webView.evaluateJavaScript("window.__beyMirrorEnable && window.__beyMirrorEnable(false);", completionHandler: nil)
        view.setNeedsLayout()
    }

    // MARK: - 固まり対策（WebContent の死亡・JS の無応答・メモリ警告）

    private var heartbeatTimer: Timer?
    private var lastHeartbeatReply = Date()
    private var lastWebRecovery = Date.distantPast

    /// WebKit の描画プロセスが OS に終了させられた（メモリ不足など）。放置すると画面が真っ白のまま固まる
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Diagnostics.shared.log("🛑 score.html の描画プロセスが終了しました（画面が白くなる原因）。再読み込みします。\(Diagnostics.shared.statusLine())")
        recoverWebView(reason: "WebContent 終了")
    }

    private func recoverWebView(reason: String) {
        guard Date().timeIntervalSince(lastWebRecovery) > 5 else { return }
        lastWebRecovery = Date()
        lastHeartbeatReply = Date()
        webView.reload()
    }

    /// JS が応答しなくなったら再読み込みする。score.html は localStorage から試合状態を復元するので、スコアは戻る
    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        lastHeartbeatReply = Date()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, UIApplication.shared.applicationState == .active, !self.webView.isLoading else {
                self?.lastHeartbeatReply = Date(); return
            }
            self.webView.evaluateJavaScript("1") { [weak self] _, error in
                if error == nil { self?.lastHeartbeatReply = Date() }
            }
            let silent = Date().timeIntervalSince(self.lastHeartbeatReply)
            if silent > 12 {
                Diagnostics.shared.log(String(format: "🛑 score.html の JS が %.0f 秒応答しません。再読み込みします。%@", silent, Diagnostics.shared.statusLine()))
                self.recoverWebView(reason: "JS 無応答")
            }
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        Diagnostics.shared.log("⚠️ メモリ警告。リプレイの保持を20秒分に縮めます。\(Diagnostics.shared.statusLine())")
        camera.recorder.trim(keepSeconds: 20)
    }

    /// score.html の読み込みが終わったら（起動時・SYS_RELOAD のリロード後）、HDMI 側への複製を始め直す。
    /// ページが読み込み中に「開始」を指示しても、差し込んだスクリプトがまだ無く取りこぼすため。
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastHeartbeatReply = Date()
        startHeartbeat()
        startMirror()
    }

    /// スマホ側 score.html の画面の変化を HDMI 側へ送り始める（最初に全体を送る）。
    /// HDMI 側のページの準備が済んでいるときだけ送る（準備ができたら externalReady から改めて呼ばれる）
    func startMirror() {
        guard externalConnected, DisplayCoordinator.shared.external?.isReady == true else { return }
        webView.evaluateJavaScript("window.__beyMirrorEnable && window.__beyMirrorEnable(true);", completionHandler: nil)
    }

    // MARK: - JS → Native

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "beyMirror" {
            if let json = message.body as? String { DisplayCoordinator.shared.forwardMirror(json) }
            return
        }
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

    /// score.html の CSS transform と同じ変形を、スマホ側と HDMI 側の両方にかける。
    private func applyTransform(_ body: [String: Any]) {
        transform = HUDTransform(body: body)
        applyCurrentTransform()
        DisplayCoordinator.shared.transformChanged(transform)
    }

    private func applyCurrentTransform() {
        transform.apply(preview: previewView, replay: replay.view, stageSize: stageView.bounds.size)
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
