import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var controller: DockController
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var model: MixerModel

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case audio = "Audio & Dial"
        case appearance = "Appearance"
        case apps = "Apps & Blacklist"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .audio: return "dial.medium.fill"
            case .appearance: return "paintpalette.fill"
            case .apps: return "app.badge.checkmark.fill"
            }
        }
    }

    enum PreviewMode: String, CaseIterable, Identifiable {
        case expanded = "Dial Ring"
        case bubble = "Resting Bubble"

        var id: String { rawValue }
    }

    @State private var selectedTab: SettingsTab = .general
    @State private var appSearchQuery: String = ""
    @State private var showingResetAlert = false

    // Appearance Live Preview State
    @State private var previewVolume: Double = 0.72
    @State private var previewIsMuted: Bool = false
    @State private var previewMode: PreviewMode = .expanded

    init(controller: DockController) {
        self.controller = controller
        self.model = controller.model
    }

    var body: some View {
        ZStack {
            // Background Liquid Glass Backdrop
            Color(white: 0.10).opacity(0.85)
                .ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Window Header & Tab Selector
                headerView
                    .padding(.top, 24)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                Divider().opacity(0.25)

                // Tab Content Area
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .general:
                            generalSettingsView
                        case .audio:
                            audioSettingsView
                        case .appearance:
                            appearanceSettingsView
                        case .apps:
                            appsSettingsView
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(width: 680, height: 600)
        .alert(isPresented: $showingResetAlert) {
            Alert(
                title: Text("Reset All App Volumes?"),
                message: Text("This will remove all saved per-app volume adjustments and reset every application to 100% volume."),
                primaryButton: .destructive(Text("Reset All")) {
                    model.resetAllVolumes()
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Header & Tab Bar

    private var headerView: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "dial.medium.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(settings.accentTheme.primaryColor)
                        .shadow(color: settings.accentTheme.glowColor, radius: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("VolumeDial Preferences")
                            .font(.system(size: 16, weight: .bold))
                        Text("Liquid Glass Per-App CoreAudio Mixer")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                }

                Spacer()

                // Theme quick indicator pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(settings.accentTheme.primaryColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: settings.accentTheme.glowColor, radius: 3)
                    Text(settings.accentTheme.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            // Glass Segment Tab Bar
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            ZStack {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.primary.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.15), radius: 4, y: 1)
                                }
                            }
                        )
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - General Tab

    private var generalSettingsView: some View {
        VStack(spacing: 18) {
            settingsCard(title: "System & Startup", icon: "power") {
                VStack(spacing: 12) {
                    toggleRow(
                        title: "Launch at Login",
                        description: "Start VolumeDial automatically whenever you log in to macOS.",
                        isOn: $settings.launchAtLogin
                    )

                    Divider().opacity(0.2)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Join All Spaces & Fullscreen")
                                .font(.system(size: 13, weight: .medium))
                            Text("Dial remains available seamlessly across all Mission Control virtual desktops.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        Text("Active")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                }
            }

            settingsCard(title: "Resting & Idle Behavior", icon: "moon.fill") {
                VStack(spacing: 14) {
                    toggleRow(
                        title: "Auto-Tuck at Screen Edge",
                        description: "Automatically collapse into an unobtrusive edge tab when idle to stay out of the way.",
                        isOn: Binding(
                            get: { controller.autoTuck },
                            set: { _ in controller.toggleAutoTuck() }
                        )
                    )

                    Divider().opacity(0.2)

                    toggleRow(
                        title: "Attach to Screen Edge (Semi-Circle Mode)",
                        description: "Anchors the dial flush against the monitor bezel for an integrated bezel-dial look.",
                        isOn: Binding(
                            get: { controller.isAttachedToEdge },
                            set: { _ in controller.toggleAttachedToEdge() }
                        )
                    )

                    Divider().opacity(0.2)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Idle Dial Opacity")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Transparency of the dial when mouse is not hovering over it.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Text("\(Int(settings.idleOpacity * 100))%")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(settings.accentTheme.primaryColor)
                        }

                        Slider(value: $settings.idleOpacity, in: 0.20...1.0, step: 0.05)
                            .tint(settings.accentTheme.primaryColor)
                    }
                }
            }
        }
    }

    // MARK: - Audio & Dial Tab

    private var audioSettingsView: some View {
        VStack(spacing: 18) {
            settingsCard(title: "Dial Gestures & Controls", icon: "hand.draw.fill") {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Trackpad / Scroll Wheel Sensitivity")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Controls how rapidly rotating the mouse wheel changes the volume.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1fx", settings.scrollSensitivity))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(settings.accentTheme.primaryColor)
                        }

                        Slider(value: $settings.scrollSensitivity, in: 0.5...2.5, step: 0.1)
                            .tint(settings.accentTheme.primaryColor)
                    }

                    Divider().opacity(0.2)

                    toggleRow(
                        title: "Haptic Tick Feedback",
                        description: "Triggers subtle physical alignment ticks on Apple Force Touch trackpads as you rotate.",
                        isOn: $settings.hapticFeedback
                    )
                }
            }

            settingsCard(title: "Smart App Filtering", icon: "waveform.badge.magnifyingglass") {
                VStack(spacing: 12) {
                    toggleRow(
                        title: "Show Active Audio Apps Only",
                        description: "Hides non-audio background apps (Finder, Terminal, Notes) so the dial only rotates between media apps.",
                        isOn: $model.showAudioOnly
                    )
                }
            }

            settingsCard(title: "CoreAudio Process Tap Engine", icon: "cpu.fill") {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Engine Status")
                                .font(.system(size: 13, weight: .medium))
                            Text("Apple CoreAudio Process Tap (AudioHardwareCreateProcessTap)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text("Operational")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                    }

                    Divider().opacity(0.2)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset All App Volumes")
                                .font(.system(size: 13, weight: .medium))
                            Text("Clears all stored per-app levels and tears down active aggregate taps.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        Button("Reset to 100%") {
                            showingResetAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.red.opacity(0.85))
                    }
                }
            }
        }
    }

    // MARK: - Appearance Tab

    private var appearanceSettingsView: some View {
        VStack(spacing: 20) {
            // Interactive Real-Time Dial Preview Canvas
            settingsCard(title: "Interactive Dial Canvas", icon: "sparkles") {
                VStack(spacing: 16) {
                    // Preview Mode Switcher
                    HStack {
                        Text("Live Visualizer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary)

                        Spacer()

                        Picker("", selection: $previewMode) {
                            ForEach(PreviewMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    // Dial Canvas Display
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .overlay(
                                RadialGradient(
                                    colors: [
                                        settings.accentTheme.glowColor.opacity(previewIsMuted ? 0.05 : Double(settings.glowIntensity) * 0.35),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 140
                                )
                            )

                        if previewMode == .expanded {
                            liveExpandedPreview
                                .transition(.scale(scale: 0.88).combined(with: .opacity))
                        } else {
                            liveBubblePreview
                                .transition(.scale(scale: 0.88).combined(with: .opacity))
                        }
                    }
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Live Interactive Scrub Controls
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: previewIsMuted ? "speaker.slash.fill" : (previewVolume < 0.33 ? "speaker.wave.1.fill" : (previewVolume < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(previewIsMuted ? Color.red : settings.accentTheme.primaryColor)
                                .frame(width: 20)

                            Slider(value: $previewVolume, in: 0.0...1.0)
                                .tint(settings.accentTheme.primaryColor)

                            Text("\(Int(round(previewVolume * 100)))%")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(previewIsMuted ? Color.secondary : settings.accentTheme.primaryColor)
                                .frame(width: 44, alignment: .trailing)
                        }

                        HStack(spacing: 8) {
                            // Mute toggle pill button
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                    previewIsMuted.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: previewIsMuted ? "speaker.fill" : "speaker.slash.fill")
                                    Text(previewIsMuted ? "Unmute" : "Mute")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(previewIsMuted ? Color.red.opacity(0.20) : Color.primary.opacity(0.08))
                                )
                                .overlay(
                                    Capsule().strokeBorder(previewIsMuted ? Color.red.opacity(0.50) : Color.white.opacity(0.12), lineWidth: 0.8)
                                )
                                .foregroundStyle(previewIsMuted ? Color.red : Color.primary)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            // Preset volume jump buttons
                            ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { pct in
                                Button {
                                    withAnimation(settings.petalBounceEnabled ? .spring(response: 0.32, dampingFraction: 0.58) : .easeOut(duration: 0.15)) {
                                        previewVolume = pct
                                        previewIsMuted = false
                                    }
                                } label: {
                                    Text("\(Int(pct * 100))%")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.primary.opacity(0.06))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Accent Themes Grid
            settingsCard(title: "Accent Themes", icon: "paintpalette.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select a luminous spectral hue for volume petals, active audio waves, and ambient caustics.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(AccentTheme.allCases) { theme in
                            let isSelected = settings.accentTheme == theme
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                    settings.accentTheme = theme
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(theme.petalGradient)
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Circle().strokeBorder(Color.white.opacity(0.60), lineWidth: 1)
                                            )
                                            .shadow(color: theme.glowColor, radius: 6)

                                        Image(systemName: theme.symbolName)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Color.black.opacity(0.40))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(theme.rawValue)
                                            .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                                            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                                        Text(theme.subtitle)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(theme.primaryColor)
                                            .shadow(color: theme.glowColor, radius: 4)
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelected ? theme.glowColor.opacity(0.20) : Color.primary.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(isSelected ? theme.primaryColor.opacity(0.65) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Dial Sizing & Geometry
            settingsCard(title: "Display Scale & Sizing", icon: "arrow.up.left.and.arrow.down.right") {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dial Display Scale")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Scales the floating dial on your display to match screen resolution.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Text("\(Int(round(settings.dialScale * 100)))%")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(settings.accentTheme.primaryColor)
                        }

                        Slider(value: $settings.dialScale, in: 0.85...1.15, step: 0.05)
                            .tint(settings.accentTheme.primaryColor)

                        // Preset buttons
                        HStack(spacing: 8) {
                            scalePresetButton(title: "Compact (85%)", scale: 0.85)
                            scalePresetButton(title: "Default (100%)", scale: 1.00)
                            scalePresetButton(title: "Large (115%)", scale: 1.15)
                        }
                    }
                }
            }

            // Luminescence & Optics
            settingsCard(title: "Luminescence & Optics", icon: "sun.max.fill") {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Caustic Glow & Bloom Intensity")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Strength of the radial light dispersion and ambient shadows cast by active volume petals.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Text("\(Int(round(settings.glowIntensity * 100)))%")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(settings.accentTheme.primaryColor)
                        }

                        Slider(value: $settings.glowIntensity, in: 0.20...1.0, step: 0.05)
                            .tint(settings.accentTheme.primaryColor)
                    }

                    Divider().opacity(0.2)

                    toggleRow(
                        title: "Specular Lens Flare & Reflections",
                        description: "Simulates curved optical refraction and specular highlights across the glass surfaces.",
                        isOn: $settings.glassSpecularSheen
                    )

                    Divider().opacity(0.2)

                    toggleRow(
                        title: "Elastic Petal Bounce",
                        description: "Volume petals spring outward with fluid momentum when volume increases.",
                        isOn: $settings.petalBounceEnabled
                    )

                    Divider().opacity(0.2)

                    toggleRow(
                        title: "Volume Percentage Overlay",
                        description: "Show bold numerical volume readout in the center disc while rotating.",
                        isOn: $settings.showVolumePercentage
                    )
                }
            }
        }
    }

    private func scalePresetButton(title: String, scale: Double) -> some View {
        let isSelected = abs(settings.dialScale - scale) < 0.02
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                settings.dialScale = scale
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? settings.accentTheme.primaryColor.opacity(0.20) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? settings.accentTheme.primaryColor.opacity(0.60) : Color.white.opacity(0.10), lineWidth: 0.8)
                )
                .foregroundStyle(isSelected ? settings.accentTheme.primaryColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var liveExpandedPreview: some View {
        let size: CGFloat = 130
        let petalWidth: CGFloat = size * 0.058
        let petalLength: CGFloat = size * 0.165
        let innerRadius: CGFloat = size * 0.27
        let petalCount = 16

        return ZStack {
            // Glass base
            Circle()
                .fill(Color(white: 0.14, opacity: 0.80))
                .frame(width: size, height: size)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )

            // 16 Sample Petals
            ForEach(0..<petalCount, id: \.self) { i in
                let angle = Double(i) * (360.0 / Double(petalCount))
                let amount = min(max(previewVolume * Double(petalCount) - Double(i), 0), 1)

                ZStack {
                    // Track
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: petalWidth, height: petalLength)

                    // Active Petal
                    Capsule()
                        .fill(
                            previewIsMuted
                                ? LinearGradient(colors: [Color.secondary.opacity(0.4), Color.secondary.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                                : settings.accentTheme.petalGradient
                        )
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.60 * amount), lineWidth: 0.75)
                        )
                        .shadow(
                            color: previewIsMuted ? Color.clear : settings.accentTheme.glowColor.opacity(Double(settings.glowIntensity) * amount),
                            radius: 5
                        )
                        .frame(width: petalWidth, height: petalLength)
                        .scaleEffect(
                            x: 1.0 + 0.35 * amount,
                            y: 1.0 + 0.20 * amount
                        )
                        .opacity(amount)
                }
                .offset(y: -(innerRadius + petalLength / 2))
                .rotationEffect(.degrees(angle))
            }

            // Center Glass Disc
            ZStack {
                Circle()
                    .fill(Color(white: 0.12, opacity: 0.85))
                    .frame(width: size * 0.52, height: size * 0.52)
                    .shadow(color: Color.black.opacity(0.35), radius: 6, y: 2)

                if settings.glassSpecularSheen {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.40), Color.white.opacity(0.06), Color.black.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size * 0.52, height: size * 0.52)
                }

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.85), location: 0.0),
                                .init(color: Color.white.opacity(0.30), location: 0.5),
                                .init(color: Color.white.opacity(0.45), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                    .frame(width: size * 0.52, height: size * 0.52)

                if settings.showVolumePercentage && !previewIsMuted {
                    Text("\(Int((previewVolume * 100).rounded()))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                } else {
                    Image(systemName: previewIsMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(previewIsMuted ? Color.secondary : settings.accentTheme.primaryColor)
                }
            }
        }
        .scaleEffect(CGFloat(settings.dialScale))
        .animation(.spring(response: 0.30, dampingFraction: 0.70), value: settings.dialScale)
    }

    private var liveBubblePreview: some View {
        let size: CGFloat = 68
        let effVol = previewIsMuted ? 0.0 : previewVolume

        return ZStack {
            // Shadow
            Circle()
                .fill(Color.black.opacity(0.30))
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.40), radius: 10, y: 4)

            // Glass Disc
            Circle()
                .fill(Color(white: 0.14, opacity: 0.85))
                .frame(width: size, height: size)

            if settings.glassSpecularSheen {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.45), Color.white.opacity(0.08), Color.black.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
            }

            Circle()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.90), location: 0.0),
                            .init(color: Color.white.opacity(0.35), location: 0.45),
                            .init(color: Color.white.opacity(0.55), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.3
                )
                .frame(width: size, height: size)

            // Volume Arc
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 2.2)
                    .padding(3.5)

                Circle()
                    .trim(from: 0, to: CGFloat(effVol))
                    .stroke(
                        LinearGradient(
                            colors: previewIsMuted ? [
                                Color.secondary.opacity(0.40),
                                Color.secondary.opacity(0.15)
                            ] : [
                                Color.white.opacity(0.95),
                                settings.accentTheme.primaryColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(3.5)
                    .shadow(
                        color: previewIsMuted ? Color.clear : settings.accentTheme.glowColor,
                        radius: 3
                    )
            }
            .frame(width: size, height: size)

            // Animated wave or speaker icon
            Image(systemName: previewIsMuted ? "speaker.slash.fill" : "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(previewIsMuted ? Color.secondary : settings.accentTheme.primaryColor)
        }
    }

    // MARK: - Apps & Blacklist Tab

    private var appsSettingsView: some View {
        VStack(spacing: 16) {
            // Search & Action Header
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                    TextField("Search running apps...", text: $appSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !appSearchQuery.isEmpty {
                        Button {
                            appSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )

                if !model.hiddenApps.isEmpty {
                    Button("Unhide All (\(model.hiddenApps.count))") {
                        model.unhideAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Running Apps List
            let filteredApps = model.rawApps.filter { app in
                appSearchQuery.isEmpty ||
                app.name.localizedCaseInsensitiveContains(appSearchQuery) ||
                app.bundleIdentifier.localizedCaseInsensitiveContains(appSearchQuery)
            }

            VStack(spacing: 4) {
                if filteredApps.isEmpty {
                    Text("No matching applications found.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .padding(.vertical, 30)
                } else {
                    ForEach(filteredApps) { app in
                        HStack(spacing: 12) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "app.fill")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(Color.secondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    if app.hasActiveAudio {
                                        HStack(spacing: 2) {
                                            Image(systemName: "waveform")
                                                .font(.system(size: 8, weight: .bold))
                                            Text("Active")
                                                .font(.system(size: 9, weight: .semibold))
                                        }
                                        .foregroundStyle(Color.cyan)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.cyan.opacity(0.18)))
                                    }
                                }

                                Text(app.bundleIdentifier)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Volume level readout
                            Text("\(Int(app.volume * 100))%")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(app.isMuted ? Color.red : Color.secondary)
                                .frame(width: 44, alignment: .trailing)

                            // Hide / Unhide Button
                            Button {
                                if app.isHidden {
                                    model.unhideApp(key: app.persistenceKey)
                                } else {
                                    model.hideApp(id: app.id)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: app.isHidden ? "eye" : "eye.slash")
                                    Text(app.isHidden ? "Unhide" : "Hide")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(app.isHidden ? Color.cyan.opacity(0.20) : Color.primary.opacity(0.08))
                                )
                                .overlay(
                                    Capsule().strokeBorder(app.isHidden ? Color.cyan.opacity(0.40) : Color.white.opacity(0.12), lineWidth: 0.8)
                                )
                                .foregroundStyle(app.isHidden ? Color.cyan : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(app.isHidden ? Color.black.opacity(0.25) : Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                                )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Reusable Settings Card & Components

    private func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(settings.accentTheme.primaryColor)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }

            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
        )
    }

    private func toggleRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
