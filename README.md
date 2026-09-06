# LyricsFloat
This app was (unfortunately) made entirely by Claude.ai except for the app icon ;)
A tiny always-on-top floating lyrics overlay for macOS that syncs to whatever
you're playing in **Apple Music, Pine Player, or most other players** — no
per-app integration needed. It reads plain `.lrc`/enhanced `.lrc` (word-timed)
or `.ttml` (Apple Music's own word-by-word format) lyric files.

I can't compile a macOS `.app` from this chat (this environment isn't a Mac),
so this is the full Swift source — building it takes about 2 minutes in Xcode.

## What's new in this build

- **Lines of context**: Settings → **Display** — pick how many lines show
  above/below the current one (0–5 each way, independently).
- **Lock window**: Settings → **Display**, or the menu-bar icon — prevents
  the panel from being moved or resized. The two stay in sync automatically.
- **Auto Yes**: Settings → **Display** — skips the "Using '\<file\>' —
  correct?" banner entirely and accepts every auto-match immediately.
- **Current line color**: Settings → **Appearance** → **Text** — the
  current line/word now has its own color, separate from the other
  (dimmed) lines.
- **Auto Resize**: Settings → **Display** — the window shrinks/grows to fit
  whatever's currently showing, growing away from whichever screen edge
  it's parked against. Dock it in a corner and it stays anchored to that
  corner as lines get longer or shorter.
- **Fullscreen "ghost" window fix**: switching into/out of a full-screen app
  could leave a stale snapshot of the panel's previous content on screen.
  Fixed by disabling the implicit cross-fade animation AppKit normally
  applies to this kind of always-on-every-Space panel, plus a forced
  redraw whenever the active Space changes as a second layer of defense.

## Previous fixes (still in effect)

- **"Couldn't read lyrics file" on every file** — a broken iCloud-download
  check was throwing on ordinary local files.
- **Drift / late word highlighting** — a drift-correction timer was
  polling the private MediaRemote framework at 1000Hz, flooding it. Now 8Hz.
  File loading also moved off the main thread so it can't stall the display
  timer.
- **Sync Offset** (Settings → Timing) for any residual per-app reporting lag.


## Quick fact: "TTF" vs "TTML"
`.ttf` is a **font** file — it has no lyric or timing data in it, so an app
literally cannot read lyrics from one. You almost certainly mean **`.ttml`**,
the timed-text format Apple Music itself uses for word-by-word lyrics. This
app reads `.ttml` directly.

## Build steps

1. Open Xcode → **File → New → Project → macOS → App**.
   - Product Name: `LyricsFloat`
   - Interface: **SwiftUI**
   - Language: **Swift**
2. Delete the auto-generated `ContentView.swift` and the `App.swift` Xcode created.
3. Drag all files from this project's `Sources/` folder into your Xcode project
   (check "Copy items if needed").
4. Select your target → **Signing & Capabilities**:
   - **Do not** enable "App Sandbox". The app reads a private system framework
     (`MediaRemote`) to detect what's playing anywhere on your Mac; sandboxing
     blocks that.
5. Build & run (`⌘R`). You'll see a small icon appear in the menu bar (a
   quote-bubble icon) and a floating lyrics window appear on screen.

## Using it

1. Open **Settings…** (⌘, from the menu-bar icon) → **Lyrics Folders** tab →
   **Add Folder…** and pick a folder where you keep your `.lrc`/`.ttml`
   files. You can add as many folders as you like — they're all searched
   recursively (subfolders included). If one of those folders also contains
   a subfolder of song/audio files (or anything else you don't want
   scanned), click **Exclude Folder…** and pick it.
2. Name each lyric file **`Artist - Title.lrc`** (or `.ttml`) matching the
   track's metadata — e.g. `Radiohead - Karma Police.lrc`. LyricsFloat looks
   up the currently-playing track's title/artist and matches it
   automatically. If no exact match is found, it falls back to any file
   whose name contains the track title.
3. Play something in Apple Music or Pine Player — the floating panel updates
   live, highlighting the current line and, for word-timed files, the current
   word.
4. **The first time** a song plays, a small banner appears at the top of the
   panel: *"Using '\<filename\>' — correct?"* with **Yes**/**No**.
   - **Yes** dismisses it and remembers the match — that song will never ask again.
   - **No** opens a file picker so you can point it at the right file, which
     is then remembered the same way.
   - If no file was found at all, the panel shows a **Choose Lyrics File…**
     button directly instead of a banner.
5. Drag the panel anywhere on screen; it stays on top of other windows and
   across Spaces/full-screen apps. Use **Toggle Lyrics Window** in the menu
   to hide/show it.
6. **Appearance**: Settings… → **Appearance** tab — separate color +
   transparency controls for the window background, and for the current
   line vs. the other (dimmed) lines.
7. **Display**: Settings… → **Display** tab — lines of context before/after
   the current line, window lock, Auto Yes, and Auto Resize.
8. **Timing**: Settings… → **Timing** tab — the sync offset described above,
   if lyrics ever feel early or late relative to the audio.
9. **Click Through Window** / **Lock Window**: menu-bar icon → quick
   toggles for click-through and lock, mirroring the Display tab. Note you
   can't drag the panel while either is on, so position it first.

## How the "now playing" detection works

Rather than scripting Apple Music and Pine Player separately (Pine Player
has no public AppleScript dictionary), the app taps into the same private
`MediaRemote` framework that powers Control Center's Now Playing widget.
Any player that reports playback info to macOS system-wide (which covers
Apple Music, Pine Player, Spotify, and most others) will work automatically.

**Caveat:** this relies on an undocumented Apple framework, so it's fine for
a personal build, but such apps aren't allowed on the Mac App Store, and
Apple could change the framework's private API names in a future macOS
release.

## Files

- `LyricsFloatApp.swift` — app entry point, menu bar item, panel lifecycle
- `FloatingPanel.swift` — the borderless always-on-top `NSPanel`
- `LyricsView.swift` — SwiftUI rendering of the current/adjacent lines, with word highlight
- `LyricsManager.swift` — matches the playing track to a lyric file, loads it off the main thread, and computes highlight position with the sync offset applied
- `NowPlayingMonitor.swift` / `MediaRemoteBridge.swift` — reads system-wide playback info, drift-corrected at a sane polling rate
- `LRCParser.swift` — parses standard and enhanced (word-timed) `.lrc`
- `TTMLParser.swift` — parses Apple Music-style `.ttml` word-by-word lyrics
- `SettingsView.swift` — preferences window: appearance, timing offset, and lyrics folders (add/exclude)
- `ThemeSupport.swift` — hex-color helpers and the editable transparency-slider control
