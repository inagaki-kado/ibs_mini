import AVFoundation

// スマホ確認用の軽い版を作る（Remote Control の送信上限 30MiB に収めるため）
// usage: phone <in.mp4> <out.mp4> <videoBitrate> [from=0] [to=end] [width=854]
//   目安: 長さ L 秒を 28MiB に収めるなら videoBitrate ≒ 28*8*1048576/L - 70000
//   音声は AAC 64kbps 固定（48kbps 以下はエンコードに失敗する）
let a = CommandLine.arguments
let src = URL(fileURLWithPath: a[1]), dst = URL(fileURLWithPath: a[2])
let vbr = Int(a[3])!
let t0 = a.count > 4 ? Double(a[4])! : 0, t1 = a.count > 5 ? Double(a[5])! : 1e9
let width = a.count > 6 ? Int(a[6])! : 854
try? FileManager.default.removeItem(at: dst)
let sem = DispatchSemaphore(value: 0)
Task {
  let asset = AVURLAsset(url: src)
  let vt = try! await asset.loadTracks(withMediaType: .video).first!
  let at = try! await asset.loadTracks(withMediaType: .audio).first!
  let reader = try! AVAssetReader(asset: asset)
  let vo = AVAssetReaderTrackOutput(track: vt, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
  let ao = AVAssetReaderTrackOutput(track: at, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
  reader.add(vo); reader.add(ao)
  reader.timeRange = CMTimeRange(start: CMTime(seconds: t0, preferredTimescale: 600), end: CMTime(seconds: t1, preferredTimescale: 600))
  let writer = try! AVAssetWriter(outputURL: dst, fileType: .mp4)
  writer.shouldOptimizeForNetworkUse = true
  let vi = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: width * 9 / 16,
    AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: vbr, AVVideoMaxKeyFrameIntervalKey: 60,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoExpectedSourceFrameRateKey: 30]])
  let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 44100, AVEncoderBitRateKey: 64000])
  vi.expectsMediaDataInRealTime = false; ai.expectsMediaDataInRealTime = false
  writer.add(vi); writer.add(ai)
  reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: CMTime(seconds: t0, preferredTimescale: 600))
  let g = DispatchGroup(); var lastV = -1.0
  g.enter(); vi.requestMediaDataWhenReady(on: DispatchQueue(label: "v")) {
    while vi.isReadyForMoreMediaData {
      guard let sb = vo.copyNextSampleBuffer() else { vi.markAsFinished(); g.leave(); return }
      let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
      if t - lastV < 1.0 / 30 - 0.002 { continue }   // 約30fpsに間引き
      lastV = t; vi.append(sb)
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
  print("status", writer.status == .completed ? "ok" : "FAILED \(writer.error.map { "\($0)" } ?? "")")
  sem.signal()
}
sem.wait()
