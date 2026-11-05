import Cocoa
import SwiftUI

/// Always-on-top, non-activating, borderless transparent floating panel for the rotary dial.
public final class FloatingDialPanel: NSPanel {
    public init(contentRect: NSRect = NSRect(x: 160, y: 160, width: 220, height: 220)) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.hidesOnDeactivate = false

        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
    }

    override public var canBecomeKey: Bool {
        return false
    }

    override public var canBecomeMain: Bool {
        return false
    }

    override public func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    /// Mounts any SwiftUI View as the root of the floating dial window
    public func setSwiftUIFrontend<V: View>(_ view: V) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = []
        hostingView.frame = self.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }
}
