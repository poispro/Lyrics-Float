import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var manager: LyricsManager

    // All @AppStorage values auto-save to UserDefaults the instant they change —
    // no explicit save step needed anywhere in this view.
    @AppStorage("windowColorHex") private var windowColorHex: String = "#000000"
    @AppStorage("windowTransparency") private var windowTransparency: Double = 45
    @AppStorage("textColorHex") private var textColorHex: String = "#FFFFFF"
    @AppStorage("currentLineColorHex") private var currentLineColorHex: String = "#FFFFFF"
    @AppStorage("textTransparency") private var textTransparency: Double = 0
    @AppStorage("syncOffsetMs") private var syncOffsetMs: Double = 0
    @AppStorage("linesBefore") private var linesBefore: Int = 1
    @AppStorage("linesAfter") private var linesAfter: Int = 1
    @AppStorage("windowLocked") private var windowLocked: Bool = false
    @AppStorage("autoYes") private var autoYes: Bool = false
    @AppStorage("autoResize") private var autoResize: Bool = false

    private enum CustomizeTarget: String, CaseIterable, Identifiable {
        case window = "Window"
        case text = "Text"
        var id: String { rawValue }
    }
    @State private var customizeTarget: CustomizeTarget = .window

    var body: some View {
        TabView {
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            displayTab
                .tabItem { Label("Display", systemImage: "rectangle.on.rectangle") }
            timingTab
                .tabItem { Label("Timing", systemImage: "metronome") }
            foldersTab
                .tabItem { Label("Lyrics Folders", systemImage: "folder") }
        }
        .frame(width: 460, height: 460)
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Customize the floating lyrics window's background box, or the lyrics text itself.")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Customize", selection: $customizeTarget) {
                ForEach(CustomizeTarget.allCases) { target in
                    Text(target.rawValue).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch customizeTarget {
            case .window:
                ColorPicker("Window color", selection: windowColorBinding, supportsOpacity: false)
                TransparencyControl(label: "Window transparency", transparency: $windowTransparency)
                Text(windowTransparency >= 99
                     ? "Fully transparent — only the text floats, no box behind it."
                     : "0% is a solid box; 100% is fully see-through.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .text:
                ColorPicker("Current line color", selection: currentLineColorBinding, supportsOpacity: false)
                ColorPicker("Other lines color", selection: textColorBinding, supportsOpacity: false)
                TransparencyControl(label: "Text transparency", transparency: $textTransparency)
                Text("The current line/word uses its own color at full brightness; earlier and upcoming lines use the other color, dimmed relative to it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Divider()

            Button("Reset to Defaults") { resetAppearance() }
        }
        .padding(20)
    }

    private func resetAppearance() {
        windowColorHex = "#000000"
        windowTransparency = 45
        textColorHex = "#FFFFFF"
        currentLineColorHex = "#FFFFFF"
        textTransparency = 0
    }

    private var windowColorBinding: Binding<Color> {
        Binding(get: { Color(hex: windowColorHex) }, set: { windowColorHex = $0.toHex() })
    }
    private var textColorBinding: Binding<Color> {
        Binding(get: { Color(hex: textColorHex) }, set: { textColorHex = $0.toHex() })
    }
    private var currentLineColorBinding: Binding<Color> {
        Binding(get: { Color(hex: currentLineColorHex) }, set: { currentLineColorHex = $0.toHex() })
    }

    // MARK: - Display

    private var displayTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lines of Context").font(.headline)
                Text("How many extra lines show above/below the current one.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper("Lines before: \(linesBefore)", value: $linesBefore, in: 0...5)
                Stepper("Lines after: \(linesAfter)", value: $linesAfter, in: 0...5)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Lock window (prevent moving or resizing)", isOn: $windowLocked)
                Text("Also available from the menu-bar icon for quick access mid-song.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto Yes — skip the match confirmation", isOn: $autoYes)
                Text("Normally, the first time a song plays, LyricsFloat asks you to confirm the lyric file it found. Turning this on accepts every auto-match immediately instead of asking.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto Resize", isOn: $autoResize)
                Text("The window shrinks or grows to fit whatever's currently showing. It grows away from whichever screen edge it's parked against — e.g. tuck it into the bottom-right corner and a longer line extends it left and up, so the corner it's docked to never moves.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Timing

    private var timingTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lyric Sync Offset").font(.headline)
            Text("Shifts when lines/words highlight, relative to the reported playback position. If lyrics consistently show up late — after you've already heard the word — increase this. If they show up early, decrease it.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Slider(value: $syncOffsetMs, in: -2000...2000, step: 10)
                Text(offsetLabel)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }

            Text("Most players report their playback position accurately enough that this can stay at 0. A few third-party players report it with a consistent built-in lag — this offset compensates for that.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Divider()
            Button("Reset to 0ms") { syncOffsetMs = 0 }
        }
        .padding(20)
    }

    private var offsetLabel: String {
        let ms = Int(syncOffsetMs.rounded())
        return ms == 0 ? "0ms" : (ms > 0 ? "+\(ms)ms" : "\(ms)ms")
    }

    // MARK: - Folders

    private var foldersTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lyrics Folders").font(.headline)
            Text("Searched recursively (including subfolders) for \"Artist - Title.lrc\"/.ttml files. Add as many as you like.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            folderList(manager.lyricsFolders, remove: manager.removeLyricsFolder)
            Button("Add Folder…") { pickFolder { manager.addLyricsFolder($0) } }

            Divider().padding(.vertical, 4)

            Text("Excluded Folders").font(.headline)
            Text("Skipped during the scan, even if inside a folder above — e.g. a folder that holds your song/audio files rather than lyrics.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            folderList(manager.excludedFolders, remove: manager.removeExcludedFolder)
            Button("Exclude Folder…") { pickFolder { manager.addExcludedFolder($0) } }
        }
        .padding(20)
    }

    private func folderList(_ folders: [URL], remove: @escaping (URL) -> Void) -> some View {
        Group {
            if folders.isEmpty {
                Text("None set").font(.callout).foregroundColor(.secondary)
            } else {
                List {
                    ForEach(folders, id: \.self) { folder in
                        HStack {
                            Text(folder.path)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                remove(folder)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 80)
            }
        }
    }

    private func pickFolder(_ onPick: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }
}
