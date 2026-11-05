# MacVolumeDialSwift 🎛️✨

A modern, fluid, floating per-app volume mixer dial for macOS Sonoma and later, crafted with SwiftUI and Apple's CoreAudio Process Tap API (`AudioHardwareCreateProcessTap`).

Designed with a luminous Liquid Glass aesthetic, adaptive edge-docking physics, and multi-app audio controls.

---

## ✨ Features

- **Per-App Audio Control**: Individually monitor, adjust, and mute volumes of running macOS applications without altering system-wide output.
- **Luminous Liquid Glass Aesthetic**: Multi-layer chromatic refraction, vector shadows, specular caustic highlights, and frosted depth that blends into any desktop wallpaper.
- **Smart Edge Docking & Snapping**:
  - Drag and drop anywhere to float freely or snap magnetically to screen edges (left, right, top, bottom) and corners.
  - Multi-display aware: cleanly stays anchored to its active screen without cursor-dependent jumping.
- **Compact Resting Bubble & Auto-Tuck**:
  - Automatically collapses into a compact resting bubble or edge-tucked tab when idle to stay unobtrusive.
  - Expands with spring physics upon hover or mouse interaction.
- **Rotary Petal Visualization**: 20 spring-animated liquid petals fill clockwise to display the active app's volume level.
- **Curved Radial App Selector**: Long-press the center disc to bloom an interactive curved radial menu for fast app switching.
- **Full App Mixer Card**: Expand the dial into an expanded mixer card to view and adjust volume sliders for all audio-producing apps simultaneously.
- **Status Bar Integration**: Quick access to docking positions, per-app volume resets, and visibility toggling directly from the macOS menu bar extra.

---

## 🛠️ Requirements

- macOS 14.2 (Sonoma) or newer (required for CoreAudio `AudioHardwareCreateProcessTap`)
- Xcode 15.2+ with Command Line Tools
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

---

## 🚀 Quick Start

### Automated Build & Run
Run the included build script to generate the Xcode project, compile, apply the entitlements, and launch:

```bash
./build_and_run.sh
```

### Manual Build Steps
1. **Generate the Xcode Project**:
   ```bash
   xcodegen generate
   ```

2. **Build the Application**:
   ```bash
   xcodebuild -project VolumeDialApp.xcodeproj \
              -scheme VolumeDialApp \
              -configuration Debug \
              -derivedDataPath ./build \
              build
   ```

3. **Sign with CoreAudio Entitlements**:
   ```bash
   codesign --force --deep --sign - \
            --entitlements Config/VolumeDialApp.entitlements \
            ./build/Build/Products/Debug/VolumeDialApp.app
   ```

4. **Launch**:
   ```bash
   open ./build/Build/Products/Debug/VolumeDialApp.app
   ```

---

## 🎮 Controls & Gestures

| Action | Gesture |
| :--- | :--- |
| **Adjust Volume** | Drag along the petal ring or scroll with mouse wheel / trackpad |
| **Cycle Apps** | Tap the center disc |
| **Curved App Menu** | Press and hold the center disc (or scroll wheel to rotate focus) |
| **Move / Dock Dial** | Drag the center disc to move freely or snap to edges/corners |
| **Mute / Unmute** | Right-click the dial and select Mute, or use the context menu |
| **Expand Mixer** | Menu Bar Item → *Toggle App Volumes Mixer* (or shortcut `⌘M`) |
| **Dock Controls** | Right-click dial or use Menu Bar extra to select edge/corner docking |

---

## 🏗️ Architecture

```
MacVolumeDialSwift/
├── Config/
│   ├── Info.plist                     # Application configuration & permissions
│   └── VolumeDialApp.entitlements     # Audio input & non-sandboxed process tap entitlements
├── Sources/
│   ├── App/
│   │   └── AppDelegate.swift          # App lifecycle, menu bar extra, panel mounting
│   ├── CoreAudioEngine/
│   │   ├── AudioVolumeController.swift # CoreAudio Process Tap engine & volume leveling
│   │   └── RunningAppsMonitor.swift   # Running audio applications discovery & icon caching
│   └── Windowing/
│       └── FloatingDialPanel.swift    # Always-on-top, non-activating floating NSPanel
├── Frontend/
│   ├── DialView.swift                 # Rotary dial, petal animations, unified drag gestures
│   ├── RootView.swift                 # Dial & expanded mixer card layout coordinator
│   ├── DockController.swift           # Physics, edge snapping, screen geometry, bubble mode
│   ├── MixerModel.swift               # Observable model bridging CoreAudio to SwiftUI
│   ├── Glass.swift                    # Liquid glass shader and depth modifiers
│   └── CurvedAppMenuView.swift        # Radial curved application selector
├── project.yml                        # XcodeGen project specification
└── build_and_run.sh                   # One-click build, sign, and launch script
```

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
