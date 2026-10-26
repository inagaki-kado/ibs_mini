import AppKit

// frames が書き出した f_<秒>.jpg を、時刻ラベル付きの一覧画像にまとめる
// usage: sheet <dir> <out.jpg> [cols=8]
// ラベルはファイル名の秒数から付けるので、行・列を目で数えず必ずラベルで時刻を読むこと
let a = CommandLine.arguments
let dir = a[1], out = a[2]
let cols = a.count > 3 ? Int(a[3])! : 8
let files = try! FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".jpg") }.sorted()
guard !files.isEmpty else { print("no frames in \(dir)"); exit(1) }
let w = 1920.0 / Double(cols), h = w * 0.46, pad = 18.0
let rows = (files.count + cols - 1) / cols
let W = Double(cols) * w, H = Double(rows) * (h + pad)
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
NSColor.black.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
for (i, f) in files.enumerated() {
  let c = Double(i % cols), r = Double(i / cols)
  let y = H - (r + 1) * (h + pad)
  NSImage(contentsOfFile: "\(dir)/\(f)")?.draw(in: NSRect(x: c * w, y: y, width: w - 4, height: h))
  let t = Double(f.dropFirst(2).dropLast(4)) ?? 0
  let lbl = String(format: "%d:%05.2f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
  (lbl as NSString).draw(at: NSPoint(x: c * w + 4, y: y + h + 2),
                         withAttributes: [.foregroundColor: NSColor.yellow, .font: NSFont.boldSystemFont(ofSize: 13)])
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])!.write(to: URL(fileURLWithPath: out))
