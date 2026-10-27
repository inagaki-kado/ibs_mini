import AVFoundation

// 完成した 1080p 動画を YouTube 推奨の形式に書き出し直す（編集内容は変えない）
// usage: youtube <in.mp4> <out.mp4>
//   ・映像: H.264 High / 1920x1080 / 固定 59.94fps / 12Mbps（bey_edit の出力は freeze やリプレイで可変fpsになるため固定化する）
//   ・音声: AAC 48kHz ステレオ 256kbps（384kbps は AVFoundation の AAC エンコーダーが受け付けない）
//   ・moov を先頭に置く（アップロード後の処理開始が早い）
let a = CommandLine.arguments
let src = URL(fileURLWithPath: a[1]), dst = URL(fileURLWithPath: a[2])
try? FileManager.default.removeItem(at: dst)
let frame = CMTime(value: 1001, timescale: 60000)
let sem = DispatchSemaphore(value: 0)
Task {
  let asset = AVURLAsset(url: src)
  let vt = try! await asset.loadTracks(withMediaType: .video).first!
  let at = try! await asset.loadTracks(withMediaType: .audio).first!
  let duration = try! await asset.load(.duration)
  let reader = try! AVAssetReader(asset: asset)
  let vo = AVAssetReaderTrackOutput(track: vt, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
  let ao = AVAssetReaderTrackOutput(track: at, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
                                                                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                                                                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
  vo.alwaysCopiesSampleData = false
  reader.add(vo); reader.add(ao)
  let writer = try! AVAssetWriter(outputURL: dst, fileType: .mp4)
  writer.shouldOptimizeForNetworkUse = true
  let vi = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000, AVVideoMaxKeyFrameIntervalKey: 30,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                      AVVideoExpectedSourceFrameRateKey: 60, AVVideoAllowFrameReorderingKey: true]])
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vi, sourcePixelBufferAttributes: nil)
  let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2,
                                                                  AVSampleRateKey: 48000, AVEncoderBitRateKey: 256000])
  vi.expectsMediaDataInRealTime = false; ai.expectsMediaDataInRealTime = false
  writer.add(vi); writer.add(ai)
  reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)

  let g = DispatchGroup()
  // 固定fps化: 出力の各コマ時刻 T に、T 以前で最新の元フレームを当てる（足りなければ前のコマを繰り返す）
  var n: Int64 = 0
  var cur: CVPixelBuffer? = nil
  var next: CMSampleBuffer? = vo.copyNextSampleBuffer()
  let total = Int64((duration.seconds / frame.seconds).rounded(.down))
  var lastPct = -1
  g.enter(); vi.requestMediaDataWhenReady(on: DispatchQueue(label: "v")) {
    while vi.isReadyForMoreMediaData {
      if n >= total { vi.markAsFinished(); g.leave(); return }
      let T = CMTimeMultiply(frame, multiplier: Int32(n))
      while let s = next, CMSampleBufferGetPresentationTimeStamp(s) <= T + CMTime(value: 1, timescale: 1000) {
        cur = CMSampleBufferGetImageBuffer(s); next = vo.copyNextSampleBuffer()
      }
      if cur == nil, let s = next { cur = CMSampleBufferGetImageBuffer(s) }
      if let pb = cur { adaptor.append(pb, withPresentationTime: T) }
      n += 1
      let pct = Int(n * 100 / max(total, 1))
      if pct % 10 == 0 && pct != lastPct { lastPct = pct; print("progress \(pct)%"); fflush(stdout) }
    }
  }
  g.enter(); ai.requestMediaDataWhenReady(on: DispatchQueue(label: "a")) {
    while ai.isReadyForMoreMediaData {
      guard let sb = ao.copyNextSampleBuffer() else { ai.markAsFinished(); g.leave(); return }
      ai.append(sb)
    }
  }
  await withCheckedContinuation { c in g.notify(queue: .global()) { c.resume() } }
  await writer.finishWriting()
  print("status", writer.status == .completed ? "ok" : "FAILED \(writer.error.map { "\($0)" } ?? "")", "frames", n)
  sem.signal()
}
sem.wait()
