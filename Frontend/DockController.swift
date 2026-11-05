import SwiftUI
import AppKit
import Combine

/// Borderless, always-on-top panel that never steals focus from the app you're working in.
final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Custom hosting view that passes mouse clicks through transparent canvas areas outside the dial to underlying apps.
final class DialHostingView: NSHostingView<RootView> {
    weak var controller: DockController?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller else { return super.hitTest(point) }
        // When mixer is expanded, or app menu is open, or dragging window, accept all clicks in window
        if controller.isExpanded || controller.isAppMenuOpen || controller.isMoving {
            return super.hitTest(point)
        }
        // When resting/closed, only accept clicks inside the dial or bubble
        let rect: NSRect
        if controller.isBubble {
            rect = controller.currentBubbleRect()
                .offsetBy(dx: -controller.panel.frame.minX, dy: -controller.panel.frame.minY)
                .insetBy(dx: -16, dy: -16)
        } else {
            rect = controller.currentDialRect()
                .offsetBy(dx: -controller.panel.frame.minX, dy: -controller.panel.frame.minY)
                .insetBy(dx: -8, dy: -8)
        }
        if rect.contains(point) {
            return super.hitTest(point)
        }
        return nil
    }
}

/// Owns the floating panel: edge docking, snapping, auto-tucking, expand/collapse, idle fade, scroll-to-adjust.
final class DockController: ObservableObject {
    // Layout constants
    static let dialPadding: CGFloat = 16
    static let dialDiameter: CGFloat = 156
    static let dialSize: CGFloat = dialDiameter + dialPadding * 2   // 188
    static let gap: CGFloat = 0
    static let mixerWidth: CGFloat = 360
    static let rowHeight: CGFloat = 68
    static let maxMixerHeight: CGFloat = 540

    public enum Keys {
        static let edge = "dock.edge"
        static let along = "dock.along"
        static let autoTuck = "dock.autoTuck"
        static let attached = "dock.attached"
        static let isDocked = "dock.isDocked"
        static let floatingX = "dock.floatingX"
        static let floatingY = "dock.floatingY"
    }

    @Published public private(set) var edge: DockEdge
    @Published public private(set) var isDocked: Bool
    @Published public private(set) var isBubble: Bool = false
    @Published public var floatingOrigin: NSPoint
    @Published public private(set) var appCount: Int
    @Published public var isExpanded = false
    @Published public var isAppMenuOpen = false
    @Published public var menuFocusedIndex: Double = 0.0
    @Published public var isHovering = false
    @Published public var isAttachedToEdge: Bool {
        didSet {
            UserDefaults.standard.set(isAttachedToEdge, forKey: Keys.attached)
            relayout(animated: true)
        }
    }
    @Published public var autoTuck: Bool {
        didSet {
            UserDefaults.standard.set(autoTuck, forKey: Keys.autoTuck)
            updateTuckState()
        }
    }
    @Published public private(set) var isTucked: Bool = false
    @Published public var isScrollingVolume: Bool = false

    public var currentScreen: NSScreen {
        if let s = panel.screen {
            return s
        }
        let pFrame = panel.frame
        let bestScreen = NSScreen.screens.max { a, b in
            let areaA = a.frame.intersection(pFrame).width * a.frame.intersection(pFrame).height
            let areaB = b.frame.intersection(pFrame).width * b.frame.intersection(pFrame).height
            return areaA < areaB
        }
        return bestScreen ?? screen
    }

    public var isRightSideOfScreen: Bool {
        if isDocked {
            switch edge {
            case .right, .topRight, .bottomRight: return true
            default: return false
            }
        } else {
            let cl = menuClearance()
            let dialX = isMoving ? (panel.frame.origin.x + cl.left + Self.dialSize / 2.0) : (floatingOrigin.x + Self.dialSize / 2.0)
            return dialX >= currentScreen.visibleFrame.midX
        }
    }

    let model: MixerModel
    internal let panel: NSPanel
    public private(set) var screen: NSScreen
    /// 0...1 position of the dial along its docked edge.
    @Published public private(set) var along: CGFloat

    internal var isMoving = false
    private var moveStartMouse: NSPoint = .zero
    private var moveStartOrigin: NSPoint = .zero
    private var lastInside = Date()

    private var cancellables = Set<AnyCancellable>()
    private var scrollMonitor: Any?
    private var clickMonitor: Any?
    private var timer: Timer?
    private var scrollResetWorkItem: DispatchWorkItem?
    private var bubbleCollapseWorkItem: DispatchWorkItem?
    private var menuSnapWorkItem: DispatchWorkItem?

    var mixerHeight: CGFloat {
        let rows = CGFloat(max(appCount, 1))
        return min(40 + Self.rowHeight * rows + 12 + 4, Self.maxMixerHeight)
    }

    init(model: MixerModel = MixerModel(), panel: NSPanel? = nil) {
        self.model = model
        let defaults = UserDefaults.standard
        self.edge = DockEdge(rawValue: defaults.string(forKey: Keys.edge) ?? "") ?? .right
        self.along = CGFloat(defaults.object(forKey: Keys.along) as? Double ?? 0.5)
        self.autoTuck = defaults.bool(forKey: Keys.autoTuck)
        self.isAttachedToEdge = defaults.object(forKey: Keys.attached) as? Bool ?? true
        self.isDocked = defaults.object(forKey: Keys.isDocked) as? Bool ?? true
        let fx = defaults.object(forKey: Keys.floatingX) as? Double ?? 250.0
        let fy = defaults.object(forKey: Keys.floatingY) as? Double ?? 450.0
        self.floatingOrigin = NSPoint(x: fx, y: fy)
        self.appCount = model.apps.count
        self.screen = NSScreen.main ?? NSScreen.screens[0]

        let p = panel ?? Self.makePanel()
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        self.panel = p

        let hosting = DialHostingView(rootView: RootView(controller: self))
        hosting.sizingOptions = []
        hosting.controller = self
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = p.contentView?.bounds ?? .zero
        p.contentView = hosting

        model.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                guard let self else { return }
                self.appCount = apps.count
                if self.isExpanded { self.relayout() }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                if !NSScreen.screens.contains(self.screen) {
                    self.screen = NSScreen.main ?? NSScreen.screens[0]
                }
                self.relayout()
            }
            .store(in: &cancellables)

        relayout()

        if isDocked {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                guard self.isDocked, !self.isHovering, !self.isExpanded, !self.isMoving else { return }
                self.setBubble(true)
            }
        }
    }

    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        timer?.invalidate()
        scrollResetWorkItem?.cancel()
        scrollResetWorkItem = nil
        bubbleCollapseWorkItem?.cancel()
        bubbleCollapseWorkItem = nil
    }

    public func cancelVolumeScroll() {
        scrollResetWorkItem?.cancel()
        scrollResetWorkItem = nil
        if isScrollingVolume {
            withAnimation(.easeOut(duration: 0.15)) {
                isScrollingVolume = false
            }
        }
        scheduleBubbleCollapseIfNeeded()
    }

    private static func makePanel() -> NSPanel {
        let p = DockPanel(contentRect: .zero,
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered,
                          defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        return p
    }

    // MARK: - Docking API

    public func dock(to newEdge: DockEdge, animated: Bool = true) {
        if isExpanded {
            setExpanded(false)
        }
        screen = panel.screen ?? screen
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            isDocked = true
            isAttachedToEdge = true
            edge = newEdge
        }
        UserDefaults.standard.set(true, forKey: Keys.isDocked)
        UserDefaults.standard.set(edge.rawValue, forKey: Keys.edge)
        UserDefaults.standard.set(true, forKey: Keys.attached)
        relayout(animated: animated)
        scheduleBubbleCollapseIfNeeded(delay: 1.5)
    }

    public func undock(animated: Bool = true) {
        bubbleCollapseWorkItem?.cancel()
        bubbleCollapseWorkItem = nil
        setBubble(false, animated: animated)
        if isExpanded {
            setExpanded(false)
        }
        screen = panel.screen ?? screen
        let dial = currentDialRect()
        let vf = screen.visibleFrame
        let d = Self.dialSize
        let pull: CGFloat = 40.0
        var fx = dial.minX
        var fy = dial.minY
        switch edge {
        case .right, .topRight, .bottomRight:
            fx = max(dial.minX - pull, vf.minX)
        case .left, .topLeft, .bottomLeft:
            fx = min(dial.minX + pull, vf.maxX - d)
        case .top:
            fy = max(dial.minY - pull, vf.minY)
        case .bottom:
            fy = min(dial.minY + pull, vf.maxY - d)
        }
        floatingOrigin = NSPoint(x: fx, y: fy)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            isDocked = false
            isAttachedToEdge = false
        }
        UserDefaults.standard.set(false, forKey: Keys.isDocked)
        UserDefaults.standard.set(false, forKey: Keys.attached)
        UserDefaults.standard.set(Double(floatingOrigin.x), forKey: Keys.floatingX)
        UserDefaults.standard.set(Double(floatingOrigin.y), forKey: Keys.floatingY)
        relayout(animated: animated)
    }

    public func toggleAutoTuck() {
        autoTuck.toggle()
    }

    public func toggleAttachedToEdge() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            if !isDocked {
                isDocked = true
                isAttachedToEdge = true
            } else {
                isAttachedToEdge.toggle()
            }
        }
        UserDefaults.standard.set(isDocked, forKey: Keys.isDocked)
        UserDefaults.standard.set(isAttachedToEdge, forKey: Keys.attached)
        relayout(animated: true)
    }

    private func updateTuckState() {
        let shouldTuck = autoTuck && !isHovering && !isExpanded && !isMoving
        if shouldTuck != isTucked {
            isTucked = shouldTuck
            relayout(animated: true)
        }
    }

    // MARK: - Visibility

    func show() {
        relayout(animated: false)
        panel.orderFrontRegardless()
        installMonitors()
    }

    func toggleVisible() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    // MARK: - Curved App Selector Menu

    public func toggleAppMenu() {
        setAppMenu(!isAppMenuOpen)
    }

    public func setAppMenu(_ open: Bool) {
        guard open != isAppMenuOpen else { return }
        if open {
            bubbleCollapseWorkItem?.cancel()
            bubbleCollapseWorkItem = nil
            if isBubble {
                setBubble(false, animated: false)
            }
            if isExpanded {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    isExpanded = false
                }
                relayout(animated: true)
            }
            model.refresh()
            // Anchor initial focus directly on the currently active app
            if let selected = model.selected,
               let idx = model.apps.firstIndex(where: { $0.id == selected.id }) {
                menuFocusedIndex = Double(idx)
            } else {
                menuFocusedIndex = 0.0
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
                isAppMenuOpen = true
            }
        } else {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                isAppMenuOpen = false
            }
            scheduleBubbleCollapseIfNeeded(delay: 2.0)
        }
    }

    // MARK: - Radial App Menu Focus Navigation

    public func nudgeAppMenuFocus(by delta: Double, isInteractive: Bool = true) {
        guard !model.apps.isEmpty else { return }
        let maxIndex = Double(max(0, model.apps.count - 1))
        let target = min(max(menuFocusedIndex + delta, 0.0), maxIndex)

        if isInteractive {
            // Instant, razor-sharp interactive tracking (zero drag lag)
            withAnimation(.interactiveSpring(response: 0.08, dampingFraction: 0.92)) {
                menuFocusedIndex = target
            }
        } else {
            // Snappy, crisp spring for discrete wheel notches
            withAnimation(.spring(response: 0.16, dampingFraction: 0.78)) {
                menuFocusedIndex = target
            }
        }
    }

    public func snapAppMenuFocus(momentum: Double = 0.0) {
        guard !model.apps.isEmpty else { return }
        let maxIndex = Double(max(0, model.apps.count - 1))
        var target: Double
        if abs(momentum) > 0.35 {
            target = momentum > 0 ? ceil(menuFocusedIndex) : floor(menuFocusedIndex)
            if abs(momentum) > 1.2 {
                target += momentum > 0 ? 1.0 : -1.0
            }
        } else {
            target = round(menuFocusedIndex)
        }
        target = min(max(target, 0.0), maxIndex)

        // Snappy, decisive magnetic lock-in
        withAnimation(.spring(response: 0.18, dampingFraction: 0.76)) {
            menuFocusedIndex = target
        }
    }

    // MARK: - Preferences & Settings

    public func openSettings() {
        SettingsWindowController.shared.show(dockController: self)
    }

    // MARK: - Expand / Collapse

    func toggleExpanded() { setExpanded(!isExpanded) }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        if expanded {
            bubbleCollapseWorkItem?.cancel()
            bubbleCollapseWorkItem = nil
            if isBubble {
                setBubble(false, animated: false)
            }
            if isAppMenuOpen {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.74)) {
                    isAppMenuOpen = false
                }
            }
            model.refresh()
            if isTucked {
                isTucked = false
            }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.70)) {
                isExpanded = true
            }
            relayout(animated: true)
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                isExpanded = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                guard let self, !self.isExpanded else { return }
                self.relayout(animated: true)
                self.scheduleBubbleCollapseIfNeeded()
            }
        }
    }

    // MARK: - Moving + Snapping

    func beginMove() {
        guard !isAppMenuOpen else { return }
        bubbleCollapseWorkItem?.cancel()
        bubbleCollapseWorkItem = nil
        if isBubble {
            setBubble(false, animated: false)
        }
        if isExpanded {
            isExpanded = false
        }
        if isTucked {
            isTucked = false
        }
        isMoving = true
        moveStartMouse = NSEvent.mouseLocation
        moveStartOrigin = panel.frame.origin
    }

    func changeMove() {
        guard isMoving, !isAppMenuOpen else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: moveStartOrigin.x + mouse.x - moveStartMouse.x,
                                     y: moveStartOrigin.y + mouse.y - moveStartMouse.y))
    }

    func endMove() {
        guard isMoving else { return }
        isMoving = false

        let mouse = NSEvent.mouseLocation
        let dragTravel = hypot(mouse.x - moveStartMouse.x, mouse.y - moveStartMouse.y)
        // If docked and moved less than 24 points, do not undock — snap back cleanly
        if isDocked && dragTravel < 24 {
            relayout(animated: true)
            return
        }

        let d = Self.dialSize
        let cl = menuClearance()
        // The padded dial container origin in screen coordinates:
        let boxX = panel.frame.origin.x + cl.left
        let boxY = panel.frame.origin.y + cl.bottom
        let boxRect = NSRect(x: boxX, y: boxY, width: d, height: d)

        // The visible 156pt dial circle (inset by dialPadding = 16):
        let circleMinX = boxRect.minX + Self.dialPadding
        let circleMaxX = boxRect.maxX - Self.dialPadding
        let circleMinY = boxRect.minY + Self.dialPadding
        let circleMaxY = boxRect.maxY - Self.dialPadding

        let center = NSPoint(x: boxRect.midX, y: boxRect.midY)
        screen = NSScreen.screens.first { $0.frame.contains(center) } ?? panel.screen ?? screen
        let vf = screen.visibleFrame

        // Precise distances from the visible circular dial to screen edges:
        let distLeft = circleMinX - vf.minX
        let distRight = vf.maxX - circleMaxX
        let distBottom = circleMinY - vf.minY
        let distTop = vf.maxY - circleMaxY

        // Snapping thresholds: user must bring the dial pretty close to an edge or corner to dock
        let cornerSnapDist: CGFloat = 36.0
        let edgeSnapDist: CGFloat = 26.0

        let isTopLeft = distLeft < cornerSnapDist && distTop < cornerSnapDist
        let isTopRight = distRight < cornerSnapDist && distTop < cornerSnapDist
        let isBottomLeft = distLeft < cornerSnapDist && distBottom < cornerSnapDist
        let isBottomRight = distRight < cornerSnapDist && distBottom < cornerSnapDist

        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            if isTopLeft {
                isDocked = true
                isAttachedToEdge = true
                edge = .topLeft
            } else if isTopRight {
                isDocked = true
                isAttachedToEdge = true
                edge = .topRight
            } else if isBottomLeft {
                isDocked = true
                isAttachedToEdge = true
                edge = .bottomLeft
            } else if isBottomRight {
                isDocked = true
                isAttachedToEdge = true
                edge = .bottomRight
            } else if distLeft < edgeSnapDist {
                isDocked = true
                isAttachedToEdge = true
                edge = .left
                along = min(max((boxRect.minY - vf.minY) / max(vf.height - d, 1), 0), 1)
            } else if distRight < edgeSnapDist {
                isDocked = true
                isAttachedToEdge = true
                edge = .right
                along = min(max((boxRect.minY - vf.minY) / max(vf.height - d, 1), 0), 1)
            } else if distTop < edgeSnapDist {
                isDocked = true
                isAttachedToEdge = true
                edge = .top
                along = min(max((boxRect.minX - vf.minX) / max(vf.width - d, 1), 0), 1)
            } else if distBottom < edgeSnapDist {
                isDocked = true
                isAttachedToEdge = true
                edge = .bottom
                along = min(max((boxRect.minX - vf.minX) / max(vf.width - d, 1), 0), 1)
            } else {
                // Not dropped near any corner or edge: FREE FLOATING anywhere on screen!
                isDocked = false
                isAttachedToEdge = false
                floatingOrigin = NSPoint(
                    x: min(max(boxRect.minX, vf.minX), vf.maxX - d),
                    y: min(max(boxRect.minY, vf.minY), vf.maxY - d)
                )
            }
        }

        let defaults = UserDefaults.standard
        defaults.set(isDocked, forKey: Keys.isDocked)
        defaults.set(isAttachedToEdge, forKey: Keys.attached)
        defaults.set(edge.rawValue, forKey: Keys.edge)
        defaults.set(Double(along), forKey: Keys.along)
        defaults.set(Double(floatingOrigin.x), forKey: Keys.floatingX)
        defaults.set(Double(floatingOrigin.y), forKey: Keys.floatingY)

        relayout(animated: true)
        scheduleBubbleCollapseIfNeeded(delay: 1.2)
    }

    // MARK: - Geometry

    public struct MenuClearance: Equatable {
        public let top: CGFloat
        public let bottom: CGFloat
        public let left: CGFloat
        public let right: CGFloat

        public static let zero = MenuClearance(top: 0, bottom: 0, left: 0, right: 0)
    }

    public func menuClearance() -> MenuClearance {
        if isExpanded {
            return .zero
        }
        let ext: CGFloat = 140.0
        return MenuClearance(top: ext, bottom: ext, left: ext, right: ext)
    }

    /// Where the dial itself sits (screen coordinates).
    private func dialFrame(in vf: NSRect) -> NSRect {
        let d = Self.dialSize

        guard isDocked else {
            // Free floating anywhere on screen:
            let x = min(max(floatingOrigin.x, vf.minX), vf.maxX - d)
            let y = min(max(floatingOrigin.y, vf.minY), vf.maxY - d)
            return NSRect(x: x, y: y, width: d, height: d)
        }

        let attachOffset: CGFloat = isAttachedToEdge ? (d * 0.25) : 0
        let tuckOffset: CGFloat = isTucked ? (d * 0.50) : 0
        let offset = max(attachOffset, tuckOffset)

        switch edge {
        case .left:
            return NSRect(x: vf.minX - offset, y: vf.minY + along * (vf.height - d), width: d, height: d)
        case .right:
            return NSRect(x: vf.maxX - d + offset, y: vf.minY + along * (vf.height - d), width: d, height: d)
        case .bottom:
            return NSRect(x: vf.minX + along * (vf.width - d), y: vf.minY - offset, width: d, height: d)
        case .top:
            return NSRect(x: vf.minX + along * (vf.width - d), y: vf.maxY - d + offset, width: d, height: d)
        case .topLeft:
            return NSRect(x: vf.minX - offset, y: vf.maxY - d + offset, width: d, height: d)
        case .topRight:
            return NSRect(x: vf.maxX - d + offset, y: vf.maxY - d + offset, width: d, height: d)
        case .bottomLeft:
            return NSRect(x: vf.minX - offset, y: vf.minY - offset, width: d, height: d)
        case .bottomRight:
            return NSRect(x: vf.maxX - d + offset, y: vf.minY - offset, width: d, height: d)
        }
    }

    private func panelFrame(in vf: NSRect) -> NSRect {
        let dial = dialFrame(in: vf)
        if isExpanded {
            let d = Self.dialSize, g = Self.gap
            let mw = Self.mixerWidth, mh = mixerHeight
            var f: NSRect

            if !isDocked {
                let h = max(d, mh)
                if isRightSideOfScreen {
                    f = NSRect(x: dial.maxX - (d + g + mw), y: dial.maxY - h, width: d + g + mw, height: h)
                } else {
                    f = NSRect(x: dial.minX, y: dial.maxY - h, width: d + g + mw, height: h)
                }
            } else {
                switch edge {
                case .left, .topLeft:
                    let h = max(d, mh)
                    f = NSRect(x: dial.minX, y: dial.maxY - h, width: d + g + mw, height: h)
                case .right, .topRight:
                    let h = max(d, mh)
                    f = NSRect(x: dial.maxX - (d + g + mw), y: dial.maxY - h, width: d + g + mw, height: h)
                case .top:
                    let h = d + g + mh
                    f = NSRect(x: dial.minX, y: dial.maxY - h, width: max(d, mw), height: h)
                case .bottom:
                    f = NSRect(x: dial.minX, y: dial.minY, width: max(d, mw), height: d + g + mh)
                case .bottomLeft:
                    let h = max(d, mh)
                    f = NSRect(x: dial.minX, y: dial.minY, width: d + g + mw, height: h)
                case .bottomRight:
                    let h = max(d, mh)
                    f = NSRect(x: dial.maxX - (d + g + mw), y: dial.minY, width: d + g + mw, height: h)
                }
            }

            // Keep the whole panel on screen when expanded
            if f.maxX > vf.maxX { f.origin.x = vf.maxX - f.width }
            if f.minX < vf.minX { f.origin.x = vf.minX }
            if f.maxY > vf.maxY { f.origin.y = vf.maxY - f.height }
            if f.minY < vf.minY { f.origin.y = vf.minY }
            return f
        } else {
            let cl = menuClearance()
            let f = NSRect(
                x: dial.minX - cl.left,
                y: dial.minY - cl.bottom,
                width: dial.width + cl.left + cl.right,
                height: dial.height + cl.top + cl.bottom
            )
            return f
        }
    }

    /// Dial rect in screen coordinates.
    public func currentDialRect() -> NSRect {
        dialFrame(in: currentScreen.visibleFrame)
    }

    func relayout(animated: Bool = false) {
        if let ps = panel.screen {
            screen = ps
        }
        let frame = panelFrame(in: screen.visibleFrame)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: - Bubble Mode (Resting Docked State)

    public func setBubble(_ bubble: Bool, animated: Bool = true) {
        guard isDocked else {
            if isBubble {
                if animated {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.68)) {
                        isBubble = false
                    }
                } else {
                    isBubble = false
                }
            }
            return
        }
        guard bubble != isBubble else { return }
        if animated {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.68)) {
                isBubble = bubble
            }
        } else {
            isBubble = bubble
        }
    }

    public func scheduleBubbleCollapseIfNeeded(delay: TimeInterval = 0.85) {
        guard isDocked, !isExpanded, !isAppMenuOpen, !isMoving, !isScrollingVolume, !isHovering else { return }
        bubbleCollapseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isDocked, !self.isExpanded, !self.isAppMenuOpen, !self.isMoving, !self.isScrollingVolume, !self.isHovering else { return }
            self.setBubble(true)
        }
        bubbleCollapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    public func currentBubbleRect() -> NSRect {
        let dial = currentDialRect()
        var cx = dial.midX
        var cy = dial.midY
        if isDocked {
            let push: CGFloat = 12.0
            switch edge {
            case .right: cx += push
            case .left: cx -= push
            case .top: cy += push
            case .bottom: cy -= push
            case .topRight:
                cx += push * 0.7
                cy += push * 0.7
            case .topLeft:
                cx -= push * 0.7
                cy += push * 0.7
            case .bottomLeft:
                cx -= push * 0.7
                cy -= push * 0.7
            case .bottomRight:
                cx += push * 0.7
                cy += push * 0.7
            }
        }
        let size: CGFloat = 62.0
        return NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
    }

    // MARK: - Event Monitors + Idle Handling

    private func installMonitors() {
        guard timer == nil else { return }

        // Scroll over the dial/bubble to change volume; scroll during open menu to rotate focused apps.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel else { return event }

            if self.isAppMenuOpen {
                var dy = Double(event.scrollingDeltaY)
                var dx = Double(event.scrollingDeltaX)
                if event.isDirectionInvertedFromDevice {
                    dy = -dy
                    dx = -dx
                }
                let rawDelta = abs(dy) >= abs(dx) ? dy : dx
                if event.hasPreciseScrollingDeltas {
                    let step = -rawDelta / 18.0
                    self.nudgeAppMenuFocus(by: step, isInteractive: true)

                    if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                        self.menuSnapWorkItem?.cancel()
                        self.snapAppMenuFocus()
                    } else {
                        self.menuSnapWorkItem?.cancel()
                        let item = DispatchWorkItem { [weak self] in
                            self?.snapAppMenuFocus()
                        }
                        self.menuSnapWorkItem = item
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
                    }
                } else {
                    // Discrete mouse wheel notch
                    let step = rawDelta > 0 ? -1.0 : 1.0
                    self.nudgeAppMenuFocus(by: step, isInteractive: false)
                }
                return nil
            }

            let mouse = NSEvent.mouseLocation
            let targetRect = self.isBubble ? self.currentBubbleRect().insetBy(dx: -16, dy: -16) : self.currentDialRect()
            guard targetRect.contains(mouse) else { return event }

            if self.isBubble {
                self.bubbleCollapseWorkItem?.cancel()
                self.bubbleCollapseWorkItem = nil
                self.setBubble(false)
            }

            var dy = Double(event.scrollingDeltaY)
            if event.isDirectionInvertedFromDevice { dy = -dy }
            let sens = AppSettings.shared.scrollSensitivity
            let step = (event.hasPreciseScrollingDeltas ? dy / 400 : dy / 40) * sens
            self.model.nudgeSelected(by: step)

            if AppSettings.shared.hapticFeedback && abs(step) > 0.005 {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }

            if !self.isScrollingVolume {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.60)) {
                    self.isScrollingVolume = true
                }
            }
            self.scrollResetWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.65)) {
                    self?.isScrollingVolume = false
                }
                self?.scheduleBubbleCollapseIfNeeded()
            }
            self.scrollResetWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: item)

            return nil
        }

        // Clicking anywhere in another app closes the mixer and curved app menu.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.isAppMenuOpen {
                self.setAppMenu(false)
            }
            if self.isExpanded {
                self.setExpanded(false)
            }
        }

        // Hover & auto-tuck tracking (50ms interval for fluid wake/bloom)
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let inside: Bool
        if isMoving {
            inside = true
        } else if isExpanded || isAppMenuOpen {
            inside = panel.frame.contains(mouse)
        } else if isBubble {
            inside = currentBubbleRect().insetBy(dx: -16, dy: -16).contains(mouse)
        } else {
            inside = currentDialRect().insetBy(dx: -8, dy: -8).contains(mouse)
        }

        if inside != isHovering {
            isHovering = inside
            handleHoverChanged(inside)
        }

        if inside {
            lastInside = Date()
        } else if isExpanded, Date().timeIntervalSince(lastInside) > 3.0 {
            setExpanded(false)
        } else if autoTuck, !isTucked, Date().timeIntervalSince(lastInside) > 2.0 {
            updateTuckState()
        }
    }

    private func handleHoverChanged(_ inside: Bool) {
        if inside {
            bubbleCollapseWorkItem?.cancel()
            bubbleCollapseWorkItem = nil
            if isBubble {
                setBubble(false)
            }
            if autoTuck {
                updateTuckState()
            }
        } else {
            if autoTuck {
                updateTuckState()
            }
            scheduleBubbleCollapseIfNeeded()
        }
    }
}
