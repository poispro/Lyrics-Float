import Foundation

/// Parses TTML lyric files (the word-by-word format Apple Music itself uses,
/// e.g. from apple-music-lyrics-api style dumps). Each <p> is a line; nested
/// <span begin="..." end="..."> elements are individual timed words.
enum TTMLParser {
    static func parse(_ data: Data) -> [LyricLine] {
        let delegate = TTMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.lines
    }
}

private final class TTMLDelegate: NSObject, XMLParserDelegate {
    var lines: [LyricLine] = []

    private var inParagraph = false
    private var paragraphStart: TimeInterval = 0
    private var currentWords: [LyricWord] = []
    private var currentSpanStart: TimeInterval?
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = Self.localName(elementName)
        if name == "p", let begin = attributeDict["begin"] {
            inParagraph = true
            paragraphStart = Self.parseTime(begin)
            currentWords = []
        } else if name == "span", inParagraph, let begin = attributeDict["begin"] {
            currentSpanStart = Self.parseTime(begin)
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inParagraph else { return }
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = Self.localName(elementName)
        if name == "span", let start = currentSpanStart {
            let word = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty {
                currentWords.append(LyricWord(time: start, text: word))
            }
            currentSpanStart = nil
            currentText = ""
        } else if name == "p" {
            let fullText = currentWords.isEmpty
                ? currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                : currentWords.map(\.text).joined(separator: " ")
            if !fullText.isEmpty {
                lines.append(LyricLine(time: paragraphStart, text: fullText, words: currentWords))
            }
            inParagraph = false
            currentWords = []
            currentText = ""
        }
    }

    /// `XMLParser` reports the raw element name without stripping any XML
    /// namespace prefix (since we don't turn on namespace processing). Some
    /// real-world TTML exports declare their elements as e.g. `<tt:p>`/
    /// `<tt:span>` instead of the unprefixed `<p>`/`<span>` this parser
    /// originally only recognized, which silently produced zero lines for
    /// those files. Compare against the local (unprefixed) name instead.
    private static func localName(_ elementName: String) -> String {
        guard let colonIndex = elementName.lastIndex(of: ":") else { return elementName }
        return String(elementName[elementName.index(after: colonIndex)...])
    }

    /// Handles "00:12.345", "00:00:12.345", and "12.345s" style TTML timestamps.
    static func parseTime(_ s: String) -> TimeInterval {
        if s.hasSuffix("s") {
            return Double(s.dropLast()) ?? 0
        }
        let parts = s.split(separator: ":").map(String.init)
        switch parts.count {
        case 3:
            return (Double(parts[0]) ?? 0) * 3600 + (Double(parts[1]) ?? 0) * 60 + (Double(parts[2]) ?? 0)
        case 2:
            return (Double(parts[0]) ?? 0) * 60 + (Double(parts[1]) ?? 0)
        default:
            return Double(s) ?? 0
        }
    }
}
