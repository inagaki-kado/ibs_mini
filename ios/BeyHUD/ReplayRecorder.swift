import AVFoundation
import UIKit

/// カメラ映像を約2秒ごとの短い mp4（HEVC）に区切って書き出し続け、直近 bufferSeconds 分だけ保持するリングバッファ。
/// 区切りごとに完結したファイルなので、古い区間を捨てても残りが壊れない（ブラウザ版 MediaRecorder の弱点の解消）。
/// append 以外のメソッドもすべて `queue`（カメラの videoQueue）上で状態を触る。
final class ReplayRecorder {
    struct Segment {
        let url: URL
        let start: CMTime
        let end: CMTime
    }

    static let segmentSeconds = 2.0
    static let bufferSeconds = 60.0 // score.html の REPLAY_BUFFER_MS と同じ

    private let queue: DispatchQueue
    private let directory: URL

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var segmentStart = CMTime.invalid
    private var lastPTS = CMTime.invalid
    private var segments: [Segment] = []
    private let finishing = DispatchGroup()
    private var retainedURLs = Set<URL>() // リプレイ再生中のファイル（削除しない）
    private var forceRotate = false

    private var outputSettings: [String: Any]?
    private var rotationDegrees: CGFloat = 0

    init(queue: DispatchQueue) {
        self.queue = queue
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("replay", isDirectory: true)
        try? FileManager.default.removeItem(at: directory) // 前回起動の残骸を掃除
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - 設定（fps 切替・向き変更）

    func updateOutputSettings(_ settings: [String: Any]?) {
        queue.async {
            self.outputSettings = settings
            self.forceRotate = true // fps が変わったら新しい区間から書き直す
        }
    }

    func updateRotation(degrees: CGFloat) {
        queue.async {
            guard self.rotationDegrees != degrees else { return }
            self.rotationDegrees = degrees
            self.forceRotate = true
        }
    }

    // MARK: - 書き込み（queue 上で呼ばれる）

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard outputSettings != nil else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if let writer, writer.status == .failed {
            // 書き込み失敗（バックグラウンド移行など）はその区間を捨てて次の区間から再開する
            self.writer = nil
            input = nil
        }
        if writer != nil, forceRotate || (pts - segmentStart).seconds >= Self.segmentSeconds {
            finishCurrentSegment()
        }
        if writer == nil {
            forceRotate = false
            startSegment(at: pts, format: CMSampleBufferGetFormatDescription(sampleBuffer))
        }
        guard let input, input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) { lastPTS = pts }
    }

    private func startSegment(at pts: CMTime, format: CMFormatDescription?) {
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = true
        input.transform = CGAffineTransform(rotationAngle: rotationDegrees * .pi / 180)
        guard writer.canAdd(input) else { return }
        writer.add(input)
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: pts)
        self.writer = writer
        self.input = input
        segmentStart = pts
        lastPTS = .invalid
    }

    private func finishCurrentSegment() {
        guard let writer, let input else { return }
        self.writer = nil
        self.input = nil
        let start = segmentStart
        let end = lastPTS
        guard end.isValid, end > start else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: writer.outputURL)
            return
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: end)
        finishing.enter()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            self.queue.async {
                if writer.status == .completed {
                    self.segments.append(Segment(url: writer.outputURL, start: start, end: end))
                    self.prune()
                } else {
                    try? FileManager.default.removeItem(at: writer.outputURL)
                }
                self.finishing.leave()
            }
        }
    }

    private func prune() {
        guard let newestEnd = segments.last?.end else { return }
        segments.removeAll { seg in
            let expired = (newestEnd - seg.end).seconds > Self.bufferSeconds
            if expired && !retainedURLs.contains(seg.url) {
                try? FileManager.default.removeItem(at: seg.url)
                return true
            }
            return false
        }
    }

    // MARK: - リプレイ用

    /// 書き込み中の区間を確定させ、保持中の全区間をつないだ composition を返す（メインスレッドで completion）
    func makeReplayAsset(completion: @escaping (AVMutableComposition?) -> Void) {
        queue.async {
            self.finishCurrentSegment()
            self.finishing.notify(queue: self.queue) {
                let segs = self.segments
                segs.forEach { self.retainedURLs.insert($0.url) }
                Task {
                    let asset = await Self.compose(segs)
                    await MainActor.run { completion(asset) }
                }
            }
        }
    }

    /// リプレイ終了時に呼ぶ。再生用に保持していたファイルを削除対象に戻す
    func releaseReplay() {
        queue.async {
            self.retainedURLs.removeAll()
            self.prune()
        }
    }

    /// 新しい試合開始時（score.html の flushRecorderBuffer 相当）。書き込み中の区間は残して過去分を捨てる
    func flush() {
        queue.async {
            self.segments.removeAll { seg in
                if self.retainedURLs.contains(seg.url) { return false }
                try? FileManager.default.removeItem(at: seg.url)
                return true
            }
        }
    }

    private static func compose(_ segments: [Segment]) async -> AVMutableComposition? {
        let composition = AVMutableComposition()
        guard !segments.isEmpty,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        for seg in segments {
            let asset = AVURLAsset(url: seg.url)
            guard let src = try? await asset.loadTracks(withMediaType: .video).first,
                  let range = try? await src.load(.timeRange) else { continue }
            do {
                try track.insertTimeRange(range, of: src, at: composition.duration)
                track.preferredTransform = (try? await src.load(.preferredTransform)) ?? .identity
            } catch {
                continue
            }
        }
        return composition.duration.seconds > 0 ? composition : nil
    }
}
