import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// New experiment in three steps, each the same frame: what you fill in on the left,
/// a live picture of the result on the right, back / next at the bottom.
struct NewExperiment: View {
    enum Mode: Hashable { case context, describe, reuse, csv }
    enum Step: Int, CaseIterable {
        case question = 1, context, community
        var title: String { ["question & rules", "context", "community & start"][rawValue - 1] }
    }
    struct Source: Identifiable {
        var name: String
        var kind: String
        var detail: String
        var text = ""
        /// What was read and skipped, for repos and folders.
        var entries: [Sources.Entry] = []
        var id: String { name }
    }

    @Environment(Store.self) private var store
    @State private var step = Step.question
    @State private var hypothesis = ""
    @State private var context = ""
    @State private var sources: [Source] = []
    @State private var link = ""
    @State private var reading = false
    @State private var browsing = false
    @State private var mode = Mode.context
    @State private var described = ""
    @State private var reused: String?
    @State private var count = 6
    @State private var archetypes: [String] = []
    @State private var newArchetype = ""
    @State private var temper = 0.5
    @State private var environment = "social feed"
    @State private var rounds = 10
    @State private var actions: [String] = []
    @State private var newAction = ""
    @State private var suggesting = false
    @State private var template: String?
    @State private var community: String?
    @State private var cast: [Persona] = []
    @State private var dropping = false
    @State private var brief: Brief?
    @State private var repos: [Sources.Repo]?
    @State private var showRepos = false
    @State private var pickingFolder = false
    @State private var writing = false
    @State private var summoning = false
    @State private var pickingCast = false
    @State private var castFile: String?
    @State private var castError: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBar {
                Text("new experiment").font(.mono(12, .semibold))
                Text("· drafts aren't saved until you start").foregroundStyle(Color.muted)
            } trailing: {
                stepper
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Left fills its column and at least the window's height, so flexible blocks
                    // (notes, the cast) stretch instead of leaving a gap below.
                    ScrollView {
                        left.padding(32)
                            .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                    }
                    Rectangle().fill(Color.line).frame(width: 1)
                    right.frame(width: max(420, geo.size.width * 0.4)).frame(maxHeight: .infinity).background(Color.sidebar)
                }
            }
            footer
        }
        .onAppear(perform: applyDraft)
        .onChange(of: store.draft?.id) { applyDraft() }
        .onChange(of: store.reuse?.name) { applyDraft() }
        .onChange(of: store.reuseBrief?.title) { applyDraft() }
        .fileImporter(isPresented: $browsing, allowedContentTypes: [.plainText, .pdf, .commaSeparatedText, .json, .data],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(read) }
        }
        .fileImporter(isPresented: $pickingCast, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let imported = try CastCSV.read(url)
                    cast = imported
                    community = url.deletingPathExtension().lastPathComponent
                    castFile = url.lastPathComponent
                    castError = nil
                } catch { castError = error.localizedDescription }
            case .failure(let error): castError = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { readFolder(url) }
        }
    }

    @ViewBuilder private var left: some View {
        switch step {
        case .question: questionForm
        case .context: sourcesForm
        case .community: communityForm
        }
    }

    @ViewBuilder private var right: some View {
        switch step {
        case .question: summary
        case .context: briefPanel
        case .community: worldPreview
        }
    }

    // MARK: frame

    private func done(_ s: Step) -> Bool {
        switch s {
        case .question: !hypothesis.isEmpty
        case .context: brief != nil || !sources.isEmpty || !context.isEmpty
        case .community: !cast.isEmpty
        }
    }

    private var stepper: some View {
        HStack(spacing: 18) {
            ForEach(Step.allCases, id: \.self) { s in
                let tint = s == step ? Color.ember : done(s) ? Color.paper : Color.muted
                Button { step = s } label: {
                    HStack(spacing: 6) {
                        Text(done(s) && s != step ? "✓" : "\(s.rawValue)").font(.mono(9, .bold))
                            .frame(width: 15, height: 15)
                            .overlay(Circle().stroke(tint, lineWidth: 1))
                        Text(s.title).font(.mono(11, s == step ? .semibold : .regular))
                    }
                    .foregroundStyle(tint)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let prev = Step(rawValue: step.rawValue - 1) {
                Button("← back") { step = prev }.buttonStyle(SButton())
            }
            if let busy = store.busy { Text(busy).font(.mono(11)).foregroundStyle(Color.muted) }
            Spacer()
            switch step {
            case .question:
                if hypothesis.isEmpty { Text("write the question to continue").font(.mono(11)).foregroundStyle(Color.muted) }
                Button("next: context →") { step = .context }.buttonStyle(SButton(primary: true)).disabled(hypothesis.isEmpty)
            case .context:
                if contextSummary == nil {
                    Button("skip, no context") { step = .community }.buttonStyle(.plain).font(.mono(11)).foregroundStyle(Color.muted)
                } else if brief == nil {
                    Text("without a brief, everyone knows all of it").font(.mono(11)).foregroundStyle(Color.muted)
                }
                Button("next: community →") { step = .community }.buttonStyle(SButton(primary: true))
            case .community:
                if cast.isEmpty { Text("summon or import a community to start").font(.mono(11)).foregroundStyle(Color.muted) }
                Button("start simulation →") {
                    store.create(hypothesis: hypothesis, context: rawContext, cast: cast, community: community,
                                 environment: environment, rounds: rounds, sources: sources.map(\.name), brief: brief,
                                 actions: actions)
                }
                .buttonStyle(SButton(primary: true))
                .disabled(cast.isEmpty || hypothesis.isEmpty || store.busy != nil)
            }
        }
        .padding(.horizontal, 24).frame(height: 60)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    // MARK: ① question & rules

    private var questionForm: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 30) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
                Caps("the question")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("What if").font(.display(32)).foregroundStyle(Color.muted)
                    TextField("Lumen raised its plan from $9 to $14 a month?", text: $hypothesis, axis: .vertical)
                        .textFieldStyle(.plain).font(.display(32)).lineLimit(1...4)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Caps("or start from a template")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    ForEach(Template.all) { t in
                        Button { use(t) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(t.title).font(.display(15))
                                (Text("What if ").foregroundStyle(Color.muted) + Text(t.question))
                                    .font(.display(13, .regular)).lineLimit(2).multilineTextAlignment(.leading)
                                Text(t.context.split(separator: "\n").first.map(String.init) ?? "")
                                    .font(.mono(10)).foregroundStyle(Color.muted).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Text(t.archetypes.prefix(4).joined(separator: " · ")).font(.mono(10)).foregroundStyle(Color.ember.opacity(0.8)).lineLimit(1)
                                Text("\(t.count) people · \(t.rounds) rounds · \(t.environment)").font(.mono(10)).foregroundStyle(Color.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                            .card(template == t.id ? .ember : .line, padding: 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Caps("rules")
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("where it happens").font(.mono(10)).foregroundStyle(Color.muted)
                        FlowRow(items: environments) { env in
                            Button { environment = env } label: { Chip(text: env, on: environment == env) }.buttonStyle(.plain)
                        }
                        Text(placeNote).font(.mono(10)).foregroundStyle(Color.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading).card(padding: 16)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("rounds").font(.mono(10)).foregroundStyle(Color.muted)
                        Stepper("\(rounds) rounds", value: $rounds, in: 1...50).font(.mono(13))
                        Text("one round = everyone gets a chance to post or reply").font(.mono(10)).foregroundStyle(Color.muted)
                    }
                    .frame(width: 220, alignment: .topLeading).frame(minHeight: 120, alignment: .topLeading).card(padding: 16)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("speed").font(.mono(10)).foregroundStyle(Color.muted)
                        Tabs(options: [(12.0, "½×"), (4.0, "1×"), (0.0, "max")], selection: Binding(
                            get: { store.settings.roundGap ?? 4 },
                            set: { store.settings.roundGap = $0; store.saveSettings() }
                        ))
                        Text("pause between rounds while running, so you can read along").font(.mono(10)).foregroundStyle(Color.muted)
                    }
                    .frame(width: 220, alignment: .topLeading).frame(minHeight: 120, alignment: .topLeading).card(padding: 16)
                }
                actionsCard
            }
            Spacer(minLength: 0)
        }
    }

    /// What people can do besides talking; each action becomes a count in the feed and the report.
    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("what people can do · counted round by round").font(.mono(10)).foregroundStyle(Color.muted)
                Spacer()
                Button(suggesting ? "suggesting…" : "✦ suggest from the question") {
                    suggesting = true
                    Task {
                        let more = await store.suggestActions(hypothesis: hypothesis, context: context)
                        actions += more.filter { !actions.contains($0) }
                        suggesting = false
                    }
                }
                .buttonStyle(SButton()).disabled(hypothesis.isEmpty || suggesting)
            }
            FlowLayout {
                ForEach(actions, id: \.self) { a in
                    Button { actions.removeAll { $0 == a } } label: { Chip(text: "\(a)  ×") }
                        .buttonStyle(.plain).help("Remove")
                }
                TextField("+ add an action", text: $newAction)
                    .textFieldStyle(.plain).font(.mono(11)).frame(width: 150)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(Capsule().stroke(Color.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .onSubmit {
                        let a = newAction.trimmingCharacters(in: .whitespaces).lowercased()
                        if !a.isEmpty, !actions.contains(a) { actions.append(a) }
                        newAction = ""
                    }
                ForEach([Engine.leave, Engine.comeBack, Engine.invite], id: \.self) { Chip(text: $0, on: false) }
            }
            Text("Leaving, coming back and inviting someone are always possible. People who leave stop posting but stay on the map.")
                .font(.mono(10)).foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).card(padding: 16)
    }

    private var placeNote: String {
        switch environment {
        case "forum": "longer posts, threads, people quote each other"
        case "group chat": "short messages, fast back-and-forth, inside jokes"
        case "town square": "people talk face to face, news travels by word of mouth"
        case "workplace": "colleagues, roles and hierarchy shape who speaks up"
        default: "public posts and replies, anyone can jump in"
        }
    }

    /// Experiments whose question shares at least two meaningful words with this one.
    private var similar: [Experiment] {
        let words = Set(hypothesis.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 })
        guard words.count >= 2 else { return [] }
        return store.experiments.filter { e in
            let other = Set(e.hypothesis.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            return words.intersection(other).count >= 2
        }
    }

    private var summary: some View {
        let p = store.settings.characters
        // One call per round, plus casting, the brief and a report.
        let calls = rounds + 2 + (brief == nil ? 0 : 1)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Caps("what this will be")
                (Text("What if ").foregroundStyle(Color.muted) + Text(hypothesis.isEmpty ? "…?" : hypothesis))
                    .font(.display(22))
                VStack(alignment: .leading, spacing: 6) {
                    row("place", environment)
                    row("length", "\(rounds) rounds")
                    row("context", contextSummary ?? "—")
                    row("community", cast.isEmpty ? "—" : "\(community ?? "community") · \(cast.count) people")
                }
                Rectangle().fill(Color.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    Caps("cost on your subscription")
                    Text("about \(calls) calls to \(p.label)").font(.display(14))
                    if let u = store.usage[p] {
                        HStack(spacing: 8) {
                            Meter(value: u.fiveHour, cells: 16)
                            Text("\(Int(u.fiveHour * 100))% of the 5h window used").font(.mono(10)).foregroundStyle(Color.muted)
                        }
                    } else {
                        Text(p.usageDetail)
                            .font(.mono(10)).foregroundStyle(Color.muted)
                    }
                    Text("Runs pause at \(store.pauseThreshold.map { "\(Int($0 * 100))%" } ?? "never") and resume when the window resets.")
                        .font(.mono(10)).foregroundStyle(Color.muted)
                }
                Rectangle().fill(Color.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 10) {
                    Caps("how it will run")
                    let gap = store.settings.roundGap ?? 4
                    stage("1", "cast the community", "1 call · from your context or description")
                    stage("2", "write the brief", brief == nil && sources.isEmpty ? "optional · only if you add context" : "1 call · facts and who knows them")
                    stage("3", "play \(rounds) rounds", "\(rounds) calls · \(gap == 0 ? "back to back" : "\(Int(gap))s between rounds") · pause, inject or fork anytime")
                    stage("4", "write the report", "1 call · findings linked to the posts behind them")
                    Text("You watch it live in feed, world and graph.").font(.mono(10)).foregroundStyle(Color.muted).padding(.top, 2)
                }
                if !similar.isEmpty {
                    Rectangle().fill(Color.line).frame(height: 1)
                    VStack(alignment: .leading, spacing: 6) {
                        Caps("you've asked something like this")
                        ForEach(similar.prefix(4)) { e in
                            Button { store.open(e.id) } label: {
                                HStack {
                                    Text(e.name).font(.mono(11))
                                    Spacer()
                                    Text("r\(e.branches.map(\.round).max() ?? 0)\(e.report == nil ? "" : " · report ✓")")
                                        .font(.mono(10)).foregroundStyle(Color.muted)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    /// One line on what the world will know, nil when nothing was given.
    private var contextSummary: String? {
        if let b = brief { return "\(b.title) · \(b.facts.count) facts" }
        if !sources.isEmpty { return "\(sources.count) \(sources.count == 1 ? "source" : "sources")\(context.isEmpty ? "" : " + notes"), no brief yet" }
        return context.isEmpty ? nil : "notes only, no brief yet"
    }

    private func stage(_ n: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.mono(10, .bold)).foregroundStyle(Color.ember)
                .frame(width: 22, height: 22).overlay(Circle().stroke(Color.ember.opacity(0.6)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.display(13))
                Text(detail).font(.mono(10)).foregroundStyle(Color.muted)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.mono(10)).foregroundStyle(Color.muted).frame(width: 80, alignment: .leading)
            Text(v).font(.mono(11)).foregroundStyle(v == "—" ? Color.dim : Color.paper)
        }
    }

    // MARK: ② context

    private var sourcesForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teach the world").font(.display(26))
            Text("Characters only react to what they know. Point Sorcerer at your product and it writes a brief: every fact, and who knows it.")
                .font(.display(13, .regular)).foregroundStyle(Color.paper.opacity(0.8))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                tile("⌥", "repository", "README, changelog and docs via your gh login") { Task { repos = await Sources.repos(); showRepos = true } }
                    .popover(isPresented: $showRepos, arrowEdge: .bottom) { repoPicker }
                tile("▤", "local folder", "docs in a folder on this Mac; code and secrets skipped") { pickingFolder = true }
                tile("⎘", "files", "text, markdown, PDF or CSV; or drop them here") { browsing = true }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("◎").font(.mono(14)).foregroundStyle(Color.ember)
                        Text("website").font(.mono(12, .semibold))
                    }
                    TextField("paste a link and press ↵", text: $link).textFieldStyle(.plain).font(.mono(11)).onSubmit(fetchLink)
                    Text("the page's readable text").font(.mono(10)).foregroundStyle(Color.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                .padding(14)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                for item in providers {
                    _ = item.loadObject(ofClass: URL.self) { url, _ in
                        if let url { DispatchQueue.main.async { read(url) } }
                    }
                }
                return true
            }
            .overlay { if dropping { RoundedRectangle(cornerRadius: 8).stroke(Color.ember, lineWidth: 2) } }
            if reading { HStack { ProgressView().controlSize(.small); Text("reading on this Mac…").font(.mono(11)).foregroundStyle(Color.muted) } }
            ForEach(sources) { s in
                if s.entries.isEmpty {
                    HStack {
                        Text(s.kind).font(.mono(11)).foregroundStyle(Color.muted).frame(width: 34, alignment: .leading)
                        Text(s.name).font(.mono(12, .semibold)).lineLimit(1)
                        Spacer()
                        Text("\(s.detail) ✓").font(.mono(11)).foregroundStyle(Color.muted)
                        Button("✕") { sources.removeAll { $0.id == s.id } }.buttonStyle(.plain).foregroundStyle(Color.muted)
                    }
                    .card(padding: 12)
                } else {
                    tree(s)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Caps("notes")
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextEditor(text: $context)
                    .font(.mono(12)).scrollContentBackground(.hidden)
                    .frame(minHeight: 160, maxHeight: .infinity)
                    .card()
                    .overlay(alignment: .topLeading) {
                        if context.isEmpty {
                            Text("Anything else the world should know: prices, plans, who's who, rumors…")
                                .font(.mono(12)).foregroundStyle(Color.muted).padding(19).allowsHitTesting(false)
                        }
                    }
            }
            Text("Everything is read on this Mac. Only the brief is sent when a round needs it.")
                .font(.mono(10)).foregroundStyle(Color.muted)
        }
    }

    // MARK: ③ community & start

    private var communityForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Tabs(options: [(Mode.context, "from context"), (.describe, "describe"), (.reuse, "reuse"), (.csv, "CSV")], selection: $mode)
                Spacer()
                if mode == .context || mode == .describe {
                    HStack(spacing: 14) {
                        Button("−") { count = max(2, count - 1) }.buttonStyle(.plain)
                        Text("\(count) people").font(.mono(12, .semibold))
                        Button("+") { count = min(16, count + 1) }.buttonStyle(.plain)
                    }
                    .font(.mono(13))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.line))
                }
            }
            switch mode {
            case .context:
                VStack(alignment: .leading, spacing: 8) {
                    Text("archetypes to mix").font(.mono(10)).foregroundStyle(Color.muted)
                    FlowLayout(spacing: 6) {
                        ForEach(archetypes, id: \.self) { a in
                            Button { archetypes.removeAll { $0 == a } } label: { Chip(text: "\(a) ✕") }.buttonStyle(.plain)
                        }
                        TextField("+ archetype", text: $newArchetype)
                            .textFieldStyle(.plain).font(.mono(11))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .overlay(Capsule().stroke(Color.line))
                            .frame(width: 140)
                            .onSubmit {
                                let a = newArchetype.trimmingCharacters(in: .whitespaces)
                                if !a.isEmpty, !archetypes.contains(a) { archetypes.append(a) }
                                newArchetype = ""
                            }
                    }
                }
            case .describe:
                TextEditor(text: $described)
                    .font(.display(13, .regular)).scrollContentBackground(.hidden)
                    .frame(minHeight: 80).card()
                    .overlay(alignment: .topLeading) {
                        if described.isEmpty {
                            Text("Who lives here? e.g. a dozen regulars of a climbing gym, mostly students, two owners who disagree.")
                                .font(.display(13, .regular)).foregroundStyle(Color.muted).padding(19).allowsHitTesting(false)
                        }
                    }
            case .csv:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Import 2–16 characters from a UTF-8 CSV.").font(.display(16))
                    Text("Required: handle, role, bio. Optional: interests, goals, mood, insider. Separate interests and goals with |.")
                        .font(.mono(11)).foregroundStyle(Color.muted)
                    Text("No model call to import. Character details go to your chosen provider when used in a simulation or chat.")
                        .font(.mono(10)).foregroundStyle(Color.muted)
                    HStack {
                        Button(castFile.map { "replace \($0)…" } ?? "choose CSV…") { pickingCast = true }
                            .buttonStyle(SButton()).disabled(summoning || store.busy != nil)
                        Button("copy example") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(CastCSV.example, forType: .string)
                        }.buttonStyle(SButton())
                    }
                    if let castError { Text(castError).font(.mono(11)).foregroundStyle(Color.ember) }
                    Text("An import replaces the draft cast after validation. Traits start unset and ties empty; review the people below before starting.")
                        .font(.mono(10)).foregroundStyle(Color.muted)
                }.card(padding: 14)
            case .reuse:
                if store.communities.isEmpty {
                    Text("Communities you summon are saved here to reuse in other experiments.")
                        .font(.mono(11)).foregroundStyle(Color.muted)
                }
                ForEach(store.communities, id: \.name) { c in
                    Button { reused = c.name; community = c.name; cast = freshen(c.cast) } label: {
                        HStack {
                            HStack(spacing: -4) { ForEach(c.cast.prefix(6)) { Avatar(name: $0.handle, size: 20) } }
                            Text(c.name).font(.display(13))
                            Spacer()
                            Text("\(c.cast.count) people").font(.mono(10)).foregroundStyle(Color.muted)
                        }
                        .card(reused == c.name ? .ember : .line, padding: 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            if mode == .context || mode == .describe {
                HStack(spacing: 12) {
                    Text("agreeable").font(.mono(11)).foregroundStyle(Color.muted)
                    Slider(value: $temper).frame(maxWidth: 240)
                    Text("contrarian").font(.mono(11)).foregroundStyle(Color.muted)
                    Spacer()
                    Button(summoning ? "summoning…" : cast.isEmpty ? "summon \(count) people" : "summon again") { Task { await summon() } }
                        .buttonStyle(SButton(primary: cast.isEmpty))
                        .disabled(hypothesis.isEmpty || store.busy != nil)
                }
            }
            if cast.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Caps("the cast")
                    ForEach(0..<(mode == .csv ? 2 : min(count, 6)), id: \.self) { i in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.line).frame(width: 28, height: 28)
                            RoundedRectangle(cornerRadius: 3).fill(Color.line).frame(width: CGFloat([90, 70, 110, 80, 100, 60][i]), height: 9)
                            RoundedRectangle(cornerRadius: 3).fill(Color.line.opacity(0.6)).frame(width: CGFloat([180, 220, 150, 200, 170, 210][i]), height: 9)
                        }
                    }
                    Text(mode == .csv ? "Choose a CSV to preview your characters here before starting." : "Your \(count) people appear here after summoning. You can rename roles, mark insiders and remove anyone before round 1.")
                        .font(.mono(10)).foregroundStyle(Color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .card(.line, dashed: true, padding: 14)
                if mode != .csv {
                    VStack(alignment: .leading, spacing: 12) {
                        Caps("each person comes with")
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                            trait("personality", "skepticism, curiosity, frugality, influence, warmth")
                            trait("a starting mood", "how they feel about the question before anyone posts")
                            trait("interests & goals", "what they care about and want out of this")
                            trait("ties", "1–3 people they know: coworkers, rivals, friends")
                            trait("memory", "one line per round, so opinions build over time")
                            trait("insider or not", "insiders know the brief's insider facts")
                        }
                    }
                    .card(padding: 16)
                }
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Caps("the cast · edit anyone before round 1")
                        Spacer()
                        if brief?.facts.contains(where: { $0.audience == .insider }) == true {
                            Text("insiders know the brief's insider facts").font(.mono(10)).foregroundStyle(Color.muted)
                        }
                    }
                    ForEach($cast) { $p in
                        HStack(alignment: .top, spacing: 12) {
                            Avatar(name: p.handle, size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text("@\(p.handle)").font(.mono(12, .semibold)).frame(width: 96, alignment: .leading)
                                    TextField("role", text: $p.role).textFieldStyle(.plain).font(.mono(11)).foregroundStyle(Color.paper.opacity(0.85))
                                }
                                if !p.bio.isEmpty { Text(p.bio).font(.display(12, .regular)).foregroundStyle(Color.muted).lineLimit(2) }
                                if let ties = p.ties, !ties.isEmpty {
                                    Text("knows " + ties.keys.sorted().map { "@\($0)" }.joined(separator: ", ")).font(.mono(10)).foregroundStyle(Color.dim)
                                }
                            }
                            Text(signed(p.mood)).font(.mono(10)).foregroundStyle(p.mood < 0 ? Color.ember : Color.muted)
                            Button { p.insider = p.insider == true ? nil : true } label: {
                                Text(p.insider == true ? "insider" : "outsider").font(.mono(10))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .foregroundStyle(p.insider == true ? Color.ember : Color.muted)
                                    .overlay(Capsule().stroke(p.insider == true ? Color.ember : Color.line))
                            }
                            .buttonStyle(.plain).help("Insiders know the brief's insider facts")
                            Button("✕") { cast.removeAll { $0.id == p.id } }.buttonStyle(.plain).font(.mono(10)).foregroundStyle(Color.muted)
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.line.opacity(0.5)).frame(height: 1) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .card(padding: 14)
            }
        }
    }

    private var worldPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Caps("the world")
                Spacer()
                if summoning { Text("summoning…").font(.mono(10)).foregroundStyle(Color.ember) }
            }
            GeometryReader { geo in
                let spots = WorldView.layout(cast.map(\.handle), in: geo.size)
                ZStack(alignment: .topLeading) {
                    Dots(seed: UInt32(cast.count + 11), count: 90)
                    Canvas { ctx, _ in
                        for c in cast {
                            for other in (c.ties ?? [:]).keys {
                                guard let a = spots[c.handle], let b = spots[other] else { continue }
                                var path = Path()
                                path.move(to: a)
                                path.addLine(to: b)
                                ctx.stroke(path, with: .color(Color.dim.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            }
                        }
                    }
                    ForEach(cast) { c in
                        VStack(spacing: 3) {
                            Avatar(name: c.handle, size: 30, highlight: c.insider == true)
                            Text(c.handle).font(.mono(10)).foregroundStyle(Color.muted)
                        }
                        .position(spots[c.handle] ?? .zero)
                    }
                    if cast.isEmpty {
                        Text("Summon or import a community and it appears here.")
                            .font(.mono(11)).foregroundStyle(Color.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .card()
            Caps("ready to start")
            review("question", hypothesis.isEmpty ? nil : hypothesis, .question)
            review("rules", "\(environment) · \(rounds) rounds\(actions.isEmpty ? "" : " · " + actions.joined(separator: ", "))", .question)
            review("context", contextSummary, .context)
            review("community", cast.isEmpty ? nil : "\(cast.count) people · \(cast.reduce(0) { $0 + ($1.ties?.count ?? 0) }) ties · \(cast.filter { $0.insider == true }.count) \(cast.filter { $0.insider == true }.count == 1 ? "insider" : "insiders")", .community)
        }
        .padding(20)
    }

    private func review(_ k: String, _ v: String?, _ s: Step) -> some View {
        Button { step = s } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(v == nil ? "○" : "✓").foregroundStyle(v == nil ? Color.dim : Color.ember)
                Text(k).foregroundStyle(Color.muted).frame(width: 80, alignment: .leading)
                Text(v ?? (s == .context ? "none, characters know only the question" : "missing")).lineLimit(1)
                    .foregroundStyle(v == nil ? Color.dim : Color.paper)
                Spacer()
            }
            .font(.mono(11))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func trait(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.display(13))
            Text(detail).font(.mono(10)).foregroundStyle(Color.muted)
        }
    }

    private func use(_ t: Template) {
        template = t.id
        hypothesis = t.question
        context = t.context
        count = t.count
        archetypes = t.archetypes
        rounds = t.rounds
        environment = t.environment
        actions = t.actions
        mode = .context
        cast = []
    }

    // MARK: context helpers

    /// Everything read so far plus the typed notes: the material a brief is written from.
    private var material: [(name: String, text: String)] {
        sources.map { ($0.name, $0.text) } + (context.isEmpty ? [] : [("notes", context)])
    }

    /// Raw context, kept for experiments without a brief.
    private var rawContext: String {
        material.map { "# \($0.name)\n\($0.text)" }.joined(separator: "\n\n")
    }

    /// The casting director sees every fact, so it can cast insiders.
    private var castingContext: String {
        guard let brief else { return rawContext }
        return "\(brief.title): \(brief.tagline)\n" + brief.facts.map { "- [\($0.audience.rawValue)] \($0.text)" }.joined(separator: "\n")
    }

    private func tile(_ icon: String, _ title: String, _ detail: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(icon).font(.mono(14)).foregroundStyle(Color.ember)
                    Text("+ \(title)").font(.mono(12, .semibold))
                }
                Text(detail).font(.mono(10)).foregroundStyle(Color.muted).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(reading)
    }

    private func addButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.mono(11))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(reading)
    }

    private func tree(_ s: Source) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("⌥").font(.mono(13)).foregroundStyle(Color.ember)
                    .frame(width: 30, height: 30).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.line))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.mono(12, .semibold))
                    Text(s.kind).font(.mono(10)).foregroundStyle(Color.muted)
                }
                Spacer()
                Text("✓ \(s.entries.filter { $0.status == .read }.count) docs").font(.mono(11))
                Button("✕") { sources.removeAll { $0.id == s.id } }.buttonStyle(.plain).foregroundStyle(Color.muted)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(s.entries) { e in
                    HStack {
                        Text("├── \(e.path)").lineLimit(1)
                        Spacer()
                        Text(e.status.rawValue).foregroundStyle(e.status == .read ? Color.paper : Color.muted)
                    }
                    .font(.mono(11)).foregroundStyle(e.status == .read ? Color.paper : Color.muted)
                }
            }
            Text("Read on this Mac. Characters see the brief, never your code.").font(.mono(10)).foregroundStyle(Color.muted)
        }
        .card(padding: 14)
    }

    private var repoPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Caps("your repositories · via gh CLI")
            if let repos {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(repos) { r in
                            Button { showRepos = false; readRepo(r.nameWithOwner) } label: {
                                HStack {
                                    Text("○ \(r.nameWithOwner)").font(.mono(11))
                                    Spacer()
                                    Text("\(r.isPrivate ? "private · " : "")\(r.updatedAt.formatted(.relative(presentation: .named)))")
                                        .font(.mono(10)).foregroundStyle(Color.muted)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 260)
            } else {
                Text("Couldn't list repositories. Install the GitHub CLI and run `gh auth login`, or add a local folder instead.")
                    .font(.mono(11)).foregroundStyle(Color.muted)
            }
        }
        .padding(14).frame(width: 420)
    }

    private var briefPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Caps("the brief · what the world knows")
                Spacer()
                Text("click a tag to change who knows it").font(.mono(10)).foregroundStyle(Color.muted)
            }
            if writing {
                HStack { ProgressView().controlSize(.small); Text("writing the brief…").font(.mono(11)).foregroundStyle(Color.muted) }
            }
            if let b = brief {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Title", text: Binding(get: { b.title }, set: { brief?.title = $0 }))
                            .textFieldStyle(.plain).font(.display(28))
                        TextField("Tagline", text: Binding(get: { b.tagline }, set: { brief?.tagline = $0 }), axis: .vertical)
                            .textFieldStyle(.plain).font(.display(14, .regular)).foregroundStyle(Color.paper.opacity(0.8))
                        ForEach(b.facts) { f in
                            HStack(alignment: .top, spacing: 14) {
                                Button { cycle(f.id) } label: { AudienceTag(audience: f.audience) }.buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(f.text).font(.display(14, .regular))
                                        .foregroundStyle(f.audience == .hidden ? Color.muted : Color.paper)
                                    if !f.source.isEmpty { Text("↳ \(f.source)").font(.mono(10)).foregroundStyle(Color.muted) }
                                }
                                Spacer()
                                Button("✕") { brief?.facts.removeAll { $0.id == f.id } }.buttonStyle(.plain).font(.mono(10)).foregroundStyle(Color.muted)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            } else if !writing {
                // What a brief looks like, so the empty half explains itself.
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.line).frame(width: 160, height: 22)
                    RoundedRectangle(cornerRadius: 3).fill(Color.line.opacity(0.6)).frame(width: 300, height: 10)
                    ForEach(Array([Brief.Audience.everyone, .everyone, .insider, .everyone, .hidden].enumerated()), id: \.offset) { i, a in
                        HStack(spacing: 14) {
                            AudienceTag(audience: a).opacity(0.6)
                            RoundedRectangle(cornerRadius: 3).fill(Color.line).frame(width: CGFloat([260, 210, 280, 190, 240][i]), height: 10)
                        }
                    }
                }
                .padding(.vertical, 8)
                Text(sources.isEmpty && context.isEmpty
                     ? "Add a repository, folder, website or files on the left, or write notes. Sorcerer turns them into facts like these, each public, insider or hidden."
                     : "Your sources are ready. Sorcerer turns them into facts like these, each public, insider or hidden.")
                    .font(.mono(11)).foregroundStyle(Color.muted)
            }
            if brief != nil { Spacer(minLength: 0) }
            HStack {
                Button(brief == nil ? "write the brief from \(material.count) \(material.count == 1 ? "source" : "sources")" : "regenerate") { Task { await write() } }
                    .buttonStyle(SButton(primary: brief == nil))
                    .disabled(writing || store.busy != nil || (sources.isEmpty && context.isEmpty) || hypothesis.isEmpty)
                if let b = brief {
                    Button("save as “\(b.title)” context") { store.saveContext(b) }.buttonStyle(SButton())
                }
            }
            if brief == nil {
                Rectangle().fill(Color.line).frame(height: 1).padding(.top, 10)
                Caps("who knows what")
                audienceRow(.everyone, "everyone", "Common knowledge: the product, prices, anything public.")
                audienceRow(.insider, "only insiders", "Staff, partners, close friends of the team. They may hint at it, others can only guess.")
                audienceRow(.hidden, "nobody", "Usually the thing you're testing: characters react to it only once you inject it as an event.")
                Spacer(minLength: 0)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func audienceRow(_ a: Brief.Audience, _ who: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AudienceTag(audience: a)
            VStack(alignment: .leading, spacing: 3) {
                Text(who).font(.display(13))
                Text(detail).font(.mono(10)).foregroundStyle(Color.muted)
            }
        }
    }

    private func cycle(_ id: UUID) {
        guard let i = brief?.facts.firstIndex(where: { $0.id == id }) else { return }
        brief?.facts[i].audience = brief!.facts[i].audience.next
    }

    private func write() async {
        writing = true
        defer { writing = false }
        if let b = await store.writeBrief(hypothesis: hypothesis, material: material) { brief = b }
    }

    private func readRepo(_ name: String) {
        reading = true
        Task {
            defer { reading = false }
            do {
                let r = try await Sources.readRepo(name)
                sources.removeAll { $0.name == r.name }
                sources.append(Source(name: r.name, kind: r.kind, detail: "\(r.docs.count) docs",
                                      text: r.docs.map { "## \($0.name)\n\($0.text)" }.joined(separator: "\n\n"), entries: r.entries))
            } catch {
                store.error = error.localizedDescription
            }
        }
    }

    private func readFolder(_ url: URL) {
        reading = true
        Task.detached {
            let r = Sources.readFolder(url)
            await MainActor.run {
                reading = false
                sources.removeAll { $0.name == r.name }
                sources.append(Source(name: r.name, kind: r.kind, detail: "\(r.docs.count) docs",
                                      text: r.docs.map { "## \($0.name)\n\($0.text)" }.joined(separator: "\n\n"), entries: r.entries))
            }
        }
    }

    // MARK: actions

    private func summon() async {
        summoning = true
        defer { summoning = false }
        let r = await store.summon(hypothesis: hypothesis, context: castingContext, count: count, archetypes: archetypes,
                                   temper: temper, described: mode == .describe ? described : "")
        if !r.cast.isEmpty {
            cast = r.cast
            community = r.name
        }
    }

    /// A reused community starts clean: no memories from the other world.
    private func freshen(_ people: [Persona]) -> [Persona] {
        people.map { var p = $0; p.memories = []; return p }
    }

    /// Sidebar shortcuts and onboarding land on the step they fill.
    private func applyDraft() {
        if let t = store.draft {
            use(t)
            step = .question
            store.draft = nil
        }
        if let b = store.reuseBrief {
            brief = b
            step = .context
            store.reuseBrief = nil
        }
        if store.startOnContext {
            step = .context
            store.startOnContext = false
        }
        if let c = store.reuse {
            mode = .reuse
            reused = c.name
            community = c.name
            cast = freshen(c.cast)
            step = .community
            store.reuse = nil
        }
    }

    private func add(_ name: String, _ kind: String, _ text: String) {
        // ponytail: whole file goes in the context; chunk/summarize when people drop books.
        let clipped = String(text.prefix(20_000))
        let detail = kind == "csv" ? "\(clipped.split(separator: "\n").count - 1) rows" : "\(max(1, clipped.count / 1000)) KB"
        sources.removeAll { $0.name == name }
        sources.append(Source(name: name, kind: kind, detail: detail, text: clipped))
    }

    private func read(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf", let doc = PDFDocument(url: url), let text = doc.string {
            add(url.lastPathComponent, "pdf", text)
            sources[sources.count - 1].detail = "\(doc.pageCount) pages"
        } else if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            add(url.lastPathComponent, ext.isEmpty ? "txt" : ext, text)
        } else {
            store.error = "Couldn't read \(url.lastPathComponent) as text."
        }
    }

    /// Paste a link: fetch the page and keep its readable text.
    private func fetchLink() {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true else { return }
        reading = true
        Task {
            defer { reading = false }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let page = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                           .characterEncoding: String.Encoding.utf8.rawValue],
                                                     documentAttributes: nil)
            else { store.error = "Couldn't read \(url.host() ?? "that link")."; return }
            add(url.host() ?? url.absoluteString, "www", page.string)
            link = ""
        }
    }
}

/// Wrapping row of chips.
struct FlowRow<Content: View>: View {
    var items: [String]
    @ViewBuilder var content: (String) -> Content
    var body: some View {
        FlowLayout { ForEach(items, id: \.self) { content($0) } }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? 600, subviews)
        return CGSize(width: proposal.width ?? 600, height: rows.last.map { $0.y + $0.h } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var i = 0
        for row in arrange(bounds.width, subviews) {
            for x in row.xs {
                subviews[i].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
                i += 1
            }
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(xs: [CGFloat], y: CGFloat, h: CGFloat)] {
        var rows: [(xs: [CGFloat], y: CGFloat, h: CGFloat)] = []
        var x: CGFloat = 0, y: CGFloat = 0, h: CGFloat = 0, xs: [CGFloat] = []
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, !xs.isEmpty {
                rows.append((xs, y, h)); y += h + spacing; x = 0; h = 0; xs = []
            }
            xs.append(x); x += size.width + spacing; h = max(h, size.height)
        }
        if !xs.isEmpty { rows.append((xs, y, h)) }
        return rows
    }
}

/// public / insider / hidden pill, as in the brief.
struct AudienceTag: View {
    var audience: Brief.Audience
    var body: some View {
        Text(audience.rawValue).font(.mono(10))
            .frame(width: 64).padding(.vertical, 5)
            .foregroundStyle(audience == .insider ? Color.ember : audience == .hidden ? Color.dim : Color.paper)
            .overlay(Capsule().stroke(audience == .insider ? Color.ember : Color.line))
    }
}
