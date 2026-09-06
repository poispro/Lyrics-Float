import Foundation

struct LyricWord: Hashable {
    let time: TimeInterval
    let text: String
}

struct LyricLine: Hashable {
    let time: TimeInterval
    let text: String
    let words: [LyricWord] // empty when the source has no word-level timing
}

enum LyricsParser {
    /// Parses standard LRC ("[00:12.34]line") and enhanced/word-level LRC
    /// ("[00:12.34]<00:12.34>word<00:12.80>word ...").
    static func parseLRC(_ content: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let timeTag = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        let wordTag = try! NSRegularExpression(pattern: #"<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>"#)

        for raw in content.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsLine = line as NSString
            let matches = timeTag.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue } // metadata lines like [ar:], [ti:]

            var textStart = 0
            for m in matches { textStart = max(textStart, m.range.location + m.range.length) }
            let text = nsLine.substring(from: textStart)

            var words: [LyricWord] = []
            let nsText = text as NSString
            let wordMatches = wordTag.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for (i, wm) in wordMatches.enumerated() {
                let t = parseTime(nsText.substring(with: wm.range), regex: wordTag)
                let segStart = wm.range.location + wm.range.length
                let segEnd = (i + 1 < wordMatches.count) ? wordMatches[i + 1].range.location : nsText.length
                let wordText = nsText.substring(with: NSRange(location: segStart, length: max(0, segEnd - segStart)))
                    .trimmingCharacters(in: .whitespaces)
                if !wordText.isEmpty {
                    words.append(LyricWord(time: t, text: wordText))
                }
            }

            let plainText = text
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !plainText.isEmpty else { continue }

            for m in matches {
                let t = parseTime(nsLine.substring(with: m.range), regex: timeTag)
                lines.append(LyricLine(time: t, text: plainText, words: words))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }

    private static func parseTime(_ tag: String, regex: NSRegularExpression) -> TimeInterval {
        let ns = tag as NSString
        guard let m = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return 0 }
        let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
        let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
        var frac: Double = 0
        if m.range(at: 3).location != NSNotFound {
            let fracStr = ns.substring(with: m.range(at: 3))
            // Normalize to hundredths/thousandths regardless of 2 or 3 digit precision
            frac = Double("0.\(fracStr)") ?? 0
        }
        return minutes * 60 + seconds + frac
    }
}
