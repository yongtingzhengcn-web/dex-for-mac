import AppKit

// MARK: - Tool discovery

/// Locate a Homebrew-installed binary (scrcpy / adb) across common prefixes and PATH.
func findBinary(_ name: String) -> String? {
    let candidates = [
        "/opt/homebrew/bin/\(name)",
        "/usr/local/bin/\(name)",
    ]
    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
        return path
    }
    // Fall back to `which` using a login shell so PATH is populated.
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
    proc.arguments = ["-lc", "command -v \(name)"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = Pipe()
    do {
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) {
            return out
        }
    } catch {}
    return nil
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private var scrcpyPath: String?
    private var adbPath: String?

    private var runningProcess: Process?
    private var connectedDevice: String?   // model name, or nil
    private var deviceIsWireless = false    // true when connected over WiFi (adb tcpip)

    private let logPath = NSString(string: "~/Library/Logs/DeXBar.log").expandingTildeInPath

    // Presets
    private let resolutions = ["1920x1080", "2240x1260", "2560x1440", "3840x2160"]
    private let dpis = [120, 140, 160, 200, 240, 284]

    private var selectedResolution: String {
        get { UserDefaults.standard.string(forKey: "resolution") ?? "2240x1260" }
        set { UserDefaults.standard.set(newValue, forKey: "resolution") }
    }
    private var selectedDPI: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "dpi")
            return v == 0 ? 160 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "dpi") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        scrcpyPath = findBinary("scrcpy")
        adbPath = findBinary("adb")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "DeX")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    // Refresh device status each time the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        refreshDeviceStatus()
        rebuildMenu()
    }

    // MARK: - Device detection

    private func refreshDeviceStatus() {
        guard let adb = adbPath else { connectedDevice = nil; return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        proc.arguments = ["devices", "-l"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            connectedDevice = parseDevice(out)
        } catch {
            connectedDevice = nil
        }
    }

    /// Parse `adb devices -l` output; return a friendly model name for the first
    /// authorized device, or a sentinel string for unauthorized. Also records
    /// whether that device is connected over WiFi (serial like `192.168.x.y:5555`).
    private func parseDevice(_ output: String) -> String? {
        for line in output.split(separator: "\n").dropFirst() {
            let s = String(line)
            if s.contains("unauthorized") { return "⚠︎ unauthorized" }
            if s.contains("\tdevice") || s.range(of: #"\sdevice(\s|$)"#, options: .regularExpression) != nil {
                let serial = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
                deviceIsWireless = serial.contains(":")
                if let range = s.range(of: #"model:(\S+)"#, options: .regularExpression) {
                    let model = String(s[range]).replacingOccurrences(of: "model:", with: "")
                    return model.replacingOccurrences(of: "_", with: " ")
                }
                return "device"
            }
        }
        deviceIsWireless = false
        return nil
    }

    private var isRunning: Bool {
        runningProcess?.isRunning ?? false
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        menu.removeAllItems()

        // Missing tools banner
        if scrcpyPath == nil || adbPath == nil {
            let item = NSMenuItem(title: "⚠︎ scrcpy / adb not found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let hint = NSMenuItem(title: "Install: brew install scrcpy android-platform-tools", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(.separator())
            addQuitItem()
            return
        }

        // Status line
        let statusTitle: String
        if isRunning {
            statusTitle = "● DeX running"
        } else if let dev = connectedDevice {
            statusTitle = dev == "⚠︎ unauthorized" ? "⚠︎ USB debugging not authorized" : "Connected: \(dev)"
        } else {
            statusTitle = "No device connected"
        }
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        // Start / Stop
        if isRunning {
            let stop = NSMenuItem(title: "Stop DeX", action: #selector(stopDeX), keyEquivalent: "s")
            stop.target = self
            menu.addItem(stop)
        } else {
            let start = NSMenuItem(title: "Start DeX", action: #selector(startDeX), keyEquivalent: "d")
            start.target = self
            let canStart = connectedDevice != nil && connectedDevice != "⚠︎ unauthorized"
            start.isEnabled = canStart
            menu.addItem(start)
        }
        menu.addItem(.separator())

        // Resolution submenu
        let resItem = NSMenuItem(title: "Resolution", action: nil, keyEquivalent: "")
        let resMenu = NSMenu()
        for r in resolutions {
            let mi = NSMenuItem(title: r, action: #selector(pickResolution(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = r
            mi.state = (r == selectedResolution) ? .on : .off
            resMenu.addItem(mi)
        }
        resItem.submenu = resMenu
        menu.addItem(resItem)

        // DPI submenu
        let dpiItem = NSMenuItem(title: "DPI (density)", action: nil, keyEquivalent: "")
        let dpiMenu = NSMenu()
        for d in dpis {
            let mi = NSMenuItem(title: "\(d)", action: #selector(pickDPI(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = d
            mi.state = (d == selectedDPI) ? .on : .off
            dpiMenu.addItem(mi)
        }
        dpiItem.submenu = dpiMenu
        menu.addItem(dpiItem)

        // Current config line
        let cfg = NSMenuItem(title: "Current: \(selectedResolution) / \(selectedDPI)", action: nil, keyEquivalent: "")
        cfg.isEnabled = false
        menu.addItem(cfg)

        menu.addItem(.separator())

        let logItem = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        addQuitItem()
    }

    private func addQuitItem() {
        let quit = NSMenuItem(title: "Quit DeXBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func pickResolution(_ sender: NSMenuItem) {
        if let r = sender.representedObject as? String { selectedResolution = r }
    }

    @objc private func pickDPI(_ sender: NSMenuItem) {
        if let d = sender.representedObject as? Int { selectedDPI = d }
    }

    @objc private func startDeX() {
        guard let scrcpy = scrcpyPath, !isRunning else { return }
        refreshDeviceStatus()   // ensure deviceIsWireless is current regardless of entry path
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: scrcpy)
        var args = ["--new-display=\(selectedResolution)/\(selectedDPI)"]
        // Over WiFi, tune for smoothness: h265 (lighter bandwidth), a small buffer
        // to absorb jitter, a capped frame rate, and no audio overhead. USB stays lean.
        if deviceIsWireless {
            args += [
                "--video-codec=h265",
                "--video-bit-rate=8M",
                "--max-fps=60",
                "--video-buffer=50",
                "--no-audio",
            ]
        }
        proc.arguments = args

        // Ensure adb (a scrcpy dependency) is on PATH for the child.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existing = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + [existing]).joined(separator: ":")
        proc.environment = env

        if let logHandle = logFileHandle() {
            proc.standardOutput = logHandle
            proc.standardError = logHandle
        }

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.runningProcess = nil
                self?.rebuildMenu()
            }
        }
        do {
            try proc.run()
            runningProcess = proc
        } catch {
            runningProcess = nil
        }
        rebuildMenu()
    }

    @objc private func stopDeX() {
        runningProcess?.terminate()
        runningProcess = nil
        rebuildMenu()
    }

    @objc private func openLog() {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc private func quit() {
        runningProcess?.terminate()
        NSApp.terminate(nil)
    }

    private func logFileHandle() -> FileHandle? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil)
        }
        return FileHandle(forWritingAtPath: logPath)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
