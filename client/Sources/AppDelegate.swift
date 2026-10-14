import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: MainWindowController!
    private let session = SessionController()

    private let resolutions = ["1920x1080", "2240x1260", "2560x1440", "3840x2160"]
    private let dpis = [120, 140, 160, 200, 240, 284]

    private var devices: [DeviceManager.Device] = []
    private var selectedSerial: String? {
        get { UserDefaults.standard.string(forKey: "serial") }
        set { UserDefaults.standard.set(newValue, forKey: "serial") }
    }

    // Persisted settings shared with the DeXBar app where applicable.
    private var resolution: String {
        get { UserDefaults.standard.string(forKey: "resolution") ?? "2240x1260" }
        set { UserDefaults.standard.set(newValue, forKey: "resolution") }
    }
    private var dpi: Int {
        get { let v = UserDefaults.standard.integer(forKey: "dpi"); return v == 0 ? 160 : v }
        set { UserDefaults.standard.set(newValue, forKey: "dpi") }
    }
    private var displayMode: SessionController.DisplayMode {
        get { SessionController.DisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "auto") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "displayMode") }
    }
    private var audioEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "audio") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "audio") }
    }

    private var sessionMenu: NSMenu!
    private var startItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = MainWindowController()
        session.videoView = windowController.videoView
        session.onStateChanged = { [weak self] running, status in
            self?.windowController.setStatus(status, running: running)
            self?.rebuildMenus()
        }
        session.onError = { [weak self] msg in self?.windowController.showError(msg) }

        buildMainMenu()
        windowController.window.makeKeyAndOrderFront(nil)

        // Refresh device list periodically so the Device submenu stays current.
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
        refreshDevices()
    }

    // MARK: - Menus

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit DeXClient", action: #selector(quitApp),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let sessionItem = NSMenuItem()
        sessionMenu = NSMenu(title: "Session")
        sessionItem.submenu = sessionMenu
        mainMenu.addItem(sessionItem)

        NSApp.mainMenu = mainMenu
        rebuildMenus()
    }

    private func rebuildMenus() {
        sessionMenu.removeAllItems()
        session.config.resolution = resolution
        session.config.dpi = dpi
        session.config.displayMode = displayMode
        session.config.audio = audioEnabled

        if session.running {
            let stop = NSMenuItem(title: "Stop DeX", action: #selector(stopSession), keyEquivalent: ".")
            stop.target = self
            sessionMenu.addItem(stop)
        } else {
            startItem = NSMenuItem(title: "Start DeX", action: #selector(startSession), keyEquivalent: "d")
            startItem.target = self
            startItem.isEnabled = !devices.isEmpty
            sessionMenu.addItem(startItem)
        }
        sessionMenu.addItem(.separator())

        // Device picker
        let devItem = NSMenuItem(title: "Device", action: nil, keyEquivalent: "")
        let devMenu = NSMenu()
        if devices.isEmpty {
            let none = NSMenuItem(title: "No device connected", action: nil, keyEquivalent: "")
            none.isEnabled = false
            devMenu.addItem(none)
        } else {
            for d in devices {
                let title = d.isWireless ? "\(d.model) (WiFi)" : d.model
                let mi = NSMenuItem(title: title, action: #selector(pickDevice(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = d.serial
                mi.state = (d.serial == effectiveSerial()) ? .on : .off
                devMenu.addItem(mi)
            }
        }
        devItem.submenu = devMenu
        sessionMenu.addItem(devItem)

        // Wireless connect
        let wifi = NSMenuItem(title: "Connect Wireless (IP)…", action: #selector(connectWireless),
                              keyEquivalent: "")
        wifi.target = self
        sessionMenu.addItem(wifi)
        sessionMenu.addItem(.separator())

        // Display mode
        let modeItem = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        let modes: [(SessionController.DisplayMode, String)] = [
            (.auto, "Auto (recommended)"),
            (.newDisplay, "Virtual display (One UI 8.0)"),
            (.overlay, "Overlay display (One UI 8.5+)"),
        ]
        for (mode, label) in modes {
            let mi = NSMenuItem(title: label, action: #selector(pickMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = mode.rawValue
            mi.state = (mode == displayMode) ? .on : .off
            modeMenu.addItem(mi)
        }
        modeItem.submenu = modeMenu
        sessionMenu.addItem(modeItem)

        // Resolution
        let resItem = NSMenuItem(title: "Resolution", action: nil, keyEquivalent: "")
        let resMenu = NSMenu()
        for r in resolutions {
            let mi = NSMenuItem(title: r, action: #selector(pickResolution(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = r
            mi.state = (r == resolution) ? .on : .off
            resMenu.addItem(mi)
        }
        resItem.submenu = resMenu
        sessionMenu.addItem(resItem)

        // DPI
        let dpiItem = NSMenuItem(title: "DPI (density)", action: nil, keyEquivalent: "")
        let dpiMenu = NSMenu()
        for d in dpis {
            let mi = NSMenuItem(title: "\(d)", action: #selector(pickDPI(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = d
            mi.state = (d == dpi) ? .on : .off
            dpiMenu.addItem(mi)
        }
        dpiItem.submenu = dpiMenu
        sessionMenu.addItem(dpiItem)

        // Audio
        let audio = NSMenuItem(title: "Audio", action: #selector(toggleAudio(_:)), keyEquivalent: "")
        audio.target = self
        audio.state = audioEnabled ? .on : .off
        sessionMenu.addItem(audio)

        let cfg = NSMenuItem(title: "Current: \(resolution) / \(dpi)", action: nil, keyEquivalent: "")
        cfg.isEnabled = false
        sessionMenu.addItem(.separator())
        sessionMenu.addItem(cfg)
    }

    private func effectiveSerial() -> String? {
        if let s = selectedSerial, devices.contains(where: { $0.serial == s }) { return s }
        return devices.first?.serial
    }

    private func refreshDevices() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = self?.session.availableDevices ?? []
            DispatchQueue.main.async {
                self?.devices = found
                self?.rebuildMenus()
            }
        }
    }

    // MARK: - Actions

    @objc private func startSession() {
        refreshDevices()
        session.start(serial: effectiveSerial())
    }

    @objc private func stopSession() {
        session.stop()
    }

    @objc private func pickDevice(_ sender: NSMenuItem) {
        selectedSerial = sender.representedObject as? String
        rebuildMenus()
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let m = SessionController.DisplayMode(rawValue: raw) {
            displayMode = m
        }
        rebuildMenus()
    }

    @objc private func pickResolution(_ sender: NSMenuItem) {
        if let r = sender.representedObject as? String { resolution = r }
        rebuildMenus()
    }

    @objc private func pickDPI(_ sender: NSMenuItem) {
        if let d = sender.representedObject as? Int { dpi = d }
        rebuildMenus()
    }

    @objc private func toggleAudio(_ sender: NSMenuItem) {
        audioEnabled = !audioEnabled
        rebuildMenus()
    }

    @objc private func connectWireless() {
        let alert = NSAlert()
        alert.messageText = "Connect to phone over WiFi"
        alert.informativeText = "Enter the phone's IP address (adb must already be in TCP mode — run wireless.sh setup once, or enable Wireless debugging)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "192.168.1.100"
        alert.accessoryView = field
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var ip = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        if !ip.contains(":") { ip += ":5555" }
        session.adbConnect(ip)
        // adb connect is async; give it a moment, then refresh the device list.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refreshDevices()
        }
    }

    @objc private func quitApp() {
        session.stop()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stop()
    }
}
