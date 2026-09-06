import Foundation

typealias MRGetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
typealias MRRegisterFn = @convention(c) (DispatchQueue) -> Void

/// Wraps macOS's private MediaRemote framework, the same mechanism that feeds
/// Control Center's Now Playing widget. This lets us read title/artist/position
/// from whatever app is currently playing audio system-wide, instead of talking
/// to one specific player via AppleScript.
///
/// Note: this uses a private, undocumented framework. It's fine for a personal
/// build you compile yourself, but apps using it are not allowed on the Mac App Store.
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    private var getNowPlayingInfo: MRGetNowPlayingInfoFn?
    private var register: MRRegisterFn?

    private init() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        ) else {
            print("LyricsFloat: could not load MediaRemote framework")
            return
        }

        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getNowPlayingInfo = unsafeBitCast(sym, to: MRGetNowPlayingInfoFn.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            register = unsafeBitCast(sym, to: MRRegisterFn.self)
        }

        register?(DispatchQueue.main)
    }

    func fetchNowPlayingInfo(completion: @escaping (NowPlayingInfo?) -> Void) {
        guard let getNowPlayingInfo else {
            completion(nil)
            return
        }
        getNowPlayingInfo(DispatchQueue.main) { info in
            completion(NowPlayingInfo(dictionary: info))
        }
    }
}

struct NowPlayingInfo {
    let title: String?
    let artist: String?
    let elapsedTime: TimeInterval?
    let playbackRate: Double?
    let timestamp: Date?

    init(dictionary: [String: Any]) {
        title = dictionary["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        artist = dictionary["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        elapsedTime = dictionary["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval
        playbackRate = dictionary["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double
        timestamp = dictionary["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date
    }

    /// The elapsed snapshot goes stale between notifications, so extrapolate
    /// forward using the playback rate and time elapsed since the snapshot.
    func currentPosition(now: Date = Date()) -> TimeInterval? {
        guard let elapsedTime else { return nil }
        guard let timestamp, let rate = playbackRate, rate > 0 else { return elapsedTime }
        return elapsedTime + now.timeIntervalSince(timestamp) * rate
    }
}
