import SwiftUI

struct LyricsView: View {
    @ObservedObject var manager: LyricsManager

    @AppStorage("windowColorHex") private var windowColorHex: String = "#000000"
    @AppStorage("windowTransparency") private var windowTransparency: Double = 45
    @AppStorage("textColorHex") private var textColorHex: String = "#FFFFFF"
    @AppStorage("currentLineColorHex") private var currentLineColorHex: String = "#FFFFFF"
    @AppStorage("textTransparency") private var textTransparency: Double = 0
    @AppStorage("linesBefore") private var linesBefore: Int = 1
    @AppStorage("linesAfter") private var linesAfter: Int = 1
    @AppStorage("autoResize") private var autoResize: Bool = false

    private var windowColor: Color { Color(hex: windowColorHex) }
    private var windowOpacity: Double { 1 - (windowTransparency / 100) }
    private var textColor: Color { Color(hex: textColorHex) }
    private var currentLineColor: Color { Color(hex: currentLineColorHex) }
    private var textOpacity: Double { 1 - (textTransparency / 100) }

    var body: some View {
        VStack(spacing: 8) {
            if let pending = manager.pendingConfirmation {
                confirmationBanner(pending)
            }

            if manager.lines.isEmpty {
                VStack(spacing: 8) {
                    Text(manager.statusText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(textColor.opacity(textOpacity * 0.7))
                    Button("Choose Lyrics File…") { manager.pickFileManually() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding()
            } else {
                VStack(spacing: 6) {
                    ForEach(contextRange(around: manager.currentLineIndex), id: \.self) { i in
                        lineView(for: i, current: i == manager.currentLineIndex)
                    }
                }
                // Animate only when the *line* changes; word-level highlight recolors
                // instantly so it never feels like it's lagging behind the audio.
                .animation(.easeInOut(duration: 0.15), value: manager.currentLineIndex)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        // With Auto Resize off, this fills whatever fixed size the user set
        // manually (the old behavior). With it on, `maxWidth: .infinity`
        // would make the content always report "as wide as whatever the
        // window currently is" back to AppKit — a circular, useless number
        // for sizing the window from. Capping it instead lets the content
        // report its own natural width (which grows for a longer line, and
        // shrinks back down for a shorter one), up to a sane limit so one
        // very long line still wraps rather than spanning the whole screen.
        .frame(maxWidth: autoResize ? 900 : .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(windowColor.opacity(windowOpacity))
        )
    }

    private func confirmationBanner(_ pending: PendingMatch) -> some View {
        HStack(spacing: 10) {
            Text("Using “\(pending.fileName)” — correct?")
                .font(.caption)
                .foregroundColor(textColor.opacity(textOpacity * 0.9))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Yes") { manager.confirmMatch() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("No") { manager.rejectMatch() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    /// Governed by the "Display" settings tab — how many lines of context
    /// show before/after the currently-highlighted one.
    private func contextRange(around idx: Int) -> [Int] {
        guard !manager.lines.isEmpty else { return [] }
        guard idx >= 0 else { return [0] }
        let lower = max(0, idx - linesBefore)
        let upper = min(manager.lines.count - 1, idx + linesAfter)
        return Array(lower...upper)
    }

    @ViewBuilder
    private func lineView(for i: Int, current: Bool) -> some View {
        let line = manager.lines[i]
        if current, !line.words.isEmpty {
            wordByWordLine(line)
        } else {
            Text(line.text)
                .font(.system(size: current ? 20 : 15, weight: current ? .bold : .regular))
                .foregroundColor((current ? currentLineColor : textColor).opacity(textOpacity * (current ? 1 : 0.45)))
                .multilineTextAlignment(.center)
        }
    }

    private func wordByWordLine(_ line: LyricLine) -> some View {
        let highlighted = manager.currentWordIndex
        var text = Text("")
        for (i, word) in line.words.enumerated() {
            var t = Text(word.text + " ").font(.system(size: 20, weight: .bold))
            t = t.foregroundColor(currentLineColor.opacity(textOpacity * (i <= highlighted ? 1 : 0.4)))
            text = text + t
        }
        return text.multilineTextAlignment(.center)
    }
}
