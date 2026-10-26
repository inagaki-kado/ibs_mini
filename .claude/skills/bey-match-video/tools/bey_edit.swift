import AVFoundation
import CoreImage
import AppKit

// 大会・リーグ戦の画面収録をハイライト動画に編集する
// usage: bey_edit <config.json>                    … 本番書き出し（1920x1080 mp4）
//        bey_edit <config.json> --preview <dir> t1 t2 …  … 編集後タイムラインの t 秒の静止画を書き出す
//
// config.json（キーの意味は SKILL.md 参照）
// {
//   "source": "/path/RPReplay.mov", "output": "/path/out_1080p.mp4",
//   "zoom": 0.8515,                      // 拡大率。左右のカメラ黒帯を隠す標準値。null で全体を収める
//   "replayRate": 0.4, "replayVolume": 0.3,
//   "bgm": {"path": "../assets/BEYBLADEX_BATTLE_MUSIC.mp3", "volume": 0.025, "replayVolume": 0.08},
//   "endCard": {"image": "/path/result.png", "seconds": 42},
//   "segments": [
//     {"type": "live",   "from": 233.0, "to": 239.25, "note": "NEXT BATTLE"},
//     {"type": "freeze", "at": 230.86, "seconds": 6, "note": "WINNER を固定（音声は流れる）"},
//     {"type": "replay", "from": 319.0, "to": 323.5, "note": "決着リプレイ"}
//   ]
// }

struct Config: Decodable {
  struct Segment: Decodable { let type: String; let from: Double?; let to: Double?; let at: Double?; let seconds: Double? }
  struct BGM: Decodable { let path: String; let volume: Float?; let replayVolume: Float? }
  struct EndCard: Decodable { let image: String; let seconds: Double }
  let source: String; let output: String
  let zoom: Double?; let replayRate: Double?; let replayVolume: Float?
  let bgm: BGM?; let endCard: EndCard?
  let segments: [Segment]
}

let args = CommandLine.arguments
let configURL = URL(fileURLWithPath: args[1])
let baseDir = configURL.deletingLastPathComponent()
func resolve(_ p: String) -> URL { p.hasPrefix("/") ? URL(fileURLWithPath: p) : baseDir.appendingPathComponent(p).standardizedFileURL }
let cfg = try! JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
let isPreview = args.count > 2 && args[2] == "--preview"
let previewDir = isPreview ? args[3] : ""
let previewTimes = isPreview ? args.dropFirst(4).compactMap { Double($0) } : []

let replayRate = cfg.replayRate ?? 0.4
let replayVolume = cfg.replayVolume ?? 0.3
let bgmVolume = cfg.bgm?.volume ?? 0.025, bgmReplayVolume = cfg.bgm?.replayVolume ?? 0.08
let endCardSec = cfg.endCard?.seconds ?? 0
let renderW = 1920.0, renderH = 1080.0
let fadeSec = 1.0
let ts: CMTimeScale = 60000
func ct(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: ts) }

let sem = DispatchSemaphore(value: 0)
Task {
  do {
    let asset = AVURLAsset(url: resolve(cfg.source))
    let vSrc = try await asset.loadTracks(withMediaType: .video).first!
    let aSrc = try await asset.loadTracks(withMediaType: .audio).first!
    let (rawSize, srcTransform, minFrame) = try await vSrc.load(.naturalSize, .preferredTransform, .minFrameDuration)
    let oriented = rawSize.applying(srcTransform)
    let natural = CGSize(width: abs(oriented.width), height: abs(oriented.height))
    let oneFrame = minFrame.seconds > 0.01 ? minFrame : CMTime(value: 1001, timescale: ts)

    let comp = AVMutableComposition()
    comp.naturalSize = natural
    let v = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let a = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    v.preferredTransform = srcTransform

    var cursor = CMTime.zero
    var replayRanges: [(Double, Double)] = []
    var audioCuts: [CMTime] = []
    for seg in cfg.segments {
      switch seg.type {
      case "live":
        let r = CMTimeRange(start: ct(seg.from!), end: ct(seg.to!))
        try v.insertTimeRange(r, of: vSrc, at: cursor)
        try a.insertTimeRange(r, of: aSrc, at: cursor)
        audioCuts.append(cursor); cursor = cursor + r.duration; audioCuts.append(cursor)
      case "freeze":
        let len = ct(seg.seconds!)
        try v.insertTimeRange(CMTimeRange(start: ct(seg.at!), duration: oneFrame), of: vSrc, at: cursor)
        v.scaleTimeRange(CMTimeRange(start: cursor, duration: oneFrame), toDuration: len)
        try a.insertTimeRange(CMTimeRange(start: ct(seg.at!), duration: len), of: aSrc, at: cursor)
        audioCuts.append(cursor); cursor = cursor + len; audioCuts.append(cursor)
      case "replay":
        let r = CMTimeRange(start: ct(seg.from!), end: ct(seg.to!))
        let len = ct(r.duration.seconds / replayRate)
        try v.insertTimeRange(r, of: vSrc, at: cursor)
        v.scaleTimeRange(CMTimeRange(start: cursor, duration: r.duration), toDuration: len)
        try a.insertTimeRange(r, of: aSrc, at: cursor)
        a.scaleTimeRange(CMTimeRange(start: cursor, duration: r.duration), toDuration: len)
        replayRanges.append((cursor.seconds, (cursor + len).seconds))
        cursor = cursor + len
      default:
        fatalError("unknown segment type \(seg.type)")
      }
    }
    let endTime = cursor
    let total = endTime.seconds

    // BGM はループさせて全編に敷く
    var bgmTrack: AVMutableCompositionTrack? = nil
    if let b = cfg.bgm {
      let bgmAsset = AVURLAsset(url: resolve(b.path))
      let bgmSrc = try await bgmAsset.loadTracks(withMediaType: .audio).first!
      let bgmDur = try await bgmAsset.load(.duration)
      let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
      var bc = CMTime.zero
      while bc < endTime {
        let len = CMTimeMinimum(bgmDur, endTime - bc)
        try t.insertTimeRange(CMTimeRange(start: .zero, duration: len), of: bgmSrc, at: bc)
        bc = bc + len
      }
      bgmTrack = t
    }
    print("replays", replayRanges.map { String(format: "%.1f-%.1f", $0.0, $0.1) }.joined(separator: " "),
          String(format: "total %.2f (%d:%05.2f)", total, Int(total) / 60, total.truncatingRemainder(dividingBy: 60)))

    let srcW = natural.width, srcH = natural.height
    let scale = cfg.zoom ?? (renderW / srcW)
    let tx = -(srcW - renderW / scale) / 2 * scale
    let ty = (renderH - srcH * scale) / 2
    let full = CGRect(x: 0, y: 0, width: renderW, height: renderH)
    let black = CIImage(color: .black).cropped(to: full)

    let endStart = total - endCardSec
    var card: CIImage? = nil
    if let ec = cfg.endCard {
      let cardSrc = CIImage(contentsOf: resolve(ec.image))!
      let cs = renderH / cardSrc.extent.height
      card = cardSrc.transformed(by: CGAffineTransform(scaleX: cs, y: cs))
        .transformed(by: CGAffineTransform(translationX: (renderW - cardSrc.extent.width * cs) / 2, y: 0))
        .composited(over: CIImage(color: CIColor(red: 0.039, green: 0.055, blue: 0.09)).cropped(to: full))
    }

    // リプレイ中は画面下中央に「◀◀ REPLAY」の帯、映像の上下に赤いライン
    let label = CIFilter(name: "CIAttributedTextImageGenerator", parameters: [
      "inputText": NSAttributedString(string: String(format: "◀◀ REPLAY  ×%g", replayRate), attributes: [
        .font: NSFont(name: "AvenirNext-HeavyItalic", size: 54) ?? NSFont.boldSystemFont(ofSize: 54),
        .foregroundColor: NSColor(srgbRed: 1, green: 0, blue: 0.333, alpha: 1)]),
      "inputScaleFactor": 1.0])!.outputImage!
    let badge = CGRect(x: (renderW - label.extent.width) / 2 - 36, y: 118, width: label.extent.width + 72, height: label.extent.height + 20)
    let labelImg = label.transformed(by: CGAffineTransform(translationX: badge.minX + 36 - label.extent.minX,
                                                             y: badge.minY + 10 - label.extent.minY))
      .composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.72)).cropped(to: badge))
    let frameW = 6.0
    let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0.333))
    let lineY = max(ty, frameW)
    let border = [CGRect(x: 0, y: lineY - frameW, width: renderW, height: frameW),
                  CGRect(x: 0, y: renderH - lineY, width: renderW, height: frameW)]
      .map { red.cropped(to: $0) }.reduce(CIImage.empty()) { $1.composited(over: $0) }

    let vc = try await AVMutableVideoComposition.videoComposition(with: comp) { req in
      var out = req.sourceImage.transformed(by: CGAffineTransform(translationX: -req.sourceImage.extent.minX, y: -req.sourceImage.extent.minY))
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: tx, y: ty)))
        .composited(over: black)
        .cropped(to: full)
      let t = req.compositionTime.seconds
      if replayRanges.contains(where: { t >= $0.0 && t < $0.1 }) {
        out = labelImg.composited(over: border.composited(over: out)).cropped(to: full)
      }
      if let card, t >= endStart { out = card }
      if t > total - fadeSec {
        let k = max(0, (total - t) / fadeSec)
        out = out.applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
        ])
      }
      req.finish(with: out, context: nil)
    }
    vc.renderSize = CGSize(width: renderW, height: renderH)
    vc.frameDuration = CMTime(value: 1001, timescale: ts)

    if isPreview {
      let g = AVAssetImageGenerator(asset: comp)
      g.videoComposition = vc
      g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero
      for t in previewTimes {
        let (cg, _) = try await g.image(at: ct(t))
        let p = "\(previewDir)/p_\(String(format: "%08.3f", t)).jpg"
        try NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
          .write(to: URL(fileURLWithPath: p))
      }
      print("preview done")
    } else {
      let mix = AVMutableAudioMix()
      let p = AVMutableAudioMixInputParameters(track: a)
      p.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: ct(total - fadeSec), end: endTime))
      // つなぎ目のプツッという音を防ぐため、各区間の前後を0.05秒で上げ下げする
      let d = ct(0.05)
      for (i, c) in audioCuts.enumerated() where c.seconds < total - fadeSec - 0.1 {
        if i % 2 == 0 { p.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: c, duration: d)) }
        else if c > d { p.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: c - d, duration: d)) }
      }
      for (rs, re) in replayRanges {
        let st = ct(rs), en = ct(re)
        p.setVolumeRamp(fromStartVolume: 0, toEndVolume: replayVolume, timeRange: CMTimeRange(start: st, duration: d))
        p.setVolume(replayVolume, at: st + d)
        p.setVolumeRamp(fromStartVolume: replayVolume, toEndVolume: 0, timeRange: CMTimeRange(start: en - d, duration: d))
      }
      mix.inputParameters = [p]
      if let bgmTrack {
        let bp = AVMutableAudioMixInputParameters(track: bgmTrack)
        bp.setVolumeRamp(fromStartVolume: 0, toEndVolume: bgmVolume, timeRange: CMTimeRange(start: .zero, duration: ct(2)))
        for (rs, re) in replayRanges {
          let r = ct(0.6)
          bp.setVolumeRamp(fromStartVolume: bgmVolume, toEndVolume: bgmReplayVolume, timeRange: CMTimeRange(start: ct(rs), duration: r))
          bp.setVolumeRamp(fromStartVolume: bgmReplayVolume, toEndVolume: bgmVolume, timeRange: CMTimeRange(start: ct(re) - r, duration: r))
        }
        bp.setVolumeRamp(fromStartVolume: bgmVolume, toEndVolume: 0, timeRange: CMTimeRange(start: endTime - ct(4), end: endTime))
        mix.inputParameters.append(bp)
      }
      let outURL = resolve(cfg.output)
      try? FileManager.default.removeItem(at: outURL)
      let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPreset1920x1080)!
      ex.videoComposition = vc
      ex.audioMix = mix
      ex.audioTimePitchAlgorithm = .spectral   // スロー時も音の高さを保つ
      ex.outputURL = outURL
      ex.outputFileType = .mp4
      let timer = Timer(timeInterval: 15, repeats: true) { _ in print(String(format: "progress %.0f%%", ex.progress * 100)); fflush(stdout) }
      RunLoop.main.add(timer, forMode: .common)
      await ex.export()
      timer.invalidate()
      print("status", ex.status == .completed ? "ok" : "FAILED \(ex.error.map { "\($0)" } ?? "")")
    }
  } catch { print("ERROR", error) }
  sem.signal()
}
while sem.wait(timeout: .now() + 0.1) == .timedOut { RunLoop.main.run(until: Date() + 0.1) }
