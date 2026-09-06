import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

/// A lyric-file match awaiting the user's confirmation.
struct PendingMatch: Identifiable {
    let id = UUID()
    let trackKey: String
    let fileName: String
}

final class LyricsManager: ObservableObject {
    @Published var lines: [LyricLine] = []
    @Published var currentLineIndex: Int = -1
    @Published var currentWordIndex: Int = -1
    @Published var statusText: String = "Waiting for music…"
    @Published var pendingConfirmation: PendingMatch?

    let monitor = NowPlayingMonitor()

    /// Folders (searched recursively) that are scanned for .lrc/.ttml files.
    /// You can add as many as you like.
    @Published var lyricsFolders: [URL] = [] {
        didSet { UserDefaults.standard.set(lyricsFolders.map(\.path), forKey: "lyricsFolders") }
    }

    /// Subfolders to skip during the scan even if they live inside a lyrics
    /// folder above — e.g. a "Songs"/audio folder that isn't lyrics at all.
    @Published var excludedFolders: [URL] = [] {
        didSet { UserDefaults.standard.set(excludedFolders.map(\.path), forKey: "excludedFolders") }
    }

    private var currentLyricsURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var loadedForTrackKey = ""

    /// How many seconds to nudge the compare position by before matching it
    /// against lyric timestamps. Positive = lyrics highlight earlier (use
    /// this if words are showing up late/after they're sung). Negative =
    /// lyrics highlight later. Stored in UserDefaults directly (rather than
    /// via @AppStorage, since this class isn't a View) so SettingsView's
    /// @AppStorage binding of the same key stays in sync automatically.
    private var syncOffset: TimeInterval {
        UserDefaults.standard.double(forKey: "syncOffsetMs") / 1000.0
    }

    /// trackKey -> lyric file path, remembered once the user confirms/chooses a
    /// match so the same song never prompts twice.
    private var confirmedMatches: [String: String] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(confirmedMatches) {
                UserDefaults.standard.set(data, forKey: "confirmedLyricMatches")
            }
        }
    }

    init() {
        let defaults = UserDefaults.standard

        if let paths = defaults.array(forKey: "lyricsFolders") as? [String] {
            lyricsFolders = paths.map(URL.init(fileURLWithPath:))
        } else if let legacyPath = defaults.string(forKey: "lyricsFolder") {
            // Migrate from the old single-folder setting (pre-multi-folder builds).
            lyricsFolders = [URL(fileURLWithPath: legacyPath)]
            defaults.removeObject(forKey: "lyricsFolder")
        }

        if let paths = defaults.array(forKey: "excludedFolders") as? [String] {
            excludedFolders = paths.map(URL.init(fileURLWithPath:))
        }

        if let data = defaults.data(forKey: "confirmedLyricMatches"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            confirmedMatches = decoded
        }

        monitor.$title.combineLatest(monitor.$artist)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] title, artist in
                self?.trackChanged(title: title, artist: artist)
            }
            .store(in: &cancellables)

        monitor.$position
            .sink { [weak self] position in
                self?.updateHighlight(position: position)
            }
            .store(in: &cancellables)
    }

    // MARK: - Folder management (auto-saves via didSet above)

    func addLyricsFolder(_ url: URL) {
        guard !lyricsFolders.contains(url) else { return }
        lyricsFolders.append(url)
    }

    func removeLyricsFolder(_ url: URL) {
        lyricsFolders.removeAll { $0 == url }
    }

    func addExcludedFolder(_ url: URL) {
        guard !excludedFolders.contains(url) else { return }
        excludedFolders.append(url)
    }

    func removeExcludedFolder(_ url: URL) {
        excludedFolders.removeAll { $0 == url }
    }

    private func trackChanged(title: String, artist: String) {
        let key = "\(artist) - \(title)"
        guard key != loadedForTrackKey, !title.isEmpty else { return }
        loadedForTrackKey = key
        pendingConfirmation = nil

        // Already confirmed for this exact track (by the user, previously) — load
        // instantly with no prompt, seamlessly.
        if let savedPath = confirmedMatches[key], FileManager.default.fileExists(atPath: savedPath) {
            loadLyrics(from: URL(fileURLWithPath: savedPath))
            return
        }

        guard let file = findLyricsFile(title: title, artist: artist) else {
            lines = []
            currentLyricsURL = nil
            statusText = "No lyrics found for \"\(title)\""
            return
        }

        loadLyrics(from: file)
        // "Auto Yes" (Settings → Display) accepts every auto-match immediately
        // instead of asking — same end state as the user confirming it
        // themselves, just without showing the banner at all.
        if UserDefaults.standard.bool(forKey: "autoYes") {
            confirmedMatches[key] = file.path
        } else {
            pendingConfirmation = PendingMatch(trackKey: key, fileName: file.lastPathComponent)
        }
    }

    /// User confirmed the auto-matched file was correct — remember it so this
    /// song never needs to ask again.
    func confirmMatch() {
        guard let pending = pendingConfirmation, let url = currentLyricsURL else {
            pendingConfirmation = nil
            return
        }
        confirmedMatches[pending.trackKey] = url.path
        pendingConfirmation = nil
    }

    /// User said the auto-matched file was wrong — let them pick the real one.
    func rejectMatch() {
        pendingConfirmation = nil
        pickFileManually()
    }

    /// Opens a file picker for the currently playing track and remembers the choice.
    func pickFileManually() {
        // Same reason `openSettings()` in LyricsFloatApp.swift needs this: as
        // a menu-bar-only (.accessory) app with no Dock icon, LyricsFloat is
        // never automatically "active", and a modal panel shown from an
        // inactive accessory app can appear without focus/key status or fail
        // to properly hand control back to the app afterward.
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "lrc"),
            UTType(filenameExtension: "ttml")
        ].compactMap { $0 }
        panel.prompt = "Use This Lyrics File"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadLyrics(from: url)
        if !loadedForTrackKey.isEmpty {
            confirmedMatches[loadedForTrackKey] = url.path
        }
    }

    /// Loads and parses a lyric file. All the actual disk/iCloud I/O happens
    /// on a background queue — a previous version did this synchronously on
    /// the main thread, including a loop that could block for up to ~5
    /// seconds waiting on an iCloud download. Blocking the main thread also
    /// stalls the 60Hz display timer that drives the highlight, so that
    /// stall was a second, separate source of the reported "drift"/lag on
    /// top of the read failures. Reading now never blocks the UI.
    func loadLyrics(from url: URL) {
        currentLineIndex = -1
        currentWordIndex = -1
        statusText = "Loading…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.ensureDownloaded(url)

            let result: Result<[LyricLine], Error> = Result {
                if url.pathExtension.lowercased() == "ttml" {
                    return TTMLParser.parse(try Data(contentsOf: url))
                } else {
                    return LyricsParser.parseLRC(try Self.readLyricsText(from: url))
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let parsedLines):
                    self.lines = parsedLines
                    self.currentLyricsURL = url
                    self.statusText = parsedLines.isEmpty ? "Lyrics file had no timed lines" : ""
                case .failure(let error):
                    self.lines = []
                    self.currentLyricsURL = nil
                    self.statusText = "Couldn't read lyrics file: \(error.localizedDescription)"
                }
            }
        }
    }

    /// If `url` is an iCloud Drive (or similar) placeholder that hasn't been
    /// downloaded to this Mac yet, kick off the download and wait briefly for
    /// it to land. Lyric files are tiny, so this resolves almost instantly
    /// once iCloud starts fetching it.
    ///
    /// A previous version used `try url.resourceValues(...)`, which throws
    /// on plain local files (this ubiquity-only resource key isn't
    /// supported outside an actual iCloud container, and querying it that
    /// way errors out instead of just returning nil) — meaning it threw for
    /// basically everyone's ordinary, non-iCloud lyrics folder and turned
    /// every load into "Couldn't read lyrics file." Using `try?` throughout
    /// makes this genuinely a no-op for ordinary local files, only ever
    /// doing anything when the key resolves and actually says "not
    /// downloaded yet." It no longer throws at all — callers don't need to
    /// handle an error case that was never really about lyric-reading.
    private static func ensureDownloaded(_ url: URL) {
        guard let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus,
            status != .current else { return }

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<50 { // up to ~5s, on the background queue — never the main thread
            if (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus) == .current {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Plain `String(contentsOf:encoding: .utf8)` throws immediately on any
    /// `.lrc` file that isn't UTF-8 — which a lot of real-world lyric files
    /// aren't (many taggers/exporters, especially on Windows, write UTF-16 or
    /// Windows-1252/Latin-1). Try UTF-8 first (the common case) and fall
    /// back through the other encodings actually seen in the wild before
    /// giving up.
    private static func readLyricsText(from url: URL) throws -> String {
        let candidateEncodings: [String.Encoding] = [.utf8, .utf16, .windowsCP1252, .isoLatin1]
        var lastError: Error?
        for encoding in candidateEncodings {
            do {
                return try String(contentsOf: url, encoding: encoding)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CocoaError(.fileReadUnknown)
    }

    /// Looks for "Artist - Title.lrc"/.ttml first across every configured
    /// lyrics folder (searched recursively, minus any excluded subfolders),
    /// then falls back to any file whose name contains the track title.
    private func findLyricsFile(title: String, artist: String) -> URL? {
        let candidates = allLyricFiles()
        guard !candidates.isEmpty else { return nil }

        if let exact = candidates.first(where: {
            normalize($0.deletingPathExtension().lastPathComponent) == normalize("\(artist) - \(title)")
        }) {
            return exact
        }
        let normalizedTitle = normalize(title)
        return candidates.first { normalize($0.deletingPathExtension().lastPathComponent).contains(normalizedTitle) }
    }

    /// Recursively collects every .lrc/.ttml file across all lyrics folders,
    /// skipping any folder listed in `excludedFolders` (and everything under it) —
    /// e.g. a folder that holds your song/audio files rather than lyrics.
    private func allLyricFiles() -> [URL] {
        var results: [URL] = []
        for folder in lyricsFolders {
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                if isExcluded(url) {
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }
                if ["lrc", "ttml"].contains(url.pathExtension.lowercased()) {
                    results.append(url)
                }
            }
        }
        return results
    }

    private func isExcluded(_ url: URL) -> Bool {
        excludedFolders.contains { excluded in
            url.path == excluded.path || url.path.hasPrefix(excluded.path + "/")
        }
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateHighlight(position: TimeInterval) {
        guard !lines.isEmpty else { return }

        let adjustedPosition = position + syncOffset

        var lineIdx = -1
        for (i, line) in lines.enumerated() {
            if line.time <= adjustedPosition { lineIdx = i } else { break }
        }
        // Only assign (and thus publish) when the value actually changes —
        // this runs on every position update, and an unconditional
        // assignment would re-trigger SwiftUI far more than needed even
        // while the highlighted line/word hasn't moved.
        if currentLineIndex != lineIdx {
            currentLineIndex = lineIdx
        }

        guard lineIdx >= 0, !lines[lineIdx].words.isEmpty else {
            if currentWordIndex != -1 { currentWordIndex = -1 }
            return
        }
        var wordIdx = -1
        for (i, word) in lines[lineIdx].words.enumerated() {
            if word.time <= adjustedPosition { wordIdx = i } else { break }
        }
        if currentWordIndex != wordIdx {
            currentWordIndex = wordIdx
        }
    }
}
