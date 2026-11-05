import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private weak var currentController: DockController?

    private override init() {
        super.init()
    }

    func show(dockController: DockController) {
        self.currentController = dockController

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "VolumeDial Preferences"
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        newWindow.hasShadow = true
        newWindow.center()

        let hosting = NSHostingView(rootView: SettingsView(controller: dockController))
        hosting.autoresizingMask = [.width, .height]
        newWindow.contentView = hosting
        newWindow.delegate = self

        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        // Window remains retained in `window` property so reopening is instantaneous
    }
}
