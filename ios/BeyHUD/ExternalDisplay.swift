import UIKit
import WebKit
import AVFoundation

// MARK: - ステージ（16:9）

/// スマホ画面と HDMI で同じ見た目にするための基準領域（16:9）。
/// HDMI 接続中は、スマホ側も 16:9 に収めて（左右に黒帯）、レイアウトを HDMI と一致させる。
enum Stage {
    static let aspect: CGFloat = 16.0 / 9.0

    /// rect の中に収まる最大の 16:9 の領域（中央寄せ）
    static func fit(in rect: CGRect) -> CGRect {
        guard rect.width > 0, rect.height > 0 else { return rect }
        var w = rect.width
        var h = w / aspect
        if h > rect.height { h = rect.height; w = h * aspect }
        return CGRect(x: rect.minX + (rect.width - w) / 2, y: rect.minY + (rect.height - h) / 2, width: w, height: h).integral
    }
}

// MARK: - カメラ・リプレイの変形

/// score.html の CSS transform `rotate(r) scale(s) translate(tx,ty)` と同じ変形（JS から届く値）。
/// 画面ごとに大きさが違うので、移動量（px）は `unit`（その画面のステージ幅 / スマホのステージ幅）で換算して使う。
struct HUDTransform {
    var rot: CGFloat = 0
    var scale: CGFloat = 1
    var tx: CGFloat = 0
    var ty: CGFloat = 0
    var rscale: CGFloat = 1
    var ox: CGFloat = 50
    var oy: CGFloat = 50

    init() {}

    init(body: [String: Any]) {
        func num(_ key: String, _ fallback: Double) -> CGFloat {
            CGFloat((body[key] as? NSNumber)?.doubleValue ?? fallback)
        }
        rot = num("rot", 0) * .pi / 180
        tx = num("tx", 0)
        ty = num("ty", 0)
        scale = num("scale", 1)
        rscale = num("rscale", Double(scale))
        ox = num("ox", 50)
        oy = num("oy", 50)
    }

    /// カメラは中心基準、リプレイは 2x ズーム用に transform-origin（ox%, oy%）を反映する。
    /// UIView の transform は中心基準なので、origin までのずれ d を挟んで p' = d + T(p - d) にする。
    func apply(preview: UIView, replay: UIView, stageSize: CGSize, unit: CGFloat = 1) {
        func css(scale s: CGFloat) -> CGAffineTransform {
            CGAffineTransform(rotationAngle: rot).scaledBy(x: s, y: s).translatedBy(x: tx * unit, y: ty * unit)
        }
        preview.transform = css(scale: scale)
        let d = CGPoint(x: (ox / 100 - 0.5) * stageSize.width, y: (oy / 100 - 0.5) * stageSize.height)
        replay.transform = CGAffineTransform(translationX: -d.x, y: -d.y)
            .concatenating(css(scale: rscale))
            .concatenating(CGAffineTransform(translationX: d.x, y: d.y))
    }
}

// MARK: - 画面どうしの橋渡し

/// スマホ画面（HUDViewController）と HDMI 画面（ExternalHUDViewController）をつなぐ。
final class DisplayCoordinator {
    static let shared = DisplayCoordinator()
    private init() {}

    private(set) weak var main: HUDViewController?
    private(set) weak var external: ExternalHUDViewController?

    /// スマホ側ステージの大きさ（pt = score.html の CSS px）。HDMI 側の拡大率（pageZoom）の基準
    private(set) var mainStageSize: CGSize = .zero
    private(set) var transform = HUDTransform()

    func register(main: HUDViewController) {
        self.main = main
        if let external { main.attachExternal(external) }
    }

    func externalConnected(_ vc: ExternalHUDViewController) {
        external = vc
        main?.attachExternal(vc)
    }

    func externalDisconnected(_ vc: ExternalHUDViewController) {
        guard external === vc else { return }
        external = nil
        main?.detachExternal(vc)
    }

    func externalReady() { main?.startMirror() }

    func mainStageChanged(_ size: CGSize) {
        mainStageSize = size
        external?.relayout()
    }

    func transformChanged(_ t: HUDTransform) {
        transform = t
        external?.applyTransform()
    }

    func forwardMirror(_ json: String) {
        #if DEBUG
        NSLog("[Mirror] forward %d bytes (external=%@)", json.utf8.count, external == nil ? "nil" : "ok")
        #endif
        external?.applyMirror(json)
    }
}

// MARK: - HDMI 側の画面

/// HDMI に出す画面。スマホと同じ 16:9 のステージに、カメラ・リプレイ・HUD を重ねる。
/// カメラ/リプレイは同じ撮影セッション/プレーヤーのレイヤーをもう1枚持ち、スマホと同じ変形をかける。
/// HUD は mirror.html に、スマホ側 score.html の画面の変化を複製して表示する。
final class ExternalHUDViewController: UIViewController, WKNavigationDelegate {
    /// HDMI 側のカメラ映像（カメラのフレームを受け取って表示する。プレビューレイヤーは使わない）
    let previewView = ExternalCameraView()
    let replayView = ReplayPlayerView()
    private let stageView = UIView()
    private var webView: WKWebView!
    private(set) var isReady = false
    private var lastViewportKey = ""

    override var prefersStatusBarHidden: Bool { true }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .black
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        stageView.clipsToBounds = true
        view.addSubview(stageView)
        stageView.addSubview(previewView)
        #if DEBUG
        DebugGridView.attach(to: previewView)
        #endif

        replayView.isHidden = true
        replayView.isUserInteractionEnabled = false
        replayView.backgroundColor = UIColor(red: 0x0a / 255, green: 0x0e / 255, blue: 0x17 / 255, alpha: 1) // cyber-bg
        replayView.playerLayer.videoGravity = .resizeAspectFill
        stageView.addSubview(replayView)

        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = false
        stageView.addSubview(webView)

        if let url = Bundle.main.url(forResource: "mirror", withExtension: "html", subdirectory: "web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        relayout()
    }

    /// ステージ（16:9）を画面に収め、中身を敷き直す。HUD は pageZoom で、スマホ側と同じ CSS の大きさに揃える。
    func relayout() {
        guard isViewLoaded else { return }
        let frame = Stage.fit(in: view.bounds)
        stageView.frame = frame
        let local = CGRect(origin: .zero, size: frame.size)
        // previewView / replayView は transform を持つため frame ではなく bounds/center で配置する
        previewView.bounds = local
        previewView.center = CGPoint(x: local.midX, y: local.midY)
        replayView.bounds = local
        replayView.center = previewView.center
        webView.frame = local
        // HUD は、スマホ側のステージ幅（CSS px）を表示幅に固定し、HDMI の幅に合わせて倍率をかける
        let mainW = DisplayCoordinator.shared.mainStageSize.width
        if isReady, mainW > 0, frame.width > 0 {
            let scale = frame.width / mainW
            let key = String(format: "%.1f|%.4f", mainW, scale)
            if key != lastViewportKey {
                lastViewportKey = key
                webView.evaluateJavaScript("window.__mirrorViewport(\(mainW), \(scale));") { _, error in
                    #if DEBUG
                    NSLog("[Mirror] viewport width=%.1f scale=%.4f error=%@", mainW, scale, String(describing: error))
                    #endif
                }
            }
        }
        applyTransform()
    }

    func applyTransform() {
        guard isViewLoaded else { return }
        let size = stageView.bounds.size
        let mainW = DisplayCoordinator.shared.mainStageSize.width
        let unit = (mainW > 0 && size.width > 0) ? size.width / mainW : 1
        DisplayCoordinator.shared.transform.apply(preview: previewView, replay: replayView, stageSize: size, unit: unit)
    }

    /// スマホ側 score.html から届いた画面の変化（JSON 文字列）を HDMI 側のページへ渡す
    func applyMirror(_ json: String) {
        guard isReady else { return }
        webView.evaluateJavaScript("window.__mirrorApply && window.__mirrorApply(\(json));") { _, error in
            #if DEBUG
            if let error { NSLog("[Mirror] apply error: %@", String(describing: error)) }
            #endif
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[Mirror] follower fail: %@", String(describing: error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Diagnostics.shared.log("⚠️ HDMI 側の描画プロセスが終了しました。再読み込みします")
        isReady = false
        webView.reload()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[Mirror] follower provisional fail: %@", String(describing: error))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        NSLog("[Mirror] follower page loaded")
        #endif
        isReady = true
        relayout() // 読み込み前に敷いた pageZoom は無効になることがあるため、読み込み後に改めて合わせる
        DisplayCoordinator.shared.externalReady()
    }
}

// MARK: - HDMI 側のカメラ映像

/// カメラのフレーム（CMSampleBuffer）をそのまま表示するビュー。
/// 通常の AVCaptureSession はプレビューレイヤーを1つしか持てず、2枚目をつなぐとスマホ側が真っ黒になるため、
/// HDMI 側はこちらで表示する。フレームはセンサーの向きのままなので、スマホ側のプレビューと同じ角度で回す。
final class ExternalCameraView: UIView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var angle: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.masksToBounds = true
        displayLayer.videoGravity = .resizeAspectFill // スマホ側と同じ cover 表示
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// スマホ側プレビューの videoRotationAngle と同じ角度（度）。メインスレッドで呼ぶ
    func setRotation(_ degrees: CGFloat) {
        guard degrees != angle else { return }
        angle = degrees
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let sideways = abs(sin(angle * .pi / 180)) > 0.5
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.setAffineTransform(.identity)
        displayLayer.bounds = CGRect(origin: .zero, size: sideways ? CGSize(width: b.height, height: b.width) : b.size)
        displayLayer.position = CGPoint(x: b.midX, y: b.midY)
        displayLayer.setAffineTransform(CGAffineTransform(rotationAngle: angle * .pi / 180))
        CATransaction.commit()
    }

    /// カメラのキュー（videoQueue）から呼ばれる。届いた瞬間に表示させる
    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        var copy: CMSampleBuffer?
        guard CMSampleBufferCreateCopy(allocator: nil, sampleBuffer: sampleBuffer, sampleBufferOut: &copy) == noErr,
              let copy else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(copy, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        if renderer.isReadyForMoreMediaData { renderer.enqueue(copy) }
    }

    /// HDMI を抜いたとき。最後のコマを残さない
    func clear() {
        displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }
}

// MARK: - 外部ディスプレイ用シーン

final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let vc = ExternalHUDViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = vc
        window.isHidden = false
        self.window = window
        DisplayCoordinator.shared.externalConnected(vc)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let vc = window?.rootViewController as? ExternalHUDViewController {
            DisplayCoordinator.shared.externalDisconnected(vc)
        }
        window = nil
    }
}

#if DEBUG
/// シミュレータ確認用（-BeyMirrorDebug のときだけ）。カメラが無くても、ズーム・移動・回転が
/// スマホ側と HDMI 側で同じに見えるかを目で確かめられるよう、格子と「TOP」を描く。本番ビルドには入らない。
final class DebugGridView: UIView {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-BeyMirrorDebug") }

    static func attach(to host: UIView) {
        guard enabled else { return }
        let grid = DebugGridView(frame: host.bounds)
        grid.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(grid)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.14, alpha: 1)
        contentMode = .redraw
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.cyan.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(1)
        let n: CGFloat = 8
        for i in 0...Int(n) {
            let x = bounds.width * CGFloat(i) / n, y = bounds.height * CGFloat(i) / n
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height))
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        ctx.strokePath()
        ctx.setStrokeColor(UIColor.yellow.cgColor)
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: bounds.midX, y: 0)); ctx.addLine(to: CGPoint(x: bounds.midX, y: bounds.height))
        ctx.move(to: CGPoint(x: 0, y: bounds.midY)); ctx.addLine(to: CGPoint(x: bounds.width, y: bounds.midY))
        ctx.strokePath()
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: bounds.height * 0.09), .foregroundColor: UIColor.red]
        ("TOP ▲" as NSString).draw(at: CGPoint(x: bounds.midX + 6, y: 4), withAttributes: attrs)
    }
}
#endif
