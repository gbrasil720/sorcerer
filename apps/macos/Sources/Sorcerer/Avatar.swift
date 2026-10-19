import SwiftUI

/// What a character looks like. Cosmetic only: never sent to a model.
struct Look: Codable, Hashable {
    enum Hair: Int, Codable, CaseIterable { case short, long, bun, buzz, curly }
    enum Accessory: String, Codable, CaseIterable { case glasses, beanie, headphones, earring, scarf, beard }

    var hair: Hair
    var hairColor: Int
    var skin: Int
    var outfit: Int
    var background: Int
    var accent: Int
    var accessories: Set<Accessory>

    static let hairColors: [UInt32] = [0x1E1A17, 0x5A3A22, 0xC08A4A, 0xE6D27A, 0xD9D6CF, 0xF0773A, 0x6F7FE0]
    static let skins: [UInt32] = [0xF4D9C0, 0xE2B48C, 0xC48A62, 0x9A6440, 0x6B4429]
    static let outfits: [UInt32] = [0x2A2724, 0xF0773A, 0x3F6B5C, 0x3B4A8C, 0x7A3346, 0xE9E6DF]
    static let backgrounds: [UInt32] = [0x3A2A1F, 0x23221F, 0x1C2733, 0x1F2A20, 0x2A1F2A]
    static let accents: [UInt32] = [0xF0773A, 0xE9E6DF, 0x6F7FE0, 0x4FA37D, 0xE0C24A]

    /// The face a handle gets until someone edits it. Same rules as the landing page's Avatar,
    /// so the default faces match; only the first 6 hair colors are used here for that reason.
    static func derived(from name: String) -> Look {
        // FNV-1a: stable across launches, unlike hashValue.
        let h = name.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        var acc: Set<Accessory> = []
        let glasses = h >> 18 % 3 == 0
        let beanie = !glasses && h >> 20 % 4 == 0
        let beard = h >> 24 % 5 == 0
        if glasses { acc.insert(.glasses) }
        if beanie { acc.insert(.beanie) }
        if !beanie && h >> 22 % 6 == 0 { acc.insert(.headphones) }
        if beard { acc.insert(.beard) }
        if h >> 26 % 5 == 0 { acc.insert(.earring) }
        if !beard && h >> 28 % 6 == 0 { acc.insert(.scarf) }
        return Look(hair: Hair(rawValue: Int(h % 5))!, hairColor: Int(h >> 3 % 6), skin: Int(h >> 6 % 5),
                    outfit: Int(h >> 9 % 6), background: Int(h >> 12 % 5), accent: Int(h >> 15 % 5), accessories: acc)
    }

    static func random() -> Look {
        Look(hair: Hair.allCases.randomElement()!, hairColor: hairColors.indices.randomElement()!,
             skin: skins.indices.randomElement()!, outfit: outfits.indices.randomElement()!,
             background: backgrounds.indices.randomElement()!, accent: accents.indices.randomElement()!,
             accessories: Set(Accessory.allCases.filter { _ in Int.random(in: 0..<4) == 0 }))
    }
}

/// 16×16 pixel portrait. Uses the look passed in, else the character's saved look, else the default.
struct Avatar: View {
    @Environment(Store.self) private var store: Store?
    var name: String
    var size: CGFloat = 28
    var highlight = false
    var look: Look?

    var body: some View {
        Portrait(look: look ?? store?.look(of: name) ?? .derived(from: name))
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size / 7))
            .overlay(RoundedRectangle(cornerRadius: size / 7).stroke(highlight ? Color.ember : Color.line))
            .accessibilityHidden(true)
    }
}

private struct Portrait: View {
    var look: Look

    var body: some View {
        let hair = Color(hex: Look.hairColors[look.hairColor])
        let skin = Color(hex: Look.skins[look.skin])
        let outfit = Color(hex: Look.outfits[look.outfit])
        let bg = Color(hex: Look.backgrounds[look.background])
        let accent = Color(hex: Look.accents[look.accent])
        let has = look.accessories.contains
        let style = look.hair
        let dark = Color(hex: 0x1A1714)

        Canvas { ctx, sz in
            let p = sz.width / 16
            func px(_ x: Int, _ y: Int, _ c: Color) {
                ctx.fill(Path(CGRect(x: CGFloat(x) * p, y: CGFloat(y) * p, width: p + 0.3, height: p + 0.3)), with: .color(c))
            }
            func row(_ y: Int, _ xs: ClosedRange<Int>, _ c: Color) { for x in xs { px(x, y, c) } }

            ctx.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(bg))
            for y in 0..<16 { for x in 0..<16 where (x / 2 + y / 2) % 2 == 0 { px(x, y, Color.white.opacity(0.04)) } }

            // Hair behind the face.
            if style == .long { for y in 4...11 { row(y, 2...3, hair); row(y, 12...13, hair) } }
            if style == .curly { for y in 3...8 { row(y, 2...3, hair); row(y, 12...13, hair) } }

            // Face, chin, neck, ears.
            for y in 4...9 { row(y, 4...11, skin) }
            row(10, 5...10, skin)
            row(11, 7...8, skin)
            if [.short, .bun, .buzz].contains(style) { px(3, 7, skin); px(12, 7, skin) }

            // Hair on top.
            switch style {
            case .buzz: row(3, 4...11, hair)
            case .curly:
                row(1, 4...11, hair); row(2, 3...12, hair); row(3, 3...12, hair)
                for x in stride(from: 4, through: 11, by: 2) { px(x, 1, hair.opacity(0.75)) }
            default:
                row(2, 4...11, hair); row(3, 3...12, hair); px(3, 4, hair); px(12, 4, hair)
                if style == .bun { row(0, 6...9, hair); row(1, 7...8, hair) }
            }

            // Brows, eyes, cheeks, mouth.
            row(6, 5...6, hair.opacity(0.9)); row(6, 9...10, hair.opacity(0.9))
            px(6, 7, dark); px(9, 7, dark)
            px(4, 8, Color(hex: 0xE89A8A)); px(11, 8, Color(hex: 0xE89A8A))
            row(9, 7...8, Color(hex: 0x7A3B2A))

            // Outfit.
            row(12, 5...10, outfit)
            for y in 13...15 { row(y, 3...12, outfit) }
            px(7, 12, skin); px(8, 12, skin)

            // Accessories.
            if has(.beard) { row(9, 4...6, hair); row(9, 9...11, hair); row(10, 5...10, hair) }
            if has(.glasses) { row(7, 4...11, dark); row(8, 5...6, dark); row(8, 9...10, dark) }
            if has(.beanie) {
                row(1, 4...11, accent); row(2, 3...12, accent); row(3, 3...12, accent.opacity(0.85))
                for x in stride(from: 4, through: 12, by: 2) { px(x, 2, accent.opacity(0.7)) }
                row(0, 7...8, accent)
            }
            if has(.headphones) { row(2, 3...12, accent); for y in 6...8 { row(y, 2...3, accent); row(y, 12...13, accent) } }
            if has(.earring) { px(3, 9, accent) }
            if has(.scarf) { row(11, 4...11, accent); row(12, 4...11, accent) }
        }
    }
}

// MARK: editor

/// appearance · @eli — pick hair, skin, outfit, background and accessories.
struct AvatarEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var handle: String
    @State private var look: Look

    init(handle: String, look: Look) {
        self.handle = handle
        _look = State(initialValue: look)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("appearance · ").font(.mono(11)).foregroundStyle(Color.muted)
                + Text("@\(handle)").font(.mono(11, .semibold))
            HStack(alignment: .top, spacing: 0) {
                previews.frame(width: 300).padding(22)
                Rectangle().fill(Color.line).frame(width: 1)
                options.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Rectangle().fill(Color.line).frame(height: 1)
            HStack {
                Text("appearance is cosmetic — it never changes how @\(handle) thinks").font(.mono(11)).foregroundStyle(Color.muted)
                Spacer()
                Button("cancel") { dismiss() }.buttonStyle(SButton()).keyboardShortcut(.cancelAction)
                Button("save") { store.setLook(handle, look); dismiss() }.buttonStyle(SButton(primary: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22).frame(height: 62)
        }
        .padding(.top, 14)
        .frame(width: 980, height: 680)
        .background(Color.ink)
    }

    private var previews: some View {
        VStack(alignment: .leading, spacing: 16) {
            Avatar(name: handle, size: 200, look: look)
                .padding(12)
                .background(Color.panel, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach([(72.0, "profile"), (36.0, "feed"), (24.0, "list"), (16.0, "map")], id: \.1) { size, label in
                    VStack(spacing: 6) {
                        Avatar(name: handle, size: size, look: look)
                        Text(label).font(.mono(10)).foregroundStyle(Color.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if let post = store.branch?.posts.last(where: { $0.author == handle }) {
                HStack(alignment: .top, spacing: 10) {
                    Avatar(name: handle, size: 26, look: look)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("@\(handle) · r\(post.round)").font(.mono(10)).foregroundStyle(Color.muted)
                        Text(post.text).font(.display(12, .regular)).lineLimit(3)
                    }
                }
                .card(padding: 12)
            }
            HStack(spacing: 10) {
                Button("⚄ randomize") { look = .random() }.buttonStyle(SButton()).frame(maxWidth: .infinity)
                Button("↺ reset") { look = .derived(from: handle) }.buttonStyle(SButton()).frame(maxWidth: .infinity)
            }
        }
    }

    private var options: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Caps("hair")
                    HStack(spacing: 10) {
                        ForEach(Look.Hair.allCases, id: \.self) { style in
                            var sample = look
                            let _ = sample.hair = style
                            Button { look.hair = style } label: {
                                VStack(spacing: 6) {
                                    Avatar(name: handle, size: 54, look: sample)
                                    Text("\(style)").font(.mono(10)).foregroundStyle(look.hair == style ? Color.ember : Color.muted)
                                }
                                .padding(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(look.hair == style ? Color.ember : Color.line))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    swatches(Look.hairColors, $look.hairColor)
                }
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) { Caps("skin"); swatches(Look.skins, $look.skin) }
                    VStack(alignment: .leading, spacing: 10) { Caps("outfit"); swatches(Look.outfits, $look.outfit) }
                }
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) { Caps("background"); swatches(Look.backgrounds, $look.background, square: true) }
                    VStack(alignment: .leading, spacing: 10) { Caps("accessory color"); swatches(Look.accents, $look.accent) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Caps("accessories")
                    FlowRow(items: Look.Accessory.allCases.map(\.rawValue)) { name in
                        let a = Look.Accessory(rawValue: name)!
                        let on = look.accessories.contains(a)
                        Button {
                            if on { look.accessories.remove(a) } else { look.accessories.insert(a) }
                        } label: {
                            Text("\(on ? "■" : "□") \(name)").font(.mono(11))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .foregroundStyle(on ? Color.ember : Color.muted)
                                .overlay(Capsule().stroke(on ? Color.ember : Color.line))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func swatches(_ colors: [UInt32], _ selection: Binding<Int>, square: Bool = false) -> some View {
        HStack(spacing: 8) {
            ForEach(colors.indices, id: \.self) { i in
                let on = selection.wrappedValue == i
                Button { selection.wrappedValue = i } label: {
                    Group {
                        if square {
                            RoundedRectangle(cornerRadius: 6).fill(Color(hex: colors[i]))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Color.ember : Color.line, lineWidth: on ? 2 : 1))
                        } else {
                            Circle().fill(Color(hex: colors[i]))
                                .overlay(Circle().stroke(on ? Color.ember : Color.line, lineWidth: on ? 2 : 1).padding(-3))
                        }
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
    }
}
