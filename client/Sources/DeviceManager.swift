import Foundation

/// adb wrapper + One UI detection + overlay display management.
/// Reuses the bundled adb (Resources/adb) with a system install as fallback.
final class DeviceManager {

    struct Device {
        let model: String
        let serial: String
        let isWireless: Bool
    }

    let adbPath: String?

    init() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("adb").path
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled) {
            adbPath = bundled
        } else {
            adbPath = DeviceManager.which("adb")
        }
    }

    static func which(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Run adb synchronously with a timeout; returns (status, stdout). For short
    /// queries only — never call on the main thread.
    @discardableResult
    func run(_ args: [String], serial: String? = nil, timeout: TimeInterval = 8) -> (Int32, String) {
        guard let adbPath else { return (-1, "") }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        var full: [String] = []
        if let serial { full += ["-s", serial] }
        full += args
        proc.arguments = full
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return (-1, "") }
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if proc.isRunning { proc.terminate() }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (proc.terminationStatus, out)
    }

    func devices() -> [Device] {
        let (status, out) = run(["devices", "-l"])
        guard status == 0 else { return [] }
        var result: [Device] = []
        for line in out.split(separator: "\n").dropFirst() {
            let s = String(line)
            let parts = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2, parts[1] == "device" else { continue }
            var model = parts[0]
            if let range = s.range(of: #"model:(\S+)"#, options: .regularExpression) {
                model = String(s[range]).replacingOccurrences(of: "model:", with: "")
                    .replacingOccurrences(of: "_", with: " ")
            }
            result.append(Device(model: model, serial: parts[0], isWireless: parts[0].contains(":")))
        }
        return result
    }

    /// One UI version as a Double (8.0, 8.5, 9.0 …), nil when undetectable.
    func oneUIVersion(serial: String) -> Double? {
        let (status, out) = run(["shell", "getprop", "ro.build.version.oneui"], serial: serial, timeout: 5)
        guard status == 0 else { return nil }
        return Double(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Overlay display (One UI 8.5+)

    func displayIds(serial: String) -> Set<String> {
        let (_, out) = run(["shell", "dumpsys", "display"], serial: serial, timeout: 6)
        var ids = Set<String>()
        if let re = try? NSRegularExpression(pattern: #"mDisplayId=(\d+)"#) {
            let ns = out as NSString
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                ids.insert(ns.substring(with: m.range(at: 1)))
            }
        }
        return ids
    }

    /// Create an hdmi-tagged overlay display and return its new display id.
    /// One UI treats it as an external monitor → full DeX even on One UI 8.5+.
    func createOverlayDisplay(serial: String, spec: String) -> String? {
        let before = displayIds(serial: serial)
        let (status, _) = run(["shell", "settings", "put", "global",
                               "overlay_display_devices", "\(spec),hdmi"], serial: serial)
        guard status == 0 else { return nil }
        for _ in 0..<16 {
            Thread.sleep(forTimeInterval: 0.4)
            let now = displayIds(serial: serial)
            if let newId = now.subtracting(before).first { return newId }
        }
        removeOverlayDisplay(serial: serial)
        return nil
    }

    func removeOverlayDisplay(serial: String) {
        run(["shell", "settings", "delete", "global", "overlay_display_devices"], serial: serial)
    }
}
