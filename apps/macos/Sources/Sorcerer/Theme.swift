import SwiftUI

// Same palette as apps/web/src/index.css.
extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static let ink = Color(hex: 0x0B0B0A)
    static let sidebar = Color(hex: 0x0E0E0D)
    static let panel = Color(hex: 0x141413)
    static let line = Color(hex: 0x262624)
    static let paper = Color(hex: 0xECEBE4)
    static let muted = Color(hex: 0x8F8E87)
    static let dim = Color(hex: 0x4A4945)
    static let ember = Color(hex: 0xF0773A)
}

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func display(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
}

/// Uppercase mono section label: "CHARACTERS · MOOD".
struct Caps: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.mono(10)).tracking(1.2).foregroundStyle(Color.muted)
    }
}

struct SButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        Look(configuration: configuration, primary: primary)
    }

    /// A view so it can read isEnabled: disabled buttons must look disabled.
    private struct Look: View {
        @Environment(\.isEnabled) private var enabled
        var configuration: Configuration
        var primary: Bool
        var body: some View {
            let hot = primary && enabled
            configuration.label
                .font(.mono(12, .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(hot ? Color.ink : enabled ? Color.paper : Color.dim)
                .background(hot ? Color.ember : Color.panel, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(hot ? Color.clear : Color.line))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(.rect)
        }
    }
}

extension View {
    func card(_ border: Color = .line, dashed: Bool = false, padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(Color.panel, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : [])))
    }
}

struct Chip: View {
    var text: String
    var on = true
    var body: some View {
        Text(text).font(.mono(11))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(on ? Color.ember : Color.muted)
            .overlay(Capsule().stroke(on ? Color.ember.opacity(0.7) : Color.line))
    }
}

/// Small bordered mono label: "round 5", "at round 5 · branch B".
struct Pill: View {
    var text: Text
    var body: some View {
        text.font(.mono(11))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.line))
    }
}

/// Segmented control drawn like the design: dark track, the active tab lifted.
struct Tabs<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button { selection = value } label: {
                    Text(label).font(.mono(11, selection == value ? .semibold : .regular))
                        .foregroundStyle(selection == value ? Color.paper : Color.muted)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(selection == value ? Color.line : .clear, in: .rect(cornerRadius: 5))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.panel, in: .rect(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.line))
    }
}

/// Scattered dim dots, the starfield behind world maps and the welcome screen.
struct Dots: View {
    var seed: UInt32 = 7
    var count = 60
    var body: some View {
        Canvas { ctx, size in
            var h = seed
            for _ in 0..<count {
                h = h &* 1_103_515_245 &+ 12345
                let x = CGFloat(h >> 8 % 10_000) / 10_000 * size.width
                h = h &* 1_103_515_245 &+ 12345
                let y = CGFloat(h >> 8 % 10_000) / 10_000 * size.height
                let big = h % 7 == 0
                ctx.fill(Path(CGRect(x: x, y: y, width: big ? 2 : 1.4, height: big ? 2 : 1.4)),
                         with: .color(big ? Color.muted.opacity(0.5) : Color.dim.opacity(0.7)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: pixel art

struct Pixels: View {
    var rows: [String]
    var size: CGFloat
    /// Leave a hairline between pixels, like the block letters in the design.
    var gap: CGFloat = 0
    var body: some View {
        Canvas { ctx, _ in
            for (y, row) in rows.enumerated() {
                for (x, c) in row.enumerated() {
                    guard let color = Self.colors[c] else { continue }
                    let r = CGRect(x: CGFloat(x) * size, y: CGFloat(y) * size, width: size - gap, height: size - gap)
                    ctx.fill(Path(r), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(rows[0].count) * size, height: CGFloat(rows.count) * size)
        .accessibilityHidden(true)
    }

    static let colors: [Character: Color] = [
        "#": .paper, "w": Color(hex: 0xFFF8EE), "o": .ember, "O": Color(hex: 0xB5532D),
        "g": Color(hex: 0x8C8983), "d": Color(hex: 0x6E6B66),
    ]

    /// The brand hat, traced from the identity artboard: sparkle, stepped crown, two ember stars,
    /// ember band, shaded right edge and a shadow under the brim.
    static let hat = [
        ".o............",
        "owo......##...",
        ".o......##g...",
        ".......###g...",
        "......##o#g...",
        "......####g...",
        ".....#o####g..",
        ".....######g..",
        "....#######g..",
        "....oooooooO..",
        "...#########g.",
        "#############g",
        ".ddddddddddd..",
    ]

    static let letters: [Character: [String]] = [
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    ]
}

/// SORCERER in block letters; the last R carries an ember pixel, as in the design.
struct Wordmark: View {
    var size: CGFloat = 8
    var body: some View {
        let word = Array("SORCERER")
        HStack(spacing: size * 1.4) {
            ForEach(Array(word.enumerated()), id: \.offset) { i, l in
                var rows = Pixels.letters[l]!
                if i == word.count - 1 { rows[0] = "###o." }
                return Pixels(rows: rows, size: size, gap: max(1, size / 6))
            }
        }
        .accessibilityLabel("Sorcerer")
    }
}

/// Block bar: solid cells for the value, dithered cells for the rest.
private struct BlockBar: View {
    var filled: Int
    var cells: Int
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            let w = size.width / CGFloat(cells)
            for i in 0..<cells {
                let r = CGRect(x: CGFloat(i) * w, y: 0, width: w - 1, height: size.height)
                if i < filled {
                    ctx.fill(Path(r), with: .color(color))
                } else {
                    // 2px checker, like the design's empty track.
                    for y in stride(from: 0, to: size.height, by: 2) {
                        for x in stride(from: r.minX, to: r.maxX, by: 2) where (Int(x) / 2 + Int(y) / 2) % 2 == 0 {
                            ctx.fill(Path(CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(Color.dim))
                        }
                    }
                }
            }
        }
        .frame(width: CGFloat(cells) * 7, height: 10)
    }
}

/// Mood -1..1, ember when negative.
struct MoodBar: View {
    var mood: Double
    var cells = 14
    var body: some View {
        BlockBar(filled: Int(((mood + 1) / 2 * Double(cells)).rounded()), cells: cells, color: mood < 0 ? .ember : .paper)
            .accessibilityElement()
            .accessibilityValue("mood \(signed(mood))")
    }
}

/// 0..1 meter (traits, usage). Ember once it runs high.
struct Meter: View {
    var value: Double
    var cells = 10
    var body: some View {
        let v = min(1, max(0, value))
        BlockBar(filled: Int((v * Double(cells)).rounded()), cells: cells, color: v >= 0.7 ? .ember : .paper)
            .accessibilityElement()
            .accessibilityValue("\(Int(v * 100)) percent")
    }
}

func signed(_ v: Double) -> String { (v > 0 ? "+" : "") + String(format: "%.1f", v) }
