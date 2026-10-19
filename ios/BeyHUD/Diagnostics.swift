import UIKit
import MetricKit
import os

/// 端末内の診断ログ。大会中に「止まった」ときの原因を、あとから調べられるようにする。
///
/// 保存先: アプリの Documents/diagnostics.log（約400KBで古い方から切り詰める）。
/// iPhone の「ファイル」アプリ → このiPhone内 → BeyHUD から取り出せる（Info.plist で共有を有効にしている）。
///
/// 記録するもの:
///  - 起動時: 前回がフォアグラウンド中に突然終了していないか（クラッシュ・メモリ不足・固まっての強制終了）と、その直前の状態
///  - 30秒ごと: メモリ使用量・残りメモリ・発熱状態・電源状態
///  - 発熱・メモリ警告・アプリの状態変化・メインスレッドの応答停止
///  - カメラや Web 表示の異常と、自動復旧の実行（他のファイルから `Diagnostics.shared.log` で書く）
///  - MetricKit の診断（クラッシュ・ハング・メモリ強制終了など。OS が次回起動時に届ける）
final class Diagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = Diagnostics()

    private let queue = DispatchQueue(label: "beyhud.diagnostics")
    private let logURL: URL
    private let flagURL: URL
    private let maxBytes = 400_000
    private let lineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        return f
    }()

    // メインスレッドの応答監視（heartbeat はメインでだけ更新し、監視は別スレッドで行う）
    private let beatLock = NSLock()
    private var lastMainBeat = CACurrentMediaTime()
    private var hangStart: CFTimeInterval?
    private var watchTimer: DispatchSourceTimer?
    private var statusTimer: DispatchSourceTimer?
    private var started = false

    private override init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        logURL = docs.appendingPathComponent("diagnostics.log")
        flagURL = FileManager.default.temporaryDirectory.appendingPathComponent("beyhud_active.flag")
        super.init()
    }

    // MARK: - 開始

    func start() {
        guard !started else { return }
        started = true
        let previous = try? String(contentsOf: flagURL, encoding: .utf8)
        log("==== 起動 ==== \(Self.appVersion()) / iOS \(UIDevice.current.systemVersion) / \(Self.deviceModel())")
        if let previous, !previous.isEmpty {
            log("⚠️ 前回はフォアグラウンド中に突然終了しました（クラッシュ／メモリ不足／固まって強制終了のいずれか）。直前の状態: \(previous)")
        }
        log("起動時の状態: \(statusLine())")

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(willTerminate), name: UIApplication.willTerminateNotification, object: nil)
        nc.addObserver(self, selector: #selector(memoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        nc.addObserver(self, selector: #selector(thermalChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(powerChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)

        MXMetricManager.shared.add(self)
        startMainThreadWatch()
        startStatusTimer()
    }

    // MARK: - ログ

    /// どのスレッドからでも呼べる。ファイル書き込みは専用キューで行う
    func log(_ message: String) {
        let line = "\(lineFormatter.string(from: Date())) \(message)\n"
        NSLog("[Diag] %@", message)
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: self.logURL)
            }
            self.trimIfNeeded()
        }
    }

    private func trimIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size]) as? Int, size > maxBytes,
              let text = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        // 後ろ半分だけ残す（行の途中で切らない）
        let tail = String(text.suffix(maxBytes / 2))
        let trimmed = tail.drop(while: { $0 != "\n" }).dropFirst()
        try? ("（古い記録は切り詰めました）\n" + trimmed).write(to: logURL, atomically: true, encoding: .utf8)
    }

    // MARK: - 状態

    /// メモリ・発熱・電源の一行まとめ
    func statusLine() -> String {
        let pi = ProcessInfo.processInfo
        let avail = os_proc_available_memory() / 1_048_576
        let thermal: String
        switch pi.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "SERIOUS"
        case .critical: thermal = "CRITICAL"
        @unknown default: thermal = "?"
        }
        let battery = UIDevice.current.isBatteryMonitoringEnabled ? String(format: "%.0f%%", UIDevice.current.batteryLevel * 100) : "-"
        return String(format: "メモリ使用 %.0fMB / 残り %dMB / 発熱 %@ / 低電力 %@ / バッテリー %@",
                      Self.footprintMB(), avail, thermal, pi.isLowPowerModeEnabled ? "ON" : "OFF", battery)
    }

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    private static func appVersion() -> String {
        let info = Bundle.main.infoDictionary
        return "BeyHUD \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    private static func deviceModel() -> String {
        var sys = utsname()
        uname(&sys)
        return withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    // MARK: - 突然終了の検出（フラグ）

    /// フォアグラウンドの間だけフラグを立てる。残っていれば、次の起動時に「突然終了」と分かる。
    /// フラグの中身は直前の状態（30秒ごとに更新）
    private func setActiveFlag() {
        try? statusLine().write(to: flagURL, atomically: true, encoding: .utf8)
    }
    private func clearActiveFlag() { try? FileManager.default.removeItem(at: flagURL) }

    @objc private func didBecomeActive() { log("アプリがアクティブになりました"); setActiveFlag() }
    @objc private func willResignActive() { log("アプリが非アクティブになります（通知・コントロールセンター・切替など）") }
    @objc private func didEnterBackground() { log("バックグラウンドへ移行（カメラが止まります）"); clearActiveFlag() }
    @objc private func willEnterForeground() { log("フォアグラウンドへ復帰") }
    @objc private func willTerminate() { log("アプリが終了します"); clearActiveFlag() }
    @objc private func memoryWarning() { log("⚠️ メモリ警告を受け取りました。\(statusLine())") }
    @objc private func thermalChanged() { log("発熱状態が変わりました。\(statusLine())"); setActiveFlag() }
    @objc private func powerChanged() { log("低電力モード: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "OFF")") }

    private func startStatusTimer() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 30, repeating: 30)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState == .active else { return }
                self.log("定期: \(self.statusLine())")
                self.setActiveFlag()
            }
        }
        t.resume()
        statusTimer = t
    }

    // MARK: - メインスレッドの応答監視

    /// メインスレッドが止まる（固まる）と、画面が反応しなくなる。止まった時間を記録する。
    /// ※ 検知と記録だけ（止まりの原因そのものは MetricKit のハング診断が次回起動時に届ける）
    private func startMainThreadWatch() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "beyhud.watch", qos: .utility))
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.beatLock.lock(); self.lastMainBeat = CACurrentMediaTime(); self.beatLock.unlock()
            }
            self.beatLock.lock(); let silent = CACurrentMediaTime() - self.lastMainBeat; self.beatLock.unlock()
            // アプリが非アクティブ（バックグラウンド）の間は、メインが止まるのが普通なので見ない
            guard UIApplication.shared.applicationState != .background || self.hangStart != nil else { return }
            if silent > 3, self.hangStart == nil {
                self.hangStart = CACurrentMediaTime() - silent
                self.log(String(format: "🛑 メインスレッドが %.1f 秒以上応答していません", silent))
            } else if silent < 1.5, let start = self.hangStart {
                self.log(String(format: "メインスレッドが復帰しました（約 %.1f 秒止まっていました）", CACurrentMediaTime() - start))
                self.hangStart = nil
            }
        }
        t.resume()
        watchTimer = t
    }

    // MARK: - MetricKit（OS が集めた診断。次回起動時などに届く）

    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads {
            log("MetricKit: 利用状況の集計を受信（\(p.timeStampBegin) 〜 \(p.timeStampEnd)）")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            let crashes = p.crashDiagnostics?.count ?? 0
            let hangs = p.hangDiagnostics?.count ?? 0
            let cpu = p.cpuExceptionDiagnostics?.count ?? 0
            let disk = p.diskWriteExceptionDiagnostics?.count ?? 0
            log("MetricKit 診断を受信: クラッシュ \(crashes) / ハング \(hangs) / CPU例外 \(cpu) / ディスク書込み \(disk)（\(p.timeStampBegin) 〜 \(p.timeStampEnd)）")
            p.crashDiagnostics?.forEach { c in
                log("  クラッシュ: 例外タイプ \(c.exceptionType?.stringValue ?? "?") / シグナル \(c.signal?.stringValue ?? "?") / 終了理由 \(c.terminationReason ?? "-")")
            }
            p.hangDiagnostics?.forEach { h in
                log("  ハング: \(h.hangDuration.converted(to: .seconds).value) 秒")
            }
            // 詳細（スタックを含む）は別ファイルに全文を保存する
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let name = "metrickit-\(Int(Date().timeIntervalSince1970)).json"
            try? p.jsonRepresentation().write(to: docs.appendingPathComponent(name))
            log("  詳細を \(name) に保存しました")
        }
    }
}
