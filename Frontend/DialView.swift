import SwiftUI
import AppKit

/// A glass circle with a ring of pill-shaped "petals". Volume fills them clockwise from 12 o'clock,
/// and each petal springs with an elastic liquid bounce as it fills.
///
/// Ring: drag or scroll to change volume.
/// Center: click = next app, hold = show/hide the app list, drag = move the dial, right-click = dock menu.
struct DialView: View {
    let volume: Double
    let isMuted: Bool
    let icon: NSImage?
    let label: String
    var selectedID: pid_t? = nil
    var isScrollingVolume: Bool = false
    var isAttachedToEdge: Bool = true
    var isDocked: Bool = true
    var isBubble: Bool = false
    var isAppMenuOpen: Bool = false
    var menuFocusedIndex: Double = 0.0
    var onNudgeFocus: (Double) -> Void = { _ in }
    var onSnapFocus: (Double) -> Void = { _ in }
    var apps: [AudioApp] = []
    var isRightSideOfScreen: Bool = true
    var along: CGFloat = 0.5
    var dockEdge: DockEdge = .right
    var size: CGFloat = 156
    var autoTuck: Bool = false
    var isTucked: Bool = false
    var currentEdge: DockEdge = .right

    var onVolumeChange: (Double) -> Void
    var onTap: () -> Void
    var onLongPress: () -> Void
    var onSelectApp: (pid_t) -> Void = { _ in }
    var onToggleMute: () -> Void
    var onMoveBegan: () -> Void
    var onMoveChanged: () -> Void
    var onMoveEnded: () -> Void
    var onDockEdge: (DockEdge) -> Void = { _ in }
    var onUndock: () -> Void = {}
    var onToggleAutoTuck: () -> Void = {}
    var onToggleAttachedToEdge: () -> Void = {}

    private enum DragMode {
        case ring
        case move
    }

    @State private var dragMode: DragMode? = nil
    @State private var dragStartLocation: CGPoint = .zero
    @State private var hasMovedSignificantly = false
    @State private var isDragging = false
    @State private var lastRaw: Double? = nil
    @State private var isMovingWindow = false
    @State private var longPressWorkItem: DispatchWorkItem? = nil
    @State private var didTriggerLongPress: Bool = false

    private var isShowingVolumeReadout: Bool {
        isDragging || isScrollingVolume
    }

    private var isPressedDisc: Bool {
        dragMode == .move && !isMovingWindow
    }

    private var petalWidth: CGFloat { size * 0.058 }
    private var petalLength: CGFloat { size * 0.165 }
    private var innerRadius: CGFloat { size * 0.27 }

    private var bubbleOffset: CGSize {
        guard isBubble && isDocked else { return .zero }
        let push: CGFloat = 12.0
        switch dockEdge {
        case .right: return CGSize(width: push, height: 0)
        case .left: return CGSize(width: -push, height: 0)
        case .top: return CGSize(width: 0, height: -push)
        case .bottom: return CGSize(width: 0, height: push)
        case .topRight: return CGSize(width: push * 0.7, height: -push * 0.7)
        case .topLeft: return CGSize(width: -push * 0.7, height: -push * 0.7)
        case .bottomLeft: return CGSize(width: -push * 0.7, height: push * 0.7)
        case .bottomRight: return CGSize(width: push * 0.7, height: push * 0.7)
        }
    }

    private var activeHitShape: AnyShape {
        if isBubble {
            let r: CGFloat = innerRadius * 1.25 / 2 + 8
            let cx = size / 2 + bubbleOffset.width
            let cy = size / 2 + bubbleOffset.height
            return AnyShape(
                Path { path in
                    path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                }
            )
        } else {
            return AnyShape(Circle())
        }
    }

    var body: some View {
        ZStack {
            // Curved App Selector Menu (blooms outside the dial when long pressed)
            if isAppMenuOpen && !isBubble {
                CurvedAppMenuView(
                    apps: apps,
                    selectedID: selectedID,
                    dockEdge: dockEdge,
                    isDocked: isDocked,
                    isRightSideOfScreen: isRightSideOfScreen,
                    focusedIndex: menuFocusedIndex,
                    onNudgeFocus: onNudgeFocus,
                    onSnapFocus: onSnapFocus,
                    onSelectApp: onSelectApp
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.38, anchor: .center).combined(with: .opacity),
                        removal: .scale(scale: 0.30, anchor: .center).combined(with: .opacity)
                    )
                )
            }

            // The Dial itself
            dialCore
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isAppMenuOpen)
    }

    private var dialCore: some View {
        ZStack {
            // Main liquid glass dial base (smoothly hides in bubble mode)
            Color.clear.liquidGlass(in: Circle())
                .opacity(isBubble ? 0.0 : 1.0)
                .scaleEffect(isBubble ? 0.45 : 1.0)

            // Petals ring: fixed 20 slots with permanent IDs (smoothly retracts in bubble mode, softens in menu mode)
            ForEach(0..<20, id: \.self) { i in
                petal(i)
            }
            .opacity(isBubble ? 0.0 : (isAppMenuOpen ? 0.42 : 1.0))
            .scaleEffect(isBubble ? 0.40 : (isAppMenuOpen ? 0.96 : 1.0))

            // Floating liquid glass center disc (morphs into the compact resting bubble)
            centerDisc
                .offset(bubbleOffset)

            // Edge docking tab indicator when tucked
            if isTucked && !isBubble {
                edgeTuckIndicator
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isShowingVolumeReadout ? 1.025 : (isTucked ? 0.95 : 1.0))
        .animation(.spring(response: 0.36, dampingFraction: 0.68), value: isBubble)
        .animation(.spring(response: 0.32, dampingFraction: 0.40), value: isShowingVolumeReadout)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isTucked)
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isAppMenuOpen)
        .contentShape(activeHitShape)
        .gesture(dialGesture)
        .contextMenu {
            Button(isMuted ? "Unmute" : "Mute", action: onToggleMute)
            Button("Switch App Menu (Curved)", action: onLongPress)
            Divider()
            Button(isAttachedToEdge ? "✓ Attached to Edge (Partially Visible)" : "Attach to Edge (Partially Visible)", action: onToggleAttachedToEdge)
            Menu("Dock to Screen Edge or Corner") {
                Section("Screen Edges") {
                    Button(isDocked && currentEdge == .left ? "✓ Left Edge" : "Left Edge") { onDockEdge(.left) }
                    Button(isDocked && currentEdge == .right ? "✓ Right Edge" : "Right Edge") { onDockEdge(.right) }
                    Button(isDocked && currentEdge == .top ? "✓ Top Edge" : "Top Edge") { onDockEdge(.top) }
                    Button(isDocked && currentEdge == .bottom ? "✓ Bottom Edge" : "Bottom Edge") { onDockEdge(.bottom) }
                }
                Section("Screen Corners") {
                    Button(isDocked && currentEdge == .topLeft ? "✓ Top-Left Corner" : "Top-Left Corner") { onDockEdge(.topLeft) }
                    Button(isDocked && currentEdge == .topRight ? "✓ Top-Right Corner" : "Top-Right Corner") { onDockEdge(.topRight) }
                    Button(isDocked && currentEdge == .bottomLeft ? "✓ Bottom-Left Corner" : "Bottom-Left Corner") { onDockEdge(.bottomLeft) }
                    Button(isDocked && currentEdge == .bottomRight ? "✓ Bottom-Right Corner" : "Bottom-Right Corner") { onDockEdge(.bottomRight) }
                }
                Divider()
                Button(!isDocked ? "✓ Undock (Free Floating Anywhere)" : "Undock (Free Floating Anywhere)", action: onUndock)
            }
            Button(autoTuck ? "✓ Auto-Tuck at Screen Edge" : "Auto-Tuck at Screen Edge", action: onToggleAutoTuck)
        }
        .help(label)
    }

    // MARK: - Edge Tuck Handle

    private var edgeTuckIndicator: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2.0
            )
            .scaleEffect(1.04)
            .shadow(color: Color.white.opacity(0.4), radius: 6)
            .transition(.opacity)
    }

    // MARK: - Petals & Smooth Docking State

    private struct PillState {
        let isVisible: Bool
        let orderIndex: Int?     // Order within visible arc (0...10), or index (0...19) when detached
        let angle: Double
        let staggerDelay: Double
    }

    private func pillState(for index: Int) -> PillState {
        let baseAngle = Double(index) * 18.0
        guard isAttachedToEdge else {
            return PillState(
                isVisible: true,
                orderIndex: index,
                angle: baseAngle,
                staggerDelay: 0.0
            )
        }

        let (isVisible, orderIndex, angle, distance): (Bool, Int?, Double, Double) = {
            switch dockEdge {
            case .right:
                // Visible hemisphere: left half (180° -> 270° -> 360°/0°)
                // Indices 10...19 and 0
                if index >= 10 {
                    return (true, index - 10, baseAngle, Double(abs(index - 15)))
                } else if index == 0 {
                    return (true, 10, baseAngle, 5.0)
                } else {
                    // Submerged indices 1...9 (centered at index 5, 90°)
                    return (false, nil, baseAngle, Double(abs(index - 5)))
                }

            case .left:
                // Visible hemisphere: right half (0° -> 90° -> 180°)
                // Indices 0...10 (order 10 down to 0: bottom is 10, top is 0)
                if index <= 10 {
                    return (true, 10 - index, baseAngle, Double(abs(index - 5)))
                } else {
                    // Submerged indices 11...19 (centered at index 15, 270°)
                    return (false, nil, baseAngle, Double(abs(index - 15)))
                }

            case .bottom:
                // Visible hemisphere: top half (270° -> 0° -> 90°)
                // Indices 15...19 and 0...5
                if index >= 15 {
                    return (true, index - 15, baseAngle, Double(abs(index - 15)))
                } else if index <= 5 {
                    return (true, index + 5, baseAngle, Double(index))
                } else {
                    // Submerged indices 6...14 (centered at index 10, 180°)
                    return (false, nil, baseAngle, Double(abs(index - 10)))
                }

            case .top:
                // Visible hemisphere: bottom half (90° -> 180° -> 270°)
                // Indices 5...15 (order: left is 15, right is 5 -> 15 down to 5)
                if index >= 5 && index <= 15 {
                    return (true, 15 - index, baseAngle, Double(abs(index - 10)))
                } else {
                    // Submerged indices 16...19 and 0...4 (centered at index 0, 0°)
                    let dist = index >= 16 ? Double(20 - index) : Double(index)
                    return (false, nil, baseAngle, dist)
                }

            case .topRight:
                // Submerged corner: 0°...90° (top-right, around index 2.5)
                // Visible arc: 162°...288° (indices 9...16, 8 pills, safe 18pt margin from bezels, centered at 225° SW)
                if index >= 9 && index <= 16 {
                    return (true, index - 9, baseAngle, abs(Double(index) - 12.5))
                } else {
                    let d = index <= 8 ? abs(Double(index) - 2.5) : abs(Double(index - 20) - 2.5)
                    return (false, nil, baseAngle, d)
                }

            case .topLeft:
                // Submerged corner: 270°...360° (top-left, around index 17.5)
                // Visible arc: 72°...198° (indices 4...11, 8 pills, safe 18pt margin from bezels, centered at 135° SE)
                if index >= 4 && index <= 11 {
                    return (true, index - 4, baseAngle, abs(Double(index) - 7.5))
                } else {
                    let d = index >= 12 ? abs(Double(index) - 17.5) : abs(Double(index + 20) - 17.5)
                    return (false, nil, baseAngle, d)
                }

            case .bottomLeft:
                // Submerged corner: 180°...270° (bottom-left, around index 12.5)
                // Visible arc: 342°...108° (indices 19, 0...6, 8 pills, safe 18pt margin from bezels, centered at 45° NE)
                if index == 19 {
                    return (true, 0, baseAngle, abs(Double(index - 20) - 2.5))
                } else if index <= 6 {
                    return (true, index + 1, baseAngle, abs(Double(index) - 2.5))
                } else {
                    return (false, nil, baseAngle, abs(Double(index) - 12.5))
                }

            case .bottomRight:
                // Submerged corner: 90°...180° (bottom-right, around index 7.5)
                // Visible arc: 252°...18° (indices 14...19, 0...1, 8 pills, safe 18pt margin from bezels, centered at 315° NW)
                if index >= 14 {
                    return (true, index - 14, baseAngle, abs(Double(index) - 17.5))
                } else if index <= 1 {
                    return (true, index + 6, baseAngle, abs(Double(index + 20) - 17.5))
                } else {
                    return (false, nil, baseAngle, abs(Double(index) - 7.5))
                }
            }
        }()

        // Stagger ripple: pills closest to the screen bezel submerge first
        let delay = distance * 0.015
        return PillState(
            isVisible: isVisible,
            orderIndex: orderIndex,
            angle: angle,
            staggerDelay: delay
        )
    }

    private func petal(_ index: Int) -> some View {
        let state = pillState(for: index)
        let isVis = state.isVisible
        let count = isAttachedToEdge ? (dockEdge.isCorner ? 8 : 11) : 20
        let effectiveOrder = state.orderIndex ?? index
        let amount = isVis ? min(max(volume * Double(count) - Double(effectiveOrder), 0), 1) : 0
        let strength = isMuted ? 0.25 : 1.0

        return ZStack {
            // Glass track groove
            Capsule()
                .fill(Color.primary.opacity(isVis ? 0.12 : 0.0))
                .frame(width: petalWidth, height: petalLength)
                .scaleEffect(isVis ? 1.0 : 0.35)

            // Luminous active liquid petal
            Capsule()
                .fill(
                    LinearGradient(
                        colors: isMuted
                            ? [Color.secondary.opacity(0.45), Color.secondary.opacity(0.15)]
                            : [
                                Color.white.opacity(0.95),
                                Color.primary.opacity(0.70 + 0.30 * amount)
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.65 * amount * strength), lineWidth: 0.75)
                )
                .shadow(color: (isMuted || !isVis) ? Color.clear : Color.white.opacity(0.38 * amount), radius: 5, x: 0, y: 0)
                .frame(width: petalWidth, height: petalLength)
                // Continuous, smooth spring swell:
                .scaleEffect(
                    x: isVis ? (1.0 + 0.38 * amount) : 0.35,
                    y: isVis ? (1.0 + 0.22 * amount) : 0.35
                )
                .offset(y: isVis ? -(amount * 3.0) : 4.0)
                .opacity(isVis ? (amount * strength) : 0.0)
        }
        .offset(y: -(innerRadius + petalLength / 2))
        .rotationEffect(.degrees(state.angle))
        .animation(.spring(response: 0.30, dampingFraction: 0.54, blendDuration: 0.04), value: amount)
        .animation(.spring(response: 0.38, dampingFraction: 0.72).delay(state.staggerDelay), value: isVis)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: dockEdge)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: state.angle)
        .animation(.easeOut(duration: 0.25), value: isMuted)
    }

    // MARK: - Center Disc

    private var centerDisc: some View {
        ZStack {
            // Pure vector circular shadow behind the glass disc (no Material in this layer)
            Circle()
                .fill(Color.black.opacity(isBubble ? 0.28 : 0.18))
                .shadow(color: Color.black.opacity(isBubble ? 0.35 : 0.24), radius: isBubble ? 12 : 8, x: 0, y: isBubble ? 5 : 4)

            // Translucent dark base preventing raw desktop capture flash during window moves
            Circle()
                .fill(Color(white: 0.14, opacity: 0.65))

            // Liquid Glass Disc Body
            Circle()
                .fill(.ultraThinMaterial)

            // Specular sheen on the glass disc
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isBubble ? 0.50 : 0.40),
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Glass lens rim highlight
            Circle()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isBubble ? 0.90 : 0.85), location: 0.0),
                            .init(color: Color.white.opacity(0.32), location: 0.45),
                            .init(color: Color.white.opacity(0.10), location: 0.70),
                            .init(color: Color.white.opacity(isBubble ? 0.55 : 0.50), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isBubble ? 1.4 : 1.25
                )

            // Luminous halo highlight when the radial app menu is blossomed
            if isAppMenuOpen && !isBubble {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.35, green: 0.80, blue: 1.00)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.8
                    )
                    .shadow(color: Color(red: 0.35, green: 0.80, blue: 1.00).opacity(0.55), radius: 6)
                    .transition(.opacity)
            }

            // Clean, Glowing Volume Arc in Bubble Mode
            if isBubble {
                let effVol = isMuted ? 0.0 : volume
                ZStack {
                    // Subtle background track
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 2.0)
                        .padding(3.5)

                    // Active luminous volume arc with subtle pearl-to-azure gradient
                    Circle()
                        .trim(from: 0, to: CGFloat(effVol))
                        .stroke(
                            LinearGradient(
                                colors: isMuted ? [
                                    Color.secondary.opacity(0.40),
                                    Color.secondary.opacity(0.15)
                                ] : [
                                    Color.white.opacity(0.95),
                                    Color(red: 0.42, green: 0.72, blue: 0.95) // Soft, muted ice blue
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(3.5)
                        .shadow(
                            color: isMuted ? Color.clear : Color(red: 0.42, green: 0.72, blue: 0.95).opacity(0.35),
                            radius: 2.5
                        )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }

            // Dynamic Content
            ZStack {
                if isShowingVolumeReadout && !isBubble {
                    Text("\(Int((volume * 100).rounded()))")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                        .shadow(color: Color.white.opacity(0.3), radius: 2)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                } else if isBubble {
                    // Living animated fluid core inside the resting bubble (no logo!)
                    BubbleInteriorView(volume: volume, isMuted: isMuted)
                        .transition(.scale(scale: 0.70).combined(with: .opacity))
                } else if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size * 0.38, height: size * 0.38)
                        .opacity(isMuted ? 0.35 : 1)
                        .shadow(color: Color.black.opacity(0.2), radius: 3, y: 2)
                        .id(selectedID ?? 0)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.70)
                                    .combined(with: .opacity)
                                    .combined(with: .offset(y: 8)),
                                removal: .scale(scale: 1.18)
                                    .combined(with: .opacity)
                                    .combined(with: .offset(y: -8))
                            )
                        )
                } else {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(isMuted ? Color.secondary : Color.primary)
                        .id("fallback-\(selectedID ?? 0)")
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.70)
                                    .combined(with: .opacity)
                                    .combined(with: .offset(y: 8)),
                                removal: .scale(scale: 1.18)
                                    .combined(with: .opacity)
                                    .combined(with: .offset(y: -8))
                            )
                        )
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.65), value: isShowingVolumeReadout)
        }
        .frame(
            width: innerRadius * (isBubble ? 1.25 : 1.80),
            height: innerRadius * (isBubble ? 1.25 : 1.80)
        )
        .scaleEffect(
            isShowingVolumeReadout ? 1.06 : (
                isMovingWindow ? 0.94 : (
                    isAppMenuOpen ? 1.04 : (
                        isPressedDisc ? 0.93 : 1.0
                    )
                )
            )
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.58), value: isShowingVolumeReadout)
        .animation(.spring(response: 0.30, dampingFraction: 0.55), value: isMovingWindow)
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isPressedDisc)
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isAppMenuOpen)
        .animation(.spring(response: 0.36, dampingFraction: 0.68), value: isBubble)
    }

    // MARK: - Unified Dial & Window Gesture

    private var dialGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                let dx = g.startLocation.x - size / 2
                let dy = g.startLocation.y - size / 2
                let dist = hypot(dx, dy)

                if dragMode == nil {
                    dragStartLocation = g.startLocation
                    hasMovedSignificantly = false
                    didTriggerLongPress = false

                    if !isBubble && dist >= innerRadius * 0.92 {
                        dragMode = .ring
                        isDragging = true
                        lastRaw = nil
                    } else {
                        dragMode = .move
                        // Start long-press timer on center disc (0.35s):
                        longPressWorkItem?.cancel()
                        let item = DispatchWorkItem {
                            if !hasMovedSignificantly && !isMovingWindow {
                                didTriggerLongPress = true
                                isMovingWindow = false
                                onLongPress()
                            }
                        }
                        longPressWorkItem = item
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
                    }
                }

                switch dragMode {
                case .ring:
                    var raw = value(at: g.location)
                    if let last = lastRaw, abs(raw - last) > 0.5 {
                        raw = last > 0.5 ? 1 : 0
                    }
                    lastRaw = raw
                    onVolumeChange(raw)

                case .move:
                    guard !didTriggerLongPress, !isAppMenuOpen else { break }
                    let travel = hypot(g.location.x - dragStartLocation.x, g.location.y - dragStartLocation.y)
                    // Responsive threshold for smooth dragging anywhere on screen
                    let moveThreshold: CGFloat = isDocked ? 26.0 : 18.0
                    if travel > moveThreshold {
                        longPressWorkItem?.cancel()
                        longPressWorkItem = nil
                        if !isMovingWindow {
                            isMovingWindow = true
                            hasMovedSignificantly = true
                            onMoveBegan()
                        }
                        if isMovingWindow {
                            onMoveChanged()
                        }
                    }

                case .none:
                    break
                }
            }
            .onEnded { _ in
                longPressWorkItem?.cancel()
                longPressWorkItem = nil

                switch dragMode {
                case .ring:
                    isDragging = false
                    lastRaw = nil

                case .move:
                    if isMovingWindow && !didTriggerLongPress && !isAppMenuOpen {
                        isMovingWindow = false
                        onMoveEnded()
                    } else if !hasMovedSignificantly && !didTriggerLongPress {
                        // Quick tap on center disc: cycle to next app (or close menu if open)
                        onTap()
                    }

                case .none:
                    break
                }
                dragMode = nil
                hasMovedSignificantly = false
                didTriggerLongPress = false
            }
    }

    private func value(at p: CGPoint) -> Double {
        let dx = Double(p.x - size / 2)
        let dy = Double(p.y - size / 2)

        if !isAttachedToEdge {
            var degrees = atan2(dy, dx) * 180 / .pi + 90
            degrees = degrees.truncatingRemainder(dividingBy: 360)
            if degrees < 0 { degrees += 360 }
            return degrees / 360
        }

        let r = Double(innerRadius + petalLength / 2)
        switch dockEdge {
        case .right, .left:
            // Dragging up increases volume (dy < 0), dragging down decreases (dy > 0)
            let fraction = 0.5 - (dy / (2.0 * r * 0.95))
            return min(max(fraction, 0.0), 1.0)
        case .bottom, .top:
            // Dragging right increases volume (dx > 0), dragging left decreases (dx < 0)
            let fraction = 0.5 + (dx / (2.0 * r * 0.95))
            return min(max(fraction, 0.0), 1.0)
        case .topRight:
            var deg = atan2(dy, dx) * 180 / .pi + 90
            deg = deg.truncatingRemainder(dividingBy: 360)
            if deg < 0 { deg += 360 }
            if deg >= 288.0 || deg < 45.0 {
                return 1.0
            } else if deg < 162.0 {
                return 0.0
            } else {
                return (deg - 162.0) / 126.0
            }
        case .topLeft:
            var deg = atan2(dy, dx) * 180 / .pi + 90
            deg = deg.truncatingRemainder(dividingBy: 360)
            if deg < 0 { deg += 360 }
            if deg >= 198.0 && deg < 315.0 {
                return 1.0
            } else if deg >= 315.0 || deg < 72.0 {
                return 0.0
            } else {
                return (deg - 72.0) / 126.0
            }
        case .bottomLeft:
            var deg = atan2(dy, dx) * 180 / .pi + 90
            deg = deg.truncatingRemainder(dividingBy: 360)
            if deg < 0 { deg += 360 }
            if deg >= 108.0 && deg < 225.0 {
                return 1.0
            } else if deg >= 225.0 && deg < 342.0 {
                return 0.0
            } else {
                let degOffset = deg >= 342.0 ? (deg - 342.0) : (deg + 18.0)
                return degOffset / 126.0
            }
        case .bottomRight:
            var deg = atan2(dy, dx) * 180 / .pi + 90
            deg = deg.truncatingRemainder(dividingBy: 360)
            if deg < 0 { deg += 360 }
            if deg >= 18.0 && deg < 135.0 {
                return 1.0
            } else if deg >= 135.0 && deg < 252.0 {
                return 0.0
            } else {
                let degOffset = deg >= 252.0 ? (deg - 252.0) : (deg + 108.0)
                return degOffset / 126.0
            }
        }
    }
}

// MARK: - Animated Bubble Interior (Subtle Muted Liquid Aurora)

/// A subtle, understated liquid aurora screensaver resting inside the glass bubble.
/// Gentle, muted pastel color drift under frosted glass — calm, elegant, and distraction-free.
struct BubbleInteriorView: View {
    let volume: Double
    let isMuted: Bool

    @State private var rotate1: Double = 0.0
    @State private var rotate2: Double = 0.0
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            // Deep glass tint
            Circle()
                .fill(
                    isMuted
                        ? Color.black.opacity(0.28)
                        : Color(red: 0.06, green: 0.07, blue: 0.12).opacity(0.35)
                )

            if !isMuted {
                // Subtle Aurora Layer 1: Soft Muted Ice Blue
                Circle()
                    .fill(
                        Color(red: 0.38, green: 0.68, blue: 0.88)
                            .opacity(0.30 + 0.15 * volume)
                    )
                    .frame(width: 20, height: 20)
                    .offset(x: pulse ? 4.5 : -4.5, y: pulse ? -4.0 : 4.0)
                    .rotationEffect(.degrees(rotate1))
                    .blur(radius: 8)

                // Subtle Aurora Layer 2: Soft Muted Lavender
                Circle()
                    .fill(
                        Color(red: 0.52, green: 0.48, blue: 0.76)
                            .opacity(0.25 + 0.14 * volume)
                    )
                    .frame(width: 18, height: 18)
                    .offset(x: pulse ? -4.5 : 5.0, y: pulse ? 4.5 : -4.0)
                    .rotationEffect(.degrees(rotate2))
                    .blur(radius: 8)

                // Subtle Aurora Layer 3: Soft Pearl Core Glow
                Circle()
                    .fill(
                        Color.white
                            .opacity(0.16 + 0.12 * volume)
                    )
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.15 : 0.85)
                    .blur(radius: 6)
            } else {
                // Muted state: serene, whisper-soft moonlight glow
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 14, height: 14)
                    .offset(x: pulse ? 2.5 : -2.5, y: pulse ? -2.5 : 2.5)
                    .blur(radius: 6)
            }

            // Frosted glass lens layer
            Circle()
                .fill(.ultraThinMaterial.opacity(0.18))

            // Soft specular lens highlight
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
        }
        .clipShape(Circle())
        .scaleEffect(pulse ? 1.04 : 0.96)
        .padding(8.5) // Clean margin separating the fluid core from the perimeter volume arc
        .onAppear {
            withAnimation(.linear(duration: 9.0).repeatForever(autoreverses: false)) {
                rotate1 = 360
            }
            withAnimation(.linear(duration: 13.0).repeatForever(autoreverses: false)) {
                rotate2 = -360
            }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Curved App Selector Menu (Outside the Dial)

/// Curved radial menu that blossoms outside the dial when long-pressing the center icon.
/// Arranges apps in a smooth, continuous string that tightly hugs the circular curvature of the disc,
/// with progressive depth-of-field blur and focal scaling.
struct CurvedAppMenuView: View {
    let apps: [AudioApp]
    let selectedID: pid_t?
    let dockEdge: DockEdge
    let isDocked: Bool
    let isRightSideOfScreen: Bool
    let focusedIndex: Double
    let onNudgeFocus: (Double) -> Void
    var onSnapFocus: (Double) -> Void = { _ in }
    let onSelectApp: (pid_t) -> Void

    @State private var didBloom = false
    @State private var dragAccumulator: CGFloat = 0

    private var isCorner: Bool {
        guard isDocked else { return false }
        switch dockEdge {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }

    private var centerAngle: Double {
        guard isDocked else {
            return isRightSideOfScreen ? 270.0 : 90.0
        }
        switch dockEdge {
        case .right: return 270.0
        case .left: return 90.0
        case .top: return 180.0
        case .bottom: return 0.0
        case .topRight: return 225.0
        case .topLeft: return 135.0
        case .bottomLeft: return 45.0
        case .bottomRight: return 315.0
        }
    }

    private var angleStep: Double { isCorner ? 22.0 : 27.0 }

    private func angle(for index: Int) -> Double {
        let relDist = Double(index) - focusedIndex
        return centerAngle + relDist * angleStep
    }

    private func offset(for angleDeg: Double, radius: CGFloat) -> CGSize {
        let rad = angleDeg * .pi / 180.0
        let x = CGFloat(sin(rad)) * radius
        let y = -CGFloat(cos(rad)) * radius
        return CGSize(width: x, height: y)
    }

    private func visualAttributes(for absDist: Double) -> (blur: CGFloat, scale: CGFloat, opacity: Double, isInteractive: Bool) {
        let maxDist = isCorner ? 2.5 : 3.4
        if absDist > maxDist {
            return (blur: 10.0, scale: 0.50, opacity: 0.0, isInteractive: false)
        }

        // Progressive Depth Blur (0 at center -> 1.0 at dist 1 -> 3.2 at dist 2 -> 6.5 at dist 3)
        let blur: CGFloat
        if absDist <= 0.4 {
            blur = 0.0
        } else if absDist <= 1.2 {
            blur = CGFloat((absDist - 0.4) / 0.8 * 1.2)
        } else if absDist <= 2.2 {
            blur = CGFloat(1.2 + (absDist - 1.2) / 1.0 * 2.2)
        } else {
            blur = CGFloat(3.4 + (absDist - 2.2) / 1.0 * 3.2)
        }

        // Progressive Focal Scale (1.12 at center -> 0.94 at dist 1 -> 0.80 at dist 2 -> 0.65 at dist 3)
        let scale: CGFloat
        if absDist <= 1.0 {
            scale = CGFloat(1.12 - absDist * 0.18)
        } else if absDist <= 2.0 {
            scale = CGFloat(0.94 - (absDist - 1.0) * 0.14)
        } else {
            scale = CGFloat(0.80 - (absDist - 2.0) * 0.15)
        }

        // Progressive Opacity (1.0 at center -> 0.95 at dist 1 -> 0.72 at dist 2 -> 0.30 at dist 3)
        let opacity: Double
        if absDist <= 0.8 {
            opacity = 1.0
        } else if absDist <= 1.8 {
            opacity = 1.0 - (absDist - 0.8) * 0.15
        } else if absDist <= 2.8 {
            opacity = 0.85 - (absDist - 1.8) / 1.0 * 0.45
        } else {
            opacity = 0.40 * (1.0 - (absDist - 2.8) / (maxDist - 2.8))
        }

        let isInteractive = absDist <= 2.4
        return (blur: blur, scale: scale, opacity: max(0, min(1, opacity)), isInteractive: isInteractive)
    }

    var body: some View {
        ZStack {
            // String of App Icon Buttons following the circular curvature of the disc
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                let relDist = Double(index) - focusedIndex
                let absDist = abs(relDist)
                let ang = angle(for: index)
                let isSelected = app.id == selectedID
                let isFocused = absDist < 0.45
                let attrs = visualAttributes(for: absDist)

                // Radius calculation: keeps the inner edge of EVERY node exactly 8pt
                // from the perimeter of the dial disc (dial radius = 78pt),
                // so the entire string of apps follows the exact circular curvature of the disc.
                let targetRadius: CGFloat = 86.0 + 19.0 * attrs.scale
                let r = didBloom ? targetRadius : 48.0
                let pos = offset(for: ang, radius: r)

                if attrs.opacity > 0.01 {
                    AppNodeButton(
                        app: app,
                        isSelected: isSelected,
                        isFocused: isFocused,
                        onSelect: {
                            onSelectApp(app.id)
                        }
                    )
                    .offset(pos)
                    .scaleEffect(didBloom ? attrs.scale : 0.20)
                    .opacity(didBloom ? attrs.opacity : 0.0)
                    .blur(radius: didBloom ? attrs.blur : 0.0)
                    .allowsHitTesting(attrs.isInteractive)
                    .animation(
                        .spring(response: 0.38, dampingFraction: 0.70)
                            .delay(min(absDist, 3.0) * 0.030),
                        value: didBloom
                    )
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.70)) {
                didBloom = true
            }
        }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { g in
                    let travel: CGFloat
                    if !isDocked {
                        travel = isRightSideOfScreen ? -g.translation.height : g.translation.height
                    } else {
                        switch dockEdge {
                        case .right:
                            travel = -g.translation.height
                        case .left:
                            travel = g.translation.height
                        case .top:
                            travel = g.translation.width
                        case .bottom:
                            travel = -g.translation.width
                        case .topRight, .bottomRight:
                            travel = -(g.translation.width + g.translation.height) * 0.707
                        case .topLeft, .bottomLeft:
                            travel = (g.translation.width - g.translation.height) * 0.707
                        }
                    }
                    let delta = Double((travel - dragAccumulator) / 20.0)
                    dragAccumulator = travel
                    onNudgeFocus(-delta)
                }
                .onEnded { g in
                    let travelCurrent: CGFloat
                    let travelPredicted: CGFloat
                    if !isDocked {
                        travelCurrent = isRightSideOfScreen ? -g.translation.height : g.translation.height
                        travelPredicted = isRightSideOfScreen ? -g.predictedEndTranslation.height : g.predictedEndTranslation.height
                    } else {
                        switch dockEdge {
                        case .right:
                            travelCurrent = -g.translation.height
                            travelPredicted = -g.predictedEndTranslation.height
                        case .left:
                            travelCurrent = g.translation.height
                            travelPredicted = g.predictedEndTranslation.height
                        case .top:
                            travelCurrent = g.translation.width
                            travelPredicted = g.predictedEndTranslation.width
                        case .bottom:
                            travelCurrent = -g.translation.width
                            travelPredicted = -g.predictedEndTranslation.width
                        case .topRight, .bottomRight:
                            travelCurrent = -(g.translation.width + g.translation.height) * 0.707
                            travelPredicted = -(g.predictedEndTranslation.width + g.predictedEndTranslation.height) * 0.707
                        case .topLeft, .bottomLeft:
                            travelCurrent = (g.translation.width - g.translation.height) * 0.707
                            travelPredicted = (g.predictedEndTranslation.width - g.predictedEndTranslation.height) * 0.707
                        }
                    }
                    let momentum = Double((travelPredicted - travelCurrent) / 20.0)
                    dragAccumulator = 0
                    onSnapFocus(-momentum)
                }
        )
    }
}

/// A liquid glass circular app icon button on the curved menu arc.
struct AppNodeButton: View {
    let app: AudioApp
    let isSelected: Bool
    let isFocused: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                // Drop shadow
                Circle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 38, height: 38)
                    .shadow(color: Color.black.opacity(0.38), radius: 6, y: 3)

                // Liquid glass disc body
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 38, height: 38)

                // Specular sheen
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity((isSelected || isFocused) ? 0.48 : 0.30),
                                Color.white.opacity(0.05),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)

                // Active highlight border
                Circle()
                    .strokeBorder(
                        (isSelected || isFocused)
                            ? LinearGradient(
                                colors: [
                                    Color.white,
                                    Color(red: 0.35, green: 0.75, blue: 1.00)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.70 : 0.32),
                                    Color.white.opacity(isHovered ? 0.28 : 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: (isSelected || isFocused) ? 2.0 : (isHovered ? 1.4 : 1.0)
                    )
                    .frame(width: 38, height: 38)
                    .shadow(
                        color: (isSelected || isFocused)
                            ? Color(red: 0.35, green: 0.75, blue: 1.00).opacity(0.55)
                            : (isHovered ? Color.white.opacity(0.35) : Color.clear),
                        radius: 5
                    )

                // App Icon
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 25, height: 25)
                        .opacity(app.isMuted ? 0.40 : 1.0)
                        .shadow(color: Color.black.opacity(0.20), radius: 2, y: 1)
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }

                // Small active selection indicator dot
                if isSelected {
                    Circle()
                        .fill(Color(red: 0.30, green: 0.85, blue: 1.00))
                        .frame(width: 6, height: 6)
                        .shadow(color: Color(red: 0.30, green: 0.85, blue: 1.00).opacity(0.8), radius: 3)
                        .offset(x: 13, y: -13)
                }
            }
            .scaleEffect(isHovered ? 1.10 : (isFocused ? 1.06 : (isSelected ? 1.04 : 1.0)))
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isHovered)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isSelected)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isFocused)
        }
        .buttonStyle(.plain)
        .frame(width: 38, height: 38)
        .contentShape(Circle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
