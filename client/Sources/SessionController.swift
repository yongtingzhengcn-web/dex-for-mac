import Cocoa

/// Orchestrates one DeX session: device → display creation → server → channels →
/// decode/render/input/audio. Call start/stop from the main thread.
final class SessionController {

    enum DisplayMode: String { case auto, newDisplay = "new-display", overlay }

    struct Config {
        var resolution = "2240x1260"
        var dpi = 160
        var displayMode: DisplayMode = .auto
        var audio = true
    }

    private let deviceManager = DeviceManager()
    private var server: ScrcpyServer?
    private var videoChannel: SocketChannel?
    private var audioChannel: SocketChannel?
    private var controlChannel: SocketChannel?
    private var decoder: VideoDecoder?
    private let audioPlayer = AudioPlayer()
    private let workQueue = DispatchQueue(label: "dexclient.session")

    private var serial: String?
    private var usedOverlay = false
    private(set) var running = false

    var config = Config()

    /// UI callbacks — always invoked on the main thread.
    var onStateChanged: (Bool, String) -> Void = { _, _ in }
    var onError: (String) -> Void = { _ in }

    weak var videoView: VideoView?

    var availableDevices: [DeviceManager.Device] { deviceManager.devices() }

    /// `adb connect ip:port` for wireless sessions.
    func adbConnect(_ hostPort: String) {
        workQueue.async { [weak self] in
            self?.deviceManager.run(["connect", hostPort], timeout: 8)
        }
    }

    // MARK: - Start

    func start(serial requestedSerial: String?) {
        guard !running else { return }
        running = true
        onStateChanged(false, "Connecting…")

        workQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.startInternal(serial: requestedSerial)
            } catch {
                DispatchQueue.main.async {
                    self.running = false
                    self.onError(error.localizedDescription)
                    self.onStateChanged(false, "Failed")
                }
                self.cleanup()
            }
        }
    }

    private func startInternal(serial requestedSerial: String?) throws {
        // 1. Pick a device.
        let devices = deviceManager.devices()
        let device = devices.first(where: { $0.serial == requestedSerial }) ?? devices.first
        guard let device else {
            throw NSError(domain: "DeXClient", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "No device. Connect a Galaxy phone via USB (USB debugging authorized)."])
        }
        serial = device.serial

        // 2. Decide display creation path. One UI 8.5+ needs the hdmi overlay.
        var displayId: String?
        let useOverlay: Bool
        switch config.displayMode {
        case .overlay: useOverlay = true
        case .newDisplay: useOverlay = false
        case .auto:
            let v = deviceManager.oneUIVersion(serial: device.serial)
            useOverlay = (v ?? 8.0) >= 8.5
        }
        if useOverlay {
            setStatus("Creating overlay display…")
            guard let id = deviceManager.createOverlayDisplay(
                serial: device.serial, spec: "\(config.resolution)/\(config.dpi)") else {
                throw NSError(domain: "DeXClient", code: 11,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to create overlay display on the phone."])
            }
            displayId = id
            usedOverlay = true
        }

        // 3. Launch the server + tunnel.
        guard let adbPath = deviceManager.adbPath else {
            throw NSError(domain: "DeXClient", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "adb not found (bundled or system)."])
        }
        let server = ScrcpyServer(adbPath: adbPath)
        self.server = server
        setStatus("Starting server…")
        let port = try server.start(config: .init(
            serial: device.serial,
            resolution: config.resolution,
            dpi: config.dpi,
            displayId: displayId,
            videoCodec: device.isWireless ? "h265" : "h264",
            videoBitRate: 8_000_000,
            maxFPS: 60,
            audio: config.audio))

        // 4. Connect channels in order: video, audio, control.
        setStatus("Opening stream…")
        let video = SocketChannel(label: "video")
        guard connectSync(video, port: port) else { throw channelError("video") }
        videoChannel = video

        // Video socket header: dummy byte, 64-byte device name, u32 codec id.
        guard readSync(video, 1) != nil else { throw channelError("dummy byte") }
        var deviceName = "DeX"
        if let nameData = readSync(video, 64) {
            deviceName = String(data: nameData, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters.union(.whitespaces))
                .replacingOccurrences(of: "\0", with: "") ?? "DeX"
        }
        guard let codecData = readSync(video, 4) else { throw channelError("codec id") }
        let codecId = codecData.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        guard let codec = VideoDecoder.Codec(rawValue: codecId) else {
            throw NSError(domain: "DeXClient", code: 13,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported video codec id"])
        }
        let decoder = VideoDecoder(codec: codec)
        self.decoder = decoder
        decoder.onFrame = { [weak self] buffer in
            self?.videoView?.render(pixelBuffer: buffer)
        }
        decoder.onError = { [weak self] msg in
            DispatchQueue.main.async { self?.onError(msg) }
        }

        if config.audio {
            let audio = SocketChannel(label: "audio")
            guard connectSync(audio, port: port) else { throw channelError("audio") }
            audioChannel = audio
            _ = readSync(audio, 4)  // audio codec id ("raw")
            audioPlayer.start()
        }

        let control = SocketChannel(label: "control")
        guard connectSync(control, port: port) else { throw channelError("control") }
        controlChannel = control

        // 5. Wire input events from the video view to the control channel.
        DispatchQueue.main.async { [weak self] in
            self?.videoView?.inputHandler = { [weak self] event in
                self?.sendInput(event)
            }
            self?.onStateChanged(true, "DeX running — \(deviceName)")
        }

        // 6. Start read loops.
        videoReadLoop()
        if audioChannel != nil { audioReadLoop() }
        controlReadLoop()
    }

    // MARK: - Read loops

    private let packetFlagSession: UInt64 = 1 << 63
    private let packetFlagConfig: UInt64 = 1 << 62
    private let ptsMask: UInt64 = 0x3FFFFFFFFFFFFFFF

    private func videoReadLoop() {
        guard let video = videoChannel else { return }
        video.readExact(12) { [weak self] header in
            guard let self, let header else { self?.streamEnded(); return }
            let flagsAndPts = header.withUnsafeBytes { $0.load(as: UInt64.self) }.bigEndian
            if flagsAndPts & self.packetFlagSession != 0 {
                // Session packet: width/height in bytes 4-11.
                let w = header.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }.bigEndian
                let h = header.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }.bigEndian
                DispatchQueue.main.async {
                    self.videoView?.updateStreamSize(CGSize(width: Int(w), height: Int(h)))
                }
                self.videoReadLoop()
                return
            }
            let size = header.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }.bigEndian
            video.readExact(Int(size)) { [weak self] payload in
                guard let self, let payload else { self?.streamEnded(); return }
                if flagsAndPts & self.packetFlagConfig != 0 {
                    self.decoder?.handleConfig(payload)
                } else {
                    self.decoder?.handlePacket(payload, pts: flagsAndPts & self.ptsMask)
                }
                self.videoReadLoop()
            }
        }
    }

    private func audioReadLoop() {
        guard let audio = audioChannel else { return }
        audio.readExact(12) { [weak self] header in
            guard let self, let header else { return }
            let flagsAndPts = header.withUnsafeBytes { $0.load(as: UInt64.self) }.bigEndian
            let size = header.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }.bigEndian
            if flagsAndPts & self.packetFlagConfig != 0 || size == 0 {
                if size > 0 {
                    audio.readExact(Int(size)) { [weak self] _ in self?.audioReadLoop() }
                } else {
                    self.audioReadLoop()
                }
                return
            }
            audio.readExact(Int(size)) { [weak self] payload in
                guard let self else { return }
                if let payload { self.audioPlayer.enqueue(payload) }
                self.audioReadLoop()
            }
        }
    }

    /// Device → client messages on the control socket (clipboard sync).
    private func controlReadLoop() {
        guard let control = controlChannel else { return }
        control.readExact(1) { [weak self] typeByte in
            guard let self, let typeByte else { return }
            let type = typeByte[typeByte.startIndex]
            if type == 0 {  // DEVICE_MESSAGE_TYPE_CLIPBOARD
                control.readExact(4) { [weak self] lenData in
                    guard let self, let lenData else { return }
                    let len = lenData.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
                    guard len > 0, len < (1 << 18) else { self.controlReadLoop(); return }
                    control.readExact(Int(len)) { [weak self] textData in
                        guard let self else { return }
                        if let textData, let text = String(data: textData, encoding: .utf8) {
                            DispatchQueue.main.async {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            }
                        }
                        self.controlReadLoop()
                    }
                }
            } else {
                // Unknown device message type — stop reading to avoid desync.
                NSLog("DeXClient: unknown device message type \(type)")
            }
        }
    }

    private func streamEnded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            self.stop()
            self.onError("Stream ended (device disconnected?)")
        }
    }

    // MARK: - Input

    private func sendInput(_ event: VideoView.InputEvent) {
        guard let control = controlChannel else { return }
        let w = Int(videoView?.streamSize.width ?? 1920)
        let h = Int(videoView?.streamSize.height ?? 1080)
        let data: Data?
        switch event {
        case let .touch(action, x, y, pressure, actionButton, buttons):
            data = ControlMessages.injectTouch(action: action, x: x, y: y,
                                               displayW: w, displayH: h,
                                               pressure: pressure,
                                               actionButton: actionButton, buttons: buttons)
        case let .scroll(x, y, hScroll, vScroll, buttons):
            data = ControlMessages.injectScroll(x: x, y: y, displayW: w, displayH: h,
                                                hScroll: hScroll, vScroll: vScroll,
                                                buttons: buttons)
        case let .key(action, keycode, meta):
            data = ControlMessages.injectKeycode(action: action, keycode: keycode, meta: meta)
        case let .text(text):
            data = ControlMessages.injectText(text)
        case let .paste(text):
            data = ControlMessages.setClipboard(text, paste: true)
        }
        if let data { control.write(data) }
    }

    // MARK: - Stop

    func stop() {
        guard running else { return }
        running = false
        onStateChanged(false, "Stopped")
        workQueue.async { [weak self] in self?.cleanup() }
    }

    private func cleanup() {
        videoChannel?.close(); videoChannel = nil
        audioChannel?.close(); audioChannel = nil
        controlChannel?.close(); controlChannel = nil
        decoder?.invalidate(); decoder = nil
        audioPlayer.stop()
        if let serial { server?.stop(serial: serial) }
        server = nil
        if usedOverlay, let serial {
            deviceManager.removeOverlayDisplay(serial: serial)
            usedOverlay = false
        }
        DispatchQueue.main.async { [weak self] in
            self?.videoView?.inputHandler = nil
        }
    }

    // MARK: - Sync channel helpers (called on workQueue only)

    private func connectSync(_ channel: SocketChannel, port: UInt16) -> Bool {
        var ok = false
        let sem = DispatchSemaphore(value: 0)
        channel.connect(port: port) { result in ok = result; sem.signal() }
        sem.wait()
        return ok
    }

    private func readSync(_ channel: SocketChannel, _ n: Int) -> Data? {
        var result: Data?
        let sem = DispatchSemaphore(value: 0)
        channel.readExact(n) { data in result = data; sem.signal() }
        _ = sem.wait(timeout: .now() + 10)
        return result
    }

    private func setStatus(_ s: String) {
        DispatchQueue.main.async { [weak self] in self?.onStateChanged(false, s) }
    }

    private func channelError(_ what: String) -> NSError {
        NSError(domain: "DeXClient", code: 14,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open \(what) channel"])
    }
}
