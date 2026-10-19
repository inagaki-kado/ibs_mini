import AVFoundation
import UIKit

/// プレビュー用ビュー。レイヤー自体が AVCaptureVideoPreviewLayer。
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// JS 側へ通知するカメラ状態
struct CameraState {
    var requestedFPS: Int
    var activeFPS: Double = 0
    var width: Int = 0
    var height: Int = 0
    var error: String? = nil

    var json: [String: Any] {
        var d: [String: Any] = ["requestedFps": requestedFPS, "activeFps": activeFPS, "width": width, "height": height]
        if let error { d["error"] = error }
        return d
    }
}

/// 背面広角カメラを指定 fps で駆動する。
/// 音声は扱わない（iOS 標準の画面収録のマイク録音と競合させないため）。
final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let fpsSteps = [60, 120, 240]
    /// 起動時の fps。前回の選択は引き継がず、毎回これで始める（大会中に 240 にしても、再起動で 120 に戻る）
    static let launchFPS = 120

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "beyhud.camera.session")
    private let videoQueue: DispatchQueue
    private let videoOutput = AVCaptureVideoDataOutput()
    /// リプレイ用リングバッファ（videoQueue 上で映像を受け取る）
    let recorder: ReplayRecorder
    private var device: AVCaptureDevice?
    private var isConfigured = false

    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    /// HDMI 側のプレビュー（同じ撮影セッションをもう1枚のレイヤーに映す）。メインスレッドでのみ触る
    private var currentPreviewAngle: CGFloat?
    // HDMI 側のカメラ映像。プレビューレイヤーをもう1枚つなぐと、スマホ側の映像が奪われて真っ黒になるため、
    // 録画用に受け取っているフレームを約60fpsに間引いて渡す（videoQueue で読むので lock で守る）
    private let externalLock = NSLock()
    private var externalVideo: ExternalCameraView?
    private var lastExternalPTS = CMTime.invalid

    // 実測 fps（videoQueue 上でのみ触る）
    private var frameCount = 0
    private var frameWindowStart = CACurrentMediaTime()

    private(set) var state: CameraState

    // 負荷への対応（発熱・システム圧力）。ユーザーが選んだ fps（preferredFPS）を上限で抑える。
    // preferredFPS / throttleCap は sessionQueue 上でのみ触る
    private var preferredFPS: Int
    private var throttleCap: Int?
    private var restoreWork: DispatchWorkItem?
    private var pressureObservation: NSKeyValueObservation?

    // 映像の途絶え検知（最後にフレームが届いた時刻。videoQueue で書き、main で読む）
    private let frameLock = NSLock()
    private var lastFrameTime = CACurrentMediaTime()
    private var stallTimer: Timer?
    private var lastRestart = Date.distantPast
    private var wantsRunning = false

    /// 状態変化（メインスレッドで呼ばれる）
    var onStateChange: ((CameraState) -> Void)?
    /// 実測 fps（約1秒ごと・メインスレッドで呼ばれる）
    var onMeasuredFPS: ((Double) -> Void)?

    override init() {
        let preferred = Self.launchFPS
        preferredFPS = preferred
        state = CameraState(requestedFPS: preferred)
        let videoQueue = DispatchQueue(label: "beyhud.camera.video")
        self.videoQueue = videoQueue
        recorder = ReplayRecorder(queue: videoQueue)
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError(_:)),
                                               name: AVCaptureSession.runtimeErrorNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted(_:)),
                                               name: AVCaptureSession.wasInterruptedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded),
                                               name: AVCaptureSession.interruptionEndedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill // score.html の object-fit: cover と同じ
    }

    /// HDMI 側の映像の出し先をつなぐ／外す（nil）。メインスレッドで呼ぶ
    func setExternalVideo(_ view: ExternalCameraView?) {
        if let angle = currentPreviewAngle { view?.setRotation(angle) }
        externalLock.lock()
        let old = externalVideo
        externalVideo = view
        lastExternalPTS = .invalid
        externalLock.unlock()
        if old !== view { old?.clear() }
    }

    /// スマホ側と HDMI 側のレイヤーに、同じ向きをかける
    private func applyPreviewAngle(_ angle: CGFloat) {
        currentPreviewAngle = angle
        previewLayer?.connection?.videoRotationAngle = angle
        externalLock.lock(); let ext = externalVideo; externalLock.unlock()
        ext?.setRotation(angle)
    }

    // MARK: - 起動

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.sessionQueue.async { self.configureAndRun() } }
                else { self.publishError("カメラ許可なし（設定アプリで許可してください）") }
            }
        default:
            publishError("カメラ許可なし（設定アプリで許可してください）")
        }
    }

    /// 60 → 120 → 240 → 60 と切り替える
    func cycleFPS() {
        sessionQueue.async {
            let steps = Self.fpsSteps
            let next = steps[((steps.firstIndex(of: self.preferredFPS) ?? 0) + 1) % steps.count]
            self.setPreferredFPS(next)
        }
    }

    /// ユーザーが選んだ fps。負荷による上限（throttleCap）があれば、その範囲に抑えて適用する
    func setFPS(_ fps: Int) {
        sessionQueue.async { self.setPreferredFPS(fps) }
    }

    private func setPreferredFPS(_ fps: Int) {
        preferredFPS = fps
        applyEffectiveFPS()
    }

    /// 実際に使う fps（= ユーザーの選択を、負荷による上限で抑えた値）を適用する。sessionQueue 上で呼ぶ
    private func applyEffectiveFPS() {
        let effective = min(preferredFPS, throttleCap ?? Int.max)
        state.requestedFPS = effective
        guard isConfigured, let device = device else { return }
        session.beginConfiguration()
        applyFormat(device: device, fps: effective)
        session.commitConfiguration()
        updateRecorderSettings()
        publishState()
    }

    private func configureAndRun() {
        if !isConfigured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                publishError("カメラが見つかりません")
                return
            }
            self.device = device
            session.beginConfiguration()
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { throw NSError(domain: "BeyHUD", code: 1) }
                session.addInput(input)
            } catch {
                session.commitConfiguration()
                publishError("カメラを開けません")
                return
            }
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            applyFormat(device: device, fps: state.requestedFPS)
            session.commitConfiguration()
            updateRecorderSettings()
            isConfigured = true
            DispatchQueue.main.async {
                self.setupRotation(device: device)
                self.observePressure(device)
                self.startStallWatch()
            }
        }
        wantsRunning = true
        if !session.isRunning { session.startRunning() }
        publishState()
    }

    // MARK: - フォーマット選択

    /// 1080p を優先して目標 fps に対応するフォーマットを選ぶ。無ければ fps を下げて探す。
    private func applyFormat(device: AVCaptureDevice, fps: Int) {
        let tryOrder = Self.fpsSteps.filter { $0 <= fps }.reversed()
        for target in tryOrder {
            guard let format = bestFormat(device: device, fps: target) else { continue }
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                let duration = CMTime(value: 1, timescale: CMTimeScale(target))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.unlockForConfiguration()
            } catch {
                continue
            }
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            state.activeFPS = Double(target)
            state.width = Int(dims.width)
            state.height = Int(dims.height)
            state.error = nil
            return
        }
        state.error = "\(fps)fps に対応するフォーマットがありません"
    }

    /// 現在のフォーマット・fps に合った HEVC のエンコード設定をリプレイ録画に渡す
    private func updateRecorderSettings() {
        let settings = videoOutput.recommendedVideoSettings(forVideoCodecType: .hevc, assetWriterOutputFileType: .mp4)
            ?? videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)
        recorder.updateOutputSettings(settings)
    }

    private func bestFormat(device: AVCaptureDevice, fps: Int) -> AVCaptureDevice.Format? {
        let fullRange = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let videoRange = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let candidates = device.formats.filter { f in
            let sub = CMFormatDescriptionGetMediaSubType(f.formatDescription)
            guard sub == fullRange || sub == videoRange else { return false }
            return f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(fps) }
        }
        // 評価: 1080p に近いほど良い（超えるものは避ける）→ フルレンジ優先 → ビニングなし優先
        func score(_ f: AVCaptureDevice.Format) -> (Int, Int, Int) {
            let h = Int(CMVideoFormatDescriptionGetDimensions(f.formatDescription).height)
            let sizeScore = h <= 1080 ? h : 1080 - (h - 1080)
            let rangeScore = CMFormatDescriptionGetMediaSubType(f.formatDescription) == fullRange ? 1 : 0
            let binScore = f.isVideoBinned ? 0 : 1
            return (sizeScore, rangeScore, binScore)
        }
        return candidates.max { score($0) < score($1) }
    }

    // MARK: - 向き

    private func setupRotation(device: AVCaptureDevice) {
        guard let previewLayer else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        applyPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] c, _ in
            DispatchQueue.main.async {
                self?.applyPreviewAngle(c.videoRotationAngleForHorizonLevelPreview)
            }
        }
        // 録画は画素を回転させず、ファイルの向き情報（transform）だけ合わせる（240fps での負荷を避ける）
        recorder.updateRotation(degrees: coordinator.videoRotationAngleForHorizonLevelCapture)
        captureRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] c, _ in
            self?.recorder.updateRotation(degrees: c.videoRotationAngleForHorizonLevelCapture)
        }
    }

    // MARK: - 映像フレーム（リプレイ録画・実測 fps）

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        recorder.append(sampleBuffer)
        forwardToExternal(sampleBuffer)
        frameLock.lock(); lastFrameTime = CACurrentMediaTime(); frameLock.unlock()
        frameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - frameWindowStart
        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            frameCount = 0
            frameWindowStart = now
            DispatchQueue.main.async { self.onMeasuredFPS?(fps) }
        }
    }

    /// HDMI は実質60Hzのため、それ以上の fps でも約60fpsに間引いて渡す（負荷を抑える）
    private func forwardToExternal(_ sampleBuffer: CMSampleBuffer) {
        externalLock.lock()
        guard let ext = externalVideo else { externalLock.unlock(); return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastExternalPTS.isValid, (pts - lastExternalPTS).seconds < 1.0 / 62 {
            externalLock.unlock(); return
        }
        lastExternalPTS = pts
        externalLock.unlock()
        ext.enqueue(sampleBuffer)
    }

    // MARK: - 異常系・負荷への対応

    @objc private func sessionRuntimeError(_ note: Notification) {
        let err = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)
        Diagnostics.shared.log("カメラのセッションでエラー: \(err?.localizedDescription ?? "不明") (code \(err?.code ?? 0))。再始動します")
        // メディアサービスのリセット等で止まった場合は再始動する
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    /// 電話・他アプリのカメラ利用・システム圧力などで、OS が撮影を一時停止した
    @objc private func sessionWasInterrupted(_ note: Notification) {
        var reason = "不明"
        if let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
           let r = AVCaptureSession.InterruptionReason(rawValue: raw) {
            switch r {
            case .videoDeviceNotAvailableInBackground: reason = "バックグラウンド"
            case .audioDeviceInUseByAnotherClient: reason = "音声機器を他のアプリが使用"
            case .videoDeviceInUseByAnotherClient: reason = "カメラを他のアプリが使用"
            case .videoDeviceNotAvailableWithMultipleForegroundApps: reason = "マルチタスク"
            case .videoDeviceNotAvailableDueToSystemPressure: reason = "⚠️ 端末の負荷（発熱など）"
            default: reason = "その他(\(raw))"
            }
        }
        Diagnostics.shared.log("カメラが OS に中断されました: \(reason)。\(Diagnostics.shared.statusLine())")
    }

    @objc private func sessionInterruptionEnded() {
        Diagnostics.shared.log("カメラの中断が終わりました。撮影を再開します")
        sessionQueue.async {
            if self.wantsRunning, !self.session.isRunning { self.session.startRunning() }
        }
    }

    @objc private func appDidBecomeActive() {
        // バックグラウンドの間はフレームが届かないのが普通なので、途絶え検知の基準をリセットする
        frameLock.lock(); lastFrameTime = CACurrentMediaTime(); frameLock.unlock()
    }

    /// 発熱（ProcessInfo）とカメラのシステム圧力の両方を見て、fps に上限をかける
    @objc private func thermalStateChanged() { evaluateLoad() }

    private func observePressure(_ device: AVCaptureDevice) {
        pressureObservation = device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] d, _ in
            let s = d.systemPressureState
            Diagnostics.shared.log("カメラのシステム圧力: \(s.level.rawValue)（要因: \(s.factors)）")
            self?.evaluateLoad()
        }
    }

    private func evaluateLoad() {
        var cap: Int?
        switch ProcessInfo.processInfo.thermalState {
        case .serious: cap = 120
        case .critical: cap = 60
        default: break
        }
        if let level = device?.systemPressureState.level {
            if level == .serious { cap = min(cap ?? Int.max, 120) }
            else if level == .critical || level == .shutdown { cap = 60 }
        }
        sessionQueue.async { self.setThrottle(cap) }
    }

    /// 上限をかける／外す。外すときは、負荷が下がってもすぐには戻さず60秒待つ（上げ下げの繰り返しを避ける）
    private func setThrottle(_ cap: Int?) {
        if let cap {
            restoreWork?.cancel(); restoreWork = nil
            guard cap < (throttleCap ?? Int.max) else { return }
            throttleCap = cap
            applyEffectiveFPS()
            Diagnostics.shared.log("負荷が高いため fps を \(state.requestedFPS) に制限しました")
            publishError("端末の負荷が高いため \(state.requestedFPS)fps に制限")
        } else if throttleCap != nil, restoreWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.restoreWork = nil
                self.throttleCap = nil
                self.applyEffectiveFPS()
                Diagnostics.shared.log("負荷が下がったため fps の制限を解除しました（\(self.state.requestedFPS)fps）")
            }
            restoreWork = work
            sessionQueue.asyncAfter(deadline: .now() + 60, execute: work)
        }
    }

    // MARK: - 映像の途絶え検知

    /// セッションが動いているはずなのに映像が来なくなったら、撮影を再起動する（固まったままにしない）
    private func startStallWatch() {
        guard stallTimer == nil else { return }
        stallTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.checkStall() }
    }

    private func checkStall() {
        guard wantsRunning, isConfigured, UIApplication.shared.applicationState == .active else { return }
        frameLock.lock(); let last = lastFrameTime; frameLock.unlock()
        let silent = CACurrentMediaTime() - last
        guard silent > 4, Date().timeIntervalSince(lastRestart) > 15 else { return }
        lastRestart = Date()
        Diagnostics.shared.log(String(format: "🛑 カメラの映像が %.1f 秒途絶えています。撮影を再起動します。%@", silent, Diagnostics.shared.statusLine()))
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.session.startRunning()
        }
    }

    private func publishState() {
        let s = state
        DispatchQueue.main.async { self.onStateChange?(s) }
    }

    private func publishError(_ message: String) {
        sessionQueue.async {
            self.state.error = message
            self.publishState()
        }
    }
}
