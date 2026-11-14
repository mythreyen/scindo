import SwiftUI
import AppKit

/// Everything inside the floating panel: the dial, plus the mixer card when expanded.
struct RootView: View {
    @ObservedObject var controller: DockController
    @ObservedObject var model: MixerModel
    @ObservedObject var settings = AppSettings.shared

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
        let level = app != nil ? (model.audioLevels[app!.id] ?? 0.0) : 0.0
        return DialView(
            volume: app?.volume ?? 0,
            audioLevel: level,
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
            onToggleAttachedToEdge: { controller.toggleAttachedToEdge() },
            onHideCurrentApp: {
                if let id = model.selected?.id { model.hideApp(id: id) }
            },
            onResetCurrentAppVolume: {
                if let id = model.selected?.id { model.setVolume(1.0, for: id) }
            },
            onOpenSettings: {
                controller.openSettings()
            }
        )
        .padding(DockController.dialPadding)
        // Fade back when idle so it stays out of the way.
        .opacity(controller.isHovering || controller.isExpanded || controller.isBubble || controller.isAppMenuOpen ? 1 : settings.idleOpacity)
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
    @State private var showHiddenSection: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("App Volumes")
                    .font(.system(size: 16, weight: .bold))

                // Filter toggle: Active Audio vs All Apps
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                        model.showAudioOnly.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.showAudioOnly ? "waveform" : "square.grid.2x2")
                            .font(.system(size: 10, weight: .semibold))
                        Text(model.showAudioOnly ? "Audio Only" : "All Apps")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(model.showAudioOnly ? Color.cyan.opacity(0.20) : Color.primary.opacity(0.08))
                    )
                    .overlay(
                        Capsule().strokeBorder(model.showAudioOnly ? Color.cyan.opacity(0.40) : Color.white.opacity(0.15), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .help(model.showAudioOnly ? "Showing active audio apps only. Click to show all apps." : "Showing all apps. Click to filter active audio apps.")

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

                Button {
                    controller.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .help("Open Preferences (⌘,)")
            }
            .padding(.horizontal, 18)
            .frame(height: 52)

            Divider().opacity(0.35)

            if model.apps.isEmpty && model.hiddenApps.isEmpty {
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
                                audioLevel: model.audioLevels[app.id] ?? 0.0,
                                isSelected: app.id == model.selected?.id,
                                onSelect: {
                                    controller.cancelVolumeScroll()
                                    model.select(app.id)
                                },
                                onVolume: { value in
                                    model.select(app.id)
                                    model.setVolume(value, for: app.id)
                                },
                                onMute: { model.toggleMute(for: app.id) },
                                onHide: { model.hideApp(id: app.id) }
                            )
                        }

                        // Hidden Apps section if any are hidden
                        if !model.hiddenApps.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Divider().opacity(0.25).padding(.horizontal, 16)
                                DisclosureGroup(isExpanded: $showHiddenSection) {
                                    VStack(spacing: 4) {
                                        ForEach(model.hiddenApps) { hiddenApp in
                                            HStack(spacing: 10) {
                                                if let icon = hiddenApp.icon {
                                                    Image(nsImage: icon)
                                                        .resizable()
                                                        .frame(width: 20, height: 20)
                                                }
                                                Text(hiddenApp.name)
                                                    .font(.system(size: 12))
                                                    .lineLimit(1)
                                                Spacer()
                                                Button("Unhide") {
                                                    model.unhideApp(key: hiddenApp.persistenceKey)
                                                }
                                                .buttonStyle(.plain)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(Color.cyan)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 3)
                                        }

                                        Button("Unhide All") {
                                            model.unhideAll()
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.secondary)
                                        .padding(.top, 4)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "eye.slash")
                                            .font(.system(size: 11))
                                        Text("Hidden Apps (\(model.hiddenApps.count))")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundStyle(Color.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                }
                            }
                            .padding(.bottom, 8)
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

/// Real-time dancing 4-bar equalizer that pulses dynamically with live audio amplitude
struct LiveVUWaveformView: View {
    let level: Float
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(tint)
                    .frame(width: 2.2, height: barHeight(for: i))
            }
        }
        .frame(height: 12)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.18)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
        .animation(.spring(response: 0.12, dampingFraction: 0.55), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let factors: [CGFloat] = [0.70, 1.0, 0.85, 0.55]
        let base: CGFloat = 3.0
        let maxAdd: CGFloat = 8.5
        let val = CGFloat(max(0.0, min(1.0, level)))
        return base + maxAdd * val * factors[index]
    }
}

struct AppRow: View {
    @ObservedObject var settings = AppSettings.shared
    let app: AudioApp
    var audioLevel: Float = 0.0
    let isSelected: Bool
    var onSelect: () -> Void
    var onVolume: (Double) -> Void
    var onMute: () -> Void
    var onHide: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 40, height: 40)
                .scaleEffect(isSelected ? 1.08 : 1.0)
                .shadow(color: isSelected ? Color.white.opacity(0.35) : Color.black.opacity(0.15), radius: isSelected ? 5 : 2, y: 1)
                .animation(.spring(response: 0.32, dampingFraction: 0.58), value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                        .lineLimit(1)

                    if app.hasActiveAudio {
                        if audioLevel > 0.015 {
                            LiveVUWaveformView(level: audioLevel, tint: settings.accentTheme.primaryColor)
                        } else {
                            HStack(spacing: 2.5) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Active")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(Color.cyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.cyan.opacity(0.18)))
                        }
                    }
                }

                Slider(value: Binding(get: { app.volume }, set: onVolume), in: 0...1)
                    .controlSize(.regular)
                    .tint(settings.accentTheme.primaryColor)
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
        .contextMenu {
            Button(app.isMuted ? "Unmute" : "Mute", action: onMute)
            Button("Reset Volume to 100%") {
                onVolume(1.0)
            }
            Divider()
            Button("Hide \(app.name) from Dial", action: onHide)
        }
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
