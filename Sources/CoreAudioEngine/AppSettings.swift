import SwiftUI
import Combine
import ServiceManagement
import AppKit

// MARK: - Accent Themes

public enum AccentTheme: String, CaseIterable, Identifiable, Codable {
    case frost = "Luminous Frost"
    case cyan = "Electric Cyan"
    case amber = "Amber Caustic"
    case purple = "Aurora Violet"
    case emerald = "Emerald Mint"
    case sunset = "Sunset Coral"
    case solar = "Solar Gold"
    case slate = "Graphite Slate"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .frost: return "sparkles"
        case .cyan: return "bolt.fill"
        case .amber: return "flame.fill"
        case .purple: return "waveform.badge.magnifyingglass"
        case .emerald: return "leaf.fill"
        case .sunset: return "heart.fill"
        case .solar: return "sun.max.fill"
        case .slate: return "circle.fill"
        }
    }

    public var subtitle: String {
        switch self {
        case .frost: return "Diamond White & Specular Sheen"
        case .cyan: return "Aqua Marine & Vivid Neon"
        case .amber: return "Warm Sunset & Analog Glow"
        case .purple: return "Cosmic Orchid & Synthwave"
        case .emerald: return "Cyber Mint & Radiant Green"
        case .sunset: return "Vibrant Rose & Warm Coral"
        case .solar: return "Electric Sunburst & Gold"
        case .slate: return "Minimalist Stealth Titanium"
        }
    }

    public var primaryColor: Color {
        switch self {
        case .frost: return Color.white
        case .cyan: return Color(red: 0.15, green: 0.85, blue: 1.0)
        case .amber: return Color(red: 1.0, green: 0.65, blue: 0.15)
        case .purple: return Color(red: 0.80, green: 0.45, blue: 1.0)
        case .emerald: return Color(red: 0.25, green: 0.90, blue: 0.60)
        case .sunset: return Color(red: 1.0, green: 0.35, blue: 0.55)
        case .solar: return Color(red: 1.0, green: 0.82, blue: 0.10)
        case .slate: return Color(white: 0.85)
        }
    }

    public var glowColor: Color {
        switch self {
        case .frost: return Color.white.opacity(0.38)
        case .cyan: return Color(red: 0.10, green: 0.80, blue: 1.0, opacity: 0.45)
        case .amber: return Color(red: 1.0, green: 0.55, blue: 0.05, opacity: 0.48)
        case .purple: return Color(red: 0.75, green: 0.35, blue: 1.0, opacity: 0.45)
        case .emerald: return Color(red: 0.15, green: 0.90, blue: 0.50, opacity: 0.45)
        case .sunset: return Color(red: 1.0, green: 0.25, blue: 0.45, opacity: 0.48)
        case .solar: return Color(red: 1.0, green: 0.75, blue: 0.0, opacity: 0.48)
        case .slate: return Color.white.opacity(0.20)
        }
    }

    public var petalGradient: LinearGradient {
        switch self {
        case .frost:
            return LinearGradient(
                colors: [Color.white.opacity(0.98), Color.white.opacity(0.70)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .cyan:
            return LinearGradient(
                colors: [Color(red: 0.5, green: 0.95, blue: 1.0), Color(red: 0.05, green: 0.65, blue: 0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .amber:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.80, blue: 0.35), Color(red: 0.95, green: 0.45, blue: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .purple:
            return LinearGradient(
                colors: [Color(red: 0.90, green: 0.55, blue: 1.0), Color(red: 0.60, green: 0.20, blue: 0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .emerald:
            return LinearGradient(
                colors: [Color(red: 0.45, green: 0.98, blue: 0.75), Color(red: 0.10, green: 0.75, blue: 0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .sunset:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.50, blue: 0.70), Color(red: 0.95, green: 0.20, blue: 0.40)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .solar:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.92, blue: 0.40), Color(red: 1.0, green: 0.65, blue: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .slate:
            return LinearGradient(
                colors: [Color(white: 0.92), Color(white: 0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - AppSettings Store

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let idleOpacity = "settings.idleOpacity"
        static let scrollSensitivity = "settings.scrollSensitivity"
        static let accentTheme = "settings.accentTheme"
        static let hapticFeedback = "settings.hapticFeedback"
        static let launchAtLogin = "settings.launchAtLogin"
        static let glowIntensity = "settings.glowIntensity"
        static let dialScale = "settings.dialScale"
        static let showVolumePercentage = "settings.showVolumePercentage"
        static let petalBounceEnabled = "settings.petalBounceEnabled"
        static let glassSpecularSheen = "settings.glassSpecularSheen"
    }

    @Published public var idleOpacity: Double {
        didSet {
            defaults.set(idleOpacity, forKey: Keys.idleOpacity)
        }
    }

    @Published public var scrollSensitivity: Double {
        didSet {
            defaults.set(scrollSensitivity, forKey: Keys.scrollSensitivity)
        }
    }

    @Published public var accentTheme: AccentTheme {
        didSet {
            defaults.set(accentTheme.rawValue, forKey: Keys.accentTheme)
        }
    }

    @Published public var hapticFeedback: Bool {
        didSet {
            defaults.set(hapticFeedback, forKey: Keys.hapticFeedback)
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            setLaunchAtLogin(launchAtLogin)
        }
    }

    @Published public var glowIntensity: Double {
        didSet {
            defaults.set(glowIntensity, forKey: Keys.glowIntensity)
        }
    }

    @Published public var dialScale: Double {
        didSet {
            defaults.set(dialScale, forKey: Keys.dialScale)
        }
    }

    @Published public var showVolumePercentage: Bool {
        didSet {
            defaults.set(showVolumePercentage, forKey: Keys.showVolumePercentage)
        }
    }

    @Published public var petalBounceEnabled: Bool {
        didSet {
            defaults.set(petalBounceEnabled, forKey: Keys.petalBounceEnabled)
        }
    }

    @Published public var glassSpecularSheen: Bool {
        didSet {
            defaults.set(glassSpecularSheen, forKey: Keys.glassSpecularSheen)
        }
    }

    private init() {
        let savedOpacity = defaults.object(forKey: Keys.idleOpacity) as? Double ?? 0.65
        self.idleOpacity = max(0.20, min(1.0, savedOpacity))

        let savedSens = defaults.object(forKey: Keys.scrollSensitivity) as? Double ?? 1.0
        self.scrollSensitivity = max(0.25, min(3.0, savedSens))

        let savedThemeRaw = defaults.string(forKey: Keys.accentTheme) ?? AccentTheme.frost.rawValue
        self.accentTheme = AccentTheme(rawValue: savedThemeRaw) ?? .frost

        self.hapticFeedback = defaults.object(forKey: Keys.hapticFeedback) as? Bool ?? true

        let savedGlow = defaults.object(forKey: Keys.glowIntensity) as? Double ?? 0.70
        self.glowIntensity = max(0.20, min(1.0, savedGlow))

        let savedScale = defaults.object(forKey: Keys.dialScale) as? Double ?? 1.0
        self.dialScale = max(0.85, min(1.15, savedScale))

        self.showVolumePercentage = defaults.object(forKey: Keys.showVolumePercentage) as? Bool ?? true
        self.petalBounceEnabled = defaults.object(forKey: Keys.petalBounceEnabled) as? Bool ?? true
        self.glassSpecularSheen = defaults.object(forKey: Keys.glassSpecularSheen) as? Bool ?? true

        // Read system status for launch at login
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("[AppSettings] Failed to update LaunchAtLogin: \(error)")
            }
        }
    }
}
