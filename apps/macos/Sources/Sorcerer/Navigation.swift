import SwiftUI

/// The window after onboarding: one sidebar that never changes shape, and the current screen.
struct Workspace: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            Sidebar().frame(width: 232).background(Color.sidebar)
            Rectangle().fill(Color.line).frame(width: 1)
            VStack(spacing: 0) {
                switch store.route {
                case .new: NewExperiment()
                case .feed: FeedScreen()
                case .character(let h): CharacterScreen(handle: h)
                case .report: ReportScreen()
                case .context: ContextScreen()
                }
                if let error = store.error {
                    HStack {
                        Text("! " + error).font(.mono(11)).foregroundStyle(Color.ember).lineLimit(2)
                        Spacer()
                        Button("dismiss") { store.error = nil }.buttonStyle(SButton())
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.ember.opacity(0.08))
                }
            }
        }
        .background(Color.ink)
        .ignoresSafeArea()
        .modifier(Exporter())
        .sheet(isPresented: $store.paletteOpen) { Palette() }
        .sheet(isPresented: Bindable(store.updater).showing) { UpdateSheet() }
        .task { await store.updater.check(quietly: true) }
    }
}

/// Top bar shared by every screen: breadcrumb on the left, actions on the right.
struct TopBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) { leading }.font(.mono(12)).lineLimit(1)
            Spacer()
            trailing
        }
        .padding(.horizontal, 18).frame(height: 54)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1) }
    }
}

/// "lumen-pricing / branch B · $14"
func crumbs(_ parts: [String], last: Color = .paper) -> Text {
    parts.enumerated().reduce(Text("")) { t, p in
        let piece = Text(p.element).foregroundStyle(p.offset == parts.count - 1 ? last : Color.paper)
        return p.offset == 0 ? piece : t + Text(" / ").foregroundStyle(Color.muted) + piece
    }
}

extension Branch {
    var title: String { label.map { "\(name) · \($0)" } ?? name }
}

// MARK: experiment bar

enum ExperimentTab: CaseIterable {
    case feed, characters, report, context
    var title: String { "\(self)" }
    var key: KeyEquivalent { ["1", "2", "3", "4"][Self.allCases.firstIndex(of: self)!] }
}

extension Route {
    var tab: ExperimentTab? {
        switch self {
        case .feed: .feed
        case .character: .characters
        case .report: .report
        case .context: .context
        case .new: nil
        }
    }
}

/// The bar on every experiment screen: back, name, branch, the four tabs, then the screen's own actions.
/// Everything inside an experiment is one click from here.
struct ExperimentBar<Trailing: View>: View {
    @Environment(Store.self) private var store
    @Environment(\.openSettings) private var openSettings
    @ViewBuilder var trailing: Trailing
    @State private var renaming: Renaming?

    enum Renaming: Identifiable { case experiment, branch; var id: Self { self } }

    var body: some View {
        if let e = store.experiment, let b = store.branch {
            VStack(spacing: 0) {
                TopBar {
                    Button { store.goBack() } label: { Text("‹").font(.mono(16)) }
                        .buttonStyle(.plain).foregroundStyle(store.back.isEmpty ? Color.dim : Color.paper)
                        .disabled(store.back.isEmpty).help("Back (⌘[)")
                    Text(e.name).font(.mono(12, .semibold))
                    Text("/").foregroundStyle(Color.muted)
                    branchMenu(e, b)
                    Pill(text: Text("round ") + Text("\(b.round)").bold())
                    if store.running { Text("● running").foregroundStyle(Color.ember) }
                    if store.pausedUntil != nil { Text("❚❚ paused at limit").foregroundStyle(Color.ember) }
                    if let busy = store.busy { Text(busy).foregroundStyle(Color.muted) }
                } trailing: {
                    trailing
                    moreMenu
                }
                HStack(spacing: 4) {
                    ForEach(ExperimentTab.allCases, id: \.self) { tab in
                        let on = store.route.tab == tab
                        Button { open(tab) } label: {
                            VStack(spacing: 7) {
                                Text(label(tab, e, b)).font(.mono(11, on ? .semibold : .regular))
                                    .foregroundStyle(on ? Color.paper : Color.muted)
                                Rectangle().fill(on ? Color.ember : .clear).frame(height: 2)
                            }
                            .padding(.horizontal, 10).padding(.top, 9)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("\(tab.title.capitalized) (⌘\(String(tab.key.character)))")
                    }
                    Spacer()
                    Text("⌘K go to anything").font(.mono(10)).foregroundStyle(Color.dim).padding(.trailing, 18)
                }
                .padding(.leading, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1) }
            }
            .alert("Rename experiment", isPresented: binding(.experiment)) {
                RenameField(initial: e.name) { store.rename($0) }
            }
            .alert("Label branch \(b.name)", isPresented: binding(.branch)) {
                RenameField(initial: b.label ?? "", placeholder: "e.g. $14 + offline") { store.label(b.id, $0) }
            }
        }
    }

    private func label(_ tab: ExperimentTab, _ e: Experiment, _ b: Branch) -> String {
        switch tab {
        case .feed: "feed · \(b.posts.count)"
        case .characters: "characters · \(b.characters.count)"
        case .report: e.report == nil ? "report" : "report ✓"
        case .context: e.brief.map { "context · \($0.facts.count) facts" } ?? "context"
        }
    }

    private func open(_ tab: ExperimentTab) {
        switch tab {
        case .feed: store.go(.feed)
        case .characters: store.showCharacters()
        case .report: store.go(.report)
        case .context: store.go(.context)
        }
    }

    private func binding(_ r: Renaming) -> Binding<Bool> {
        Binding(get: { renaming == r }, set: { if !$0 { renaming = nil } })
    }

    private func branchMenu(_ e: Experiment, _ b: Branch) -> some View {
        Menu {
            ForEach(e.branches) { other in
                Button("\(other.id == b.id ? "● " : "")branch \(other.title) · r\(other.round)") { store.switchBranch(other.id) }
            }
            Divider()
            Button("Fork this moment") { store.fork() }
            Button("Label this branch…") { renaming = .branch }
        } label: {
            Text("branch \(b.title) ▾").font(.mono(12)).foregroundStyle(Color.ember)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Switch, fork or label branches")
    }

    private var moreMenu: some View {
        Menu {
            Button("Rename experiment…") { renaming = .experiment }
            Button("Label branch…") { renaming = .branch }
            Divider()
            ForEach([ExportKind.experiment, .bundle, .report], id: \.self) { k in
                Button(k.label) { store.exporting = k }.disabled(store.exportPayload(k) == nil)
            }
            Divider()
            Button("Models & limits…") { store.settingsPane = .providers; openSettings() }
            Divider()
            Button("Delete experiment", role: .destructive) { if let id = store.selected { store.delete(id) } }
        } label: {
            Text("⋯").font(.mono(14, .bold)).frame(width: 30, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.line))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Rename, export, delete")
    }
}

private struct RenameField: View {
    var initial: String
    var placeholder = ""
    var save: (String) -> Void
    @State private var text = ""
    var body: some View {
        TextField(placeholder, text: $text).onAppear { text = initial }
        Button("Save") { save(text) }
        Button("Cancel", role: .cancel) {}
    }
}

// MARK: sidebar

struct Sidebar: View {
    @Environment(Store.self) private var store
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Pixels(rows: Pixels.hat, size: 1.9)
                Text("sorcerer").font(.mono(14, .semibold))
                Spacer()
                let creating = store.route == .new
                Button { store.go(.new) } label: {
                    Text("+").font(.mono(15, .bold)).frame(width: 26, height: 26)
                        .foregroundStyle(creating ? Color.ink : Color.paper)
                        .background(creating ? Color.ember : Color.panel, in: .rect(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(creating ? .clear : Color.line))
                }
                .buttonStyle(.plain)
                .help("New experiment (⌘N)")
            }
            .padding(.top, 44)

            // Looks like a search field; opens Go to… which searches everything.
            Button { store.paletteOpen = true } label: {
                HStack {
                    Text("/").foregroundStyle(Color.muted)
                    Text("Go to…").foregroundStyle(Color.muted)
                    Spacer()
                    Text("⌘K").foregroundStyle(Color.muted)
                }
                .font(.mono(11))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.panel, in: .rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.line))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Caps("experiments")
                            Spacer()
                            Button("import") { importing = true }
                                .buttonStyle(.plain).font(.mono(10)).foregroundStyle(Color.muted)
                                .help("Open a .sorcerer.json someone shared with you")
                        }
                        .padding(.bottom, 6)
                        ForEach(store.experiments) { row($0) }
                        if store.experiments.isEmpty {
                            Text("No worlds yet.").font(.mono(11)).foregroundStyle(Color.muted).padding(.vertical, 6)
                        }
                    }
                    if store.route == .new {
                        if !store.contexts.isEmpty {
                            section("saved contexts", store.contexts.map { b in (b.title, "\(b.facts.count) facts", { store.reuseBrief = b }) })
                        }
                    }
                    if !store.communities.isEmpty {
                        section("communities", store.communities.map { c in
                            (c.name, "\(c.cast.count)", { store.reuse = c; store.go(.new) })
                        })
                    }
                }
            }
            VStack(spacing: 8) {
                UpdateRow()
                UsageBlock()
                UsageBlock.SettingsRow()
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 14)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { store.importWorld(url) }
        }
    }

    private func section(_ title: String, _ items: [(String, String?, () -> Void)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Caps(title).padding(.bottom, 6)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button(action: item.2) {
                    HStack {
                        Text(item.0).font(.display(13, .regular)).lineLimit(1)
                        Spacer()
                        if let n = item.1 { Text(n).font(.mono(10)).foregroundStyle(Color.muted) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func status(_ e: Experiment, _ b: Branch?) -> some View {
        let here = store.selected == e.id && (b == nil || store.branchID == b?.id)
        let live = store.running && here
        let paused = store.pausedUntil != nil && here
        let round = b?.round ?? e.branches.map(\.round).max() ?? 0
        return Text(live ? "live" : paused ? "❚❚" : "r\(round)")
            .font(.mono(10)).foregroundStyle(live ? Color.ember : Color.muted)
    }

    /// An experiment; when open it unfolds its screens and branches right here.
    @ViewBuilder
    private func row(_ e: Experiment) -> some View {
        let isOpen = store.selected == e.id && store.route != .new
        Button { isOpen ? store.go(.feed) : store.open(e.id) } label: {
            HStack(spacing: 7) {
                Circle().fill(isOpen && store.running ? Color.ember : .clear).frame(width: 6, height: 6)
                Text(e.name).font(.display(13, isOpen ? .semibold : .regular)).lineLimit(1)
                Spacer()
                status(e, nil)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(isOpen ? Color.panel : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { store.open(e.id) }
            Button("Report") { store.open(e.id, route: .report) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(e.id) }
        }

        if isOpen, let b = store.branch {
            VStack(alignment: .leading, spacing: 1) {
                sub("feed", on: store.route == .feed) { store.go(.feed) }
                sub("characters · \(b.characters.count)", on: store.route.tab == .characters) { store.showCharacters() }
                sub("report", on: store.route == .report) { store.go(.report) }
                sub(e.brief.map { "context · \($0.facts.count) facts" } ?? "context", on: store.route == .context) { store.go(.context) }
                if e.branches.count > 1 {
                    ForEach(e.branches) { br in
                        Button { store.switchBranch(br.id) } label: {
                            HStack {
                                Text("⑂ \(br.title)").font(.mono(11)).lineLimit(1)
                                    .foregroundStyle(store.branchID == br.id ? Color.ember : Color.muted)
                                Spacer()
                                status(e, br)
                            }
                            .padding(.leading, 22).padding(.trailing, 8).padding(.vertical, 4)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, 6)
        }
    }

    private func sub(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle().fill(on ? Color.ember : Color.line).frame(width: 2, height: 14)
                Text(title).font(.mono(11, on ? .semibold : .regular)).foregroundStyle(on ? Color.paper : Color.muted)
                Spacer()
            }
            .padding(.leading, 16).padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// ●─●─● r3, then ├─● A · $9 / └─●─● B · $14, the active branch in ember.
struct BranchTree: View {
    @Environment(Store.self) private var store
    var experiment: Experiment

    var body: some View {
        let branches = experiment.branches
        let fork = branches.dropFirst().compactMap { b in b.parent.flatMap { Int($0.split(separator: "r").last ?? "") } }.min()
        VStack(alignment: .leading, spacing: 4) {
            if branches.count > 1, let fork {
                Text(String(repeating: "●─", count: min(fork, 6)) + "● r\(fork)").font(.mono(11)).foregroundStyle(Color.muted)
            }
            ForEach(Array(branches.enumerated()), id: \.element.id) { i, b in
                let active = b.id == store.branchID
                let extra = max(0, b.round - (fork ?? 0))
                Button { store.switchBranch(b.id) } label: {
                    HStack(spacing: 6) {
                        Text(branches.count > 1 ? (i == branches.count - 1 ? "  └─" : "  ├─") : "")
                            .foregroundStyle(Color.muted)
                        Text(String(repeating: "●─", count: min(max(extra, 1), 6) - 1) + "● \(b.title)")
                            .foregroundStyle(active ? Color.ember : Color.paper)
                        Spacer()
                        Text("r\(b.round)").foregroundStyle(Color.muted)
                    }
                    .font(.mono(11)).lineLimit(1)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: ⌘K

/// Go to anything: experiments, screens, branches, characters, and the things you can do.
struct Palette: View {
    struct Item: Identifiable {
        var title: String
        var detail: String
        var action: () -> Void
        var id: String { title + detail }
    }

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let items = filtered
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("/").foregroundStyle(Color.ember)
                TextField("Go to an experiment, character, branch or action…", text: $query)
                    .textFieldStyle(.plain).focused($focused)
                    .onSubmit { run(items) }
                    .onKeyPress(.downArrow) { index = min(index + 1, max(0, items.count - 1)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .font(.mono(14))
            .padding(16)
            Rectangle().fill(Color.line).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            Button { index = i; run(items) } label: {
                                HStack {
                                    Text(item.title).font(.display(13))
                                    Spacer()
                                    Text(item.detail).font(.mono(10)).foregroundStyle(Color.muted)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(i == index ? Color.line : .clear, in: .rect(cornerRadius: 6))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .id(i)
                        }
                        if items.isEmpty {
                            Text("Nothing matches “\(query)”.").font(.mono(11)).foregroundStyle(Color.muted).padding(14)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: index) { proxy.scrollTo(index) }
            }
            .frame(height: 360)
            Rectangle().fill(Color.line).frame(height: 1)
            Text("↑↓ to move · ↩ to go · esc to close").font(.mono(10)).foregroundStyle(Color.muted).padding(10)
        }
        .frame(width: 560)
        .background(Color.sidebar)
        .onAppear { focused = true }
        .onChange(of: query) { index = 0 }
    }

    private var filtered: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { ($0.title + " " + $0.detail).lowercased().contains(q) }
    }

    private func run(_ items: [Item]) {
        guard items.indices.contains(index) else { return }
        let action = items[index].action
        dismiss()
        action()
    }

    private var all: [Item] {
        var items: [Item] = []
        if let e = store.experiment, let b = store.branch {
            items += [
                Item(title: "Feed", detail: "\(e.name) · ⌘1") { store.go(.feed) },
                Item(title: "Characters", detail: "\(e.name) · ⌘2") { store.showCharacters() },
                Item(title: "Report", detail: "\(e.name) · ⌘3") { store.go(.report) },
                Item(title: "Context", detail: "\(e.name) · ⌘4") { store.go(.context) },
                Item(title: store.running ? "Pause" : "Run", detail: "⌘R") { store.running ? store.pause() : store.run() },
                Item(title: "Step one round", detail: "⌘→") { Task { await store.step() } },
                Item(title: "Inject an event", detail: "⌘E") { store.go(.feed); store.focusInject += 1 },
                Item(title: "Fork this moment", detail: "branch \(b.name) at r\(b.round)") { store.fork() },
                Item(title: "Generate report", detail: "⇧⌘R") { store.go(.report); Task { await store.report() } },
                Item(title: "Export experiment…", detail: e.name) { store.exporting = .experiment },
                Item(title: "Share bundle…", detail: "fresh scenario") { store.exporting = .bundle },
            ]
            items += e.branches.filter { $0.id != b.id }.map { br in
                Item(title: "Branch \(br.title)", detail: "r\(br.round)\(br.parent.map { " · \($0)" } ?? "")") { store.switchBranch(br.id) }
            }
            items += b.characters.map { c in
                Item(title: "@\(c.handle)", detail: c.role) { store.go(.character(c.handle)) }
            }
        }
        items += store.experiments.filter { $0.id != store.selected }.map { e in
            Item(title: e.name, detail: "What if \(e.hypothesis)") { store.open(e.id) }
        }
        items += [
            Item(title: "New experiment", detail: "⌘N") { store.go(.new) },
            Item(title: "Back", detail: "⌘[") { store.goBack() },
            Item(title: "Settings", detail: "⌘,") { store.settingsPane = .providers; openSettings() },
            Item(title: "Settings · providers & models", detail: "which AI, which model, test it") { store.settingsPane = .providers; openSettings() },
            Item(title: "Settings · who plays what", detail: "characters, reports, chats") { store.settingsPane = .roles; openSettings() },
            Item(title: "Settings · limits & pacing", detail: "usage, auto-pause, speed") { store.settingsPane = .limits; openSettings() },
            Item(title: "Settings · storage", detail: "~/Sorcerer") { store.settingsPane = .storage; openSettings() },
        ]
        return items
    }
}

/// Shows up at the bottom of the sidebar only when there's a newer Sorcerer (or one waiting to restart).
struct UpdateRow: View {
    @Environment(Store.self) private var store

    var body: some View {
        let u = store.updater
        let ready = if case .ready = u.phase { true } else { false }
        if u.available {
            Button { u.showing = true } label: {
                HStack(spacing: 8) {
                    Text(ready ? "↻" : "↑").foregroundStyle(Color.ink)
                        .frame(width: 18, height: 18).background(Color.ember, in: .rect(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ready ? "restart to update" : "update available").font(.mono(11, .semibold))
                        Text("v\(Updater.current) → v\(u.latest?.version ?? "")").font(.mono(10)).foregroundStyle(Color.muted)
                    }
                    Spacer()
                    Text("›").foregroundStyle(Color.muted)
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ember.opacity(0.6)))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("See what's new and update")
        }
    }
}
