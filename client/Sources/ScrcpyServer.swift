import Foundation

/// Manages the on-device scrcpy server: pushes the bundled server jar, sets up
/// the adb forward tunnel, and launches `app_process`. The process stays alive
/// for the whole session; killing it stops the stream.
final class ScrcpyServer {

    /// Must match the bundled server jar exactly (server rejects mismatched clients).
    static let serverVersion = "5.0.1"
    static let remoteJarPath = "/data/local/tmp/dexclient-server.jar"

    struct Config {
        var serial: String
        var resolution: String          // "WxH"
        var dpi: Int
        var displayId: String?          // overlay path; nil → server creates new_display
        var videoCodec: String          // "h264" | "h265"
        var videoBitRate: Int
        var maxFPS: Int
        var audio: Bool
    }

    private let adbPath: String
    private var serverProcess: Process?
    private(set) var tunnelPort: UInt16 = 0
    private var scidHex = ""

    var log: (String) -> Void = { NSLog("DeXClient server: \($0)") }

    init(adbPath: String) {
        self.adbPath = adbPath
    }

    /// Push jar, open tunnel, launch server. Returns the local tunnel port.
    func start(config: Config) throws -> UInt16 {
        guard let jar = Bundle.main.resourceURL?.appendingPathComponent("scrcpy-server").path else {
            throw NSError(domain: "DeXClient", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Bundled scrcpy-server not found"])
        }

        // Push the server (idempotent-ish; cheap over USB, small over WiFi).
        let push = runAdb(["-s", config.serial, "push", jar, Self.remoteJarPath], timeout: 30)
        guard push.0 == 0 else {
            throw NSError(domain: "DeXClient", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "adb push failed: \(push.1)"])
        }

        // Random 31-bit scid; the abstract socket name is derived from it.
        let scid = Int.random(in: 1...0x7FFFFFFF)
        scidHex = String(format: "%08x", scid)
        let abstract = "localabstract:scrcpy_\(scidHex)"

        let fwd = runAdb(["-s", config.serial, "forward", "tcp:0", abstract], timeout: 8)
        guard fwd.0 == 0, let port = UInt16(fwd.1.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "DeXClient", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "adb forward failed: \(fwd.1)"])
        }
        tunnelPort = port

        // Launch the server. exec-out avoids PTY wrapping.
        var args = ["-s", config.serial, "exec-out",
                    "env", "CLASSPATH=\(Self.remoteJarPath)",
                    "app_process", "/", "com.genymobile.scrcpy.Server", Self.serverVersion,
                    "scid=\(scidHex)",
                    "log_level=warn",
                    "tunnel_forward=true",
                    "video=true",
                    "video_codec=\(config.videoCodec)",
                    "video_bit_rate=\(config.videoBitRate)",
                    "max_fps=\(config.maxFPS)",
                    "audio=\(config.audio)",
                    "audio_codec=raw",
                    "control=true",
                    "clipboard_autosync=true",
                    "display_ime_policy=local"]
        if let displayId = config.displayId {
            args.append("display_id=\(displayId)")
        } else {
            args.append("new_display=\(config.resolution)/\(config.dpi)")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        proc.arguments = args
        let errPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = errPipe
        proc.terminationHandler = { [weak self] p in
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            if !err.isEmpty { self?.log("server exited (\(p.terminationStatus)): \(err)") }
        }
        try proc.run()
        serverProcess = proc
        return port
    }

    func stop(serial: String) {
        serverProcess?.terminationHandler = nil
        serverProcess?.terminate()
        serverProcess = nil
        _ = runAdb(["-s", serial, "forward", "--remove", "tcp:\(tunnelPort)"], timeout: 5)
    }

    private func runAdb(_ args: [String], timeout: TimeInterval) -> (Int32, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return (-1, "\(error)") }
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if proc.isRunning { proc.terminate() }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (proc.terminationStatus, out)
    }
}
