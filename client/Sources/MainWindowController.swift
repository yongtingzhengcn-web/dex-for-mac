import Cocoa

/// Main window: the DeX video surface plus a placeholder shown when idle.
/// Session settings live in the main menu (Session menu) — see AppDelegate.
final class MainWindowController: NSObject, NSWindowDelegate {

    let window: NSWindow
    let videoView = VideoView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), device: nil)
    private let placeholder = NSTextField(labelWithString: "Connect a Galaxy phone, then Session ▸ Start DeX")
    private let statusLabel = NSTextField(labelWithString: "")

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init()

        window.title = "DeX"
        window.minSize = NSSize(width: 480, height: 300)
        window.delegate = self
        window.center()

        videoView.autoresizingMask = [.width, .height]
        videoView.frame = window.contentView!.bounds
        window.contentView!.addSubview(videoView)

        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.font = .systemFont(ofSize: 14)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
        ])

        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -8),
        ])
    }

    func setStatus(_ text: String, running: Bool) {
        placeholder.isHidden = running
        statusLabel.stringValue = text
        if running {
            window.title = "DeX — \(text.replacingOccurrences(of: "DeX running — ", with: ""))"
        } else {
            window.title = "DeX"
        }
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "DeX error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
