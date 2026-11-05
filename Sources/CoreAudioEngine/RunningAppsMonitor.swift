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

    public var icon: NSImage? {
        RunningAppsMonitor.shared.icon(for: pid)
    }

    public init(pid: pid_t, bundleIdentifier: String, name: String, volume: Float = 1.0, isMuted: Bool = false) {
        self.id = pid
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.volume = volume
        self.isMuted = isMuted
    }
}

public final class RunningAppsMonitor: ObservableObject {
    public static let shared = RunningAppsMonitor()

    @Published public private(set) var activeApps: [AudioAppInfo] = []
    private var cancellables = Set<AnyCancellable>()
    private var iconCache: [pid_t: NSImage] = [:]

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
        let workspaceApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }

        // Clean up cache for terminated apps
        let currentPids = Set(workspaceApps.map { $0.processIdentifier })
        iconCache = iconCache.filter { currentPids.contains($0.key) }

        var updated: [AudioAppInfo] = []
        for app in workspaceApps {
            let pid = app.processIdentifier
            let name = app.localizedName ?? "Unknown App"
            let bundleId = app.bundleIdentifier ?? "unknown.\(pid)"
            let currentVol = AudioVolumeController.shared.getVolume(forPID: pid)
            let isMuted = AudioVolumeController.shared.isMuted(forPID: pid)
            updated.append(AudioAppInfo(pid: pid, bundleIdentifier: bundleId, name: name, volume: currentVol, isMuted: isMuted))
        }
        self.activeApps = updated.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
