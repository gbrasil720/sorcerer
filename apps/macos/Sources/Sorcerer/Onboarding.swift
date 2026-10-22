import SwiftUI

struct Onboarding: View {
    @Environment(Store.self) private var store
    @Environment(\.openSettings) private var openSettings
    @State private var step = 0
    enum Found { case missing, signedOut, ready }
    @State private var scan: [Provider: Found] = [:]
    @State private var ollama: [String] = []
    @State private var scanning = true
    @State private var picked: Template? = Template.all[1]

    private let titles = ["welcome to sorcerer", "how it works", "connect your AI", "limits & storage", "ready"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if step == 0 { Pixels(rows: Pixels.hat, size: 1) }
                Text(titles[step]).font(.mono(11)).foregroundStyle(Color.muted)
            }
            .frame(height: 38)
            Group {
                switch step {
                case 0: welcome
                case 1: howItWorks
                case 2: connect
                case 3: limits
                default: firstQuestion
                }
            }
            // Each step sits in the middle of the window instead of hugging the top.
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(Color.ink)
        .ignoresSafeArea()
        .task { await runScan() }
    }

    private var enabled: [Provider] { store.settings.enabled ?? [] }

    // MARK: 1 welcome

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            Pixels(rows: Pixels.hat, size: 5)
            ZStack {
                Dots(seed: 3, count: 70).frame(width: 560, height: 220)
                Wordmark(size: 8)
                ForEach(Array(["bruno", "chen", "ada", "dara", "fumi", "eli"].enumerated()), id: \.offset) { i, n in
                    HStack(spacing: 6) { Avatar(name: n, size: 18); Text(n).font(.mono(11)).foregroundStyle(Color.muted) }
                        .offset(x: [-80, 160, -250, 250, -170, 60][i], y: [-82, -66, -12, 44, 84, 100][i])
                }
            }
            .frame(height: 230)
            VStack(spacing: 4) {
                Text("Create a community. Explore a hypothesis.").font(.display(34))
                Text("Watch what happens.").font(.display(34)).foregroundStyle(Color.ember)
            }
            Text("Sorcerer brings small worlds of AI characters to life on your Mac, powered by the AI you already use. Setup takes about a minute.")
                .font(.display(14, .regular)).foregroundStyle(Color.paper.opacity(0.75))
                .multilineTextAlignment(.center).frame(maxWidth: 480)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 2 how it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("— it starts with “what if…?”").font(.mono(11)).foregroundStyle(Color.ember)
            Text("Three moves, as many worlds as you like.").font(.display(32))
            HStack(alignment: .top, spacing: 14) {
                moveCard("01", "Summon a community", "Characters with personalities, goals, relationships and memory — generated from your context or written by you.") {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(["ada", "bruno", "chen", "dara"].enumerated()), id: \.offset) { i, n in
                            Avatar(name: n, size: 22, highlight: i == 3).offset(x: [8, 64, 120, 40][i], y: [14, 0, 14, 44][i])
                        }
                        Text("·····").font(.mono(10)).foregroundStyle(Color.muted).offset(x: 34, y: 18)
                        Text("·····").font(.mono(10)).foregroundStyle(Color.muted).offset(x: 66, y: 48)
                    }
                }
                moveCard("02", "Cast a hypothesis", "Drop in a product, a price, a rumor or a rule and watch it ripple through rounds of posts and replies.") {
                    ZStack(alignment: .topLeading) {
                        Text("~~~~~~~\n~  ✦  ~\n~~~~~~~").font(.mono(11)).foregroundStyle(Color.ember).offset(x: 48, y: 8)
                        ForEach(Array(["eli", "fumi", "gus", "iris"].enumerated()), id: \.offset) { i, n in
                            Avatar(name: n, size: 18).opacity(0.7).offset(x: [0, 150, 0, 150][i], y: [0, 0, 48, 48][i])
                        }
                    }
                }
                moveCard("03", "Observe and branch", "Pause, talk to anyone, inject events. Save a moment and fork it to compare different futures.") {
                    VStack(alignment: .leading, spacing: 4) {
                        (Text("●─●─").foregroundStyle(Color.ember) + Text("●─● A").foregroundStyle(Color.muted))
                        (Text("   └─") + Text("●─● B").foregroundStyle(Color.ember)).foregroundStyle(Color.muted)
                    }
                    .font(.mono(12)).padding(.top, 12)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("!  Simulations surface possible reactions and objections. Treat what you see as hypotheses to investigate, not evidence.")
                .font(.display(13, .regular)).foregroundStyle(Color.paper.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(.line, dashed: true)
        }
    }

    private func moveCard<Art: View>(_ n: String, _ title: String, _ body: String, @ViewBuilder art: () -> Art) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            art().frame(maxWidth: .infinity, minHeight: 90, maxHeight: 90, alignment: .topLeading)
            Text(n).font(.mono(10)).foregroundStyle(Color.muted)
            Text(title).font(.display(19))
            Text(body).font(.display(13, .regular)).foregroundStyle(Color.paper.opacity(0.75))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .card(padding: 20)
    }

    // MARK: 3 connect

    private var connect: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bring your own AI.").font(.display(30))
                    Text("We looked for AI tools you're already signed in to, and for models running on this Mac.")
                        .font(.display(13, .regular)).foregroundStyle(Color.paper.opacity(0.75))
                }
                Spacer()
                Text(scanning ? "scanning…" : "✓ scan complete").font(.mono(11)).foregroundStyle(scanning ? Color.muted : Color.paper)
                Meter(value: scanning ? 0.4 : 1, cells: 12)
            }
            
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Caps("CLI sessions on this Mac")
                    providerRow(.claude, "Cl")
                    providerRow(.codex, "GP")
                    providerRow(.gemini, "Ge")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Caps("local models")
                    providerRow(.ollama, "Ol")
                    if !ollama.isEmpty {
                        FlowRow(items: ollama) { m in
                            Button { store.settings.ollamaModel = m } label: { Chip(text: m, on: store.settings.ollamaModel == m) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack {
                Text(enabled.contains(.compatible) ? "Your API endpoint is enabled." : "Use LM Studio or an API key?").font(.mono(11)).foregroundStyle(Color.muted)
                Button("configure endpoint…") { store.settingsPane = .providers; openSettings() }.buttonStyle(SButton())
            }
            flow.padding(.top, 8)
            Text("◆  Sorcerer uses the sign-in each tool already has and never asks for your password. Nothing is sent to a provider until you run a simulation.")
                .font(.mono(11)).foregroundStyle(Color.muted)
        }
    }

    private func providerRow(_ p: Provider, _ glyph: String) -> some View {
        let found = scan[p] == .ready
        let installed = scan[p] == .signedOut || found
        let on = enabled.contains(p)
        return HStack(spacing: 12) {
            Text(glyph).font(.mono(12)).foregroundStyle(Color.ember)
                .frame(width: 34, height: 34).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.line))
            VStack(alignment: .leading, spacing: 3) {
                Text(p.label).font(.display(15))
                Text("\(p.via) · \(found ? (p == .ollama ? "● running" : "signed in") : p == .ollama ? "not running" : installed ? "installed, not signed in" : "not found")")
                    .font(.mono(11)).foregroundStyle(found ? Color.muted : Color.dim)
                Text(detail(p, found))
                    .font(.display(12, .regular)).foregroundStyle(Color.paper.opacity(found ? 0.7 : 0.45))
                    .padding(.top, 4)
            }
            Spacer()
            if installed && !found && p != .ollama {
                Text("run: " + p.loginCommand).font(.mono(11)).foregroundStyle(Color.muted)
            } else {
                Button(on ? "[■ use]" : "[  use]") { toggle(p) }
                    .buttonStyle(SButton()).disabled(!found)
                    .foregroundStyle(on ? Color.ember : Color.paper)
            }
        }
        .opacity(found ? 1 : 0.5)
        .card(on ? .ember : .line)
    }

    private func detail(_ p: Provider, _ found: Bool) -> String {
        switch p {
        case .claude: "Reports its 5-hour and weekly usage, so runs pause before you hit the limit."
        case .gemini: "Uses your Gemini CLI login. Test it in Settings to verify the session; usage windows are not reported."
        case .compatible: "Configure your endpoint and key in Settings › Providers."
        case .codex: "Doesn't report usage; runs pause only if ChatGPT says you're out."
        case .ollama: found ? "Uses your configured Ollama server. \(ollama.count) \(ollama.count == 1 ? "model" : "models") found."
                            : "Free and private. Install it from ollama.com and pull a model to run worlds offline."
        }
    }

    /// your Mac ─ only what a round needs ─▶ the AI you picked
    private var flow: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("your Mac").font(.mono(11, .semibold))
                Text("~/Sorcerer\n├ communities\n├ characters\n└ history").font(.mono(10)).foregroundStyle(Color.muted)
            }
            .card(padding: 14)
            VStack(spacing: 4) {
                Text("only what a round needs").font(.mono(10)).foregroundStyle(Color.muted)
                HStack(spacing: 0) {
                    Rectangle().fill(Color.ember.opacity(0.7)).frame(height: 1)
                    Text("▶").font(.mono(10)).foregroundStyle(Color.ember)
                }
                Text("never your password, never your files").font(.mono(10)).foregroundStyle(Color.dim)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text("the AI you picked").font(.mono(11, .semibold))
                ForEach(Provider.allCases) { p in
                    Text("\(enabled.contains(p) ? "●" : "○") \(p.label)")
                        .font(.mono(10)).foregroundStyle(enabled.contains(p) ? Color.ember : Color.dim)
                }
            }
            .frame(width: 170, alignment: .leading)
            .card(padding: 14)
        }
    }

    // MARK: 4 limits & storage

    private var limits: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Stay inside your limits.").font(.display(30))
                Text("Pick who plays which part, and how Sorcerer should pace itself. You can change all of this later.")
                    .font(.display(13, .regular)).foregroundStyle(Color.paper.opacity(0.75))
            }
            
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Caps("who plays what")
                    VStack(spacing: 0) {
                        role("characters", $store.settings.characters)
                        role("world & events", $store.settings.characters)
                        role("reports", $store.settings.reports)
                        role("1:1 chats", $store.settings.chats, last: true)
                    }
                    .background(Color.panel, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line))
                    Caps("current usage").padding(.top, 8)
                    ForEach(enabled) { p in
                        HStack(spacing: 10) {
                            Text(p.label).font(.mono(11)).frame(width: 64, alignment: .leading)
                            if let u = store.usage[p] {
                                Meter(value: u.fiveHour, cells: 16)
                                Text("\(Int(u.fiveHour * 100))% · 5h window").font(.mono(11))
                            } else {
                                Text(p.usageDetail)
                                    .font(.mono(11)).foregroundStyle(Color.muted)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Caps("pause a run when a provider reaches")
                    Tabs(options: [(70, "70%"), (80, "80%"), (90, "90%"), (0, "never")],
                         selection: Binding(get: { store.settings.pauseAt ?? 90 }, set: { store.settings.pauseAt = $0 }))
                    Toggle("Spread rounds so a run fits inside the usage window",
                           isOn: Binding(get: { store.settings.spread ?? true }, set: { store.settings.spread = $0 }))
                        .toggleStyle(.checkbox).font(.display(13, .regular))
                    Text("Paused runs resume on their own when your limit resets.").font(.mono(10)).foregroundStyle(Color.muted)
                    Caps("where your worlds live").padding(.top, 8)
                    Text("~/Sorcerer").font(.mono(12)).frame(maxWidth: .infinity, alignment: .leading).card(padding: 12)
                    Text("Communities, settings and history stay on this Mac. When a round runs on an external provider, only the data that round needs is sent to it.")
                        .font(.display(12, .regular)).foregroundStyle(Color.paper.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func role(_ title: String, _ binding: Binding<Provider>, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.mono(12)).foregroundStyle(Color.muted)
                Spacer()
                Menu {
                    ForEach(enabled.isEmpty ? Provider.allCases : enabled) { p in
                        Button(name(p)) { binding.wrappedValue = p }
                    }
                } label: {
                    Text("\(name(binding.wrappedValue)) ▾").font(.mono(11, .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.line))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            if !last { Rectangle().fill(Color.line).frame(height: 1) }
        }
    }

    private func name(_ p: Provider) -> String {
        p == .ollama && !store.settings.ollamaModel.isEmpty ? "Ollama · \(store.settings.ollamaModel)" : p.label
    }

    // MARK: 5 first question

    private var firstQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You're ready. What should we explore first?").font(.display(30))
                    Text("\(enabled.count) AI sources · pause at \(store.settings.pauseAt.map { $0 == 0 ? "never" : "\($0)%" } ?? "90%") · ~/Sorcerer")
                        .font(.mono(11)).foregroundStyle(Color.muted)
                }
                Spacer()
                ZStack(alignment: .topLeading) {
                    Dots(seed: 9, count: 24)
                    ForEach(Array(["ada", "bruno", "chen", "dara"].enumerated()), id: \.offset) { i, n in
                        Avatar(name: n, size: 16).offset(x: [0, 120, 0, 120][i], y: [0, 0, 56, 56][i])
                    }
                }
                .frame(width: 140, height: 74)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(Template.all) { t in
                    Button { picked = t } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t.tag).font(.mono(10)).foregroundStyle(picked?.id == t.id ? Color.ember : Color.muted)
                            (Text("What if ").foregroundStyle(Color.muted) + Text(t.question)).font(.display(16))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Text("\(t.count) characters · \(t.rounds) rounds").font(.mono(10)).foregroundStyle(Color.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                        .card(picked?.id == t.id ? .ember : .line)
                    }
                    .buttonStyle(.plain)
                }
                Button { picked = nil } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("blank").font(.mono(10)).foregroundStyle(Color.muted)
                        Text("Start from your own question…").font(.display(16))
                        Spacer(minLength: 0)
                        Text("empty world").font(.mono(10)).foregroundStyle(Color.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    .card(picked == nil ? .ember : .line, dashed: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(0..<titles.count, id: \.self) { i in
                    Rectangle().fill(i <= step ? Color.ember : Color.dim).frame(width: 9, height: 9)
                }
            }
            Text("\(step + 1) / \(titles.count)").font(.mono(11)).foregroundStyle(Color.muted)
            if step == 2 { Text("\(enabled.count) \(enabled.count == 1 ? "source" : "sources") on").font(.mono(11, .semibold)).padding(.leading, 12) }
            Spacer()
            if step > 0 { Button("← back") { step -= 1 }.buttonStyle(SButton()) }
            switch step {
            case 0: Button("get started →") { step = 1 }.buttonStyle(SButton(primary: true))
            case 1: Button("connect your AI →") { step = 2 }.buttonStyle(SButton(primary: true))
            case 2: Button("continue →") { step = 3 }.buttonStyle(SButton(primary: true)).disabled(enabled.isEmpty)
            case 3: Button("continue →") { step = 4 }.buttonStyle(SButton(primary: true))
            default:
                Button("skip to app") { finish(nil) }.buttonStyle(.plain).font(.mono(11)).foregroundStyle(Color.muted).padding(.horizontal, 8)
                Button("add context →") { finish(picked) }.buttonStyle(SButton(primary: true))
            }
        }
        .padding(.horizontal, 24).frame(height: 64)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    // MARK: actions

    private func runScan() async {
        async let claude = status(.claude, "claude")
        async let codex = status(.codex, "codex")
        async let gemini = status(.gemini, "gemini")
        async let models = AI.ollamaModels(host: store.settings.ollamaHost)
        let (c, x, g, m) = await (claude, codex, gemini, models)
        scan = [.claude: c, .codex: x, .gemini: g, .ollama: m?.isEmpty == false ? .ready : .missing]
        ollama = m ?? []
        if store.settings.ollamaModel.isEmpty { store.settings.ollamaModel = ollama.first ?? "" }
        if store.settings.enabled == nil {
            store.settings.enabled = Provider.allCases.filter { scan[$0] == .ready }
            assignRoles()
        }
        scanning = false
    }

    private func status(_ p: Provider, _ binary: String) async -> Found {
        guard await AI.installed(binary) else { return .missing }
        return await AI.signedIn(p) ? .ready : .signedOut
    }

    private func toggle(_ p: Provider) {
        var on = enabled
        if let i = on.firstIndex(of: p) { on.remove(at: i) } else { on.append(p) }
        store.settings.enabled = on
        assignRoles()
    }

    /// Keep every role on a switched-on provider; prefer local models for the many character calls.
    private func assignRoles() {
        guard let first = enabled.first else { return }
        let s = store.settings
        if !enabled.contains(s.characters) { store.settings.characters = enabled.contains(.ollama) ? .ollama : first }
        if !enabled.contains(s.reports) { store.settings.reports = enabled.first { $0 != .ollama } ?? first }
        if !enabled.contains(s.chats) { store.settings.chats = enabled.first { $0 != .ollama } ?? first }
    }

    private func finish(_ t: Template?) {
        store.settings.onboarded = true
        store.saveSettings()
        store.draft = t
        store.startOnContext = t != nil
        store.go(.new)
    }
}
