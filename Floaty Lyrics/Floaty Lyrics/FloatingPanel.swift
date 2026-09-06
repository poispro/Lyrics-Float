import AppKit
import SwiftUI

final class FloatingPanel<Content: View>: NSPanel {
    init(view: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 150),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating // stays above other app windows, including full-screen music players
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // AppKit normally cross-fades a window via a cached snapshot when it's
        // reordered or when the active Space changes. For a borderless,
        // transparent, always-on-every-Space panel like this one, that
        // snapshot occasionally doesn't get cleared properly when switching
        // into/out of a full-screen app — leaving a stale "ghost" of the
        // window's previous content behind. Disabling the implicit animation
        // means the OS never generates that snapshot in the first place.
        animationBehavior = .none
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let hosting = NSHostingView(rootView: view)
        hosting.frame = contentRect(forFrameRect: frame)
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
