import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var dialPanel: FloatingDialPanel!
    var statusItem: NSStatusItem!
    var dockController: DockController!

    private var dockLeftItem: NSMenuItem!
    private var dockRightItem: NSMenuItem!
    private var dockTopItem: NSMenuItem!
    private var dockBottomItem: NSMenuItem!
    private var dockTopLeftItem: NSMenuItem!
    private var dockTopRightItem: NSMenuItem!
    private var dockBottomLeftItem: NSMenuItem!
    private var dockBottomRightItem: NSMenuItem!
    private var undockItem: NSMenuItem!
    private var autoTuckItem: NSMenuItem!
    private var attachedToEdgeItem: NSMenuItem!
    private var filterAudioOnlyItem: NSMenuItem!
    private var hiddenAppsParentItem: NSMenuItem!
    private var hiddenAppsMenu: NSMenu!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarExtra()
        setupFloatingPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyManager.shared.unregisterAll()
        AudioVolumeController.shared.teardownAllTaps()
    }

    private func setupFloatingPanel() {
        dialPanel = FloatingDialPanel(contentRect: NSRect(x: 200, y: 200, width: 220, height: 220))
        let model = MixerModel()
        dockController = DockController(model: model, panel: dialPanel)
        dockController.show()
        if AppSettings.shared.globalHotkeysEnabled {
            GlobalHotKeyManager.shared.registerHotKeys(controller: dockController)
        }
    }

    private func setupMenuBarExtra() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dial.medium.fill", accessibilityDescription: "Volume Dial")
        }

        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(NSMenuItem(title: "Toggle Dial Visibility", action: #selector(toggleDial), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Toggle App Volumes Mixer", action: #selector(toggleMixer), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())

        filterAudioOnlyItem = NSMenuItem(title: "Show Audio Apps Only", action: #selector(toggleFilterAudioOnly), keyEquivalent: "")
        menu.addItem(filterAudioOnlyItem)
        menu.addItem(NSMenuItem.separator())

        // Docking Submenu
        let dockMenu = NSMenu()
        dockLeftItem = NSMenuItem(title: "Left Screen Edge", action: #selector(dockLeft), keyEquivalent: "")
        dockRightItem = NSMenuItem(title: "Right Screen Edge", action: #selector(dockRight), keyEquivalent: "")
        dockTopItem = NSMenuItem(title: "Top Screen Edge", action: #selector(dockTop), keyEquivalent: "")
        dockBottomItem = NSMenuItem(title: "Bottom Screen Edge", action: #selector(dockBottom), keyEquivalent: "")

        dockTopLeftItem = NSMenuItem(title: "Top-Left Corner", action: #selector(dockTopLeft), keyEquivalent: "")
        dockTopRightItem = NSMenuItem(title: "Top-Right Corner", action: #selector(dockTopRight), keyEquivalent: "")
        dockBottomLeftItem = NSMenuItem(title: "Bottom-Left Corner", action: #selector(dockBottomLeft), keyEquivalent: "")
        dockBottomRightItem = NSMenuItem(title: "Bottom-Right Corner", action: #selector(dockBottomRight), keyEquivalent: "")

        undockItem = NSMenuItem(title: "Undock (Free Floating Anywhere)", action: #selector(undockAction), keyEquivalent: "u")

        dockMenu.addItem(dockLeftItem)
        dockMenu.addItem(dockRightItem)
        dockMenu.addItem(dockTopItem)
        dockMenu.addItem(dockBottomItem)
        dockMenu.addItem(NSMenuItem.separator())
        dockMenu.addItem(dockTopLeftItem)
        dockMenu.addItem(dockTopRightItem)
        dockMenu.addItem(dockBottomLeftItem)
        dockMenu.addItem(dockBottomRightItem)
        dockMenu.addItem(NSMenuItem.separator())
        dockMenu.addItem(undockItem)
        dockMenu.addItem(NSMenuItem.separator())

        attachedToEdgeItem = NSMenuItem(title: "Attach to Screen Edge (Partially Visible)", action: #selector(toggleAttachedAction), keyEquivalent: "a")
        dockMenu.addItem(attachedToEdgeItem)

        autoTuckItem = NSMenuItem(title: "Auto-Tuck at Screen Edge", action: #selector(toggleAutoTuckAction), keyEquivalent: "t")
        dockMenu.addItem(autoTuckItem)

        let dockParent = NSMenuItem(title: "Dock Position", action: nil, keyEquivalent: "")
        dockParent.submenu = dockMenu
        menu.addItem(dockParent)

        menu.addItem(NSMenuItem.separator())

        hiddenAppsParentItem = NSMenuItem(title: "Hidden Apps", action: nil, keyEquivalent: "")
        hiddenAppsMenu = NSMenu()
        hiddenAppsParentItem.submenu = hiddenAppsMenu
        menu.addItem(hiddenAppsParentItem)

        menu.addItem(NSMenuItem(title: "Reset All App Volumes", action: #selector(resetAllVolumes), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit VolumeDialApp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleDial() {
        dockController.toggleVisible()
    }

    @objc private func toggleMixer() {
        dockController.toggleExpanded()
    }

    @objc private func dockLeft() {
        dockController.dock(to: .left)
    }

    @objc private func dockRight() {
        dockController.dock(to: .right)
    }

    @objc private func dockTop() {
        dockController.dock(to: .top)
    }

    @objc private func dockBottom() {
        dockController.dock(to: .bottom)
    }

    @objc private func dockTopLeft() {
        dockController.dock(to: .topLeft)
    }

    @objc private func dockTopRight() {
        dockController.dock(to: .topRight)
    }

    @objc private func dockBottomLeft() {
        dockController.dock(to: .bottomLeft)
    }

    @objc private func dockBottomRight() {
        dockController.dock(to: .bottomRight)
    }

    @objc private func undockAction() {
        dockController.undock()
    }

    @objc private func toggleAutoTuckAction() {
        dockController.toggleAutoTuck()
    }

    @objc private func toggleAttachedAction() {
        dockController.toggleAttachedToEdge()
    }

    @objc private func toggleFilterAudioOnly() {
        dockController.model.showAudioOnly.toggle()
    }

    @objc private func unhideSingleApp(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String {
            dockController.model.unhideApp(key: key)
        }
    }

    @objc private func unhideAllAppsAction() {
        dockController.model.unhideAll()
    }

    @objc private func resetAllVolumes() {
        dockController.model.resetAllVolumes()
    }

    @objc private func openSettings() {
        dockController.openSettings()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard let controller = dockController else { return }
        let isD = controller.isDocked
        dockLeftItem.state = (isD && controller.edge == .left) ? .on : .off
        dockRightItem.state = (isD && controller.edge == .right) ? .on : .off
        dockTopItem.state = (isD && controller.edge == .top) ? .on : .off
        dockBottomItem.state = (isD && controller.edge == .bottom) ? .on : .off

        dockTopLeftItem.state = (isD && controller.edge == .topLeft) ? .on : .off
        dockTopRightItem.state = (isD && controller.edge == .topRight) ? .on : .off
        dockBottomLeftItem.state = (isD && controller.edge == .bottomLeft) ? .on : .off
        dockBottomRightItem.state = (isD && controller.edge == .bottomRight) ? .on : .off

        undockItem.state = (!isD) ? .on : .off
        autoTuckItem.state = controller.autoTuck ? .on : .off
        attachedToEdgeItem.state = controller.isAttachedToEdge ? .on : .off
        filterAudioOnlyItem.state = controller.model.showAudioOnly ? .on : .off

        // Refresh hidden apps submenu
        hiddenAppsMenu.removeAllItems()
        let hidden = controller.model.hiddenApps
        if hidden.isEmpty {
            let emptyItem = NSMenuItem(title: "No Hidden Apps", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            hiddenAppsMenu.addItem(emptyItem)
        } else {
            for app in hidden {
                let item = NSMenuItem(title: "Unhide \(app.name)", action: #selector(unhideSingleApp(_:)), keyEquivalent: "")
                item.representedObject = app.persistenceKey
                hiddenAppsMenu.addItem(item)
            }
            hiddenAppsMenu.addItem(NSMenuItem.separator())
            hiddenAppsMenu.addItem(NSMenuItem(title: "Unhide All Apps", action: #selector(unhideAllAppsAction), keyEquivalent: ""))
        }
    }
}
