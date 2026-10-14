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

// MARK: - Process helper

/// Mutable flag shared with the timeout watchdog (see runProcess).
private final class Flag { var value = false }

/// Run a command off the main thread with a hard timeout, then deliver
/// (terminationStatus, stdout) on the main thread. Status is -1 when the process
/// could not be launched and -2 when it was killed for exceeding `timeout`.
/// adb can block for seconds over flaky WiFi, so every adb call goes through here —
/// it must never be waited on synchronously from the main thread.
func runProcess(_ path: String, _ args: [String], timeout: TimeInterval,
                completion: @escaping (Int32, String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            DispatchQueue.main.async { completion(-1, "") }
            return
        }
        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            if proc.isRunning { timedOut.value = true; proc.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        proc.waitUntilExit()
        watchdog.cancel()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        let status = timedOut.value ? -2 : proc.terminationStatus
        DispatchQueue.main.async { completion(status, out) }
    }
}

// MARK: - Display mode

/// How the DeX desktop display is created on the phone.
enum DisplayMode: Equatable {
    /// scrcpy creates the virtual display itself. Full DeX on One UI 8.0, but on
    /// One UI 8.5 this only yields Android's plain Desktop Mode (no window chrome,
    /// no multi-window).
    case newDisplay
    /// An `overlay_display_devices` entry tagged `hdmi` makes One UI treat the
    /// display as an external monitor → full DeX even on One UI 8.5. scrcpy then
    /// attaches to that display by id.
    case overlay(String)   // carries the created display id

    var isOverlay: Bool { if case .overlay = self { return true }; return false }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private var scrcpyPath: String?
    private var adbPath: String?

    private var runningProcess: Process?
    private var devices: [DeviceInfo] = []
    private var userRequestedStop = false   // distinguishes a user Stop from a crash

    // Session bookkeeping (captured at launch, used by the termination handler)
    private var sessionSerial: String?
    private var sessionWasWireless = false
    private var activeDisplayMode: DisplayMode?
    private var overlayInUse = false        // an overlay_display_devices entry is ours
    private var reconnectAttempts = 0       // wireless auto-reconnect budget
    private var triedOverlayFallback = false // new-display fast-fail → retry as overlay

    private let maxReconnectAttempts = 2

    private let logPath = NSString(string: "~/Library/Logs/DeXBar.log").expandingTildeInPath

    // Presets
    private let resolutions = ["1920x1080", "2240x1260", "2560x1440", "3840x2160"]
    private let dpis = [120, 140, 160, 200, 240, 284]
    private let displayModePrefs = ["auto", "new-display", "overlay"]

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
    /// Display-mode preference: "auto" (detect One UI version), "new-display",
    /// or "overlay" (force the One UI 8.5-compatible path).
    private var displayModePref: String {
        get { UserDefaults.standard.string(forKey: "displayMode") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "displayMode") }
    }
    private var selectedSerial: String? {
        get { UserDefaults.standard.string(forKey: "serial") }
        set { UserDefaults.standard.set(newValue, forKey: "serial") }
    }
    /// The device the session targets: the user's pick if still connected, else the
    /// first authorized device.
    private var selectedDevice: DeviceInfo? {
        let usable = devices.filter { !$0.unauthorized }
        if let s = selectedSerial, let d = usable.first(where: { $0.serial == s }) { return d }
        return usable.first
    }
    private var hasUnauthorized: Bool { devices.contains { $0.unauthorized } }

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

    // Refresh device status each time the menu opens: show current state immediately,
    // then update asynchronously once adb responds (adb can be slow over WiFi).
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        queryDevices { [weak self] found in
            guard let self else { return }
            self.devices = found
            self.rebuildMenu()
        }
    }

    // MARK: - Device detection

    struct DeviceInfo {
        let model: String      // friendly model name
        let serial: String     // adb serial (USB id or ip:port)
        let isWireless: Bool   // connected over WiFi (adb tcpip), serial like 192.168.x.y:5555
        let unauthorized: Bool // plugged in but USB debugging not approved
    }

    /// Run `adb devices -l` (with timeout) off the main thread, deliver on main.
    private func queryDevices(_ completion: @escaping ([DeviceInfo]) -> Void) {
        guard let adb = adbPath else { completion([]); return }
        runProcess(adb, ["devices", "-l"], timeout: 6) { _, out in
            completion(Self.parseDevices(out))
        }
    }

    /// Parse `adb devices -l` output. Pure (no shared state), safe off the main thread.
    static func parseDevices(_ output: String) -> [DeviceInfo] {
        var result: [DeviceInfo] = []
        for line in output.split(separator: "\n").dropFirst() {
            let s = String(line)
            let parts = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let serial = parts[0]
            let isWireless = serial.contains(":")
            switch parts[1] {
            case "unauthorized":
                result.append(DeviceInfo(model: "unauthorized", serial: serial,
                                         isWireless: isWireless, unauthorized: true))
            case "device":
                var model = "device"
                if let range = s.range(of: #"model:(\S+)"#, options: .regularExpression) {
                    model = String(s[range])
                        .replacingOccurrences(of: "model:", with: "")
                        .replacingOccurrences(of: "_", with: " ")
                }
                result.append(DeviceInfo(model: model, serial: serial,
                                         isWireless: isWireless, unauthorized: false))
            default:
                continue
            }
        }
        return result
    }

    private var isRunning: Bool {
        runningProcess?.isRunning ?? false
    }

    // MARK: - adb helpers

    private func adbArgs(_ args: [String], serial: String?) -> [String] {
        if let serial { return ["-s", serial] + args }
        return args
    }

    /// One UI version as a Double (e.g. 8.5), or nil when undetectable.
    private func detectOneUI(serial: String?, completion: @escaping (Double?) -> Void) {
        guard let adb = adbPath else { completion(nil); return }
        runProcess(adb, adbArgs(["shell", "getprop", "ro.build.version.oneui"], serial: serial),
                   timeout: 5) { status, out in
            let v = Double(out.trimmingCharacters(in: .whitespacesAndNewlines))
            completion(status == 0 ? v : nil)
        }
    }

    // MARK: - Overlay display (One UI 8.5 path)

    /// Currently existing display ids, parsed from `dumpsys display`.
    private func displayIds(serial: String?, completion: @escaping (Set<String>) -> Void) {
        guard let adb = adbPath else { completion([]); return }
        runProcess(adb, adbArgs(["shell", "dumpsys", "display"], serial: serial),
                   timeout: 6) { _, out in
            var ids = Set<String>()
            if let re = try? NSRegularExpression(pattern: #"mDisplayId=(\d+)"#) {
                let ns = out as NSString
                for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                    ids.insert(ns.substring(with: m.range(at: 1)))
                }
            }
            completion(ids)
        }
    }

    /// Create the hdmi-tagged overlay display, wait for its id, then attach scrcpy.
    private func launchOverlayAndRun() {
        guard adbPath != nil else { return }
        let serial = selectedDevice?.serial
        let spec = "\(selectedResolution)/\(selectedDPI),hdmi"
        log("Creating overlay display (\(spec)) …")
        displayIds(serial: serial) { [weak self] before in
            guard let self, let adb = self.adbPath else { return }
            runProcess(adb, self.adbArgs(["shell", "settings", "put", "global",
                                          "overlay_display_devices", spec], serial: serial),
                       timeout: 5) { status, _ in
                guard status == 0 else {
                    self.log("settings put overlay_display_devices failed (\(status))")
                    self.showLaunchFailure()
                    return
                }
                self.waitForNewDisplay(before: before, serial: serial, attemptsLeft: 12) { newId in
                    guard let newId else {
                        self.log("No new display id appeared; cleaning up overlay")
                        self.cleanupOverlay(serial: serial) {
                            self.showLaunchFailure()
                        }
                        return
                    }
                    self.overlayInUse = true
                    self.log("Overlay display id: \(newId)")
                    self.runScrcpy(mode: .overlay(newId))
                }
            }
        }
    }

    /// Poll `dumpsys display` until a display id that wasn't in `before` shows up.
    private func waitForNewDisplay(before: Set<String>, serial: String?,
                                   attemptsLeft: Int,
                                   completion: @escaping (String?) -> Void) {
        guard attemptsLeft > 0 else { completion(nil); return }
        displayIds(serial: serial) { now in
            if let newId = now.subtracting(before).first {
                completion(newId)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.waitForNewDisplay(before: before, serial: serial,
                                           attemptsLeft: attemptsLeft - 1,
                                           completion: completion)
                }
            }
        }
    }

    /// Remove the overlay display we created. Without this, a ghost display would
    /// linger on the phone after DeX stops.
    private func cleanupOverlay(serial: String?, completion: @escaping () -> Void) {
        guard overlayInUse, let adb = adbPath else { completion(); return }
        overlayInUse = false
        log("Removing overlay display")
        runProcess(adb, adbArgs(["shell", "settings", "delete", "global",
                                 "overlay_display_devices"], serial: serial),
                   timeout: 5) { _, _ in completion() }
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
        } else if let dev = selectedDevice {
            statusTitle = "Connected: \(dev.model)"
        } else if hasUnauthorized {
            statusTitle = "⚠︎ USB debugging not authorized"
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
            start.isEnabled = selectedDevice != nil
            menu.addItem(start)
        }
        menu.addItem(.separator())

        // Device picker (only when there's something to pick between)
        if devices.count > 1 {
            let devItem = NSMenuItem(title: "Device", action: nil, keyEquivalent: "")
            let devMenu = NSMenu()
            for d in devices where !d.unauthorized {
                let title = d.isWireless ? "\(d.model) (WiFi)" : d.model
                let mi = NSMenuItem(title: title, action: #selector(pickDevice(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = d.serial
                mi.state = (d.serial == selectedDevice?.serial) ? .on : .off
                devMenu.addItem(mi)
            }
            devItem.submenu = devMenu
            menu.addItem(devItem)
        }

        // Display mode submenu
        let modeItem = NSMenuItem(title: "Display mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        let modeLabels = [
            "auto": "Auto (recommended)",
            "new-display": "Virtual display (One UI 8.0)",
            "overlay": "Overlay display (One UI 8.5+)",
        ]
        for m in displayModePrefs {
            let mi = NSMenuItem(title: modeLabels[m] ?? m, action: #selector(pickDisplayMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = m
            mi.state = (m == displayModePref) ? .on : .off
            modeMenu.addItem(mi)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

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

    @objc private func pickDisplayMode(_ sender: NSMenuItem) {
        if let m = sender.representedObject as? String { displayModePref = m }
    }

    @objc private func pickDevice(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? String { selectedSerial = s }
    }

    @objc private func startDeX() {
        guard scrcpyPath != nil, !isRunning else { return }
        reconnectAttempts = 0
        triedOverlayFallback = false
        // Confirm connection / wireless state off the main thread, then launch —
        // regardless of whether the menu was opened first.
        queryDevices { [weak self] found in
            guard let self else { return }
            self.devices = found
            guard self.selectedDevice != nil else { self.rebuildMenu(); return }
            self.launchSession()
        }
    }

    /// Decide which display-creation path to use, then launch scrcpy.
    private func launchSession() {
        switch displayModePref {
        case "new-display":
            runScrcpy(mode: .newDisplay)
        case "overlay":
            launchOverlayAndRun()
        default: // auto — One UI 8.5 broke full DeX over --new-display
            detectOneUI(serial: selectedDevice?.serial) { [weak self] version in
                guard let self else { return }
                if let v = version, v >= 8.5 {
                    self.launchOverlayAndRun()
                } else {
                    self.runScrcpy(mode: .newDisplay)
                }
            }
        }
    }

    private func runScrcpy(mode: DisplayMode) {
        guard let scrcpy = scrcpyPath, !isRunning else { return }
        truncateLog()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: scrcpy)

        var args: [String]
        switch mode {
        case .newDisplay:
            args = ["--new-display=\(selectedResolution)/\(selectedDPI)"]
        case .overlay(let id):
            args = ["--display-id=\(id)"]
        }
        if let serial = selectedDevice?.serial {
            args += ["-s", serial]
        }
        // Over WiFi, tune for smoothness: h265 (lighter bandwidth), a small buffer
        // to absorb jitter, a capped frame rate, and no audio overhead. USB stays lean.
        let wireless = selectedDevice?.isWireless ?? false
        if wireless {
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

        userRequestedStop = false
        sessionSerial = selectedDevice?.serial
        sessionWasWireless = wireless
        activeDisplayMode = mode
        let launchDate = Date()
        proc.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else { return }
                let uptime = Date().timeIntervalSince(launchDate)
                self.runningProcess = nil

                // Wireless link dropped mid-session: try to reconnect adb and relaunch.
                if !self.userRequestedStop, self.sessionWasWireless,
                   uptime > 5, self.reconnectAttempts < self.maxReconnectAttempts,
                   let serial = self.sessionSerial {
                    self.reconnectAttempts += 1
                    self.attemptReconnect(serial: serial)
                    return
                }

                // If scrcpy died on its own within a couple of seconds, it almost
                // certainly failed to start (device gone, unauthorized, etc.).
                if !self.userRequestedStop,
                   uptime < 2.5, process.terminationStatus != 0 {
                    // One UI 8.5 silently rejects full DeX on --new-display; retry
                    // once via the overlay path before surfacing an error.
                    if self.activeDisplayMode == .newDisplay,
                       self.displayModePref == "auto", !self.triedOverlayFallback {
                        self.triedOverlayFallback = true
                        self.log("--new-display failed fast; retrying with overlay display")
                        self.launchOverlayAndRun()
                        return
                    }
                    self.showLaunchFailure()
                }
                self.rebuildMenu()
            }
        }
        do {
            try proc.run()
            runningProcess = proc
        } catch {
            runningProcess = nil
            showLaunchFailure()
        }
        rebuildMenu()
    }

    /// Reconnect adb over WiFi and relaunch with the same display mode.
    private func attemptReconnect(serial: String) {
        guard let adb = adbPath else { return }
        log("Connection lost; reconnecting to \(serial) …")
        runProcess(adb, ["connect", serial], timeout: 8) { [weak self] status, out in
            guard let self else { return }
            guard status == 0, out.contains("connected") else {
                self.log("Reconnect failed (\(status))")
                self.rebuildMenu()
                return
            }
            // Give the adb server a moment to settle before scrcpy attaches.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.log("Reconnected; restarting DeX")
                if self.activeDisplayMode?.isOverlay == true {
                    // The old overlay id may be stale; recreate from scratch.
                    self.cleanupOverlay(serial: serial) {
                        self.launchOverlayAndRun()
                    }
                } else {
                    self.runScrcpy(mode: .newDisplay)
                }
            }
        }
    }

    private func showLaunchFailure() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't start DeX"
        alert.informativeText = "scrcpy exited right after launching. Check that your phone is connected and USB debugging is authorized, then try again. See the log for details."
        alert.addButton(withTitle: "Open Log")
        alert.addButton(withTitle: "Dismiss")
        if alert.runModal() == .alertFirstButtonReturn { openLog() }
    }

    @objc private func stopDeX() {
        userRequestedStop = true
        runningProcess?.terminate()
        runningProcess = nil
        cleanupOverlay(serial: sessionSerial) {}
        rebuildMenu()
    }

    @objc private func openLog() {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc private func quit() {
        userRequestedStop = true
        runningProcess?.terminate()
        cleanupOverlay(serial: sessionSerial) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Log

    /// Start each session with a fresh log (FileHandle writes from offset 0 but does
    /// not truncate, so without this a short new log would leave stale trailing bytes).
    private func truncateLog() {
        FileManager.default.createFile(atPath: logPath, contents: nil)
    }

    private func log(_ message: String) {
        guard let handle = FileHandle(forWritingAtPath: logPath) else { return }
        defer { try? handle.close() }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {}
        }
    }

    private func logFileHandle() -> FileHandle? {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
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
