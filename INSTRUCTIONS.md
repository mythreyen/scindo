# Complete Setup, Build & Run Instructions

## Prerequisites
- macOS 14.2 (Sonoma) or newer (required for Apple's `AudioHardwareCreateProcessTap` API).
- Xcode 15.2+ installed with Command Line Tools (`xcode-select --install`).
- Homebrew installed (`brew install xcodegen`).

---

## Step 1: Extract the Archive & Add Your Swift Frontend
1. Unzip `MacVolumeDialSwift.zip` and open a terminal in the extracted folder:
   ```bash
   unzip MacVolumeDialSwift.zip
   cd MacVolumeDialSwift
   ```
2. Copy your existing `.swift` frontend view files into the `./Frontend/` folder.

---

## Step 2: Wire Your Swift Frontend to the Audio Engine

### Option A: Automated via `agy` CLI (Fastest)
Run `agy` inside `MacVolumeDialSwift` and paste this single prompt:
```text
Look at my Swift frontend files in @Frontend.
1. Connect my UI state to `RunningAppsMonitor.shared` (@Sources/CoreAudioEngine/RunningAppsMonitor.swift) for the active app list/icons and `AudioVolumeController.shared` (@Sources/CoreAudioEngine/AudioVolumeController.swift) for `setVolume(_:forPID:)` and `setMuted(_:forPID:)`.
2. Mount my root SwiftUI view inside `setupFloatingPanel()` in @Sources/App/AppDelegate.swift replacing `PlaceholderMountView()`.
3. Run `./build_and_run.sh` and fix any compiler warnings or errors.
```

### Option B: Manual Wiring (3 Lines of Code)
1. Inside your SwiftUI view file in `./Frontend/`, access the running apps and control audio:
   ```swift
   @ObservedObject var appsMonitor = RunningAppsMonitor.shared

   // Inside your dial rotation gesture:
   AudioVolumeController.shared.setVolume(Float(dialValue), forPID: selectedApp.pid)

   // Inside your mute action:
   AudioVolumeController.shared.setMuted(isMuted, forPID: selectedApp.pid)
   ```
2. Open `Sources/App/AppDelegate.swift` and change line 31 inside `setupFloatingPanel()`:
   ```swift
   dialPanel.setSwiftUIFrontend(YourCustomDialView())
   ```

---

## Step 3: Build, Sign & Run the App
We included an automated build script (`build_and_run.sh`) that runs XcodeGen, compiles the `.app` bundle, signs it with the non-sandboxed CoreAudio entitlements, and launches it:

```bash
chmod +x build_and_run.sh
./build_and_run.sh
```

Alternatively, if you prefer building inside the Xcode GUI:
```bash
xcodegen generate
open VolumeDialApp.xcodeproj
```
Then press **Cmd + R** in Xcode.

---

## Step 4: Grant macOS System Audio Capture Permission
1. The first time you rotate the dial to change an app's volume, macOS will display a prompt:
   **"VolumeDialApp would like to record system audio."**
2. Click **Allow**.
3. If you ever need to reset permissions during development, run:
   ```bash
   tccutil reset AudioCapture com.mythreyen.VolumeDialApp
   ```
