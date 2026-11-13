
import Foundation
import CoreAudio
import AudioToolbox
import Cocoa
import Darwin.libproc

/// Manages per-process CoreAudio Process Taps (macOS 14.2+) and real-time DSP gain scaling.
/// Supports multi-process applications (e.g. Brave, Chrome, Safari, Electron) by dynamically
/// discovering and tapping all helper/renderer audio processes alongside the main process.
public final class AudioVolumeController {
    public static let shared = AudioVolumeController()

    private struct ProcessTapContext {
        let pid: pid_t
        let processObjectIDs: [AudioObjectID]
        let tapID: AudioObjectID
        let tapUID: String
        let aggregateDeviceID: AudioObjectID
        var ioProcID: AudioDeviceIOProcID?
        var targetGain: Float
        var currentGain: Float
        var isMuted: Bool
    }

    private var activeTaps: [pid_t: UnsafeMutablePointer<ProcessTapContext>] = [:]
    private let lock = NSLock()
    private var processListListenerBlock: AudioObjectPropertyListenerBlock?

    private init() {
        setupProcessListListener()
    }

    deinit {
        teardownAllTaps()
        removeProcessListListener()
    }

    // MARK: - Public API

    public func setVolume(_ volume: Float, forPID pid: pid_t) {
        let clamped = max(0.0, min(1.5, volume)) // Supports 0% to 150% boost
        lock.lock()
        defer { lock.unlock() }

        if let ctxPtr = activeTaps[pid] {
            let currentIDs = Set(findProcessObjectIDs(forPID: pid))
            let existingIDs = Set(ctxPtr.pointee.processObjectIDs)
            if currentIDs != existingIDs && !currentIDs.isEmpty {
                // Audio helper processes changed (e.g. Brave spawned a new helper)
                destroyTapLocked(forPID: pid)
                try? createTapLocked(forPID: pid, initialGain: clamped, muted: ctxPtr.pointee.isMuted)
            } else {
                ctxPtr.pointee.targetGain = clamped
                if abs(clamped - 1.0) < 0.001 && !ctxPtr.pointee.isMuted {
                    destroyTapLocked(forPID: pid)
                }
            }
        } else if abs(clamped - 1.0) >= 0.001 {
            try? createTapLocked(forPID: pid, initialGain: clamped, muted: false)
        }
    }

    public func setMuted(_ muted: Bool, forPID pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }

        if let ctxPtr = activeTaps[pid] {
            let currentIDs = Set(findProcessObjectIDs(forPID: pid))
            let existingIDs = Set(ctxPtr.pointee.processObjectIDs)
            if currentIDs != existingIDs && !currentIDs.isEmpty {
                destroyTapLocked(forPID: pid)
                try? createTapLocked(forPID: pid, initialGain: ctxPtr.pointee.targetGain, muted: muted)
            } else {
                ctxPtr.pointee.isMuted = muted
            }
        } else if muted {
            try? createTapLocked(forPID: pid, initialGain: 1.0, muted: true)
        }
    }

    public func getVolume(forPID pid: pid_t) -> Float {
        lock.lock()
        defer { lock.unlock() }
        return activeTaps[pid]?.pointee.targetGain ?? 1.0
    }

    public func isMuted(forPID pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeTaps[pid]?.pointee.isMuted ?? false
    }

    public func teardownAllTaps() {
        lock.lock()
        defer { lock.unlock() }
        let pids = Array(activeTaps.keys)
        for pid in pids {
            destroyTapLocked(forPID: pid)
        }
    }

    // MARK: - CoreAudio Process Tap Setup (macOS 14.2+)

    private func createTapLocked(forPID pid: pid_t, initialGain: Float, muted: Bool) throws {
        guard #available(macOS 14.2, *) else {
            print("[AudioVolumeController] macOS 14.2+ required for AudioHardwareCreateProcessTap.")
            return
        }

        let processObjectIDs = findProcessObjectIDs(forPID: pid)
        guard !processObjectIDs.isEmpty else {
            print("[AudioVolumeController] Could not find any CoreAudio Process Object IDs for PID \(pid)")
            return
        }

        guard let defaultOutputUID = getDefaultOutputDeviceUID() else {
            print("[AudioVolumeController] Could not resolve default output device UID.")
            return
        }

        // Tap all matching processes (main app + all helpers/renderers) simultaneously
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        tapDesc.name = "VolumeDialTap-\(pid)"
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .mutedWhenTapped

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard tapStatus == noErr, tapID != kAudioObjectUnknown else {
            print("[AudioVolumeController] AudioHardwareCreateProcessTap failed with OSStatus: \(tapStatus)")
            return
        }

        let tapUID = tapDesc.uuid.uuidString

        let aggUID = "com.mythreyen.VolumeDial.agg.\(pid).\(UUID().uuidString)"
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "VolumeDialAggregate-\(pid)",
            kAudioAggregateDeviceUIDKey as String: aggUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceMainSubDeviceKey as String: defaultOutputUID,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: defaultOutputUID]
            ],
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapUID,
                    kAudioSubTapDriftCompensationKey as String: true
                ]
            ]
        ]

        var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateDeviceID)
        guard aggStatus == noErr, aggregateDeviceID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            print("[AudioVolumeController] AudioHardwareCreateAggregateDevice failed: \(aggStatus)")
            return
        }

        let ctxPtr = UnsafeMutablePointer<ProcessTapContext>.allocate(capacity: 1)
        ctxPtr.initialize(to: ProcessTapContext(
            pid: pid,
            processObjectIDs: processObjectIDs,
            tapID: tapID,
            tapUID: tapUID,
            aggregateDeviceID: aggregateDeviceID,
            ioProcID: nil,
            targetGain: initialGain,
            currentGain: initialGain,
            isMuted: muted
        ))

        var ioProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcID(
            aggregateDeviceID,
            { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, inClientData) -> OSStatus in
                guard let inClientData = inClientData else { return noErr }
                let ctx = inClientData.assumingMemoryBound(to: ProcessTapContext.self)

                let target = ctx.pointee.isMuted ? 0.0 : ctx.pointee.targetGain
                var current = ctx.pointee.currentGain

                let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
                let outputBuffers = UnsafeMutableAudioBufferListPointer(outOutputData)

                let bufferCount = min(inputBuffers.count, outputBuffers.count)
                let smoothingStep: Float = 0.005

                for b in 0..<bufferCount {
                    guard let inPtr = inputBuffers[b].mData?.assumingMemoryBound(to: Float32.self),
                          let outPtr = outputBuffers[b].mData?.assumingMemoryBound(to: Float32.self) else {
                        continue
                    }
                    let sampleCount = Int(min(inputBuffers[b].mDataByteSize, outputBuffers[b].mDataByteSize)) / MemoryLayout<Float32>.size

                    for i in 0..<sampleCount {
                        if abs(current - target) > smoothingStep {
                            current += (target > current) ? smoothingStep : -smoothingStep
                        } else {
                            current = target
                        }
                        let scaled = inPtr[i] * current
                        // Continuous soft-knee saturator to prevent harsh square-wave digital clipping on volume boost
                        if scaled > 0.90 {
                            let excess = scaled - 0.90
                            outPtr[i] = 0.90 + 0.10 * (excess / (1.0 + excess))
                        } else if scaled < -0.90 {
                            let excess = -scaled - 0.90
                            outPtr[i] = -(0.90 + 0.10 * (excess / (1.0 + excess)))
                        } else {
                            outPtr[i] = scaled
                        }
                    }
                }

                ctx.pointee.currentGain = current
                return noErr
            },
            ctxPtr,
            &ioProcID
        )

        guard ioStatus == noErr, let validIOProc = ioProcID else {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            AudioHardwareDestroyProcessTap(tapID)
            ctxPtr.deinitialize(count: 1)
            ctxPtr.deallocate()
            return
        }

        ctxPtr.pointee.ioProcID = validIOProc
        AudioDeviceStart(aggregateDeviceID, validIOProc)
        activeTaps[pid] = ctxPtr
    }

    private func destroyTapLocked(forPID pid: pid_t) {
        guard let ctxPtr = activeTaps.removeValue(forKey: pid) else { return }
        let ctx = ctxPtr.pointee

        if let ioProcID = ctx.ioProcID {
            AudioDeviceStop(ctx.aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(ctx.aggregateDeviceID, ioProcID)
        }
        AudioHardwareDestroyAggregateDevice(ctx.aggregateDeviceID)
        if #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(ctx.tapID)
        }

        ctxPtr.deinitialize(count: 1)
        ctxPtr.deallocate()
    }

    // MARK: - Dynamic Multi-Process Discovery

    /// Known media, streaming, browser, or communications apps.
    public static let knownMediaBundleIDs: Set<String> = [
        "com.spotify.client",
        "com.apple.Music",
        "com.apple.Podcasts",
        "com.apple.QuickTimePlayerX",
        "com.apple.TV",
        "org.videolan.vlc",
        "com.colliderli.iina",
        "com.google.Chrome",
        "com.brave.Browser",
        "company.thebrowser.Browser", // Arc
        "com.apple.Safari",
        "com.operasoftware.Opera",
        "org.mozilla.firefox",
        "com.tinyspeck.slackmacgap",  // Slack
        "com.hnc.Discord",            // Discord
        "us.zoom.xos",               // Zoom
        "com.microsoft.teams",       // Teams
        "com.microsoft.teams2",
        "com.apple.FaceTime",
        "com.soundcloud.desktop"
    ]

    public static func isKnownMediaApp(bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        if knownMediaBundleIDs.contains(bundleID) { return true }
        let lower = bundleID.lowercased()
        return lower.contains("music") ||
               lower.contains("player") ||
               lower.contains("podcast") ||
               lower.contains("audio") ||
               lower.contains("spotify")
    }

    /// Queries all processes currently registered with the CoreAudio hardware server.
    public func getActiveAudioProcessInfo() -> (pids: Set<pid_t>, bundleIDs: Set<String>) {
        var activePIDs = Set<pid_t>()
        var activeBundles = Set<String>()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else {
            return (activePIDs, activeBundles)
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processIDs) == noErr else {
            return (activePIDs, activeBundles)
        }

        for procID in processIDs {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var procPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            if AudioObjectGetPropertyData(procID, &pidAddress, 0, nil, &pidSize, &procPID) == noErr && procPID > 0 {
                activePIDs.insert(procPID)
            }

            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundleID: CFString = "" as CFString
            var bundleSize = UInt32(MemoryLayout<CFString>.size)
            let status = withUnsafeMutablePointer(to: &bundleID) { ptr in
                AudioObjectGetPropertyData(procID, &bundleAddress, 0, nil, &bundleSize, ptr)
            }
            if status == noErr {
                let str = (bundleID as String).trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    activeBundles.insert(str)
                }
            }
        }

        return (activePIDs, activeBundles)
    }

    /// Determines whether a given application PID or bundle ID has an active CoreAudio connection.
    public func isAppActiveAudio(pid: pid_t, bundleID: String, activePIDs: Set<pid_t>, activeBundles: Set<String>) -> Bool {
        if activePIDs.contains(pid) { return true }
        if !bundleID.isEmpty {
            if activeBundles.contains(bundleID) { return true }
            if activeBundles.contains(where: { $0.hasPrefix(bundleID + ".") || $0.hasPrefix(bundleID + "-") }) { return true }
        }
        return false
    }

    /// Resolves all CoreAudio process object IDs for a given main application PID,
    /// including helper, renderer, and audio utility processes (e.g. Brave, Chrome, Safari).
    private func findProcessObjectIDs(forPID pid: pid_t) -> [AudioObjectID] {
        var result = Set<AudioObjectID>()

        // 1. Direct translation of the main process PID
        if let directID = translatePIDToProcessObjectID(pid) {
            result.insert(directID)
        }

        // 2. Resolve target application metadata
        let app = NSRunningApplication(processIdentifier: pid)
        let targetBundleID = app?.bundleIdentifier
        let targetBundleURL = app?.bundleURL?.standardized.path

        // 3. Query all active CoreAudio process objects
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else {
            return Array(result)
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processIDs) == noErr else {
            return Array(result)
        }

        for procID in processIDs {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var procPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(procID, &pidAddress, 0, nil, &pidSize, &procPID) == noErr else {
                continue
            }

            if procPID == pid {
                result.insert(procID)
                continue
            }

            // Check bundle ID match (e.g. "com.brave.Browser" matches "com.brave.Browser.helper")
            if let targetBundleID = targetBundleID {
                var bundleAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioProcessPropertyBundleID,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var bundleID: CFString = "" as CFString
                var bundleSize = UInt32(MemoryLayout<CFString>.size)
                let status = withUnsafeMutablePointer(to: &bundleID) { ptr in
                    AudioObjectGetPropertyData(procID, &bundleAddress, 0, nil, &bundleSize, ptr)
                }
                if status == noErr {
                    let str = bundleID as String
                    if str == targetBundleID || str.hasPrefix(targetBundleID + ".") || str.hasPrefix(targetBundleID + "-") {
                        result.insert(procID)
                        continue
                    }
                }
            }

            // Check executable path (e.g. helper binaries inside /Applications/Brave Browser.app)
            if let targetBundleURL = targetBundleURL {
                var pathBuffer = [CChar](repeating: 0, count: 4096)
                let length = proc_pidpath(procPID, &pathBuffer, UInt32(pathBuffer.count))
                if length > 0 {
                    let execPath = String(cString: pathBuffer)
                    if execPath.hasPrefix(targetBundleURL) {
                        result.insert(procID)
                        continue
                    }
                }
            }
        }

        return Array(result)
    }

    // MARK: - Dynamic CoreAudio Process List Listener

    private func setupProcessListListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleProcessListChanged()
        }
        self.processListListenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeProcessListListener() {
        guard let block = processListListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        processListListenerBlock = nil
    }

    private func handleProcessListChanged() {
        lock.lock()
        defer { lock.unlock() }

        for (pid, ctxPtr) in activeTaps {
            let currentIDs = Set(findProcessObjectIDs(forPID: pid))
            let existingIDs = Set(ctxPtr.pointee.processObjectIDs)
            if currentIDs != existingIDs && !currentIDs.isEmpty {
                let targetGain = ctxPtr.pointee.targetGain
                let isMuted = ctxPtr.pointee.isMuted
                destroyTapLocked(forPID: pid)
                try? createTapLocked(forPID: pid, initialGain: targetGain, muted: isMuted)
            }
        }
    }

    // MARK: - CoreAudio Hardware Helpers

    private func translatePIDToProcessObjectID(_ pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var mutablePID = pid

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &mutablePID,
            &size,
            &processObjectID
        )
        return (status == noErr && processObjectID != kAudioObjectUnknown) ? processObjectID : nil
    }

    private func getDefaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)

        let status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, ptr)
        }
        return status == noErr ? (uid as String) : nil
    }
}
