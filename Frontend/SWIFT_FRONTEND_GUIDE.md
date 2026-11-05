# Connecting Your Swift Frontend

1. Place your `.swift` frontend files in this `Frontend/` folder.
2. In your SwiftUI View, bind to the backend singletons:
   ```swift
   @ObservedObject var appsMonitor = RunningAppsMonitor.shared
   ```
   - `appsMonitor.activeApps`: Array of `AudioAppInfo` (`pid`, `name`, `bundleIdentifier`, `volume`, `isMuted`, `icon`).
   - `AudioVolumeController.shared.setVolume(Float(newVolume), forPID: app.pid)`: Scales app audio in real time (0.0 to 1.5).
   - `AudioVolumeController.shared.setMuted(isMuted, forPID: app.pid)`: Mutes/unmutes the app.
3. Open `Sources/App/AppDelegate.swift` and replace `PlaceholderMountView()` inside `setupFloatingPanel()` with your root SwiftUI view.
