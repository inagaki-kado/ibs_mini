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
    private static let fpsDefaultsKey = "cameraFPS"

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

    // 実測 fps（videoQueue 上でのみ触る）
    private var frameCount = 0
    private var frameWindowStart = CACurrentMediaTime()

    private(set) var state: CameraState

    /// 状態変化（メインスレッドで呼ばれる）
    var onStateChange: ((CameraState) -> Void)?
    /// 実測 fps（約1秒ごと・メインスレッドで呼ばれる）
    var onMeasuredFPS: ((Double) -> Void)?

    override init() {
        let saved = UserDefaults.standard.integer(forKey: Self.fpsDefaultsKey)
        state = CameraState(requestedFPS: Self.fpsSteps.contains(saved) ? saved : 60)
        let videoQueue = DispatchQueue(label: "beyhud.camera.video")
        self.videoQueue = videoQueue
        recorder = ReplayRecorder(queue: videoQueue)
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError(_:)),
                                               name: AVCaptureSession.runtimeErrorNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill // score.html の object-fit: cover と同じ
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
        let steps = Self.fpsSteps
        let next = steps[((steps.firstIndex(of: state.requestedFPS) ?? 0) + 1) % steps.count]
        setFPS(next)
    }

    func setFPS(_ fps: Int) {
        UserDefaults.standard.set(fps, forKey: Self.fpsDefaultsKey)
        sessionQueue.async {
            self.state.requestedFPS = fps
            guard self.isConfigured, let device = self.device else { return }
            self.session.beginConfiguration()
            self.applyFormat(device: device, fps: fps)
            self.session.commitConfiguration()
            self.updateRecorderSettings()
            self.publishState()
        }
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
            DispatchQueue.main.async { self.setupRotation(device: device) }
        }
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
        previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] c, _ in
            DispatchQueue.main.async {
                self?.previewLayer?.connection?.videoRotationAngle = c.videoRotationAngleForHorizonLevelPreview
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

    // MARK: - 異常系

    @objc private func sessionRuntimeError(_ note: Notification) {
        // メディアサービスのリセット等で止まった場合は再始動する
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    @objc private func thermalStateChanged() {
        // 端末が危険温度に達したら 60fps に落とす（大会中にカメラが止まるのを防ぐ）
        if ProcessInfo.processInfo.thermalState == .critical && state.requestedFPS > 60 {
            setFPS(60)
            publishError("端末高温のため 60fps に切替")
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
