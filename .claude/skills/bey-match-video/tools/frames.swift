import AVFoundation
import AppKit

// 動画情報の表示と、指定秒の静止画書き出し（回転は自動補正）
// usage: frames <video> <outdir> [--exact] [--full] t1 t2 …
//   既定は ±0.1秒の許容で速く取り出す。--exact でフレーム単位、--full で原寸
let a = Array(CommandLine.arguments.dropFirst())
let url = URL(fileURLWithPath: a[0]), out = a[1]
let exact = a.contains("--exact"), full = a.contains("--full")
let times = a.dropFirst(2).filter { !$0.hasPrefix("--") }.map { Double($0)! }
let sem = DispatchSemaphore(value: 0)
Task {
  do {
    let asset = AVURLAsset(url: url)
    let v = try await asset.loadTracks(withMediaType: .video).first!
    let (fps, size, tr) = try await v.load(.nominalFrameRate, .naturalSize, .preferredTransform)
    let dur = try await asset.load(.duration).seconds
    let o = size.applying(tr)
    print(String(format: "duration %.2fs  fps %.2f  display %.0fx%.0f", dur, fps, abs(o.width), abs(o.height)))
    let g = AVAssetImageGenerator(asset: asset)
    g.appliesPreferredTrackTransform = true
    let tol = exact ? CMTime.zero : CMTime(value: 1, timescale: 10)
    g.requestedTimeToleranceBefore = tol; g.requestedTimeToleranceAfter = tol
    if !full { g.maximumSize = CGSize(width: 640, height: 640) }
    for t in times {
      let (img, actual) = try await g.image(at: CMTime(seconds: t, preferredTimescale: 600))
      let p = "\(out)/f_\(String(format: "%08.2f", t)).jpg"
      try NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.75])!
        .write(to: URL(fileURLWithPath: p))
      if exact { print(t, actual.seconds) }
    }
  } catch { print("ERROR", error) }
  sem.signal()
}
sem.wait()
