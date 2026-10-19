import SwiftUI

// MARK: feed

struct FeedScreen: View {
    @Environment(Store.self) private var store
    @State private var event = ""
    @State private var who: String? = nil
    @State private var latestOnly = false
    @FocusState private var injecting: Bool
    @State private var view = FeedView.feed

    enum FeedView: String, CaseIterable { case feed, world, graph }

    var body: some View {
        if let e = store.experiment, let b = store.branch {
            VStack(spacing: 0) {
                ExperimentBar {
                    if store.running {
                        Button("❚❚ pause") { store.pause() }.buttonStyle(SButton(primary: true)).help("Pause (⌘R)")
                    } else {
                        Button("▶ run") { store.run() }.buttonStyle(SButton(primary: true))
                            .disabled(store.busy != nil || b.round >= store.roundLimit).help("Run rounds until the limit (⌘R)")
                    }
                    Button("step ›") { Task { await store.step() } }.buttonStyle(SButton())
                        .disabled(store.busy != nil).help("Play one round (⌘→)")
                    Button("⑂ fork") { store.fork() }.buttonStyle(SButton()).disabled(store.busy != nil)
                        .help("Fork this moment into a new branch")
                }
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        filterBar(b)
                        switch view {
                        case .feed: feed(e, b)
                        case .world: WorldView(branch: b)
                        case .graph: GraphView(experiment: e, branch: b)
                        }
                        injectBar(b)
                    }
                    Rectangle().fill(Color.line).frame(width: 1)
                    WorldPanel(branch: b, showMap: view != .world).frame(width: 320)
                }
            }
        }
    }

    private func filterBar(_ b: Branch) -> some View {
        @Bindable var store = store
        return HStack {
            Tabs(options: FeedView.allCases.map { ($0, $0.rawValue) }, selection: $view)
            Spacer()
            if view == .feed {
            Text("filter:").foregroundStyle(Color.muted)
            Menu(who.map { "@\($0)" } ?? "all characters") {
                Button("all characters") { who = nil }
                Divider()
                ForEach(b.characters) { c in Button("@\(c.handle)") { who = c.handle } }
            }
            .menuStyle(.borderlessButton).fixedSize().tint(Color.muted)
            Text("·").foregroundStyle(Color.muted)
            Menu(latestOnly ? "latest round" : "all rounds") {
                Button("all rounds") { latestOnly = false }
                Button("latest round") { latestOnly = true }
            }
            .menuStyle(.borderlessButton).fixedSize().tint(Color.muted)
            Text("·").foregroundStyle(Color.muted)
            }
            Text("speed").foregroundStyle(Color.muted)
            Tabs(options: [(12.0, "½×"), (4.0, "1×"), (0.0, "max")], selection: Binding(
                get: { store.settings.roundGap ?? 4 },
                set: { store.settings.roundGap = $0; store.saveSettings() }
            ))
            .help("Pause between rounds while running: ½× waits 12s, 1× waits 4s, max doesn't wait")
        }
        .font(.mono(11))
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private func feed(_ e: Experiment, _ b: Branch) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if b.round == 0 {
                        (Text("What if ").foregroundStyle(Color.muted) + Text(e.hypothesis)).font(.display(20)).padding(.bottom, 6)
                        HStack {
                            Text("Round 0. The world is waiting.").font(.mono(11)).foregroundStyle(Color.muted)
                            Spacer()
                            Button("step › one round") { Task { await store.step() } }.buttonStyle(SButton())
                            Button("▶ run \(store.roundLimit) rounds") { store.run() }.buttonStyle(SButton(primary: true))
                        }
                        .disabled(store.busy != nil)
                        .card(.line, dashed: true)
                    }
                    ForEach((latestOnly ? max(1, b.round) : 1)..<(b.round + 2), id: \.self) { r in
                        let events = b.events.filter { $0.round == r }
                        let posts = b.posts.filter { $0.round == r && (who == nil || $0.author == who) }
                        if !events.isEmpty || !posts.isEmpty {
                            HStack(spacing: 8) {
                                Rectangle().fill(Color.line).frame(width: 18, height: 1)
                                Text("round \(r)").font(.mono(10)).foregroundStyle(Color.muted)
                                Rectangle().fill(Color.line).frame(height: 1)
                            }
                            .padding(.top, 8)
                        }
                        ForEach(events) { ev in
                            Text("⚡ event · injected by you — \(ev.text)\(r > b.round ? "  (next round)" : "")")
                                .font(.mono(11)).foregroundStyle(Color.ember)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card(.ember, dashed: true)
                        }
                        ForEach(posts) { post in PostCard(post: post, replies: b.posts.filter { $0.replyToPost == post.id }.count).id(post.id) }
                    }
                    if let live = store.live, live.branch == b.id {
                        LiveRoundView(live: live, branch: b)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: b.posts.count) { withAnimation { proxy.scrollTo("end") } }
            // Follow the live round as it grows.
            .onChange(of: store.live?.partial.done.count) { withAnimation { proxy.scrollTo("end") } }
            .onChange(of: store.live?.partial.typing) { withAnimation { proxy.scrollTo("end") } }
            .onChange(of: store.live?.round) { withAnimation { proxy.scrollTo("end") } }
            .task(id: store.focusPost) {
                // Wait a beat so the lazy stack has laid out before jumping to a cited post.
                guard let f = store.focusPost else { return }
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation { proxy.scrollTo(f, anchor: .center) }
            }
            .onDisappear { store.focusPost = nil }
        }
    }

    private func injectBar(_ b: Branch) -> some View {
        HStack(spacing: 10) {
            Text("⚡").foregroundStyle(Color.ember)
            TextField("Inject an event or change a condition…", text: $event)
                .textFieldStyle(.plain).font(.mono(12))
                .focused($injecting)
                .onSubmit(send)
                .onChange(of: store.focusInject) { injecting = true }
                .onAppear { if store.focusInject > 0 { injecting = true } }
            Text("⌘E · ↵ at r\(b.round + 1)").font(.mono(10)).foregroundStyle(Color.muted)
            Button("inject", action: send).buttonStyle(SButton())
                .disabled(event.isEmpty)
        }
        .card()
        .padding(14)
    }

    private func send() {
        store.inject(event)
        event = ""
    }
}

struct PostCard: View {
    @Environment(Store.self) private var store
    var post: Post
    var replies = 0

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { store.go(.character(post.author)) } label: { Avatar(name: post.author, size: 36) }
                .buttonStyle(.plain).help("Open @\(post.author)")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button("@\(post.author)") { store.go(.character(post.author)) }
                        .buttonStyle(.plain).font(.mono(11, .semibold))
                    Text(post.replyTo.map { "replied to @\($0)" } ?? "posted").font(.mono(11)).foregroundStyle(Color.muted)
                    Text("mood \(signed(post.mood))").font(.mono(11)).foregroundStyle(post.mood < 0 ? Color.ember : Color.muted)
                }
                Text(post.text).font(.display(15, .regular)).textSelection(.enabled)
                HStack(spacing: 14) {
                    Text("↩ \(replies)")
                    Text("+ \(post.agree ?? 0)")
                    Text("− \(post.disagree ?? 0)")
                    Button("ask why ›") { store.go(.character(post.author)) }.buttonStyle(.plain)
                }
                .font(.mono(10)).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)
        }
        .card(store.focusPost == post.id ? .ember : .line, padding: 16)
    }
}

/// Right column: who's talking, everyone's mood, and the branch timeline.
struct WorldPanel: View {
    @Environment(Store.self) private var store
    var branch: Branch
    /// Off when the big world map is already on screen.
    var showMap = true

    /// Loose 3-column grid with a per-name jitter, so labels never collide.
    static func spot(_ i: Int, _ handle: String) -> CGPoint {
        let h = handle.utf8.reduce(7) { ($0 &* 31 &+ Int($1)) & 0xFFFF }
        return CGPoint(x: i % 3 * 96 + h % 14, y: i / 3 * 40 + h / 14 % 10 + 8)
    }

    var body: some View {
        let live = store.live?.branch == branch.id ? store.live : nil
        let talking = live.map { Set($0.partial.done.map(\.author) + [$0.partial.typing].compactMap { $0 }) }
            ?? Set(branch.posts.filter { $0.round == branch.round }.map(\.author))
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if showMap {
                HStack {
                    Caps("world")
                    Spacer()
                    Text("\(branch.characters.count) agents · \(talking.count) talking").font(.mono(10)).foregroundStyle(Color.muted)
                }
                let spots = Dictionary(uniqueKeysWithValues: branch.characters.enumerated().map { ($1.handle, Self.spot($0, $1.handle)) })
                ZStack(alignment: .topLeading) {
                    Dots(seed: UInt32(branch.round + 3), count: 40)
                    // Ties under the avatars; ember when both ends spoke this round.
                    Canvas { ctx, _ in
                        for c in branch.characters {
                            for other in (c.ties ?? [:]).keys {
                                guard let a = spots[c.handle], let b = spots[other] else { continue }
                                var path = Path()
                                path.move(to: CGPoint(x: a.x + 8, y: a.y + 8))
                                path.addLine(to: CGPoint(x: b.x + 8, y: b.y + 8))
                                let hot = talking.contains(c.handle) && talking.contains(other)
                                ctx.stroke(path, with: .color(hot ? Color.ember.opacity(0.7) : Color.dim.opacity(0.45)),
                                           style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            }
                        }
                    }
                    ForEach(branch.characters) { c in
                        Button { store.go(.character(c.handle)) } label: {
                            HStack(spacing: 5) {
                                Avatar(name: c.handle, size: 18, highlight: talking.contains(c.handle))
                                Text(c.handle).font(.mono(10)).foregroundStyle(talking.contains(c.handle) ? Color.paper : Color.muted)
                                    .lineLimit(1).frame(maxWidth: 62, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .offset(x: spots[c.handle]?.x ?? 0, y: spots[c.handle]?.y ?? 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: CGFloat((branch.characters.count + 2) / 3) * 40 + 24)
                Rectangle().fill(Color.line).frame(height: 1)
                }
                Caps("characters · mood")
                ForEach(branch.characters) { c in
                    Button { store.go(.character(c.handle)) } label: {
                        HStack(spacing: 8) {
                            Avatar(name: c.handle, size: 20)
                            Text(c.handle).font(.mono(11, .semibold)).lineLimit(1).truncationMode(.tail)
                                .frame(width: 84, alignment: .leading)
                            MoodBar(mood: c.mood, cells: 14)
                            Spacer()
                            Text(signed(c.mood)).font(.mono(11)).foregroundStyle(c.mood < 0 ? Color.ember : Color.paper)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                Rectangle().fill(Color.line).frame(height: 1)
                Caps("timeline")
                if let e = store.experiment { BranchTree(experiment: e) }
                if branch.events.isEmpty {
                    Text("· no events").font(.mono(10)).foregroundStyle(Color.muted)
                }
                ForEach(branch.events) { ev in
                    Text("⚡ r\(ev.round) \(ev.text)").font(.mono(10)).foregroundStyle(Color.ember).lineLimit(2)
                }
            }
            .padding(16)
        }
        .background(Color.sidebar)
    }
}

/// Sidebar footer: whose subscription runs the world, how much of it is used, and the pause rule.
struct UsageBlock: View {
    @Environment(Store.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let p = store.settings.characters
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Caps(p == .ollama ? "your local model" : "your subscription")
                Spacer()
                Text("limits ›").font(.mono(10)).foregroundStyle(Color.muted)
            }
            let model = store.settings.model(for: p)
            Text("\(p.label)\(model.isEmpty ? "" : " · \(model)") · \(p.via)").font(.mono(11)).foregroundStyle(Color.paper.opacity(0.8))
            if let u = store.usage[p] {
                row(u.fiveHour, "5h window")
                if let week = u.sevenDay { row(week, "7 days") }
            } else {
                Text(p == .ollama ? "local · no limit" : p == .codex ? "ChatGPT doesn't report usage" : "usage shows after the first call")
                    .font(.mono(10)).foregroundStyle(Color.muted)
            }
            if let until = store.pausedUntil {
                let soon = until.timeIntervalSinceNow < 20 * 3600
                Text("❚❚ paused at your limit · resumes \(soon ? until.formatted(date: .omitted, time: .shortened) : until.formatted(.dateTime.weekday().hour().minute()))")
                    .font(.mono(10)).foregroundStyle(Color.ember)
            } else {
                Text(store.pauseThreshold.map { "auto-pause at \(Int($0 * 100))%" } ?? "auto-pause off")
                    .font(.mono(10)).foregroundStyle(Color.muted)
            }
        }
        .padding(10)
        .background(hover ? Color.panel : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hover = $0 }
        .onTapGesture { store.settingsPane = .limits; openSettings() }
        .help("Limits & pacing")
    }

    @State private var hover = false

    /// The always-visible way into settings, at the bottom of the sidebar.
    struct SettingsRow: View {
        @Environment(Store.self) private var store
        @Environment(\.openSettings) private var openSettings
        @State private var hover = false
        var body: some View {
            Button { store.settingsPane = .providers; openSettings() } label: {
                HStack(spacing: 10) {
                    Text("⚙").font(.mono(13)).foregroundStyle(Color.ember)
                    Text("settings").font(.mono(12, .semibold)).fixedSize()
                    Spacer()
                    Text("⌘,").font(.mono(10)).foregroundStyle(Color.muted)
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(hover ? Color.panel : .clear, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .help("Providers, models, limits, storage")
        }
    }

    private func row(_ v: Double, _ label: String) -> some View {
        HStack(spacing: 8) {
            Meter(value: v, cells: 12)
            Text("\(Int(v * 100))% · \(label)").font(.mono(10)).foregroundStyle(Color.muted)
        }
    }
}

/// The round being written: finished posts appear one by one, the one in progress types out,
/// and before anything arrives the room is visibly "reading".
struct LiveRoundView: View {
    var live: LiveRound
    var branch: Branch

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Rectangle().fill(Color.ember.opacity(0.6)).frame(width: 18, height: 1)
                PulseDot()
                Text("round \(live.round) · live").font(.mono(10)).foregroundStyle(Color.ember)
                TimelineView(.periodic(from: live.started, by: 1)) { ctx in
                    Text("· \(Int(ctx.date.timeIntervalSince(live.started)))s").font(.mono(10)).foregroundStyle(Color.muted)
                }
                Rectangle().fill(Color.ember.opacity(0.25)).frame(height: 1)
            }
            .padding(.top, 8)

            ForEach(Array(live.partial.done.enumerated()), id: \.offset) { _, p in
                PostCard(post: Post(round: live.round, author: p.author, replyTo: replyName(p.replyTo), text: p.text, mood: p.mood ?? 0))
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }

            if let who = live.partial.typing {
                typing(who, draft: live.partial.draft)
            } else {
                reading
            }
        }
        .animation(.easeOut(duration: 0.25), value: live.partial.done.count)
        .animation(.easeOut(duration: 0.2), value: live.partial.typing)
    }

    /// "A3" or a handle → the handle, for the "replied to" line of a streamed post.
    private func replyName(_ ref: String?) -> String? {
        guard let ref else { return nil }
        let r = ref.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        if r.first.map(String.init) == branch.name, let n = Int(r.dropFirst()), n >= 1, n <= branch.posts.count {
            return branch.posts[n - 1].author
        }
        return Engine.handle(ref)
    }

    private func typing(_ who: String, draft: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Avatar(name: who, size: 36, highlight: true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("@\(who)").font(.mono(11, .semibold))
                    Text("is typing").font(.mono(11)).foregroundStyle(Color.ember)
                    TypingDots()
                }
                if !draft.isEmpty {
                    (Text(draft) + Text("▍").foregroundStyle(Color.ember))
                        .font(.display(15, .regular)).foregroundStyle(Color.paper.opacity(0.85))
                }
            }
            Spacer(minLength: 0)
        }
        .card(.ember.opacity(0.5), dashed: true, padding: 16)
    }

    /// Before anyone writes: who could speak, what they're reading, how long it's been.
    private var reading: some View {
        let lastAuthors = Set(branch.posts.filter { $0.round == live.round - 1 }.map(\.author))
        return HStack(alignment: .center, spacing: 14) {
            HStack(spacing: -6) {
                ForEach(Array(branch.characters.prefix(8).enumerated()), id: \.element.id) { i, c in
                    Avatar(name: c.handle, size: 26).modifier(Bob(delay: Double(i) * 0.15))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(live.partial.done.isEmpty ? "the room is reading" : "someone else is about to reply")
                        .font(.mono(11)).foregroundStyle(Color.paper)
                    TypingDots()
                }
                Text(live.streams
                     ? (live.partial.done.isEmpty
                        ? (lastAuthors.isEmpty ? "\(branch.characters.count) people deciding what to say" : "reacting to \(lastAuthors.sorted().map { "@\($0)" }.joined(separator: ", "))")
                        : "\(live.partial.done.count) posted so far")
                     : "ChatGPT answers all at once · the whole round lands together")
                    .font(.mono(10)).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)
        }
        .card(.line, dashed: true, padding: 16)
    }
}

/// Three dots that rise in turn.
struct TypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.ember)
                        .frame(width: 4, height: 4)
                        .opacity(0.35 + 0.65 * max(0, sin((t * 4) - Double(i) * 0.9)))
                        .offset(y: -2 * max(0, sin((t * 4) - Double(i) * 0.9)))
                }
            }
        }
        .accessibilityLabel("typing")
    }
}

struct PulseDot: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { ctx in
            let a = 0.4 + 0.6 * abs(sin(ctx.date.timeIntervalSinceReferenceDate * 2.5))
            Circle().fill(Color.ember).frame(width: 6, height: 6).opacity(a)
        }
    }
}

/// Gentle up-and-down, offset per avatar, so the waiting room looks alive.
private struct Bob: ViewModifier {
    var delay: Double
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
            content.offset(y: -2.5 * max(0, sin(ctx.date.timeIntervalSinceReferenceDate * 3 - delay * 6)))
        }
    }
}
