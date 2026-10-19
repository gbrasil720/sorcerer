import SwiftUI

// MARK: feed

struct FeedScreen: View {
    @Environment(Store.self) private var store
    @State private var event = ""
    @State private var who: String? = nil
    @State private var latestOnly = false
    @FocusState private var injecting: Bool
    @State private var view = FeedView.feed
    @State private var asking = false
    @State private var question = ""
    @State private var options = "yes, no, not sure"
    @State private var publicPoll = false
    @State private var every = 0

    enum FeedView: String, CaseIterable { case feed, world, graph }

    var body: some View {
        if let e = store.experiment, let b = store.branch, let shown = store.shown {
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
                    Button(store.replay.map { "⑂ fork from r\($0)" } ?? "⑂ fork") { store.fork() }.buttonStyle(SButton())
                        .disabled(store.busy != nil)
                        .help(store.replay == nil ? "Fork this moment into a new branch" : "Start a new branch from the round you're replaying")
                }
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        filterBar(shown)
                        if b.round > 0 { Timeline(branch: b) }
                        switch view {
                        case .feed: feed(e, shown)
                        case .world: WorldView(branch: shown)
                        case .graph: GraphView(experiment: e, branch: shown)
                        }
                        injectBar(b)
                    }
                    Rectangle().fill(Color.line).frame(width: 1)
                    WorldPanel(branch: shown, showMap: view != .world).frame(width: 320)
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
                    }
                    if b.round == 0, store.replay == nil {
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
                        let acts = (b.actions ?? []).filter { $0.round == r && (who == nil || $0.who == who) }
                        if !events.isEmpty || !posts.isEmpty || !acts.isEmpty {
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
                        ForEach(acts) { ActionLine(action: $0) }
                        ForEach((b.polls ?? []).filter { $0.round == r }) { PollCard(poll: $0) }
                    }
                    if let live = store.live, live.branch == b.id, store.replay == nil {
                        LiveRoundView(live: live, branch: b)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: b.posts.count) { withAnimation { proxy.scrollTo("end") } }
            .onChange(of: store.replay) { withAnimation { proxy.scrollTo("end") } }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Tabs(options: [(false, "⚡ event"), (true, "? ask everyone")], selection: $asking)
                if asking {
                    TextField("Ask everyone something… e.g. Would you pay $14 a month?", text: $question)
                        .textFieldStyle(.plain).font(.mono(12))
                        .focused($injecting)
                        .onSubmit(sendPoll)
                    Button(store.busy == "asking everyone…" ? "asking…" : "ask", action: sendPoll).buttonStyle(SButton(primary: true))
                        .disabled(question.isEmpty || store.busy != nil)
                } else {
                    TextField("Inject an event or change a condition…", text: $event)
                        .textFieldStyle(.plain).font(.mono(12))
                        .focused($injecting)
                        .onSubmit(send)
                    Text("⌘E · ↵ at r\(b.round + 1)").font(.mono(10)).foregroundStyle(Color.muted)
                    Button("inject", action: send).buttonStyle(SButton())
                        .disabled(event.isEmpty)
                }
            }
            if asking {
                HStack(spacing: 14) {
                    Text("options").font(.mono(10)).foregroundStyle(Color.muted)
                    TextField("yes, no, not sure", text: $options).textFieldStyle(.plain).font(.mono(11)).frame(maxWidth: 260)
                    Tabs(options: [(false, "off the record"), (true, "public")], selection: $publicPoll)
                        .help("Off the record: nobody remembers being asked. Public: the poll becomes an event and everyone remembers their answer.")
                    Picker("", selection: $every) {
                        Text("once").tag(0)
                        Text("every round").tag(1)
                        Text("every 2 rounds").tag(2)
                        Text("every 3 rounds").tag(3)
                    }
                    .labelsHidden().fixedSize().font(.mono(11))
                    Spacer()
                    Text("1 call · \(b.characters.count - Engine.away(b).count) people answer").font(.mono(10)).foregroundStyle(Color.muted)
                }
            }
        }
        .onChange(of: store.focusInject) { asking = false; injecting = true }
        .onChange(of: store.focusPoll) { asking = true; injecting = true }
        .onAppear { if store.focusInject > 0 || store.focusPoll > 0 { injecting = true } }
        .card()
        .padding(14)
    }

    private func sendPoll() {
        let q = question, opts = Engine.pollOptions(options)
        guard !q.isEmpty, store.busy == nil else { return }
        question = ""
        Task { await store.poll(q, options: opts, open: publicPoll, every: every == 0 ? nil : every) }
    }

    private func send() {
        store.inject(event)
        event = ""
    }
}

/// Every round of the branch as a strip you can click through, plus a replay that plays the
/// branch back from round 0. Forking while replaying starts the new branch at that round.
struct Timeline: View {
    @Environment(Store.self) private var store
    var branch: Branch
    @State private var playing: Task<Void, Never>?
    @State private var hover: Int?

    var body: some View {
        let at = store.replay ?? branch.round
        HStack(spacing: 10) {
            Button(playing == nil ? "▶ replay" : "❚❚") { playing == nil ? play() : stop() }
                .buttonStyle(.plain).foregroundStyle(Color.ember)
                .help("Play this branch back round by round")
                .disabled(store.running || store.live != nil)
            Text("r0").foregroundStyle(Color.muted)
            HStack(spacing: 2) {
                ForEach(0...branch.round, id: \.self) { r in
                    let mood = r < branch.moodByRound.count ? branch.moodByRound[r] : 0
                    Button { stop(); store.replay = r == branch.round ? nil : r } label: {
                        Rectangle()
                            .fill(r == at ? Color.ember : r < at ? Color.paper.opacity(0.55) : Color.line)
                            .frame(maxWidth: .infinity).frame(height: hover == r ? 14 : 10)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .onHover { hover = $0 ? r : (hover == r ? nil : hover) }
                    .help("Round \(r) · mood \(signed(mood))")
                    .accessibilityLabel("Round \(r)")
                }
            }
            .frame(height: 14)
            .animation(.easeOut(duration: 0.12), value: hover)
            Text("r\(branch.round)").foregroundStyle(Color.muted)
            if let r = store.replay {
                Text("viewing r\(r)").foregroundStyle(Color.ember)
                Button("now ›") { stop(); store.replay = nil }.buttonStyle(.plain).help("Back to the latest round")
            } else {
                Text("now").foregroundStyle(Color.muted)
            }
        }
        .font(.mono(10))
        .padding(.horizontal, 18).padding(.bottom, 8)
        .onDisappear { stop() }
    }

    private func play() {
        if store.replay == nil || store.replay == branch.round { store.replay = 0 }
        playing = Task {
            while let r = store.replay, r < branch.round, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                if Task.isCancelled { return }
                withAnimation { store.replay = r + 1 }
            }
            if !Task.isCancelled { store.replay = nil }
            playing = nil
        }
    }

    private func stop() {
        playing?.cancel()
        playing = nil
    }
}

/// A poll in the feed: the question, a bar per option, and who answered what (click to read why).
struct PollCard: View {
    @Environment(Store.self) private var store
    var poll: Poll
    @State private var open = false

    var body: some View {
        let total = max(1, poll.answers.count)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("?").font(.mono(13, .semibold)).foregroundStyle(Color.ember)
                Text(poll.question).font(.display(15))
                Spacer()
                Text("\(poll.open ? "public" : "off the record")\(poll.every.map { " · every \($0 == 1 ? "round" : "\($0) rounds")" } ?? "") · \(poll.answers.count) answered")
                    .font(.mono(10)).foregroundStyle(Color.muted)
            }
            ForEach(poll.options, id: \.self) { o in
                let n = poll.count(o)
                HStack(spacing: 10) {
                    Text(o).font(.mono(11)).frame(width: 110, alignment: .leading).lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.line)
                            Rectangle().fill(Color.ember.opacity(0.8)).frame(width: geo.size.width * CGFloat(n) / CGFloat(total))
                        }
                    }
                    .frame(height: 8)
                    HStack(spacing: -4) {
                        ForEach(poll.answers.filter { $0.value.pick == o }.map(\.key).sorted(), id: \.self) { Avatar(name: $0, size: 16) }
                    }
                    .frame(width: 90, alignment: .leading)
                    Text("\(n)").font(.mono(11)).frame(width: 20, alignment: .trailing)
                }
            }
            Button(open ? "hide answers" : "why? · read every answer") { withAnimation { open.toggle() } }
                .buttonStyle(.plain).font(.mono(10)).foregroundStyle(Color.muted)
            if open {
                ForEach(poll.answers.sorted { $0.key < $1.key }, id: \.key) { who, a in
                    Button { store.go(.character(who)) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Avatar(name: who, size: 18)
                            Text("@\(who)").font(.mono(11, .semibold)).frame(width: 90, alignment: .leading)
                            Text(a.pick).font(.mono(11)).foregroundStyle(Color.ember).frame(width: 80, alignment: .leading)
                            Text(a.why).font(.display(13, .regular)).foregroundStyle(Color.paper.opacity(0.8))
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card(.ember, padding: 16)
    }
}

/// "@ada cancelled Pro · 'I'll wait for offline'" between the posts of a round.
struct ActionLine: View {
    @Environment(Store.self) private var store
    var action: Action

    var body: some View {
        let icon = action.act == Engine.leave ? "←" : action.act == Engine.comeBack ? "↩" : action.act == Engine.invite ? "+" : "◆"
        HStack(spacing: 10) {
            Text(icon).font(.mono(12)).foregroundStyle(Color.ember).frame(width: 18)
            Button { store.go(.character(action.who)) } label: {
                HStack(spacing: 6) {
                    Avatar(name: action.who, size: 18)
                    Text("@\(action.who)").font(.mono(11, .semibold))
                }
            }
            .buttonStyle(.plain)
            Text(action.act).font(.mono(11, .semibold)).foregroundStyle(Color.ember)
            if !action.why.isEmpty {
                Text("“\(action.why)”").font(.display(13, .regular)).foregroundStyle(Color.paper.opacity(0.75)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ember.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
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
        let away = Engine.away(branch)
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
                                    .opacity(away.contains(c.handle) ? 0.35 : 1)
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
                            if away.contains(c.handle) {
                                Text("left").font(.mono(10)).foregroundStyle(Color.muted)
                            } else {
                                MoodBar(mood: c.mood, cells: 14)
                            }
                            Spacer()
                            Text(signed(c.mood)).font(.mono(11)).foregroundStyle(c.mood < 0 ? Color.ember : Color.paper)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                if let acts = store.experiment?.actions {
                    Rectangle().fill(Color.line).frame(height: 1)
                    ActionTally(branch: branch, acts: acts)
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

/// What people did so far: for each action, how many people it's the latest thing they did.
struct ActionTally: View {
    var branch: Branch
    var acts: [String]

    var body: some View {
        let tally = Engine.tally(branch, acts)
        let present = branch.characters.count - Engine.away(branch).count
        let invited = branch.characters.filter { $0.joined != nil }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Caps("actions")
                Spacer()
                Text("of \(branch.characters.count) people").font(.mono(10)).foregroundStyle(Color.muted)
            }
            if (branch.actions ?? []).isEmpty {
                Text("· nobody has acted yet").font(.mono(10)).foregroundStyle(Color.muted)
            }
            ForEach(tally, id: \.act) { t in row(t.act, t.count) }
            row("still here", present, accent: false)
            if invited > 0 { row("invited in", invited, accent: false) }
        }
    }

    private func row(_ label: String, _ n: Int, accent: Bool = true) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.mono(11)).lineLimit(1).frame(width: 120, alignment: .leading)
            BlockBar(filled: Int((Double(n) / Double(max(1, branch.characters.count)) * 10).rounded()), cells: 10,
                     color: accent ? .ember : .paper)
                .opacity(accent || n > 0 ? 1 : 0.5)
            Spacer()
            Text("\(n)").font(.mono(11)).foregroundStyle(n > 0 && accent ? Color.ember : Color.paper)
        }
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
