import Foundation
import Observation

enum Route: Hashable {
    case new, feed, character(String), report, context
}

/// Where you are: which experiment, which branch, which screen. Back/forward walk these.
struct Place: Hashable {
    var experiment: UUID?
    var branch: UUID?
    var route: Route
}

enum ExportKind { case experiment, bundle, report }

@MainActor @Observable
final class Store {
    var settings = Settings()
    var experiments: [Experiment] = []
    var selected: UUID?
    var branchID: UUID?
    var route = Route.new
    var draft: Template?
    var running = false
    var busy: String?
    var error: String?
    var chats: [String: [ChatLine]] = [:]
    var usage: [Provider: Usage] = [:]
    var pausedUntil: Date?
    /// Post to scroll to and highlight when the feed opens (from a report citation).
    var focusPost: UUID?
    /// Community picked in the sidebar to reuse in a new experiment.
    var reuse: (name: String, cast: [Persona])?
    /// Saved briefs, reusable across experiments (~/Sorcerer/contexts).
    var contexts: [Brief] = []
    /// Brief picked in the sidebar for the new experiment.
    var reuseBrief: Brief?
    /// Open the new experiment on its context page (after onboarding's "add context →").
    var startOnContext = false
    var back: [Place] = []
    var forward: [Place] = []
    /// Last character looked at per experiment, so the Characters tab reopens on them.
    var lastCharacter: [UUID: String] = [:]
    /// Set from any menu or the palette; the workspace shows the save panel.
    var exporting: ExportKind?
    var paletteOpen = false
    /// The round being written right now, shown live in the feed.
    var live: LiveRound?
    /// A character's answer as it streams into the 1:1 chat.
    var chatDraft: (handle: String, text: String)?
    /// Which settings pane to show when the settings window opens (set by shortcuts into it).
    var settingsPane = SettingsPane.providers
    /// Bumped to put the cursor in the feed's inject field (⌘E).
    var focusInject = 0
    /// Round being replayed in the current branch; nil = the present.
    var replay: Int?

    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Sorcerer")
    private static let worlds = root.appendingPathComponent("experiments")
    private static let settingsFile = root.appendingPathComponent("settings.json")
    private static let contextDir = root.appendingPathComponent("contexts")

    init() {
        try? FileManager.default.createDirectory(at: Self.worlds, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Self.settingsFile),
           let s = try? JSONDecoder().decode(Settings.self, from: data) { settings = s }
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.worlds, includingPropertiesForKeys: nil)) ?? []
        experiments = files.compactMap { try? JSONDecoder().decode(Experiment.self, from: Data(contentsOf: $0)) }
            .sorted { $0.created > $1.created }
        try? FileManager.default.createDirectory(at: Self.contextDir, withIntermediateDirectories: true)
        contexts = ((try? FileManager.default.contentsOfDirectory(at: Self.contextDir, includingPropertiesForKeys: nil)) ?? [])
            .compactMap { try? JSONDecoder().decode(Brief.self, from: Data(contentsOf: $0)) }
            .sorted { $0.title < $1.title }
        if let first = experiments.first { apply(Place(experiment: first.id, branch: first.branches.last?.id, route: .feed)) }
    }

    // MARK: persistence

    func saveSettings() {
        try? JSONEncoder().encode(settings).write(to: Self.settingsFile, options: .atomic)
    }

    private func save(_ e: Experiment) {
        try? JSONEncoder().encode(e).write(to: Self.worlds.appendingPathComponent("\(e.id).json"), options: .atomic)
    }

    // MARK: selection

    var experiment: Experiment? { experiments.first { $0.id == selected } }
    var branch: Branch? { experiment?.branches.first { $0.id == branchID } }
    /// The current branch as of the replayed round, or as it is now.
    var shown: Branch? {
        guard let b = branch else { return nil }
        return replay.map { Engine.rewind(b, to: $0, start: experiment?.cast) } ?? b
    }

    // MARK: navigation

    var place: Place { Place(experiment: selected, branch: branchID, route: route) }

    /// Every screen change goes through here so back/forward work everywhere.
    func navigate(_ p: Place) {
        guard p != place else { return }
        back.append(place)
        if back.count > 50 { back.removeFirst() }
        forward = []
        apply(p)
    }

    func go(_ r: Route) { navigate(Place(experiment: selected, branch: branchID, route: r)) }

    func goBack() {
        guard let p = back.popLast() else { return }
        forward.append(place)
        apply(p)
    }

    func goForward() {
        guard let p = forward.popLast() else { return }
        back.append(place)
        apply(p)
    }

    private func apply(_ p: Place) {
        if p.experiment != selected || p.branch != branchID { replay = nil }
        selected = p.experiment
        branchID = p.branch
        route = p.route
        if case .character(let h) = p.route, let id = p.experiment { lastCharacter[id] = h }
    }

    func open(_ id: UUID, branch: UUID? = nil, route: Route = .feed) {
        navigate(Place(experiment: id, branch: branch ?? experiments.first { $0.id == id }?.branches.last?.id, route: route))
    }

    func switchBranch(_ id: UUID) {
        navigate(Place(experiment: selected, branch: id, route: route == .new ? .feed : route))
    }

    /// The Characters tab: whoever you looked at last, else the first person.
    func showCharacters() {
        guard let e = experiment, let b = branch else { return }
        let h = lastCharacter[e.id].flatMap { h in b.characters.contains { $0.handle == h } ? h : nil } ?? b.characters.first?.handle
        if let h { go(.character(h)) }
    }

    func rename(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        mutate { $0.name = n }
    }

    func setBrief(_ brief: Brief?) { mutate { $0.brief = brief } }

    // MARK: looks

    /// A character's saved look in the open experiment, if any.
    func look(of handle: String) -> Look? {
        guard let e = experiment else { return nil }
        for b in e.branches { if let l = b.characters.first(where: { $0.handle == handle })?.look { return l } }
        return e.cast?.first { $0.handle == handle }?.look
    }

    /// Appearance is the same person everywhere: every branch and the saved cast.
    func setLook(_ handle: String, _ look: Look) {
        let saved: Look? = look == .derived(from: handle) ? nil : look
        mutate { e in
            for i in e.branches.indices {
                for j in e.branches[i].characters.indices where e.branches[i].characters[j].handle == handle {
                    e.branches[i].characters[j].look = saved
                }
            }
            for j in (e.cast ?? []).indices where e.cast![j].handle == handle { e.cast![j].look = saved }
        }
    }

    private func mutate(_ f: (inout Experiment) -> Void) {
        guard let i = experiments.firstIndex(where: { $0.id == selected }) else { return }
        f(&experiments[i])
        save(experiments[i])
    }

    private func mutateBranch(_ f: (inout Branch) throws -> Void) rethrows {
        guard let i = experiments.firstIndex(where: { $0.id == selected }),
              let j = experiments[i].branches.firstIndex(where: { $0.id == branchID }) else { return }
        try f(&experiments[i].branches[j])
        save(experiments[i])
    }

    func delete(_ id: UUID) {
        experiments.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Self.worlds.appendingPathComponent("\(id).json"))
        back.removeAll { $0.experiment == id }
        forward.removeAll { $0.experiment == id }
        if selected == id { apply(Place(experiment: nil, branch: nil, route: .new)) }
    }

    // MARK: AI calls

    private func ask(_ prompt: String, _ provider: Provider, _ status: String,
                     onText: (@MainActor (String) -> Void)? = nil) async throws -> String {
        busy = status
        error = nil
        defer { busy = nil }
        do {
            let stream: (@Sendable (String) -> Void)? = onText.map { f in { text in Task { @MainActor in f(text) } } }
            let r = try await AI.complete(prompt, with: provider, ollamaModel: settings.ollamaModel,
                                          model: settings.model(for: provider), onText: stream)
            if let u = r.usage { usage[provider] = u }
            return r.text
        } catch let e as AIError {
            if let u = e.usage { usage[provider] = u }
            // ponytail: unknown reset time (ChatGPT doesn't report one) → retry in 15 min.
            if e.isLimit { pause(until: e.usage?.resume(over: pauseThreshold ?? 1) ?? .now.addingTimeInterval(15 * 60)) }
            throw e
        }
    }

    // MARK: usage control

    /// Fraction of a usage window at which runs pause; nil = never.
    var pauseThreshold: Double? {
        let p = settings.pauseAt ?? 90
        return p == 0 ? nil : Double(p) / 100
    }

    /// Stop the run now and pick it up again on its own once the provider's window resets.
    private func pause(until date: Date) {
        running = false
        pausedUntil = date
        Task {
            try? await Task.sleep(for: .seconds(max(5, date.timeIntervalSinceNow + 30)))
            guard pausedUntil == date else { return }
            pausedUntil = nil
            run()
        }
    }

    func summon(hypothesis: String, context: String, count: Int, archetypes: [String], temper: Double, described: String = "") async -> (name: String?, cast: [Persona]) {
        let prompt = Engine.summonPrompt(hypothesis: hypothesis, context: context, count: count, archetypes: archetypes, temper: temper, described: described)
        do {
            return try Engine.parseCommunity(try await ask(prompt, settings.characters, "drafting \(count) personas…"))
        } catch {
            self.error = error.localizedDescription
            return (nil, [])
        }
    }

    /// Every named community across experiments, newest first, for reuse.
    var communities: [(name: String, cast: [Persona])] {
        var seen = Set<String>()
        return experiments.compactMap { e in
            guard let name = e.community, seen.insert(name).inserted else { return nil }
            return (name, e.cast ?? e.branches.first?.characters ?? [])
        }
    }

    // MARK: context

    func writeBrief(hypothesis: String, material: [(name: String, text: String)]) async -> Brief? {
        do {
            return try Engine.parseBrief(try await ask(
                Engine.briefPrompt(hypothesis: hypothesis, material: material), settings.reports, "writing the brief…"
            ))
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func saveContext(_ brief: Brief) {
        let file = brief.title.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
        try? JSONEncoder().encode(brief).write(to: Self.contextDir.appendingPathComponent("\(file.isEmpty ? "context" : file).json"), options: .atomic)
        contexts.removeAll { $0.title == brief.title }
        contexts.append(brief)
        contexts.sort { $0.title < $1.title }
    }

    func create(hypothesis: String, context: String, cast: [Persona], community: String? = nil,
                environment: String? = nil, rounds: Int? = nil, sources: [String] = [], brief: Brief? = nil) {
        let filler: Set = ["a", "an", "the", "its", "it", "to", "of", "from", "if", "what", "we", "our", "this", "that", "into", "on", "in", "for", "and", "is", "was"]
        let slug = hypothesis.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { !filler.contains($0) }.prefix(3).joined(separator: "-")
        var b = Branch(name: "A", characters: cast)
        b.moodByRound = [Engine.averageMood(b)]
        var e = Experiment(name: slug.isEmpty ? "untitled" : slug, hypothesis: hypothesis, context: context, branches: [b])
        e.cast = cast
        e.community = community
        e.environment = environment
        e.rounds = rounds
        e.sources = sources.isEmpty ? nil : sources
        e.brief = brief
        experiments.insert(e, at: 0)
        save(e)
        open(e.id)
    }

    func step() async {
        replay = nil
        guard let e = experiment, let b = branch else { return }
        let branchID = b.id
        live = LiveRound(branch: branchID, round: b.round + 1, streams: settings.characters != .codex)
        defer { live = nil }
        do {
            let reply = try await ask(Engine.roundPrompt(e, b), settings.characters, "playing round \(b.round + 1)…") { [weak self] text in
                guard let self, self.live?.branch == branchID else { return }
                self.live?.partial = Engine.partialRound(text)
            }
            try mutateBranch { try Engine.apply(reply, to: &$0) }
        } catch {
            if pausedUntil == nil { self.error = error.localizedDescription }
        }
    }

    func run() {
        guard !running else { return }
        replay = nil
        running = true
        pausedUntil = nil
        Task {
            while running, error == nil, let b = branch, b.round < roundLimit {
                await step()
                // Breathing room between rounds so people can read along (the speed control).
                let gap = settings.roundGap ?? 4
                if running, gap > 0, (branch?.round ?? 0) < roundLimit { try? await Task.sleep(for: .seconds(gap)) }
                if running, let limit = pauseThreshold, let u = usage[settings.characters], u.peak >= limit {
                    pause(until: u.resume(over: limit))
                } else if running, settings.spread == true, let u = usage[settings.characters], let b2 = branch {
                    // ponytail: even spacing once half the window is used; a usage-per-round model could plan better.
                    let left = max(1, roundLimit - b2.round)
                    if u.fiveHour > 0.5, u.resetsAt > .now {
                        try? await Task.sleep(for: .seconds(min(600, u.resetsAt.timeIntervalSinceNow / Double(left))))
                    }
                }
            }
            running = false
        }
    }

    func pause() {
        running = false
        pausedUntil = nil
    }

    var roundLimit: Int { experiment?.rounds ?? settings.maxRounds }

    func label(_ branchID: UUID, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        mutate { e in
            if let j = e.branches.firstIndex(where: { $0.id == branchID }) { e.branches[j].label = t.isEmpty ? nil : t }
        }
    }

    // MARK: characters

    func update(_ p: Persona) {
        mutateBranch { b in
            if let i = b.characters.firstIndex(where: { $0.handle == p.handle }) { b.characters[i] = p }
        }
    }

    func duplicate(_ p: Persona) {
        guard let b = branch else { return }
        let taken = Set(b.characters.map(\.handle))
        let handle = (2...).lazy.map { "\(p.handle)\($0)" }.first { !taken.contains($0) }!
        var copy = p
        copy.handle = handle
        copy.ties = [p.handle: "near-twin of"]
        copy.memories = []
        mutateBranch { $0.characters.append(copy) }
        go(.character(handle))
    }

    /// Summons one more person into the current branch.
    func addCharacter() async {
        guard let e = experiment, let b = branch else { return }
        let r = await summon(
            hypothesis: e.hypothesis, context: e.context, count: 1, archetypes: [], temper: 0.5,
            described: "someone new who knows: " + b.characters.map(\.handle).joined(separator: ", ")
        )
        guard var p = r.cast.first else { return }
        if b.characters.contains(where: { $0.handle == p.handle }) { p.handle += "2" }
        mutateBranch { $0.characters.append(p) }
        go(.character(p.handle))
    }

    func inject(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        replay = nil
        mutateBranch { $0.events.append(WorldEvent(round: $0.round + 1, text: t)) }
    }

    /// Fork the round on screen (the replayed one, or now): same people, same memories up to
    /// that round, a new path from there.
    func fork() {
        guard let b = shown, let e = experiment else { return }
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        var copy = b
        copy.id = UUID()
        copy.name = letters[min(e.branches.count, letters.count - 1)]
        copy.parent = "from \(b.name) at r\(b.round)"
        mutate { $0.branches.append(copy) }
        switchBranch(copy.id)
    }

    // MARK: export & import

    /// Full experiment with every branch and round, or a fresh scenario: same question,
    /// context and people, no history, for someone else to run.
    func exportData(fresh: Bool) -> Data? {
        guard var e = experiment else { return nil }
        if fresh {
            var people = e.cast ?? branch?.characters ?? []
            for i in people.indices { people[i].memories = [] }
            var b = Branch(name: "A", characters: people)
            b.moodByRound = [Engine.averageMood(b)]
            e.branches = [b]
            e.report = nil
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(e)
    }

    func reportMarkdown() -> String {
        guard let e = experiment, let r = e.report else { return "" }
        var md = "# What if \(e.hypothesis)\n\n**\(r.headline)**\n\n"
        if let d = r.divergence { md += "## Where they diverged\n\n\(d)\n\n" }
        md += "## Findings\n\n"
        for (i, f) in r.findings.enumerated() {
            md += "\(i + 1). \(f.text)\n"
            for ref in f.refs {
                if let hit = Engine.resolve(ref, in: e) {
                    md += "    - \(hit.branch.name) · r\(hit.post.round) · @\(hit.post.author): \"\(hit.post.text)\"\n"
                }
            }
        }
        md += "\n## Questions to investigate\n\n" + r.questions.map { "- \($0)" }.joined(separator: "\n")
        md += "\n\n_Simulated with Sorcerer. Treat these as hypotheses to investigate, not evidence._\n"
        return md
    }

    func importWorld(_ url: URL) {
        do {
            var e = try JSONDecoder().decode(Experiment.self, from: Data(contentsOf: url))
            e.id = UUID()
            e.created = .now
            if experiments.contains(where: { $0.name == e.name }) { e.name += "-imported" }
            for i in e.branches.indices { e.branches[i].id = UUID() }
            experiments.insert(e, at: 0)
            save(e)
            open(e.id)
        } catch {
            self.error = "Couldn't import \(url.lastPathComponent): not a Sorcerer world."
        }
    }

    /// Jump from a report citation to the post in its branch.
    func focus(_ ref: String) {
        guard let e = experiment, let hit = Engine.resolve(ref, in: e) else { return }
        focusPost = hit.post.id
        navigate(Place(experiment: selected, branch: hit.branch.id, route: .feed))
    }

    /// Off the record by default. In-world, the character remembers the conversation.
    func chat(with p: Persona, _ question: String, inWorld: Bool = false) async {
        guard let e = experiment else { return }
        let history = chats[p.handle] ?? []
        chats[p.handle] = history + [ChatLine(fromUser: true, text: question)]
        do {
            chatDraft = (p.handle, "")
            defer { chatDraft = nil }
            let reply = try await ask(Engine.chatPrompt(e, p, history: history, question: question), settings.chats, "@\(p.handle) is typing…") { [weak self] text in
                // Late chunks can land after the reply is done; only update the draft still open.
                guard let self, self.chatDraft?.handle == p.handle else { return }
                self.chatDraft = (p.handle, text)
            }
            let answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            chats[p.handle, default: []].append(ChatLine(fromUser: false, text: answer))
            if inWorld, let r = branch?.round {
                mutateBranch { b in
                    guard let i = b.characters.firstIndex(where: { $0.handle == p.handle }) else { return }
                    b.characters[i].memories.append("r\(r): someone asked me \"\(question)\"; I said \"\(answer.prefix(140))\"")
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func report() async {
        guard let e = experiment else { return }
        do {
            var r = try Engine.json(Report.self, from: try await ask(Engine.reportPrompt(e), settings.reports, "writing report…"))
            r.updated = .now
            mutate { $0.report = r }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A round in flight: when it started, and what has streamed in so far.
struct LiveRound {
    var branch: UUID
    var round: Int
    /// False for providers that answer all at once (ChatGPT): nothing to show until the end.
    var streams: Bool
    var started = Date()
    var partial = Engine.Partial()
}
