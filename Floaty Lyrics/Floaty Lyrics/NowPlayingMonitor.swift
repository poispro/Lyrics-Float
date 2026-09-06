import Foundation
import Combine

final class NowPlayingMonitor: ObservableObject {
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var position: TimeInterval = 0
    @Published var isPlaying: Bool = false

    // 60Hz — matches a display's refresh rate, so the highlight is exactly
    // as smooth as anything on screen can be. Pure local arithmetic against
    // the anchor below; never talks to MediaRemote itself.
    private var displayTimer: Timer?

    // Catches drift (seeks, pauses, anything that makes our extrapolated
    // position wrong) between the slower full resyncs below.
    //
    // A previous version of this ran at 1000Hz, calling into MediaRemote on
    // almost every tick — roughly a thousand real round-trips into a private
    // framework per second. That backs up the completion-callback queue on
    // the main run loop, so by the time each callback actually lands, the
    // "current position" it reports is already stale — and the more that
    // backlog grows the longer a song plays, the further the displayed
    // highlight visibly falls behind the audio. That was the real source of
    // both the drift and the "word shows up after it's already sung" lag.
    // 8Hz is still fast enough to catch a skip/seek within ~125ms, without
    // ever flooding the queue.
    private var driftTimer: Timer?
    private static let driftCheckInterval: TimeInterval = 1.0 / 8.0

    // The app's own stopwatch. Between resyncs, ticks just do arithmetic
    // against these — no round-trip into MediaRemote on every tick.
    private var anchorPosition: TimeInterval = 0
    private var anchorClock: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var anchorRate: Double = 0

    // The unconditional "re-anchor from MediaRemote" cadence — the regular
    // correction for ordinary float drift, independent of anything the fast
    // check above catches early.
    private static let fullResyncInterval: TimeInterval = 5.0
    private var lastFullResync: TimeInterval = ProcessInfo.processInfo.systemUptime

    // Below this, don't touch the anchor at all — MediaRemote's own snapshot
    // has some inherent jitter, and re-anchoring to every last millisecond of
    // it is what caused flicker in an earlier version. Only step in for
    // drift big enough that it would actually look wrong.
    private static let driftCorrectionThreshold: TimeInterval = 0.25

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingChanged),
            name: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil
        )
        // Fires the instant play/pause/track-change happens, so we anchor
        // immediately rather than waiting for the next timer pass.
        refresh()
        startDisplayTimer()
    }

    @objc private func nowPlayingChanged() {
        refresh()
    }

    // `Timer.scheduledTimer` only schedules into the run loop's `.default`
    // mode, which stops firing the instant any modal loop takes over — e.g.
    // the file picker used for manual lyric selection (`NSOpenPanel.
    // runModal()`), or menu/window-drag tracking. Adding both timers to
    // `.common` keeps them ticking through all of that.
    private func startDisplayTimer() {
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        displayTimer = t
    }

    private func startDriftTimerIfNeeded() {
        guard driftTimer == nil else { return }
        let t = Timer(timeInterval: Self.driftCheckInterval, repeats: true) { [weak self] _ in
            self?.checkDrift()
        }
        RunLoop.main.add(t, forMode: .common)
        driftTimer = t
    }

    // No music playing means nothing to drift against, so there's nothing
    // for the fast check to usefully do — stop it rather than polling for
    // no reason while paused/stopped.
    private func stopDriftTimer() {
        driftTimer?.invalidate()
        driftTimer = nil
    }

    private func tick() {
        guard anchorRate > 0 else { return } // paused/stopped — hold position
        let elapsedSinceAnchor = ProcessInfo.processInfo.systemUptime - anchorClock
        position = anchorPosition + elapsedSinceAnchor * anchorRate
    }

    private func checkDrift() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastFullResync >= Self.fullResyncInterval {
            refresh()
            return
        }
        MediaRemoteBridge.shared.fetchNowPlayingInfo { [weak self] info in
            guard let self, let info, let actual = info.currentPosition() else { return }
            if abs(actual - self.position) > Self.driftCorrectionThreshold {
                self.anchorPosition = actual
                self.anchorClock = ProcessInfo.processInfo.systemUptime
                self.position = actual
            }
        }
    }

    private func refresh() {
        MediaRemoteBridge.shared.fetchNowPlayingInfo { [weak self] info in
            guard let self, let info else { return }
            self.title = info.title ?? ""
            self.artist = info.artist ?? ""
            let rate = info.playbackRate ?? 0
            let wasPlaying = self.isPlaying
            self.isPlaying = rate > 0

            // Was `info.elapsedTime` directly, treated as if captured this
            // instant. MediaRemote's snapshot is actually timestamped
            // slightly in the past (`kMRMediaRemoteNowPlayingInfoTimestamp`)
            // by a varying amount, so anchoring to the raw value introduced
            // a small, inconsistent jump on every resync. `currentPosition()`
            // extrapolates forward to close that gap before we anchor to it.
            guard let position = info.currentPosition() else { return }
            self.anchorPosition = position
            self.anchorClock = ProcessInfo.processInfo.systemUptime
            self.anchorRate = rate
            self.position = position
            self.lastFullResync = ProcessInfo.processInfo.systemUptime

            if self.isPlaying, !wasPlaying {
                self.startDriftTimerIfNeeded()
            } else if !self.isPlaying, wasPlaying {
                self.stopDriftTimer()
            }
        }
    }

    deinit {
        displayTimer?.invalidate()
        driftTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
