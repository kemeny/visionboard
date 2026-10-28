import Foundation

// "Random" for a text clipping: picks from looks that already work together
// (font, background and a readable text color) rather than mixing at random,
// then sizes the words to their length and gives them a slight tilt.
struct TextLook: Equatable {
    let font: TextStyle
    let background: String
    let color: String

    static let all: [TextLook] = [
        TextLook(font: .loud, background: "transparent", color: Palette.ink),
        TextLook(font: .poster, background: "rgba(0,0,0,0.75)", color: "#ffffff"),
        TextLook(font: .editorial, background: "rgba(255,255,255,0.85)", color: Palette.ink),
        TextLook(font: .elegant, background: "rgba(59,130,246,0.85)", color: "#ffffff"),
        TextLook(font: .handwritten, background: "rgba(234,179,8,0.85)", color: Palette.ink),
        TextLook(font: .compact, background: "rgba(236,72,153,0.85)", color: "#ffffff"),
        TextLook(font: .mono, background: "rgba(34,197,94,0.85)", color: "#ffffff"),
        TextLook(font: .clean, background: "rgba(139,92,246,0.85)", color: "#ffffff"),
        TextLook(font: .loud, background: "rgba(239,68,68,0.85)", color: "#ffffff"),
        TextLook(font: .editorial, background: "transparent", color: "#3b82f6"),
        TextLook(font: .elegant, background: "rgba(249,115,22,0.85)", color: "#ffffff"),
        TextLook(font: .handwritten, background: "transparent", color: Palette.ink),
        TextLook(font: .clean, background: "rgba(255,255,255,0.85)", color: "#ef4444"),
        TextLook(font: .poster, background: "rgba(234,179,8,0.85)", color: Palette.ink),
    ]
}

extension BoardItem {
    mutating func applyRandomLook() {
        guard type == .text else { return }
        let current = TextLook(font: TextStyle(fontStyle), background: bgColor ?? "transparent", color: color ?? Palette.ink)
        let look = TextLook.all.filter { $0 != current }.randomElement()!
        fontStyle = look.font.rawValue
        bgColor = look.background
        color = look.color

        // Short words can shout; long sentences need room
        let length = content.trimmingCharacters(in: .whitespacesAndNewlines).count
        let sizes: [Double] = switch length {
        case ..<14: [32, 48]
        case ..<32: [24, 32]
        default: [18, 24]
        }
        fontSize = sizes.randomElement()!
        rotation = (Double.random(in: -4...4) * 2).rounded() / 2
    }
}
