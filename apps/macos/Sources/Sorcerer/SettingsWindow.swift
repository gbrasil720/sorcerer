import AppKit
import SwiftUI

/// ⌘, — providers and models, who plays what, limits, storage.
enum SettingsPane: String, CaseIterable {
        case providers, roles = "who plays what", limits = "limits & pacing", storage, about
        var icon: String {
            switch self {
            case .providers: "◆"
            case .roles: "◐"
            case .limits: "▮"
            case .storage: "▤"
            case .about: "✦"
            }
        }
}

struct SettingsWindow: View {
    typealias Section = SettingsPane
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        let section = store.settingsPane
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Pixels(rows: Pixels.hat, size: 1.6)
                    Text("settings").font(.mono(13, .semibold))
                }
                .padding(.bottom, 16)
                ForEach(Section.allCases, id: \.self) { s in
                    Button { store.settingsPane = s } label: {
                        HStack(spacing: 10) {
                            Text(s.icon).font(.mono(11)).foregroundStyle(section == s ? Color.ember : Color.muted).frame(width: 14)
                            Text(s.rawValue).font(.mono(12, section == s ? .semibold : .regular))
                                .foregroundStyle(section == s ? Color.paper : Color.muted)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(section == s ? Color.panel : .clear, in: .rect(cornerRadius: 6))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("changes save as you make them").font(.mono(10)).foregroundStyle(Color.dim)
            }
            .padding(18)
            .frame(width: 210)
            .background(Color.sidebar)
            Rectangle().fill(Color.line).frame(width: 1)
            ScrollView {
                Group {
                    switch section {
                    case .providers: ProvidersPane()
                    case .roles: RolesPane()
                    case .limits: LimitsPane()
                    case .storage: StoragePane()
                    case .about: AboutPane()
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 860, height: 600)
        .background(Color.ink)
        // Blend the title bar into the window instead of the system grey.
        .containerBackground(Color.ink, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: store.settings) { store.saveSettings() }
    }
}

/// Title + one-line explanation at the top of every pane.
private struct PaneHeader: View {
    var title: String
    var detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.display(24))
            Text(detail).font(.display(13, .regular)).foregroundStyle(Color.paper.opacity(0.75))
        }
        .padding(.bottom, 8)
    }
}

// MARK: providers

private struct ProvidersPane: View {
    enum Status { case checking, missing, signedOut, ready }
    enum Test: Equatable { case running, ok(String), failed(String) }

    @Environment(Store.self) private var store
    @State private var status: [Provider: Status] = [:]
    @State private var models: [Provider: [AI.ModelOption]] = [:]
    @State private var tests: [Provider: Test] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                PaneHeader(title: "Providers", detail: "The AI tools Sorcerer drives. It uses the sign-in each one already has and never sees a password.")
                Spacer()
                Button("rescan") { Task { await scan() } }.buttonStyle(SButton())
            }
            ForEach(Provider.allCases) { p in card(p) }
        }
        .task { await scan() }
    }

    private var enabled: [Provider] { store.settings.enabled ?? Provider.allCases.filter { status[$0] == .ready } }

    private func card(_ p: Provider) -> some View {
        let s = status[p] ?? .checking
        let on = enabled.contains(p)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(["claude": "Cl", "codex": "GP", "ollama": "Ol"][p.rawValue]!).font(.mono(12)).foregroundStyle(Color.ember)
                    .frame(width: 34, height: 34).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.line))
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.label).font(.display(15))
                    Text("\(p.via) · \(label(s, p))").font(.mono(11)).foregroundStyle(s == .ready ? Color.muted : Color.dim)
                }
                Spacer()
                Toggle("use", isOn: Binding(get: { on }, set: { toggle(p, $0) }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .disabled(s != .ready)
            }
            if s == .ready {
                HStack(spacing: 10) {
                    Text("model").font(.mono(11)).foregroundStyle(Color.muted).frame(width: 60, alignment: .leading)
                    modelMenu(p)
                    Spacer()
                    testView(p)
                    Button("test") { Task { await test(p) } }.buttonStyle(SButton())
                        .disabled(tests[p] == .running)
                }
            } else if s == .signedOut {
                Text("Installed but not signed in. Run `\(p == .claude ? "claude" : "codex login")` in Terminal, then rescan.")
                    .font(.mono(11)).foregroundStyle(Color.muted)
            } else if s == .missing {
                Text(p == .ollama ? "Not running. Install it from ollama.com, pull a model, then rescan."
                                  : "Not installed. Install the \(p == .claude ? "Claude Code" : "Codex") CLI and sign in, then rescan.")
                    .font(.mono(11)).foregroundStyle(Color.muted)
            }
        }
        .card(on ? .ember.opacity(0.7) : .line, padding: 16)
        .opacity(s == .ready || s == .checking ? 1 : 0.7)
    }

    private func modelMenu(_ p: Provider) -> some View {
        let options = models[p] ?? []
        let current = store.settings.model(for: p)
        let picked = options.first { $0.id == current }
        return Menu {
            ForEach(options) { m in
                Button("\(m.id == current ? "● " : "")\(m.name)\(m.detail.isEmpty ? "" : " — \(m.detail)")") { setModel(p, m.id) }
            }
        } label: {
            Text("\(picked?.name ?? (current.isEmpty ? "default" : current)) ▾").font(.mono(12, .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.line))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(picked?.detail ?? "")
    }

    @ViewBuilder private func testView(_ p: Provider) -> some View {
        switch tests[p] {
        case .running: Text("asking…").font(.mono(11)).foregroundStyle(Color.muted)
        case .ok(let t): Text("✓ \(t)").font(.mono(11)).foregroundStyle(Color.paper)
        case .failed(let e): Text("✗ \(e)").font(.mono(11)).foregroundStyle(Color.ember).lineLimit(1)
        case nil: EmptyView()
        }
    }

    private func label(_ s: Status, _ p: Provider) -> String {
        switch s {
        case .checking: "checking…"
        case .missing: p == .ollama ? "not running" : "not found"
        case .signedOut: "installed, not signed in"
        case .ready: p == .ollama ? "● running" : "signed in"
        }
    }

    private func scan() async {
        for p in Provider.allCases { status[p] = .checking }
        for p in Provider.allCases {
            let s: Status
            switch p {
            case .ollama: s = await AI.ollamaModels() == nil ? .missing : .ready
            default:
                s = await AI.installed(p == .claude ? "claude" : "codex") ? (await AI.signedIn(p) ? .ready : .signedOut) : .missing
            }
            status[p] = s
            if s == .ready { models[p] = await AI.models(for: p) }
        }
    }

    private func toggle(_ p: Provider, _ on: Bool) {
        var list = enabled
        if on { if !list.contains(p) { list.append(p) } } else { list.removeAll { $0 == p } }
        store.settings.enabled = list
        // Keep every role on something that's switched on.
        if let first = list.first {
            if !list.contains(store.settings.characters) { store.settings.characters = first }
            if !list.contains(store.settings.reports) { store.settings.reports = first }
            if !list.contains(store.settings.chats) { store.settings.chats = first }
        }
    }

    private func setModel(_ p: Provider, _ id: String) {
        var m = store.settings.models ?? [:]
        m[p.rawValue] = id.isEmpty ? nil : id
        store.settings.models = m.isEmpty ? nil : m
        if p == .ollama { store.settings.ollamaModel = id }
        tests[p] = nil
    }

    private func test(_ p: Provider) async {
        tests[p] = .running
        let start = Date()
        do {
            let r = try await AI.complete("Reply with only the word: ok", with: p, ollamaModel: store.settings.ollamaModel,
                                          model: store.settings.model(for: p))
            if let u = r.usage { store.usage[p] = u }
            let model = store.settings.model(for: p)
            tests[p] = .ok("answered in \(String(format: "%.1f", Date().timeIntervalSince(start)))s\(model.isEmpty ? "" : " · \(model)")")
        } catch {
            tests[p] = .failed(String(error.localizedDescription.prefix(80)))
        }
    }
}

// MARK: roles

private struct RolesPane: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(title: "Who plays what", detail: "Pick which AI does each job. Characters make the most calls; reports and chats are few but benefit from a stronger model.")
            VStack(spacing: 0) {
                role("characters & world", "every round: posts, replies, moods, memories", $store.settings.characters)
                role("reports", "findings and comparisons across branches", $store.settings.reports)
                role("1:1 chats", "talking to a character off the record or in-world", $store.settings.chats, last: true)
            }
            .background(Color.panel, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line))
            Text("Model per provider is set in Providers.").font(.mono(10)).foregroundStyle(Color.muted)
            VStack(alignment: .leading, spacing: 12) {
                Caps("where the calls go · a 10-round experiment")
                calls("characters & world", 12, "casting 1 · a round 1 each · that's most of your usage")
                calls("reports", 2, "the brief 1 · each report 1")
                calls("1:1 chats", 0, "1 per message you send · none unless you chat")
                Text("Tip: a fast, light model for characters and a stronger one for reports keeps runs cheap without weaker findings.")
                    .font(.mono(10)).foregroundStyle(Color.muted).padding(.top, 4)
            }
            .card(padding: 16)
        }
    }

    private func calls(_ role: String, _ n: Int, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Text(role).font(.mono(11)).frame(width: 140, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { i in
                    Rectangle().fill(i < n ? Color.ember : Color.line).frame(width: 9, height: 10)
                }
            }
            Text(n == 0 ? "as needed" : "~\(n) calls").font(.mono(11)).frame(width: 80, alignment: .leading)
            Text(detail).font(.mono(10)).foregroundStyle(Color.muted).lineLimit(1)
        }
    }

    private var options: [Provider] { store.settings.enabled?.isEmpty == false ? store.settings.enabled! : Provider.allCases }

    private func role(_ title: String, _ detail: String, _ binding: Binding<Provider>, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.display(14))
                    Text(detail).font(.mono(10)).foregroundStyle(Color.muted)
                }
                Spacer()
                Menu {
                    ForEach(options) { p in Button(name(p)) { binding.wrappedValue = p } }
                } label: {
                    Text("\(name(binding.wrappedValue)) ▾").font(.mono(12, .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.line))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            .padding(16)
            if !last { Rectangle().fill(Color.line).frame(height: 1) }
        }
    }

    private func name(_ p: Provider) -> String {
        let m = store.settings.model(for: p)
        return m.isEmpty ? p.label : "\(p.label) · \(m)"
    }
}

// MARK: limits

private struct LimitsPane: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(title: "Limits & pacing", detail: "Sorcerer runs on your subscriptions. These keep a simulation from eating your whole window.")
            VStack(alignment: .leading, spacing: 10) {
                Caps("current usage")
                ForEach(store.settings.enabled ?? Provider.allCases) { p in
                    HStack(spacing: 12) {
                        Text(p.label).font(.mono(12)).frame(width: 80, alignment: .leading)
                        if let u = store.usage[p] {
                            Meter(value: u.fiveHour, cells: 20)
                            Text("\(Int(u.fiveHour * 100))% · 5h").font(.mono(11))
                            if let w = u.sevenDay { Text("· \(Int(w * 100))% · 7 days").font(.mono(11)).foregroundStyle(Color.muted) }
                            Spacer()
                            Text("resets \(u.resetsAt.formatted(date: .omitted, time: .shortened))").font(.mono(10)).foregroundStyle(Color.muted)
                        } else {
                            Text(p == .ollama ? "local · no limit" : p == .codex ? "ChatGPT doesn't report usage" : "measured on the next call")
                                .font(.mono(11)).foregroundStyle(Color.muted)
                        }
                    }
                }
            }
            .card(padding: 16)

            setting("pause a run when a window reaches", "Paused runs resume on their own when the window resets.") {
                Tabs(options: [(70, "70%"), (80, "80%"), (90, "90%"), (0, "never")],
                     selection: Binding(get: { store.settings.pauseAt ?? 90 }, set: { store.settings.pauseAt = $0 }))
            }
            setting("spread rounds", "Once half the 5h window is used, space rounds out so a run fits before it resets.") {
                Toggle("", isOn: Binding(get: { store.settings.spread ?? true }, set: { store.settings.spread = $0 }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            setting("speed", "Pause between rounds while running, so you can read along.") {
                Tabs(options: [(12.0, "½×"), (4.0, "1×"), (0.0, "max")],
                     selection: Binding(get: { store.settings.roundGap ?? 4 }, set: { store.settings.roundGap = $0 }))
            }
            setting("default rounds", "Used when an experiment doesn't set its own.") {
                Stepper("\(store.settings.maxRounds) rounds", value: $store.settings.maxRounds, in: 1...50).font(.mono(12))
            }
        }
    }

    private func setting<C: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.display(14))
                Text(detail).font(.mono(10)).foregroundStyle(Color.muted)
            }
            Spacer()
            control()
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1).offset(y: 6) }
    }
}

// MARK: storage

private struct StoragePane: View {
    @Environment(Store.self) private var store
    @State private var bytes: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(title: "Storage", detail: "Everything lives on this Mac, as plain JSON you can read, back up or delete.")
            HStack(spacing: 12) {
                Text("~/Sorcerer").font(.mono(13, .semibold))
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.mono(11)).foregroundStyle(Color.muted)
                Button("show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.root]) }.buttonStyle(SButton())
            }
            .card(padding: 16)
            HStack(spacing: 12) {
                stat("\(store.experiments.count)", "experiments")
                stat("\(store.communities.count)", "communities")
                stat("\(store.contexts.count)", "saved contexts")
                stat("\(store.experiments.reduce(0) { $0 + $1.branches.count })", "branches")
            }
            VStack(alignment: .leading, spacing: 8) {
                Caps("what's in there")
                Text("experiments/ · one file per experiment: question, brief, every branch, post and report")
                Text("contexts/ · briefs you saved to reuse")
                Text("settings.json · this window")
            }
            .font(.mono(11)).foregroundStyle(Color.paper.opacity(0.8))
            .card(padding: 16)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Replay onboarding").font(.display(14))
                    Text("Shows the welcome steps again; your worlds stay.").font(.mono(10)).foregroundStyle(Color.muted)
                }
                Spacer()
                Button("replay") { store.settings.onboarded = false; store.saveSettings() }.buttonStyle(SButton())
            }
        }
        .task {
            let files = FileManager.default.enumerator(at: Store.root, includingPropertiesForKeys: [.fileSizeKey])
            var total: Int64 = 0
            while let f = files?.nextObject() as? URL { total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            bytes = total
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).font(.display(26))
            Text(label).font(.mono(10)).foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

// MARK: about

private struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                Pixels(rows: Pixels.hat, size: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Wordmark(size: 4)
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · open source · MIT")
                        .font(.mono(11)).foregroundStyle(Color.muted)
                }
            }
            Text("Create a community. Explore a hypothesis. Watch what happens.").font(.display(16))
            Text("Simulations surface possible reactions, objections and consequences. Treat them as hypotheses to investigate; they don't replace evidence from the real world.")
                .font(.display(13, .regular)).foregroundStyle(Color.paper.opacity(0.75))
            Text("Inspired by MiroFish. Runs on the AI you already use.").font(.mono(11)).foregroundStyle(Color.muted)
            VStack(alignment: .leading, spacing: 8) {
                Caps("keyboard")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(Self.keys, id: \.0) { key, what in
                        HStack(spacing: 12) {
                            Text(key).font(.mono(11, .semibold)).frame(width: 46, alignment: .leading)
                            Text(what).font(.mono(11)).foregroundStyle(Color.paper.opacity(0.8))
                        }
                    }
                }
            }
            .card(padding: 16)
        }
    }

    static let keys = [("⌘K", "go to anything"), ("⌘N", "new experiment"), ("⌘1–4", "feed · characters · report · context"),
                       ("⌘[ ⌘]", "back · forward"), ("⌘R", "run / pause"), ("⌘→", "play one round"),
                       ("⌘E", "inject an event"), ("⇧⌘F", "fork this moment"), ("⇧⌘R", "generate report"), ("⌘,", "settings")]
}
