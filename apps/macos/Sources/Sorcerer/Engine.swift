import Foundation

/// Prompts and parsing. Pure functions, so the simulation rules are testable without a model.
enum Engine {
    static let traitNames = ["skepticism", "curiosity", "frugality", "influence", "warmth"]

    /// Models wrap JSON in prose or code fences; take the outermost object.
    static func json<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b else {
            throw AIError(message: "The model didn't reply with JSON. Try again or switch provider.")
        }
        return try JSONDecoder().decode(T.self, from: Data(text[a...b].utf8))
    }

    static func handle(_ raw: String) -> String {
        raw.lowercased().trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    static func clamp(_ v: Double) -> Double { min(1, max(-1, v)) }

    // MARK: summon

    struct SummonOut: Decodable {
        struct P: Decodable {
            var handle: String
            var role: String?
            var bio: String?
            var traits: [String: Double]?
            var interests: [String]?
            var goals: [String]?
            var mood: Double?
            var ties: [String: String]?
            var insider: Bool?
        }
        var community: String?
        var characters: [P]
    }

    static func summonPrompt(hypothesis: String, context: String, count: Int, archetypes: [String], temper: Double, described: String = "") -> String {
        let temperament = temper < 0.35 ? "mostly agreeable" : temper > 0.65 ? "mostly contrarian" : "a balanced mix of agreeable and contrarian"
        return """
        You are the casting director for Sorcerer, a social simulation.
        Hypothesis: What if \(hypothesis)
        What the world knows:
        \(context.isEmpty ? "(nothing yet)" : context)

        \(described.isEmpty ? "" : "Who lives in this world, in the user's words: \(described)\n")Create \(count) distinct characters who would plausibly react to this hypothesis.
        Mix these archetypes: \(archetypes.isEmpty ? "your choice" : archetypes.joined(separator: ", ")).
        Temperament: \(temperament).

        Reply with ONLY JSON, no prose:
        {"community":"2-3 word name for this group, e.g. Lumen customers","characters":[{"handle":"unique lowercase first name","role":"short role · one defining trait","bio":"one sentence","traits":{"skepticism":0.0,"curiosity":0.0,"frugality":0.0,"influence":0.0,"warmth":0.0},"interests":["2-4 short items"],"goals":["2 short goals"],"mood":0.0,"ties":{"other handle":"short relation, e.g. coworker, rivals, roommate, follows their posts"},"insider":false}]}
        Traits are 0..1. mood is -1..1, the character's starting attitude toward the hypothesis.
        Give each character 1-3 ties to other characters in this same list; ties shape who listens to whom.
        Set insider true only for people who would plausibly know internal plans (staff, partners, close friends of the team).
        """
    }

    static func parseSummon(_ text: String) throws -> [Persona] {
        try parseCommunity(text).cast
    }

    static func parseCommunity(_ text: String) throws -> (name: String?, cast: [Persona]) {
        var seen = Set<String>()
        let out = try json(SummonOut.self, from: text)
        let raw = out.characters.filter { p in
            let h = handle(p.handle)
            return !h.isEmpty && seen.insert(h).inserted
        }
        return (out.community, raw.map { p in
            let h = handle(p.handle)
            // Keep only ties to other people who actually exist in this cast.
            let ties = Dictionary((p.ties ?? [:]).map { (handle($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
                .filter { $0.key != h && seen.contains($0.key) }
            return Persona(
                handle: h, role: p.role ?? "", bio: p.bio ?? "",
                traits: (p.traits ?? [:]).mapValues { min(1, max(0, $0)) },
                interests: p.interests ?? [], goals: p.goals ?? [], mood: clamp(p.mood ?? 0),
                ties: ties.isEmpty ? nil : ties, insider: p.insider == true ? true : nil
            )
        })
    }

    // MARK: rounds

    struct RoundOut: Decodable {
        struct P: Decodable {
            var author: String
            var replyTo: String?
            var text: String
            var mood: Double?
        }
        struct Reaction: Decodable {
            var agree: Int?
            var disagree: Int?
        }
        struct A: Decodable {
            var `do`: String
            var why: String?
            /// For invites: who they bring in, in a few words.
            var who: String?
        }
        var posts: [P]
        var memories: [String: String]?
        var reactions: [String: Reaction]?
        var actions: [String: A]?
    }

    // MARK: actions

    /// Built in to every experiment with actions: leaving, coming back and bringing someone in.
    static let leave = "leave", comeBack = "come back", invite = "invite"

    /// Someone a character invited this round, still to be summoned.
    struct Invite: Equatable {
        var by: String
        var who: String
    }

    /// Who has left and not come back.
    static func away(_ b: Branch) -> Set<String> {
        var out = Set<String>()
        for a in b.actions ?? [] {
            if a.act == leave { out.insert(a.who) } else if a.act == comeBack { out.remove(a.who) }
        }
        return out
    }

    /// For each action the experiment defines, how many people's latest action it is
    /// (so "upgrade" then "cancel" counts once, as cancel), in the experiment's order.
    static func tally(_ b: Branch, _ acts: [String]) -> [(act: String, count: Int)] {
        var latest: [String: String] = [:]
        for a in b.actions ?? [] where acts.contains(a.act) { latest[a.who] = a.act }
        return acts.map { act in (act, latest.values.filter { $0 == act }.count) }
    }

    private static func actionsPrompt(_ e: Experiment, _ b: Branch) -> String {
        guard let acts = e.actions else { return "" }
        let gone = away(b).sorted()
        let all = acts + [leave, comeBack, invite]
        return """

        Besides talking, characters can act. Allowed actions: \(all.map { "\"\($0)\"" }.joined(separator: ", ")).
        Only include someone in "actions" when this round changes what they do; never repeat what they last did. Most rounds only one or two people act.
        "\(leave)" means they stop taking part; "\(comeBack)" brings back someone who left; "\(invite)" brings one new person in (say who in "who").
        \(gone.isEmpty ? "" : "These people have left and don't post unless they come back: \(gone.joined(separator: ", ")).")
        """
    }

    /// Stable id of a post inside its branch: "B7" = seventh post of branch B.
    static func ref(_ b: Branch, _ index: Int) -> String { "\(b.name)\(index + 1)" }

    static func roundPrompt(_ e: Experiment, _ b: Branch) -> String {
        let next = b.round + 1
        var did: [String: String] = [:]
        for a in b.actions ?? [] { did[a.who] = "r\(a.round) \(a.act)" }
        let cast = b.characters.map {
            "- \($0.handle) — \($0.role) — mood \(String(format: "%.1f", $0.mood)) — ties: \(($0.ties ?? [:]).map { "\($0.key) (\($0.value))" }.sorted().joined(separator: ", ")) — remembers: \($0.memories.suffix(4).joined(separator: "; "))\(did[$0.handle].map { " — last did: \($0)" } ?? "")"
        }.joined(separator: "\n")
        let start = max(0, b.posts.count - 24)
        let feed = b.posts[start...].enumerated().map { i, p in
            "[\(ref(b, start + i))] r\(p.round) @\(p.author)\(p.replyTo.map { " (to @\($0))" } ?? ""): \(p.text)"
        }.joined(separator: "\n")
        let place = e.environment ?? "social feed"
        let past = b.events.filter { $0.round < next }.map { "r\($0.round): \($0.text)" }.joined(separator: "\n")
        let now = b.events.filter { $0.round == next }.map(\.text).joined(separator: "; ")
        return """
        You run round \(next) of Sorcerer, a social simulation set in a \(place). Play every character, in character.
        Hypothesis being explored: What if \(e.hypothesis)
        \(knowledge(e, b.characters))

        Characters (handle — role — mood -1..1 — ties — memories):
        \(cast)

        Earlier events:
        \(past.isEmpty ? "(none)" : past)
        Happening this round: \(now.isEmpty ? "nothing new" : now)

        Recent conversation, oldest first (post id in brackets):
        \(feed.isEmpty ? "(empty, this is the first round)" : feed)

        Write this round: 2 to \(min(b.characters.count, 6)) short messages fitting a \(place), 1-2 casual, specific sentences each.
        Characters may reply to earlier posts, most often from people they have ties with. Not everyone posts every round.
        Opinions shift gradually, react to events, and spread along ties.
        Characters who stay quiet still react: count how many agree or disagree with recent posts.\(actionsPrompt(e, b))
        Reply with ONLY JSON, no prose:
        {"posts":[{"author":"handle","replyTo":"post id it answers, e.g. A3, or null","text":"...","mood":0.0}],"reactions":{"A3":{"agree":2,"disagree":1}},"memories":{"handle":"one short line this character will remember"}\(e.actions == nil ? "" : #","actions":{"handle":{"do":"one allowed action","why":"short reason in their voice","who":"only for invite"}}"#)}
        mood is the author's attitude toward the hypothesis after posting, -1..1.
        """
    }

    /// What characters may know. With a brief, insider facts reach only insiders and hidden ones nobody;
    /// without one, the raw context is common knowledge.
    static func knowledge(_ e: Experiment, _ people: [Persona]) -> String {
        guard let brief = e.brief else {
            return "What the world knows:\n" + (e.context.isEmpty ? "(nothing)" : e.context)
        }
        let open = brief.facts.filter { $0.audience == .everyone }.map { "- \($0.text)" }
        let inside = brief.facts.filter { $0.audience == .insider }.map { "- \($0.text)" }
        let insiders = people.filter { $0.insider == true }.map(\.handle)
        var s = "What everyone knows about \(brief.title) (\(brief.tagline)):\n" + (open.isEmpty ? "(nothing)" : open.joined(separator: "\n"))
        if !inside.isEmpty && !insiders.isEmpty {
            s += "\nOnly \(insiders.joined(separator: ", ")) know, and may hint at it:\n" + inside.joined(separator: "\n")
        }
        return s + "\nNobody knows anything beyond this. Characters never quote facts they couldn't know."
    }

    // MARK: brief

    struct BriefOut: Decodable {
        struct F: Decodable {
            var text: String
            var source: String?
            var audience: String?
        }
        var title: String
        var tagline: String?
        var facts: [F]
    }

    static func briefPrompt(hypothesis: String, material: [(name: String, text: String)]) -> String {
        let docs = material.map { "=== \($0.name)\n\(String($0.text.prefix(12_000)))" }.joined(separator: "\n\n")
        return """
        You write the brief for Sorcerer, a social simulation: the facts its characters can know.
        Hypothesis that will be explored: What if \(hypothesis)

        Source material, read on the user's Mac:
        \(docs.isEmpty ? "(none)" : docs)

        Write 5 to 9 short, concrete facts about the product, place or situation. Prefer facts that matter for the hypothesis.
        audience: "public" if anyone outside could know it, "insider" if it comes from internal docs (roadmaps, costs, plans),
        "hidden" for the hypothesis itself when it isn't public yet.
        Reply with ONLY JSON, no prose:
        {"title":"name of the product or place","tagline":"one line on what it is","facts":[{"text":"one sentence","source":"file or page it came from","audience":"public"}]}
        Never include secrets, credentials, personal data or code.
        """
    }

    static func parseBrief(_ text: String) throws -> Brief {
        let out = try json(BriefOut.self, from: text)
        return Brief(title: out.title, tagline: out.tagline ?? "", facts: out.facts.map {
            Brief.Fact(text: $0.text, source: $0.source ?? "", audience: Brief.Audience(rawValue: $0.audience ?? "") ?? .everyone)
        })
    }

    /// A round as it's being written: the posts already complete, and who's mid-sentence.
    struct Partial: Equatable {
        struct Done: Equatable { var author: String; var replyTo: String?; var text: String; var mood: Double? }
        var done: [Done] = []
        var typing: String?
        var draft = ""
    }

    /// Reads a round's JSON while it streams in. Complete post objects are decoded; the open one
    /// yields its author and the text so far. Never throws: half a JSON is the normal case here.
    static func partialRound(_ text: String) -> Partial {
        var out = Partial()
        guard let posts = text.range(of: "\"posts\""),
              let open = text[posts.upperBound...].firstIndex(of: "[") else { return out }
        var i = text.index(after: open)
        var depth = 0, inString = false, escaped = false
        var start: String.Index?
        while i < text.endIndex {
            let c = text[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                if depth == 0 { start = i }
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0, let s = start {
                    if let p = try? JSONDecoder().decode(RoundOut.P.self, from: Data(text[s...i].utf8)) {
                        out.done.append(.init(author: handle(p.author), replyTo: p.replyTo, text: p.text, mood: p.mood))
                    }
                    start = nil
                }
            } else if c == "]" && depth == 0 {
                return out // posts array closed
            }
            i = text.index(after: i)
        }
        // An object still open: pull out its author and as much text as has arrived.
        if let s = start {
            let obj = String(text[s...])
            out.typing = field("author", in: obj).map(handle)
            out.draft = field("text", in: obj, partial: true) ?? ""
        }
        return out
    }

    /// Value of a string field in a JSON fragment; with `partial`, also an unterminated one.
    private static func field(_ name: String, in obj: String, partial: Bool = false) -> String? {
        guard let key = obj.range(of: "\"\(name)\""),
              let colon = obj[key.upperBound...].firstIndex(of: ":"),
              let quote = obj[colon...].firstIndex(of: "\"") else { return nil }
        var value = "", escaped = false
        for c in obj[obj.index(after: quote)...] {
            if escaped {
                value.append(c == "n" ? "\n" : c)
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "\"" {
                return value
            } else {
                value.append(c)
            }
        }
        return partial ? value : nil
    }

    /// Applies a model's round to the branch. Unknown authors are dropped, moods clamped.
    /// Applies a round; returns the people characters invited, for the caller to summon.
    @discardableResult
    static func apply(_ text: String, to b: inout Branch, actions acts: [String]? = nil) throws -> [Invite] {
        let out = try json(RoundOut.self, from: text)
        let next = b.round + 1
        let known = Set(b.characters.map(\.handle))
        let goneBefore = away(b)
        var invites: [Invite] = []
        if let acts {
            let allowed = Set((acts + [leave, comeBack, invite]).map { $0.lowercased() })
            for (raw, a) in (out.actions ?? [:]).sorted(by: { $0.key < $1.key }) {
                let who = handle(raw), act = a.do.trimmingCharacters(in: .whitespaces)
                guard known.contains(who), allowed.contains(act.lowercased()) else { continue }
                let name = acts.first { $0.lowercased() == act.lowercased() } ?? act.lowercased()
                // Someone who left can only come back; only someone who left can come back.
                if goneBefore.contains(who) != (name == comeBack) { continue }
                if name == invite {
                    guard invites.isEmpty, let w = a.who, !w.isEmpty else { continue }
                    invites.append(Invite(by: who, who: w))
                }
                b.actions = (b.actions ?? []) + [Action(round: next, who: who, act: name, why: a.why ?? "")]
            }
        }
        // People who were away all round stay silent; a goodbye post the round they leave is fine.
        let silent = goneBefore.intersection(away(b))
        // Reactions point at posts that already existed, so resolve them before appending.
        for (id, r) in out.reactions ?? [:] {
            guard let i = index(of: id, in: b) else { continue }
            b.posts[i].agree = (b.posts[i].agree ?? 0) + max(0, r.agree ?? 0)
            b.posts[i].disagree = (b.posts[i].disagree ?? 0) + max(0, r.disagree ?? 0)
        }
        for p in out.posts {
            let author = handle(p.author)
            guard known.contains(author), !silent.contains(author), !p.text.isEmpty else { continue }
            let mood = clamp(p.mood ?? b.characters.first { $0.handle == author }!.mood)
            // replyTo is a post id ("A3") or, from older prompts and sloppier models, a handle.
            var post = Post(round: next, author: author, text: p.text, mood: mood)
            if let target = p.replyTo, let i = index(of: target, in: b), b.posts[i].author != author {
                post.replyTo = b.posts[i].author
                post.replyToPost = b.posts[i].id
            } else if let h = p.replyTo.map(handle), known.contains(h), h != author {
                post.replyTo = h
            }
            b.posts.append(post)
            if let i = b.characters.firstIndex(where: { $0.handle == author }) { b.characters[i].mood = mood }
        }
        for (raw, line) in out.memories ?? [:] {
            if let i = b.characters.firstIndex(where: { $0.handle == handle(raw) }) {
                // Models sometimes prefix "r3:" themselves; don't double it.
                let clean = line.replacing(#/^\s*r\d+\s*:\s*/#, with: "")
                b.characters[i].memories = Array((b.characters[i].memories + ["r\(next): \(clean)"]).suffix(12))
            }
        }
        if b.moodByRound.isEmpty { b.moodByRound.append(averageMood(b)) }
        b.round = next
        b.moodByRound.append(averageMood(b))
        return invites
    }

    // MARK: polls

    static func pollPrompt(_ e: Experiment, _ b: Branch, question: String, options: [String]) -> String {
        let gone = away(b)
        let people = b.characters.filter { !gone.contains($0.handle) }.map {
            "- \($0.handle) — \($0.role) — mood \(String(format: "%.1f", $0.mood)) — traits: \($0.traits.map { "\($0.key) \(String(format: "%.1f", $0.value))" }.sorted().joined(separator: ", ")) — remembers: \($0.memories.suffix(5).joined(separator: "; "))"
        }.joined(separator: "\n")
        let recent = b.posts.suffix(12).map { "r\($0.round) @\($0.author): \($0.text)" }.joined(separator: "\n")
        return """
        Sorcerer simulates a community exploring: What if \(e.hypothesis)
        \(knowledge(e, b.characters))

        After round \(b.round), everyone is asked, privately and one by one: "\(question)"
        Options: \(options.map { "\"\($0)\"" }.joined(separator: ", "))

        People (handle — role — mood -1..1 — traits — memories):
        \(people)

        What was said lately:
        \(recent.isEmpty ? "(nothing yet)" : recent)

        Answer for each person, in character, from what they know and remember. Don't make them more agreeable than they are;
        it's fine if most pick the same option or if the answers split.
        Reply with ONLY JSON: {"answers":{"handle":{"pick":"one of the options, exactly","why":"one short sentence in their voice"}}}
        """
    }

    /// Answers from known people who are still here, with picks matched to the options.
    static func parsePoll(_ text: String, options: [String], in b: Branch) throws -> [String: Poll.Answer] {
        struct Out: Decodable {
            struct A: Decodable { var pick: String; var why: String? }
            var answers: [String: A]
        }
        let gone = away(b)
        let known = Set(b.characters.map(\.handle)).subtracting(gone)
        var out: [String: Poll.Answer] = [:]
        for (raw, a) in try json(Out.self, from: text).answers {
            let who = handle(raw)
            let p = a.pick.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
            guard known.contains(who), let pick = options.first(where: { $0.lowercased() == p.lowercased() }) else { continue }
            out[who] = Poll.Answer(pick: pick, why: a.why ?? "")
        }
        return out
    }

    /// A poll's answers as they stream in: the ones complete, and whose answer is being written.
    struct PartialPoll: Equatable {
        var done: [(who: String, answer: Poll.Answer)] = []
        var typing: String?
        var pick: String?
        var draft = ""

        static func == (a: Self, b: Self) -> Bool {
            a.done.map(\.who) == b.done.map(\.who) && a.typing == b.typing && a.pick == b.pick && a.draft == b.draft
        }
    }

    /// Reads `{"answers":{"ada":{"pick":..,"why":..},…}}` while it streams. Never throws.
    static func partialPoll(_ text: String) -> PartialPoll {
        var out = PartialPoll()
        guard let key = text.range(of: "\"answers\""), let open = text[key.upperBound...].firstIndex(of: "{") else { return out }
        var i = text.index(after: open)
        var depth = 0, inString = false, escaped = false
        var stringStart: String.Index?, lastString = "", who: String?, start: String.Index?
        while i < text.endIndex {
            let c = text[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" {
                    inString = false
                    if depth == 0, let s = stringStart { lastString = String(text[text.index(after: s)..<i]) }
                }
            } else if c == "\"" {
                inString = true
                stringStart = i
            } else if c == "{" {
                if depth == 0 { start = i; who = handle(lastString) }
                depth += 1
            } else if c == "}" {
                if depth == 0 { return out } // answers closed
                depth -= 1
                if depth == 0, let s = start, let w = who {
                    struct A: Decodable { var pick: String; var why: String? }
                    if let a = try? JSONDecoder().decode(A.self, from: Data(text[s...i].utf8)) {
                        out.done.append((w, Poll.Answer(pick: a.pick, why: a.why ?? "")))
                    }
                    start = nil
                }
            }
            i = text.index(after: i)
        }
        if let s = start, let w = who {
            let obj = String(text[s...])
            out.typing = w
            out.pick = field("pick", in: obj)
            out.draft = field("why", in: obj, partial: true) ?? ""
        }
        return out
    }

    /// Options typed as "yes, no, maybe"; a blank or single option falls back to yes / no / not sure.
    static func pollOptions(_ text: String) -> [String] {
        var seen = Set<String>()
        let opts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return opts.count >= 2 ? Array(opts.prefix(6)) : ["yes", "no", "not sure"]
    }

    /// Recurring polls due after the round just played: their latest run is `every` rounds old.
    static func duePolls(_ b: Branch) -> [Poll] {
        let polls = b.polls ?? []
        let latest = Dictionary(grouping: polls.filter { $0.every != nil }, by: \.question).compactMap { $0.value.max { $0.round < $1.round } }
        return latest.filter { p in b.round - p.round >= (p.every ?? .max) }
    }

    static func suggestActionsPrompt(hypothesis: String, context: String) -> String {
        """
        Sorcerer simulates a small community reacting to: What if \(hypothesis)
        Context: \(context.prefix(2000))
        List 3 to 5 things a person in this community could DO about it (not say), as short verbs the outcome can be counted by.
        Examples: "upgrade to Pro", "cancel", "recommend it", "sign the petition", "move away".
        Don't include leaving, coming back or inviting someone; those always exist.
        Reply with ONLY JSON: {"actions":["..."]}
        """
    }

    static func parseActions(_ text: String) throws -> [String] {
        struct Out: Decodable { var actions: [String] }
        var seen = Set<String>()
        return try json(Out.self, from: text).actions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && ![leave, comeBack, invite].contains($0) && seen.insert($0).inserted }
            .prefix(6).map { $0 }
    }

    private static func index(of ref: String, in b: Branch) -> Int? {
        let r = ref.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        guard r.first.map(String.init) == b.name, let n = Int(r.dropFirst()), n >= 1, n <= b.posts.count else { return nil }
        return n - 1
    }

    /// Each character's mood after every round (index 0 = before round 1), rebuilt from posts:
    /// the last post they wrote in a round sets it, otherwise it carries over.
    static func moodSeries(_ b: Branch, start: [Persona]?) -> [String: [Double]] {
        var out: [String: [Double]] = [:]
        for c in b.characters {
            var m = start?.first { $0.handle == c.handle }?.mood
                ?? b.posts.first { $0.author == c.handle }?.mood ?? c.mood
            var series = [m]
            for r in stride(from: 1, through: max(b.round, 0), by: 1) {
                if let last = b.posts.last(where: { $0.round == r && $0.author == c.handle }) { m = last.mood }
                series.append(m)
            }
            out[c.handle] = series
        }
        return out
    }

    /// The branch as it stood after round `n`: later posts, events and memories gone, everyone's
    /// mood back to what it was then. Used to replay a branch and to fork from a past round.
    static func rewind(_ b: Branch, to n: Int, start: [Persona]?) -> Branch {
        guard n >= 0, n < b.round else { return b }
        let moods = moodSeries(b, start: start)
        var out = b
        out.round = n
        out.posts = b.posts.filter { $0.round <= n }
        out.events = b.events.filter { $0.round <= n || ($0.plannedAt.map { $0 <= n } ?? false) }
        out.chats = b.chats?.mapValues { $0.filter { ($0.round ?? 0) <= n } }.filter { !$0.value.isEmpty }
        out.moodByRound = Array(b.moodByRound.prefix(n + 1))
        out.actions = b.actions?.filter { $0.round <= n }
        out.polls = b.polls?.filter { $0.round <= n }
        out.characters = b.characters.filter { ($0.joined ?? 0) <= n }
        // ponytail: agree/disagree counts are totals, so reactions from later rounds stay on old posts;
        // store reactions per round if replays need exact counts.
        for i in out.characters.indices {
            let h = out.characters[i].handle
            if let m = moods[h], n < m.count { out.characters[i].mood = m[n] }
            out.characters[i].memories = out.characters[i].memories.filter { line in
                guard let r = line.firstMatch(of: #/^r(\d+):/#).flatMap({ Int($0.1) }) else { return true }
                return r <= n
            }
        }
        return out
    }

    static func averageMood(_ b: Branch) -> Double {
        b.characters.isEmpty ? 0 : b.characters.map(\.mood).reduce(0, +) / Double(b.characters.count)
    }

    /// "A3" → third post of branch A.
    static func resolve(_ ref: String, in e: Experiment) -> (branch: Branch, post: Post)? {
        let r = ref.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        guard let letter = r.first, let n = Int(r.dropFirst()),
              let b = e.branches.first(where: { $0.name == String(letter) }),
              n >= 1, n <= b.posts.count else { return nil }
        return (b, b.posts[n - 1])
    }

    // MARK: chat & report

    static func chatPrompt(_ e: Experiment, _ p: Persona, history: [ChatLine], question: String, inWorld: Bool = false) -> String {
        let visible = history.filter { ($0.inWorld ?? false) == inWorld }
        let convo = (visible + [ChatLine(fromUser: true, text: question)])
            .map { "\($0.fromUser ? "you" : p.handle): \($0.text)" }.joined(separator: "\n")
        return """
        You are @\(p.handle), a character in a social simulation. \(p.role). \(p.bio)
        Interests: \(p.interests.joined(separator: ", ")). Goals: \(p.goals.joined(separator: "; ")).
        People you know: \((p.ties ?? [:]).map { "\($0.key) (\($0.value))" }.sorted().joined(separator: ", ")).
        Your memories: \(p.memories.joined(separator: "; "))
        Your mood about "What if \(e.hypothesis)" is \(String(format: "%.1f", p.mood)) on a -1..1 scale.
        \(knowledge(e, [p]))
        Answer in character, in 2-4 sentences. Plain text only. \(inWorld ? "The character will remember this conversation." : "This conversation is off the record and changes nothing in the world.")

        \(convo)
        \(p.handle):
        """
    }

    /// What people did and answered in a branch, for the report.
    private static func actionsAndPolls(_ b: Branch) -> String {
        var s = ""
        if let acts = b.actions, !acts.isEmpty {
            s += "\nActions: " + acts.map { "r\($0.round) @\($0.who) \($0.act)\($0.why.isEmpty ? "" : " (\($0.why))")" }.joined(separator: "; ")
        }
        for p in b.polls ?? [] {
            s += "\nPoll after r\(p.round) \"\(p.question)\": " + p.options.map { "\($0) \(p.count($0))" }.joined(separator: " · ")
                + " — " + p.answers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.pick)" }.joined(separator: ", ")
        }
        return s
    }

    /// Metrics counted from the world rather than judged by the model: actions and the latest run of each poll.
    static func counted(_ e: Experiment, _ b: Branch) -> [BranchSummary.Metric] {
        var out: [BranchSummary.Metric] = []
        let total = b.characters.count
        if let acts = e.actions {
            for t in tally(b, acts) where t.count > 0 { out.append(.init(label: t.act, value: "\(t.count) / \(total)")) }
            let gone = away(b).count
            if gone > 0 { out.append(.init(label: "left", value: "\(gone) / \(total)")) }
        }
        let latest = Dictionary(grouping: b.polls ?? [], by: \.question).compactMap { $0.value.max { $0.round < $1.round } }
        for p in latest.sorted(by: { $0.round < $1.round }) {
            guard let top = p.options.max(by: { p.count($0) < p.count($1) }) else { continue }
            let q = p.question.count > 34 ? p.question.prefix(33) + "…" : Substring(p.question)
            out.append(.init(label: "\(q) · \(top)", value: "\(p.count(top)) / \(p.answers.count)"))
        }
        return Array(out.prefix(6))
    }

    /// How many people's latest action is each one, after every round (index 0 = before round 1).
    static func actionSeries(_ b: Branch, _ acts: [String]) -> [(act: String, counts: [Int])] {
        let rounds = Array(0...max(0, b.round))
        let tallies = rounds.map { r in tally(rewind(b, to: r, start: nil), acts) }
        return acts.enumerated().map { i, a in (a, tallies.map { $0[i].count }) }
    }

    static func reportPrompt(_ e: Experiment) -> String {
        let branches = e.branches.map { b in
            """
            ## Branch \(b.name)\(b.parent.map { " (\($0))" } ?? "") — \(b.round) rounds
            Average mood by round: \(b.moodByRound.map { String(format: "%.2f", $0) }.joined(separator: ", "))
            Final moods: \(b.characters.map { "\($0.handle) \(String(format: "%.1f", $0.mood))" }.joined(separator: ", "))
            Events: \(b.events.filter { $0.round <= b.round }.map { "r\($0.round) \($0.text)" }.joined(separator: "; "))\(actionsAndPolls(b))
            Posts (id in brackets):
            \(b.posts.enumerated().map { "[\(b.name)\($0.offset + 1)] r\($0.element.round) @\($0.element.author): \($0.element.text)" }.joined(separator: "\n"))
            """
        }.joined(separator: "\n\n")
        return """
        You analyze a social simulation. Hypothesis: What if \(e.hypothesis)

        \(branches)

        Reply with ONLY JSON, no prose:
        {"branches":[\(e.branches.map { "{\"name\":\"\($0.name)\",\"summary\":\"what this branch was, max 6 words\",\"metrics\":[{\"label\":\"short label\",\"value\":\"short value\"}]}" }.joined(separator: ","))],"headline":"what happened\(e.branches.count > 1 ? ", comparing branches" : ""), max 20 words","divergence":\(e.branches.count > 1 ? "\"1-2 sentences: where and why the branches split; if they didn't, say so\"" : "null"),"findings":[{"text":"a finding, max 35 words","refs":["post ids that back it, e.g. A3"]}],"questions":["2 questions worth investigating in the real world"]}
        Write exactly 3 findings. Each cites 1-3 post ids from the brackets above.
        For each branch give 2 metrics that matter for this hypothesis, judged from the posts (e.g. "open objections": "2").
        Counted metrics (actions taken, poll results) are added automatically: don't repeat them.
        """
    }
}
