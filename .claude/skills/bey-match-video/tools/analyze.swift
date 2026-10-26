import AVFoundation

// 動画全体を縮小デコードし、10fps で指標を CSV 出力する（回転は自動補正）
// usage: analyze <video> > metrics.csv
// 列: t, motion（スタジアム中央の前フレーム差＝手やベイの動き）,
//     sat（中央の彩度＝決まり手表示 XTREME/OVER/BURST/SPIN FINISH で跳ねる）,
//     ld, rd（左右スコア数字の1秒前との差＝得点の変化）,
//     pld, prd（下部ベイ名パネルの1秒前との差＝ベイ見せのときに名前が変わる）,
//     lp, rp（下部パネル位置の暗さ。両方 0.85 超が NEXT BATTLE などの全画面画面）
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)
Task {
  let track = try! await asset.loadTracks(withMediaType: .video).first!
  let tr = try! await track.load(.preferredTransform)
  let rotated = abs(tr.b) == 1   // 縦持ち収録（横向き表示）なら90°回転
  let W = 262, H = 120
  let reader = try! AVAssetReader(asset: asset)
  let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: rotated ? H : W, kCVPixelBufferHeightKey as String: rotated ? W : H])
  out.alwaysCopiesSampleData = false
  reader.add(out); reader.startReading()
  var prev: [UInt8]? = nil
  var hist: [[UInt8]] = []
  var idx = 0
  func region(_ px: [UInt8], _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> [Double] {
    var r: [Double] = []
    for y in Int(y0 * Double(H))..<Int(y1 * Double(H)) { for x in Int(x0 * Double(W))..<Int(x1 * Double(W)) {
      let o = (y * W + x) * 4; r.append(Double(px[o]) + Double(px[o + 1]) + Double(px[o + 2])) } }
    return r
  }
  func diff(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Double(a.count) / 3 }
  print("t,motion,sat,ld,rd,pld,prd,lp,rp")
  while let sb = out.copyNextSampleBuffer() {
    defer { idx += 1 }
    if idx % 6 != 0 { continue }
    let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
    let pb = CMSampleBufferGetImageBuffer(sb)!
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    let bpr = CVPixelBufferGetBytesPerRow(pb)
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    var px = [UInt8](repeating: 0, count: W * H * 4)
    for Y in 0..<H { for X in 0..<W {
      let (rx, ry) = rotated ? (tr.b < 0 ? (H - 1 - Y, X) : (Y, W - 1 - X)) : (X, Y)
      for c in 0..<4 { px[(Y * W + X) * 4 + c] = base[ry * bpr + rx * 4 + c] } } }
    CVPixelBufferUnlockBaseAddress(pb, .readOnly)

    let st = region(px, 0.30, 0.70, 0.20, 0.85)
    let motion = prev.map { diff(st, region($0, 0.30, 0.70, 0.20, 0.85)) } ?? 0
    var sat = 0.0, n = 0.0
    for y in Int(0.30 * Double(H))..<Int(0.70 * Double(H)) { for x in Int(0.35 * Double(W))..<Int(0.65 * Double(W)) {
      let o = (y * W + x) * 4; let b = Double(px[o]), g = Double(px[o + 1]), r = Double(px[o + 2])
      sat += max(r, g, b) - min(r, g, b); n += 1 } }
    var ld = 0.0, rd = 0.0, pld = 0.0, prd = 0.0
    if hist.count >= 10 {
      let o = hist[hist.count - 10]
      ld = diff(region(px, 0.13, 0.26, 0.12, 0.38), region(o, 0.13, 0.26, 0.12, 0.38))
      rd = diff(region(px, 0.74, 0.87, 0.12, 0.38), region(o, 0.74, 0.87, 0.12, 0.38))
      pld = diff(region(px, 0.09, 0.37, 0.84, 0.94), region(o, 0.09, 0.37, 0.84, 0.94))
      prd = diff(region(px, 0.63, 0.91, 0.84, 0.94), region(o, 0.63, 0.91, 0.84, 0.94))
    }
    func dark(_ x0: Double, _ x1: Double) -> Double { let r = region(px, x0, x1, 0.86, 0.92); return Double(r.filter { $0 < 120 }.count) / Double(r.count) }
    print(String(format: "%.2f,%.2f,%.1f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f", t, motion, sat / n, ld, rd, pld, prd, dark(0.10, 0.36), dark(0.64, 0.90)))
    prev = px; hist.append(px); if hist.count > 12 { hist.removeFirst() }
  }
  sem.signal()
}
sem.wait()
