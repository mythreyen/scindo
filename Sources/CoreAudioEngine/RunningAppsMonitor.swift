import Cocoa
import Combine
import CoreAudio

public struct AudioAppInfo: Identifiable, Hashable, Codable {
    public let id: pid_t
    public let pid: pid_t
    public let bundleIdentifier: String
    public let name: String
    public var volume: Float
    public var isMuted: Bool
    public var hasActiveAudio: Bool
    public var isHidden: Bool

    public var icon: NSImage? {
        RunningAppsMonitor.shared.icon(for: pid)
    }

    public var persistenceKey: String {
        bundleIdentifier.isEmpty ? name : bundleIdentifier
    }

    public init(
        pid: pid_t,
        bundleIdentifier: String,
        name: String,
        volume: Float = 1.0,
        isMuted: Bool = false,
        hasActiveAudio: Bool = false,
        isHidden: Bool = false
    ) {
        self.id = pid
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.volume = volume
        self.isMuted = isMuted
        self.hasActiveAudio = hasActiveAudio
        self.isHidden = isHidden
    }
}

public final class RunningAppsMonitor: ObservableObject {
    public static let shared = RunningAppsMonitor()

    @Published public private(set) var activeApps: [AudioAppInfo] = []
    private var cancellables = Set<AnyCancellable>()
    private var iconCache: [pid_t: NSImage] = [:]
    private let refreshQueue = DispatchQueue(label: "com.volumedial.runningapps.refresh", qos: .userInitiated)

    private init() {
        refreshApps()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshApps()
            }
            .store(in: &cancellables)
    }

    /// Returns a crisp, high-resolution Retina icon (up to 512x512) for the application.
    public func icon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] {
            return cached
        }
        guard let runningApp = NSRunningApplication(processIdentifier: pid) else { return nil }

        let rawSource: NSImage?
        if let bundleURL = runningApp.bundleURL {
            rawSource = NSWorkspace.shared.icon(forFile: bundleURL.path)
        } else {
            rawSource = runningApp.icon
        }

        guard let source = rawSource else { return nil }

        // Extract high-resolution 512x512 pixel representation for ultra-sharp Retina rendering
        var proposed = NSRect(x: 0, y: 0, width: 512, height: 512)
        if let cg = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
            let crisp = NSImage(cgImage: cg, size: NSSize(width: 256, height: 256))
            iconCache[pid] = crisp
            return crisp
        }

        if let copy = source.copy() as? NSImage {
            copy.size = NSSize(width: 256, height: 256)
            iconCache[pid] = copy
            return copy
        }

        iconCache[pid] = source
        return source
    }

    public func refreshApps() {
        refreshQueue.async { [weak self] in
            self?.performRefresh()
        }
    }

    private func performRefresh() {
        let workspaceApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }

        // Clean up cache for terminated apps on main thread
        let currentPids = Set(workspaceApps.map { $0.processIdentifier })
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.iconCache = self.iconCache.filter { currentPids.contains($0.key) }
        }

        // Query active CoreAudio process objects and helpers
        let activeAudio = AudioVolumeController.shared.getActiveAudioProcessInfo()
        let persistence = AudioPersistenceManager.shared

        var updated: [AudioAppInfo] = []
        for app in workspaceApps {
            let pid = app.processIdentifier
            let name = app.localizedName ?? (app.executableURL?.lastPathComponent ?? "Unknown App")
            let bundleId = app.bundleIdentifier ?? ""
            let persistKey = !bundleId.isEmpty ? bundleId : name

            let hasActiveAudio = AudioVolumeController.shared.isAppActiveAudio(
                pid: pid,
                bundleID: bundleId,
                activePIDs: activeAudio.pids,
                activeBundles: activeAudio.bundleIDs
            )

            let isHidden = persistence.isHidden(key: persistKey)

            // Resolve volume & mute: in-memory active tap -> persisted value -> default 1.0
            var currentVol = AudioVolumeController.shared.getVolume(forPID: pid)
            var isMuted = AudioVolumeController.shared.isMuted(forPID: pid)

            if let savedVol = persistence.volume(for: persistKey) {
                let savedFloat = Float(savedVol)
                if abs(currentVol - 1.0) < 0.001 && abs(savedFloat - 1.0) >= 0.001 {
                    currentVol = savedFloat
                    AudioVolumeController.shared.setVolume(currentVol, forPID: pid)
                }
            }

            if let savedMuted = persistence.isMuted(for: persistKey) {
                if !isMuted && savedMuted {
                    isMuted = true
                    AudioVolumeController.shared.setMuted(true, forPID: pid)
                }
            }

            updated.append(AudioAppInfo(
                pid: pid,
                bundleIdentifier: bundleId,
                name: name,
                volume: currentVol,
                isMuted: isMuted,
                hasActiveAudio: hasActiveAudio,
                isHidden: isHidden
            ))
        }

        // Prioritized smart sort:
        // 1. Apps with active audio streams right now
        // 2. Apps with custom volume / muted
        // 3. Known media / streaming apps
        // 4. Alphabetical by name
        let sorted = updated.sorted { a, b in
            if a.hasActiveAudio != b.hasActiveAudio {
                return a.hasActiveAudio && !b.hasActiveAudio
            }
            let aCustom = abs(a.volume - 1.0) > 0.001 || a.isMuted
            let bCustom = abs(b.volume - 1.0) > 0.001 || b.isMuted
            if aCustom != bCustom {
                return aCustom && !bCustom
            }
            let aMedia = AudioVolumeController.isKnownMediaApp(bundleID: a.bundleIdentifier)
            let bMedia = AudioVolumeController.isKnownMediaApp(bundleID: b.bundleIdentifier)
            if aMedia != bMedia {
                return aMedia && !bMedia
            }
            return a.name.lowercased() < b.name.lowercased()
        }

        DispatchQueue.main.async { [weak self] in
            self?.activeApps = sorted
        }
    }
}
