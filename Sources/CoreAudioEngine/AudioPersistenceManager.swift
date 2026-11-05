import Foundation

/// Manages persistent storage for per-app volumes, mute states, hidden apps, and audio filtering preferences.
public final class AudioPersistenceManager {
    public static let shared = AudioPersistenceManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let volumes = "audio.persisted.volumes"
        static let muted = "audio.persisted.muted"
        static let hidden = "audio.persisted.hidden"
        static let filterAudioOnly = "audio.filterAudioOnly"
    }

    public private(set) var volumes: [String: Double]
    public private(set) var muted: [String: Bool]
    public private(set) var hidden: Set<String>

    public var filterAudioOnly: Bool {
        didSet {
            defaults.set(filterAudioOnly, forKey: Keys.filterAudioOnly)
        }
    }

    private init() {
        self.volumes = defaults.dictionary(forKey: Keys.volumes) as? [String: Double] ?? [:]
        self.muted = defaults.dictionary(forKey: Keys.muted) as? [String: Bool] ?? [:]
        let hiddenArr = defaults.stringArray(forKey: Keys.hidden) ?? []
        self.hidden = Set(hiddenArr)
        self.filterAudioOnly = defaults.bool(forKey: Keys.filterAudioOnly)
    }

    // MARK: - Volumes

    public func volume(for key: String) -> Double? {
        guard !key.isEmpty else { return nil }
        return volumes[key]
    }

    public func setVolume(_ volume: Double, for key: String) {
        guard !key.isEmpty else { return }
        volumes[key] = volume
        defaults.set(volumes, forKey: Keys.volumes)
    }

    // MARK: - Mute

    public func isMuted(for key: String) -> Bool? {
        guard !key.isEmpty else { return nil }
        return muted[key]
    }

    public func setMuted(_ isMuted: Bool, for key: String) {
        guard !key.isEmpty else { return }
        muted[key] = isMuted
        defaults.set(muted, forKey: Keys.muted)
    }

    // MARK: - Hidden Apps

    public func isHidden(key: String) -> Bool {
        guard !key.isEmpty else { return false }
        return hidden.contains(key)
    }

    public func setHidden(_ isHidden: Bool, for key: String) {
        guard !key.isEmpty else { return }
        if isHidden {
            hidden.insert(key)
        } else {
            hidden.remove(key)
        }
        defaults.set(Array(hidden), forKey: Keys.hidden)
    }

    public func unhide(key: String) {
        setHidden(false, for: key)
    }

    public func unhideAll() {
        hidden.removeAll()
        defaults.removeObject(forKey: Keys.hidden)
    }

    // MARK: - Reset All

    public func resetAll() {
        volumes.removeAll()
        muted.removeAll()
        defaults.removeObject(forKey: Keys.volumes)
        defaults.removeObject(forKey: Keys.muted)
    }
}
