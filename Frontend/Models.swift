import AppKit
import SwiftUI
import Combine

/// Which screen edge or corner the dial is docked to.
public enum DockEdge: String, CaseIterable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    public var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }

    public var displayName: String {
        switch self {
        case .left: return "Left Screen Edge"
        case .right: return "Right Screen Edge"
        case .top: return "Top Screen Edge"
        case .bottom: return "Bottom Screen Edge"
        case .topLeft: return "Top-Left Corner"
        case .topRight: return "Top-Right Corner"
        case .bottomLeft: return "Bottom-Left Corner"
        case .bottomRight: return "Bottom-Right Corner"
        }
    }
}

/// One app whose volume can be controlled.
public struct AudioApp: Identifiable, Equatable {
    public let pid: pid_t
    public var id: pid_t { pid }
    public var bundleIdentifier: String
    public var name: String
    public var icon: NSImage?
    public var volume: Double      // 0...1
    public var isMuted: Bool
    public var hasActiveAudio: Bool
    public var isHidden: Bool

    public var persistenceKey: String {
        bundleIdentifier.isEmpty ? name : bundleIdentifier
    }

    public init(
        pid: pid_t,
        bundleIdentifier: String = "",
        name: String,
        icon: NSImage? = nil,
        volume: Double = 1.0,
        isMuted: Bool = false,
        hasActiveAudio: Bool = false,
        isHidden: Bool = false
    ) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.icon = icon
        self.volume = volume
        self.isMuted = isMuted
        self.hasActiveAudio = hasActiveAudio
        self.isHidden = isHidden
    }

    public init(info: AudioAppInfo) {
        self.pid = info.pid
        self.bundleIdentifier = info.bundleIdentifier
        self.name = info.name
        self.icon = info.icon
        self.volume = Double(info.volume)
        self.isMuted = info.isMuted
        self.hasActiveAudio = info.hasActiveAudio
        self.isHidden = info.isHidden
    }

    public static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.pid == rhs.pid &&
        lhs.name == rhs.name &&
        lhs.volume == rhs.volume &&
        lhs.isMuted == rhs.isMuted &&
        lhs.hasActiveAudio == rhs.hasActiveAudio &&
        lhs.isHidden == rhs.isHidden
    }
}

/// The seam where the real audio logic plugs in.
public protocol AudioBackend: AnyObject {
    func fetchApps() -> [AudioApp]
    func setVolume(_ volume: Double, for pid: pid_t)
    func setMuted(_ muted: Bool, for pid: pid_t)
}

/// Real CoreAudio backend using RunningAppsMonitor and AudioVolumeController.
public final class CoreAudioBackend: AudioBackend {
    public init() {}

    public func fetchApps() -> [AudioApp] {
        RunningAppsMonitor.shared.refreshApps()
        return RunningAppsMonitor.shared.activeApps.map { AudioApp(info: $0) }
    }

    public func setVolume(_ volume: Double, for pid: pid_t) {
        AudioVolumeController.shared.setVolume(Float(volume), forPID: pid)
    }

    public func setMuted(_ muted: Bool, for pid: pid_t) {
        AudioVolumeController.shared.setMuted(muted, forPID: pid)
    }
}

/// Mock backend for previews or testing.
public final class MockAudioBackend: AudioBackend {
    private var volumes: [pid_t: Double] = [:]
    private var muted: Set<pid_t> = []

    public init() {}

    public func fetchApps() -> [AudioApp] {
        return [
            AudioApp(pid: 101, bundleIdentifier: "com.apple.Music", name: "Music", icon: nil, volume: volumes[101] ?? 0.7, isMuted: muted.contains(101), hasActiveAudio: true),
            AudioApp(pid: 102, bundleIdentifier: "com.apple.Safari", name: "Safari", icon: nil, volume: volumes[102] ?? 0.7, isMuted: muted.contains(102), hasActiveAudio: false),
            AudioApp(pid: 103, bundleIdentifier: "com.spotify.client", name: "Spotify", icon: nil, volume: volumes[103] ?? 0.7, isMuted: muted.contains(103), hasActiveAudio: true)
        ]
    }

    public func setVolume(_ volume: Double, for pid: pid_t) {
        volumes[pid] = volume
    }

    public func setMuted(_ isMuted: Bool, for pid: pid_t) {
        if isMuted { muted.insert(pid) } else { muted.remove(pid) }
    }
}

/// UI-facing state: the list of apps and which one the dial currently controls.
public final class MixerModel: ObservableObject {
    @Published public private(set) var rawApps: [AudioApp] = []
    @Published public private(set) var apps: [AudioApp] = []
    @Published public private(set) var hiddenApps: [AudioApp] = []
    @Published public var selectedID: pid_t?

    @Published public var showAudioOnly: Bool {
        didSet {
            AudioPersistenceManager.shared.filterAudioOnly = showAudioOnly
            updateFilteredApps()
        }
    }

    private let backend: AudioBackend
    private var cancellables = Set<AnyCancellable>()

    public init(backend: AudioBackend = CoreAudioBackend()) {
        self.backend = backend
        self.showAudioOnly = AudioPersistenceManager.shared.filterAudioOnly

        // Live subscription to RunningAppsMonitor for active app list and icons
        RunningAppsMonitor.shared.$activeApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeList in
                guard let self = self else { return }
                self.syncWithActiveApps(activeList)
            }
            .store(in: &cancellables)

        refresh()
    }

    public var selected: AudioApp? {
        apps.first { $0.id == selectedID } ?? apps.first
    }

    public func refresh() {
        RunningAppsMonitor.shared.refreshApps()
        syncWithActiveApps(RunningAppsMonitor.shared.activeApps)
    }

    private func syncWithActiveApps(_ activeList: [AudioAppInfo]) {
        self.rawApps = activeList.map { AudioApp(info: $0) }
        updateFilteredApps()
    }

    public func updateFilteredApps() {
        let nonHidden = rawApps.filter { !$0.isHidden }
        if showAudioOnly {
            let filtered = nonHidden.filter { app in
                app.hasActiveAudio ||
                abs(app.volume - 1.0) > 0.001 ||
                app.isMuted ||
                AudioVolumeController.isKnownMediaApp(bundleID: app.bundleIdentifier)
            }
            self.apps = filtered.isEmpty ? nonHidden : filtered
        } else {
            self.apps = nonHidden
        }
        self.hiddenApps = rawApps.filter { $0.isHidden }

        if selectedID == nil || !apps.contains(where: { $0.id == selectedID }) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
                selectedID = apps.first?.id
            }
        }
    }

    public func select(_ id: pid_t) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
            selectedID = id
        }
    }

    /// Cycles the dial to the next app, wrapping around at the end.
    public func selectNext() {
        guard !apps.isEmpty else { return }
        let current = apps.firstIndex { $0.id == selected?.id } ?? -1
        withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
            selectedID = apps[(current + 1) % apps.count].id
        }
    }

    public func setVolume(_ value: Double, for id: pid_t) {
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(value, 0.0), 1.0)
        apps[index].volume = clamped
        backend.setVolume(clamped, for: id)
        AudioPersistenceManager.shared.setVolume(clamped, for: apps[index].persistenceKey)

        if apps[index].isMuted && clamped > 0 {
            apps[index].isMuted = false
            backend.setMuted(false, for: id)
            AudioPersistenceManager.shared.setMuted(false, for: apps[index].persistenceKey)
        }
    }

    public func toggleMute(for id: pid_t) {
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[index].isMuted.toggle()
        backend.setMuted(apps[index].isMuted, for: id)
        AudioPersistenceManager.shared.setMuted(apps[index].isMuted, for: apps[index].persistenceKey)
    }

    @discardableResult
    public func nudgeSelected(by delta: Double) -> (didChange: Bool, actualDelta: Double, reachedBoundary: Bool) {
        guard let app = selected else { return (false, 0.0, false) }
        let currentVol = app.volume
        let clamped = min(max(currentVol + delta, 0.0), 1.0)
        let actualDelta = clamped - currentVol
        if abs(actualDelta) > 0.0001 {
            let reached = (clamped == 1.0 && currentVol < 1.0) || (clamped == 0.0 && currentVol > 0.0)
            setVolume(clamped, for: app.id)
            return (true, actualDelta, reached)
        }
        return (false, 0.0, false)
    }

    public func hideApp(id: pid_t) {
        guard let app = rawApps.first(where: { $0.id == id }) else { return }
        AudioPersistenceManager.shared.setHidden(true, for: app.persistenceKey)
        refresh()
    }

    public func unhideApp(key: String) {
        AudioPersistenceManager.shared.unhide(key: key)
        refresh()
    }

    public func unhideAll() {
        AudioPersistenceManager.shared.unhideAll()
        refresh()
    }

    public func resetAllVolumes() {
        AudioPersistenceManager.shared.resetAll()
        AudioVolumeController.shared.teardownAllTaps()
        refresh()
    }
}
