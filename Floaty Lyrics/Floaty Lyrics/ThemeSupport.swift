import SwiftUI
import AppKit

// MARK: - Hex color storage
//
// @AppStorage supports String natively (so it auto-saves for free), but not
// Color, so colors are persisted as "#RRGGBB" strings and converted here.

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let color = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Transparency slider with an editable percent field
//
// `transparency` is 0...100, where 0% = fully opaque and 100% = fully
// invisible. Drag the slider, or click directly on the "%" label to type an
// exact value.

struct TransparencyControl: View {
    let label: String
    @Binding var transparency: Double

    @State private var isEditing = false
    @State private var draftText = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                percentField
            }
            Slider(value: $transparency, in: 0...100, step: 1)
        }
    }

    @ViewBuilder
    private var percentField: some View {
        if isEditing {
            HStack(spacing: 2) {
                TextField("", text: $draftText, onCommit: commitDraft)
                    .frame(width: 40)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                Text("%")
                    .foregroundColor(.secondary)
            }
            .onAppear { fieldFocused = true }
            .onChange(of: fieldFocused) { focused in
                if !focused { commitDraft() }
            }
        } else {
            Text("\(Int(transparency.rounded()))%")
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    draftText = "\(Int(transparency.rounded()))"
                    isEditing = true
                }
        }
    }

    private func commitDraft() {
        if let value = Double(draftText) {
            transparency = min(100, max(0, value))
        }
        isEditing = false
    }
}
