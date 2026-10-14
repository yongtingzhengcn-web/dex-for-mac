import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.regular)   // normal windowed app with Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
