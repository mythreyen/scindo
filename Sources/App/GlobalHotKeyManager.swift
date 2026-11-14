import Cocoa
import Carbon

/// Manages system-wide global hotkeys via Carbon RegisterEventHotKey.
/// Does NOT require macOS Accessibility permissions.
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    enum HotKeyAction: UInt32 {
        case toggleDial = 1001
        case toggleMixer = 1002
        case volumeUp = 1003
        case volumeDown = 1004
        case toggleMute = 1005
    }

    private var registeredRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    weak var dockController: DockController?
    private var isRegistered = false

    private init() {
        installEventHandler()
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppSettingsGlobalHotkeysChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let controller = self.dockController else { return }
            if AppSettings.shared.globalHotkeysEnabled {
                self.registerHotKeys(controller: controller)
            } else {
                self.unregisterAll()
            }
        }
    }

    deinit {
        unregisterAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Event Handler Installation

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                GlobalHotKeyManager.shared.handleHotKey(id: hotKeyID.id)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    // MARK: - Registration

    func registerHotKeys(controller: DockController) {
        self.dockController = controller
        guard !isRegistered else { return }

        // Carbon Modifiers
        let optMod = UInt32(optionKey)
        let optShiftMod = UInt32(optionKey | shiftKey)

        // Key Codes (HIToolbox standard ANSI)
        let kVK_D: UInt32 = 0x02
        let kVK_M: UInt32 = 0x29
        let kVK_UpArrow: UInt32 = 0x7E
        let kVK_DownArrow: UInt32 = 0x7D

        // ⌥ + D -> Toggle Dial
        register(action: .toggleDial, keyCode: kVK_D, modifiers: optMod)

        // ⌥ + M -> Toggle Mixer
        register(action: .toggleMixer, keyCode: kVK_M, modifiers: optMod)

        // ⌥ + ↑ -> Volume Up 5%
        register(action: .volumeUp, keyCode: kVK_UpArrow, modifiers: optMod)

        // ⌥ + ↓ -> Volume Down 5%
        register(action: .volumeDown, keyCode: kVK_DownArrow, modifiers: optMod)

        // ⌥ + ⇧ + M -> Toggle Mute
        register(action: .toggleMute, keyCode: kVK_M, modifiers: optShiftMod)

        isRegistered = true
    }

    func unregisterAll() {
        for ref in registeredRefs {
            UnregisterEventHotKey(ref)
        }
        registeredRefs.removeAll()
        isRegistered = false
    }

    private func register(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(1936483188), id: action.rawValue) // 'SCIN'
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            registeredRefs.append(ref)
        }
    }

    // MARK: - Dispatch

    private func handleHotKey(id: UInt32) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let controller = self.dockController else { return }
            guard let action = HotKeyAction(rawValue: id) else { return }

            switch action {
            case .toggleDial:
                controller.toggleVisible()

            case .toggleMixer:
                if !controller.panel.isVisible {
                    controller.show()
                }
                controller.toggleExpanded()

            case .volumeUp:
                let nudge = controller.model.nudgeSelected(by: 0.05)
                if nudge.didChange {
                    controller.cancelVolumeScroll()
                }

            case .volumeDown:
                let nudge = controller.model.nudgeSelected(by: -0.05)
                if nudge.didChange {
                    controller.cancelVolumeScroll()
                }

            case .toggleMute:
                if let selected = controller.model.selected {
                    controller.model.toggleMute(for: selected.id)
                }
            }
        }
    }
}
