import SwiftUI
import AppKit

@MainActor
public final class SnapshotGenerator {
    public static func run() {
        print("==> Running Scindo Actual Build Snapshot Generator...")

        // Set accent theme to Electric Cyan for vivid visual pop
        AppSettings.shared.accentTheme = .cyan

        // 1. Resolve real system icons from running/installed applications
        let musicIcon = resolveIcon(bundlePath: "/System/Applications/Music.app")
        let braveIcon = resolveIcon(bundlePath: "/Applications/Brave Browser.app", fallback: "/System/Applications/Safari.app")
        let notionIcon = resolveIcon(bundlePath: "/Applications/Notion.app", fallback: "/System/Applications/Notes.app")
        let termIcon = resolveIcon(bundlePath: "/System/Applications/Utilities/Terminal.app")
        let stickiesIcon = resolveIcon(bundlePath: "/System/Applications/Stickies.app")

        let apps: [AudioApp] = [
            AudioApp(pid: 99135, bundleIdentifier: "com.apple.Music", name: "Music", icon: musicIcon, volume: 0.82, isMuted: false, hasActiveAudio: true),
            AudioApp(pid: 503, bundleIdentifier: "com.brave.Browser", name: "Brave Browser", icon: braveIcon, volume: 0.65, isMuted: false, hasActiveAudio: true),
            AudioApp(pid: 28208, bundleIdentifier: "notion.id", name: "Notion", icon: notionIcon, volume: 0.40, isMuted: false, hasActiveAudio: false),
            AudioApp(pid: 496, bundleIdentifier: "com.apple.Terminal", name: "Terminal", icon: termIcon, volume: 1.0, isMuted: false, hasActiveAudio: false),
            AudioApp(pid: 513, bundleIdentifier: "com.apple.Stickies", name: "Stickies", icon: stickiesIcon, volume: 0.50, isMuted: true, hasActiveAudio: false)
        ]

        let audioLevels: [pid_t: Float] = [
            99135: 0.74,
            503: 0.42,
            28208: 0.0,
            496: 0.0,
            513: 0.0
        ]

        let assetsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets")
        try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let model = MixerModel()
        model.setAppsForTesting(apps, levels: audioLevels)
        let controller = DockController(model: model)

        // ----------------------------------------------------
        // Snapshot 1: Macro Dial Detail (scindo-dial-detail.png)
        // ----------------------------------------------------
        let dialCard = ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.14, green: 0.16, blue: 0.22), Color(red: 0.05, green: 0.06, blue: 0.09)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 260
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            HStack(spacing: 36) {
                // Dial with active app icon and acoustic aura
                VStack(spacing: 12) {
                    DialView(
                        volume: 0.82,
                        audioLevel: 0.74,
                        isMuted: false,
                        icon: musicIcon,
                        label: "Music",
                        selectedID: 99135,
                        isScrollingVolume: false,
                        isAttachedToEdge: false,
                        isDocked: false,
                        isBubble: false,
                        isAppMenuOpen: false,
                        menuFocusedIndex: 0.0,
                        apps: apps,
                        size: 190,
                        onVolumeChange: { _ in },
                        onTap: {},
                        onLongPress: {},
                        onToggleMute: {},
                        onMoveBegan: {},
                        onMoveChanged: {},
                        onMoveEnded: {}
                    )

                    Text("Active App & Acoustic Aura")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.70))
                }

                // Dial with volume percentage readout
                VStack(spacing: 12) {
                    DialView(
                        volume: 0.82,
                        audioLevel: 0.74,
                        isMuted: false,
                        icon: musicIcon,
                        label: "Music",
                        selectedID: 99135,
                        isScrollingVolume: true,
                        isAttachedToEdge: false,
                        isDocked: false,
                        isBubble: false,
                        isAppMenuOpen: false,
                        menuFocusedIndex: 0.0,
                        apps: apps,
                        size: 190,
                        onVolumeChange: { _ in },
                        onTap: {},
                        onLongPress: {},
                        onToggleMute: {},
                        onMoveBegan: {},
                        onMoveChanged: {},
                        onMoveEnded: {}
                    )

                    Text("Liquid Volume Arc (82%)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
            }
            .padding(32)
        }
        .frame(width: 680, height: 420)

        captureViewViaWindow(view: dialCard, size: CGSize(width: 680, height: 420), to: assetsDir.appendingPathComponent("scindo-dial-detail.png"))
        print("  -> Captured assets/scindo-dial-detail.png")

        // ----------------------------------------------------
        // Snapshot 2: Curved Radial App Selector (scindo-radial-menu.png)
        // ----------------------------------------------------
        let radialMenuCard = ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.14, green: 0.16, blue: 0.22), Color(red: 0.05, green: 0.06, blue: 0.09)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 260
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            DialView(
                volume: 0.82,
                audioLevel: 0.74,
                isMuted: false,
                icon: musicIcon,
                label: "Music",
                selectedID: 99135,
                isScrollingVolume: false,
                isAttachedToEdge: false,
                isDocked: false,
                isBubble: false,
                isAppMenuOpen: true,
                menuFocusedIndex: 0.0,
                apps: apps,
                size: 156,
                onVolumeChange: { _ in },
                onTap: {},
                onLongPress: {},
                onToggleMute: {},
                onMoveBegan: {},
                onMoveChanged: {},
                onMoveEnded: {}
            )
            .padding(40)
        }
        .frame(width: 500, height: 500)

        captureViewViaWindow(view: radialMenuCard, size: CGSize(width: 500, height: 500), to: assetsDir.appendingPathComponent("scindo-radial-menu.png"))
        print("  -> Captured assets/scindo-radial-menu.png")

        // ----------------------------------------------------
        // Snapshot 3: Features Bento Grid Showcase (scindo-features-bento.png)
        // ----------------------------------------------------
        let bentoShowcase = ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.10)

            HStack(spacing: 28) {
                // Left Column: Full Mixer Console with real apps
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.vertical.3")
                            .foregroundStyle(Color.cyan)
                        Text("MULTI-TRACK APP MIXER")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.cyan)
                    }
                    .padding(.leading, 8)

                    MixerCard(model: model, controller: controller)
                        .frame(width: 360, height: 460)
                }

                // Right Column: Radial Menu Card + Key Features
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "circle.grid.cross.fill")
                                .foregroundStyle(Color.cyan)
                            Text("RADIAL APP SELECTOR")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.cyan)
                        }
                        .padding(.leading, 6)

                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                                )

                            DialView(
                                volume: 0.82,
                                audioLevel: 0.74,
                                isMuted: false,
                                icon: musicIcon,
                                label: "Music",
                                selectedID: 99135,
                                isScrollingVolume: false,
                                isAttachedToEdge: false,
                                isDocked: false,
                                isBubble: false,
                                isAppMenuOpen: true,
                                menuFocusedIndex: 0.0,
                                apps: apps,
                                size: 120,
                                onVolumeChange: { _ in },
                                onTap: {},
                                onLongPress: {},
                                onToggleMute: {},
                                onMoveBegan: {},
                                onMoveChanged: {},
                                onMoveEnded: {}
                            )
                        }
                        .frame(width: 320, height: 260)
                    }

                    // Key features pill cards
                    HStack(spacing: 12) {
                        featureCard(icon: "waveform.badge.magnifyingglass", title: "Live VU Equalizer", subtitle: "Instant RMS audio feedback")
                        featureCard(icon: "command", title: "Carbon Hotkeys", subtitle: "Zero permission shortcuts")
                    }
                    .frame(width: 320)
                }
            }
            .padding(32)
        }
        .frame(width: 780, height: 560)

        captureViewViaWindow(view: bentoShowcase, size: CGSize(width: 780, height: 560), to: assetsDir.appendingPathComponent("scindo-features-bento.png"))
        print("  -> Captured assets/scindo-features-bento.png")

        // ----------------------------------------------------
        // Snapshot 4: Hero Showcase Banner (scindo-hero.png)
        // ----------------------------------------------------
        let heroBanner = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.13),
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.02, green: 0.03, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Ambient background glow accents
            Circle()
                .fill(Color.cyan.opacity(0.12))
                .blur(radius: 90)
                .frame(width: 380, height: 380)
                .offset(x: -220, y: -40)

            Circle()
                .fill(Color.purple.opacity(0.10))
                .blur(radius: 110)
                .frame(width: 420, height: 420)
                .offset(x: 240, y: 60)

            VStack(spacing: 24) {
                // Top header title
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "dial.medium.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.cyan)
                        Text("Scindo")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                    Text("Luminous Liquid Glass Per-App CoreAudio Mixer for macOS")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
                .padding(.top, 14)

                // Interactive UI components in real layout
                HStack(alignment: .center, spacing: 36) {
                    // Floating Dial
                    VStack(spacing: 12) {
                        DialView(
                            volume: 0.82,
                            audioLevel: 0.74,
                            isMuted: false,
                            icon: musicIcon,
                            label: "Music",
                            selectedID: 99135,
                            isScrollingVolume: false,
                            isAttachedToEdge: false,
                            isDocked: false,
                            isBubble: false,
                            isAppMenuOpen: false,
                            menuFocusedIndex: 0.0,
                            apps: apps,
                            size: 190,
                            onVolumeChange: { _ in },
                            onTap: {},
                            onLongPress: {},
                            onToggleMute: {},
                            onMoveBegan: {},
                            onMoveChanged: {},
                            onMoveEnded: {}
                        )

                        Text("Liquid Glass Dial (Music 82%)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.60))
                    }

                    // Expanded Mixer Card
                    VStack(spacing: 12) {
                        MixerCard(model: model, controller: controller)
                            .frame(width: 360, height: 390)

                        Text("Multi-App Volume Console & Live VU Meters")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.60))
                    }
                }
            }
            .padding(32)
        }
        .frame(width: 960, height: 600)

        captureViewViaWindow(view: heroBanner, size: CGSize(width: 960, height: 600), to: assetsDir.appendingPathComponent("scindo-hero.png"))
        print("  -> Captured assets/scindo-hero.png")

        print("==> All actual build snapshots generated successfully!")
    }

    private static func resolveIcon(bundlePath: String, fallback: String? = nil) -> NSImage {
        let path = FileManager.default.fileExists(atPath: bundlePath) ? bundlePath : (fallback ?? "")
        if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            let img = NSWorkspace.shared.icon(forFile: path)
            img.size = NSSize(width: 256, height: 256)
            return img
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private static func featureCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.cyan)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.cyan.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// Renders the SwiftUI view via NSWindow with Window Server compositing
    private static func captureViewViaWindow<V: View>(view: V, size: CGSize, to fileURL: URL) {
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFront(nil)
        window.displayIfNeeded()

        // Allow WindowServer a cycle to composite
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))

        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-l", "\(window.windowNumber)", "-o", fileURL.path]
        try? task.run()
        task.waitUntilExit()

        window.orderOut(nil)
    }
}
