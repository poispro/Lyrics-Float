import SwiftUI
import AppKit
import Combine

@main
struct LyricsFloatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // This app is menu-bar-only (.accessory, no Dock icon) with no main window,
    // so it still needs *some* Scene to satisfy `App`. We don't actually use
    // this one — AppDelegate opens its own NSWindow for Settings (see
    // `openSettings()` below), since the system's Settings-scene plumbing
    // (`showSettingsWindow:`) is unreliable for accessory apps on newer macOS.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = LyricsManager()
    private var panel: FloatingPanel<LyricsView>?
    private var statusItem: NSStatusItem?
    private var clickThroughItem: NSMenuItem?
    private var lockItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var resizeCancellable: AnyCancellable?

    private var isClickThrough = false {
        didSet { applyInteractivity() }
    }
    // Mirrors the "Lock window" toggle in Settings → Display (both read/write
    // the same "windowLocked" UserDefaults key, kept in sync via the
    // UserDefaults.didChangeNotification observer below).
    private var isLocked = false {
        didSet { applyInteractivity() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon

        let view = LyricsView(manager: manager)
        let panel = FloatingPanel(view: view)
        panel.setFrameOrigin(NSPoint(x: 420, y: 120))
        panel.orderFrontRegardless()
        self.panel = panel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "Lyrics")
        item.menu = buildMenu()
        statusItem = item

        isClickThrough = UserDefaults.standard.bool(forKey: "clickThrough")
        isLocked = UserDefaults.standard.bool(forKey: "windowLocked")

        NotificationCenter.default.addObserver(
            self, selector: #selector(userDefaultsChanged),
            name: UserDefaults.didChangeNotification, object: nil
        )
        // Belt-and-suspenders against the fullscreen/Space-switch ghosting:
        // FloatingPanel already disables the implicit cross-fade animation
        // that's the likely cause, but forcing a hard reorder on every Space
        // change guarantees any stale snapshot gets cleared regardless.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )

        // Anything that can change what's on screen (a new lyric line, the
        // confirmation banner appearing/disappearing, the status text) is a
        // reason to re-check the size when Auto Resize is on. Deferred one
        // run-loop tick via `DispatchQueue.main.async` so SwiftUI has
        // actually finished laying out the new content before we ask the
        // hosting view how big it wants to be.
        resizeCancellable = manager.$lines
            .combineLatest(manager.$currentLineIndex, manager.$pendingConfirmation, manager.$statusText)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.autoResizeIfNeeded() }
            }
    }

    // Lyrics-folder management and appearance (background/text color & transparency)
    // live in Settings… now — this menu only keeps the things you'd want mid-song.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let loadItem = menu.addItem(withTitle: "Load Lyrics File for Current Song…", action: #selector(loadFile), keyEquivalent: "")
        loadItem.target = self
        let toggleItem = menu.addItem(withTitle: "Toggle Lyrics Window", action: #selector(toggleWindow), keyEquivalent: "")
        toggleItem.target = self

        menu.addItem(.separator())

        let clickThrough = NSMenuItem(title: "Click Through Window", action: #selector(toggleClickThrough), keyEquivalent: "")
        clickThrough.target = self
        menu.addItem(clickThrough)
        clickThroughItem = clickThrough

        let lock = NSMenuItem(title: "Lock Window", action: #selector(toggleLock), keyEquivalent: "")
        lock.target = self
        menu.addItem(lock)
        lockItem = lock

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        let quitItem = menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = self

        menu.items.forEach { if $0.target == nil && $0.action != nil { $0.target = self } }
        return menu
    }

    /// Applies the current click-through/lock state to the actual window.
    /// Locking wins over drag-to-move; click-through and lock both disable
    /// it, so either one alone is enough to make the window non-draggable.
    private func applyInteractivity() {
        guard let panel else { return }
        panel.ignoresMouseEvents = isClickThrough
        panel.isMovableByWindowBackground = !isClickThrough && !isLocked
        panel.isMovable = !isLocked
        if isLocked {
            panel.styleMask.remove(.resizable)
        } else {
            panel.styleMask.insert(.resizable)
        }
        clickThroughItem?.state = isClickThrough ? .on : .off
        lockItem?.state = isLocked ? .on : .off
    }

    @objc private func toggleClickThrough() {
        isClickThrough.toggle()
        UserDefaults.standard.set(isClickThrough, forKey: "clickThrough")
    }

    @objc private func toggleLock() {
        isLocked.toggle()
        UserDefaults.standard.set(isLocked, forKey: "windowLocked")
    }

    /// Settings' "Lock window" toggle writes straight to UserDefaults via
    /// @AppStorage; this is how that change reaches the actual NSPanel.
    @objc private func userDefaultsChanged() {
        let locked = UserDefaults.standard.bool(forKey: "windowLocked")
        if locked != isLocked { isLocked = locked }
    }

    @objc private func activeSpaceChanged() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Resizes the panel to fit its current content (when Auto Resize is on),
    /// growing/shrinking away from whichever screen edges it's closest to so
    /// a corner-docked window stays docked to that same corner instead of
    /// drifting as it resizes.
    private func autoResizeIfNeeded() {
        // A locked window is meant to stay exactly as the user left it,
        // size included, so auto-resize sits out while locked.
        guard UserDefaults.standard.bool(forKey: "autoResize"), !isLocked,
              let panel, let hosting = panel.contentView else { return }

        let fitting = hosting.fittingSize
        guard fitting.width > 1, fitting.height > 1 else { return }
        resizePanel(to: fitting)
    }

    private func resizePanel(to contentSize: CGSize) {
        guard let panel else { return }

        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let newWidth = min(max(240, ceil(contentSize.width)), screenFrame.width)
        let newHeight = min(max(60, ceil(contentSize.height)), screenFrame.height)

        let frame = panel.frame
        guard abs(frame.width - newWidth) > 0.5 || abs(frame.height - newHeight) > 0.5 else { return }

        // Grow/shrink away from whichever edge the window is currently
        // closer to on each axis, so the corner it's parked in stays put.
        let anchorLeft = (frame.minX - screenFrame.minX) <= (screenFrame.maxX - frame.maxX)
        let anchorBottom = (frame.minY - screenFrame.minY) <= (screenFrame.maxY - frame.maxY)

        var newX = anchorLeft ? frame.minX : frame.maxX - newWidth
        var newY = anchorBottom ? frame.minY : frame.maxY - newHeight
        // Safety clamp so it can never end up partly off-screen.
        newX = min(max(newX, screenFrame.minX), screenFrame.maxX - newWidth)
        newY = min(max(newY, screenFrame.minY), screenFrame.maxY - newHeight)

        panel.setFrame(NSRect(x: newX, y: newY, width: newWidth, height: newHeight), display: true, animate: true)
    }

    @objc private func loadFile() {
        manager.pickFileManually()
    }

    @objc private func toggleWindow() {
        guard let panel else { return }
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }

    // Manages its own NSWindow instead of going through SwiftUI's `Settings`
    // scene / `showSettingsWindow:` — that path is flaky for .accessory apps
    // (menu-bar-only, no Dock icon) on newer macOS versions and can silently
    // fail to open anything. This approach always works.
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(manager: manager))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Floaty Lyrics Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
    }
}
