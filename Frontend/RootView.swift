import SwiftUI
import AppKit

/// Everything inside the floating panel: the dial, plus the mixer card when expanded.
struct RootView: View {
    @ObservedObject var controller: DockController
    @ObservedObject var model: MixerModel

    init(controller: DockController) {
        _controller = ObservedObject(wrappedValue: controller)
        _model = ObservedObject(wrappedValue: controller.model)
    }

    var body: some View {
        let cl = controller.menuClearance()
        ZStack {
            if controller.isAppMenuOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        controller.setAppMenu(false)
                    }
            }

            content
                .padding(EdgeInsets(
                    top: cl.top,
                    leading: cl.left,
                    bottom: cl.bottom,
                    trailing: cl.right
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelAlignment)
        }
    }

    // The dial stays pinned to its corner/edge; the mixer grows toward the inside of the screen.
    @ViewBuilder
    private var content: some View {
        if controller.isExpanded {
            expandedContent
        } else {
            dial
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if !controller.isDocked {
            // Free floating anywhere on screen:
            if controller.isRightSideOfScreen {
                HStack(alignment: .top, spacing: DockController.gap) {
                    mixer
                    dial
                }
            } else {
                HStack(alignment: .top, spacing: DockController.gap) {
                    dial
                    mixer
                }
            }
        } else {
            switch controller.edge {
            case .left, .topLeft:
                HStack(alignment: .top, spacing: DockController.gap) {
                    dial
                    mixer
                }
            case .right, .topRight:
                HStack(alignment: .top, spacing: DockController.gap) {
                    mixer
                    dial
                }
            case .top:
                VStack(alignment: .leading, spacing: DockController.gap) {
                    dial
                    mixer
                }
            case .bottom:
                VStack(alignment: .leading, spacing: DockController.gap) {
                    mixer
                    dial
                }
            case .bottomLeft:
                HStack(alignment: .bottom, spacing: DockController.gap) {
                    dial
                    mixer
                }
            case .bottomRight:
                HStack(alignment: .bottom, spacing: DockController.gap) {
                    mixer
                    dial
                }
            }
        }
    }

    private var panelAlignment: Alignment {
        guard controller.isExpanded else {
            return .center
        }
        if !controller.isDocked {
            return controller.isRightSideOfScreen ? .topTrailing : .topLeading
        }
        switch controller.edge {
        case .left, .top, .topLeft: return .topLeading
        case .right, .topRight: return .topTrailing
        case .bottom, .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    private var transitionAnchor: UnitPoint {
        if !controller.isDocked {
            return controller.isRightSideOfScreen ? .trailing : .leading
        }
        switch controller.edge {
        case .left, .topLeft, .bottomLeft: return .leading
        case .right, .topRight, .bottomRight: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    private var dial: some View {
        let app = model.selected
        return DialView(
            volume: app?.volume ?? 0,
            isMuted: app?.isMuted ?? false,
            icon: app?.icon,
            label: app?.name ?? "No app selected",
            selectedID: app?.id,
            isScrollingVolume: controller.isScrollingVolume,
            isAttachedToEdge: controller.isAttachedToEdge,
            isDocked: controller.isDocked,
            isBubble: controller.isBubble,
            isAppMenuOpen: controller.isAppMenuOpen,
            menuFocusedIndex: controller.menuFocusedIndex,
            onNudgeFocus: { delta in controller.nudgeAppMenuFocus(by: delta, isInteractive: true) },
            onSnapFocus: { momentum in controller.snapAppMenuFocus(momentum: momentum) },
            apps: model.apps,
            isRightSideOfScreen: controller.isRightSideOfScreen,
            along: controller.along,
            dockEdge: controller.edge,
            size: DockController.dialDiameter,
            autoTuck: controller.autoTuck,
            isTucked: controller.isTucked,
            currentEdge: controller.edge,
            onVolumeChange: { value in
                if let id = model.selected?.id { model.setVolume(value, for: id) }
            },
            onTap: {
                if controller.isAppMenuOpen {
                    controller.setAppMenu(false)
                } else {
                    controller.cancelVolumeScroll()
                    model.selectNext()
                }
            },
            onLongPress: {
                controller.toggleAppMenu()
            },
            onSelectApp: { id in
                model.select(id)
                controller.setAppMenu(false)
            },
            onToggleMute: {
                if let id = model.selected?.id { model.toggleMute(for: id) }
            },
            onMoveBegan: { controller.beginMove() },
            onMoveChanged: { controller.changeMove() },
            onMoveEnded: { controller.endMove() },
            onDockEdge: { newEdge in controller.dock(to: newEdge) },
            onUndock: { controller.undock() },
            onToggleAutoTuck: { controller.toggleAutoTuck() },
            onToggleAttachedToEdge: { controller.toggleAttachedToEdge() }
        )
        .padding(DockController.dialPadding)
        // Fade back when idle so it stays out of the way.
        .opacity(controller.isHovering || controller.isExpanded || controller.isBubble || controller.isAppMenuOpen ? 1 : 0.65)
        .animation(.easeInOut(duration: 0.35), value: controller.isHovering)
        .animation(.easeInOut(duration: 0.35), value: controller.isExpanded)
        .animation(.easeInOut(duration: 0.35), value: controller.isBubble)
        .animation(.easeInOut(duration: 0.35), value: controller.isAppMenuOpen)
    }

    private var mixer: some View {
        MixerCard(model: model, controller: controller)
            .frame(width: DockController.mixerWidth - 16,
                   height: controller.mixerHeight - 16)
            .padding(8)
            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: transitionAnchor)))
    }
}

/// Expanded list: one row per app with its own slider and mute button.
struct MixerCard: View {
    @ObservedObject var model: MixerModel
    let controller: DockController

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("App Volumes")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .help("Refresh app list")
            }
            .padding(.horizontal, 18)
            .frame(height: 52)

            Divider().opacity(0.35)

            if model.apps.isEmpty {
                Text("No apps found")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(model.apps) { app in
                            AppRow(
                                app: app,
                                isSelected: app.id == model.selected?.id,
                                onSelect: {
                                    controller.cancelVolumeScroll()
                                    model.select(app.id)
                                },
                                onVolume: { value in
                                    model.select(app.id)
                                    model.setVolume(value, for: app.id)
                                },
                                onMute: { model.toggleMute(for: app.id) }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .liquidGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

struct AppRow: View {
    let app: AudioApp
    let isSelected: Bool
    var onSelect: () -> Void
    var onVolume: (Double) -> Void
    var onMute: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 40, height: 40)
                .scaleEffect(isSelected ? 1.08 : 1.0)
                .shadow(color: isSelected ? Color.white.opacity(0.35) : Color.black.opacity(0.15), radius: isSelected ? 5 : 2, y: 1)
                .animation(.spring(response: 0.32, dampingFraction: 0.58), value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                    .lineLimit(1)
                Slider(value: Binding(get: { app.volume }, set: onVolume), in: 0...1)
                    .controlSize(.regular)
                    .tint(Color.primary)
                    .opacity(app.isMuted ? 0.4 : 1)
            }

            Button(action: onMute) {
                Image(systemName: app.isMuted || app.volume == 0
                      ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(app.isMuted ? Color.red.opacity(0.20) : Color.primary.opacity(0.08))
                    )
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(app.isMuted ? Color.red : Color.primary)
            .scaleEffect(app.isMuted ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: app.isMuted)
            .help(app.isMuted ? "Unmute" : "Mute")
        }
        .padding(.horizontal, 16)
        .frame(height: DockController.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isSelected ? 1.015 : 1.0)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .animation(.spring(response: 0.32, dampingFraction: 0.62), value: isSelected)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = app.icon {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.secondary)
        }
    }
}
