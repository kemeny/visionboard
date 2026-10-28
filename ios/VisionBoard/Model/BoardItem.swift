import SwiftUI

// Same JSON shape as the web app's BoardItem (lib/types.ts), so a board synced
// from the browser opens here unchanged and the other way round.
struct BoardItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case image, text
    }

    var id: String
    var type: Kind
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    // Text, or for images: "/api/sync/images/…" (cloud), "local:<file>" (this
    // device only, not yet uploaded) or a web "data:" URL.
    var content: String
    var zIndex: Double
    var fontStyle: String?
    var fontSize: Double?
    var color: String?
    var bgColor: String?
    var rotation: Double?
    var originalContent: String?
    var locked: Bool?
    var liked: Bool?

    var isLocked: Bool { locked ?? false }
    var isLiked: Bool { liked ?? false }

    static func newID() -> String {
        "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8).lowercased())"
    }
}

struct BoardFile: Codable {
    var version: Int?
    var items: [BoardItem]
    var maxZIndex: Double?
}

// The web app's starter text for a new note. Never shown in the feed or reminders.
let placeholderText = "Click to style, triple-click to edit"

enum TextStyle: String, CaseIterable, Identifiable {
    case clean, editorial, loud, elegant, mono, handwritten, compact, poster

    var id: String { rawValue }

    init(_ raw: String?) {
        let legacy = ["normal": "clean", "bold": "loud", "italic": "editorial", "serif": "elegant"]
        let mapped = raw.flatMap { legacy[$0] ?? $0 } ?? "clean"
        self = TextStyle(rawValue: mapped) ?? .clean
    }

    var label: String {
        switch self {
        case .handwritten: "Script"
        default: rawValue.capitalized
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .clean: .system(size: size, weight: .semibold)
        case .editorial: .custom("Georgia-Italic", size: size)
        case .loud: .system(size: size, weight: .black)
        case .elegant: .custom("Georgia", size: size)
        case .mono: .system(size: size, weight: .medium, design: .monospaced)
        case .handwritten: .custom("BradleyHandITCTT-Bold", size: size)
        case .compact: .system(size: size, weight: .medium)
        case .poster: .system(size: size, weight: .heavy).width(.condensed)
        }
    }

    // Letter spacing in ems, as on the web
    var trackingEm: CGFloat {
        switch self {
        case .clean: -0.01
        case .loud: -0.03
        case .elegant: 0.06
        case .compact: 0.08
        default: 0
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .clean: 1.3
        case .editorial: 1.35
        case .loud: 1.1
        case .elegant, .mono: 1.5
        case .handwritten: 1.4
        case .compact: 1.2
        case .poster: 1.05
        }
    }

    var uppercased: Bool {
        [.loud, .elegant, .compact, .poster].contains(self)
    }
}

enum Palette {
    static let textColors = ["#1a1a1a", "#6b7280", "#ef4444", "#f97316", "#eab308", "#22c55e", "#3b82f6", "#8b5cf6", "#ec4899", "#ffffff"]
    static let backgrounds = [
        "transparent", "rgba(255,255,255,0.85)", "rgba(0,0,0,0.75)", "rgba(239,68,68,0.85)", "rgba(59,130,246,0.85)",
        "rgba(234,179,8,0.85)", "rgba(34,197,94,0.85)", "rgba(139,92,246,0.85)", "rgba(236,72,153,0.85)", "rgba(249,115,22,0.85)",
    ]
    static let fontSizes: [Double] = [14, 18, 24, 32, 48, 64]
}

extension Color {
    // Reads the CSS colors the web app stores: "#rgb", "#rrggbb", "rgb()/rgba()" and "transparent"
    init?(css: String?) {
        guard let raw = css?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty, raw != "transparent" else {
            return nil
        }
        if raw.hasPrefix("#") {
            var hex = String(raw.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
            self.init(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
            return
        }
        if raw.hasPrefix("rgb"), let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")") {
            let parts = raw[raw.index(after: open)..<close]
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count >= 3 else { return nil }
            self.init(.sRGB, red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, opacity: parts.count > 3 ? parts[3] : 1)
            return
        }
        if raw == "white" { self = .white; return }
        if raw == "black" { self = .black; return }
        return nil
    }
}
