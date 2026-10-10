import AVFoundation
import UIKit

/// リプレイ再生用ビュー。レイヤー自体が AVPlayerLayer。
final class ReplayPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// ReplayRecorder が保持している直近の映像を AVPlayer で再生する。
/// score.html 側は <video> と同じ感覚で操作できるよう、状態（t / dur / paused / rate）を onStateChange で通知する。
final class ReplayPlayer {
    let view = ReplayPlayerView()
    private let recorder: ReplayRecorder
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var rate: Float = 1
    private var isActive = false

    // シークの追いかけ処理: 実行中に次の要求が来たら、完了後に最新の目標へだけ飛ぶ
    private var seekTarget: CMTime?
    private var isSeeking = false

    /// 状態通知（メインスレッド）。["t", "dur", "paused", "rate"] または ["error"]
    var onStateChange: (([String: Any]) -> Void)?

    init(recorder: ReplayRecorder) {
        self.recorder = recorder
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor(red: 0x0a / 255, green: 0x0e / 255, blue: 0x17 / 255, alpha: 1) // cyber-bg
        view.playerLayer.videoGravity = .resizeAspectFill // score.html の object-fit: cover と同じ
    }

    // MARK: - 開始・終了

    /// 直近の映像を読み込み、末尾15秒前から等速再生する（ブラウザ版と同じ開始位置）
    func start() {
        guard !isActive else { return }
        isActive = true
        recorder.makeReplayAsset { [weak self] asset in
            guard let self, self.isActive else { return }
            guard let asset, asset.duration.seconds >= 0.3 else {
                self.isActive = false
                self.recorder.releaseReplay()
                self.onStateChange?(["error": "録画データなし"])
                return
            }
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            player.actionAtItemEnd = .pause
            self.player = player
            self.view.playerLayer.player = player
            self.view.isHidden = false
            self.rate = 1
            self.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] _ in
                self?.publish()
            }
            self.endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                                      object: item, queue: .main) { [weak self] _ in
                self?.publish()
            }
            let dur = asset.duration.seconds
            self.seek(to: max(0, dur - 15))
            player.rate = 1
            self.publish()
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        if let player {
            player.pause()
            if let timeObserver { player.removeTimeObserver(timeObserver) }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        seekTarget = nil
        isSeeking = false
        view.playerLayer.player = nil
        view.isHidden = true
        player = nil
        recorder.releaseReplay()
    }

    // MARK: - 操作

    func play(rate requested: Float?) {
        guard let player else { return }
        if let requested, requested > 0 { rate = requested }
        // 末尾で止まっている場合は <video> と同様に先頭から再生し直す
        if let item = player.currentItem, (item.duration - player.currentTime()).seconds < 0.05 {
            seek(to: 0)
        }
        player.rate = rate
        publish()
    }

    func pause() {
        player?.pause()
        publish()
    }

    func setRate(_ value: Float) {
        guard value > 0 else { return }
        rate = value
        if let player, player.rate != 0 { player.rate = value }
        publish()
    }

    func seek(to seconds: Double) {
        seekTarget = CMTime(seconds: max(0, seconds), preferredTimescale: 90_000)
        if !isSeeking { performSeek() }
        publish()
    }

    /// 1コマ送り/戻し（撮影 fps の1フレーム単位）
    func step(_ count: Int) {
        guard let player, let item = player.currentItem else { return }
        player.pause()
        item.step(byCount: count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.publish() }
    }

    private func performSeek() {
        guard let player, let target = seekTarget else { return }
        isSeeking = true
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.seekTarget == target {
                    self.seekTarget = nil
                    self.isSeeking = false
                    self.publish()
                } else {
                    self.performSeek()
                }
            }
        }
    }

    // MARK: - 状態通知

    private func publish() {
        guard isActive, let player, let item = player.currentItem else { return }
        let t = (seekTarget ?? player.currentTime()).seconds
        let dur = item.duration.seconds
        onStateChange?([
            "t": t.isFinite ? t : 0,
            "dur": dur.isFinite ? dur : 0,
            "paused": player.rate == 0,
            "rate": Double(rate),
        ])
    }
}
