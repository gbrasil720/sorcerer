import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude, codex, ollama

    var id: String { rawValue }
    var label: String {
        switch self {
        case .claude: "Claude"
        case .codex: "ChatGPT"
        case .ollama: "Ollama"
        }
    }
    var via: String {
        switch self {
        case .claude: "via Claude Code"
        case .codex: "via Codex CLI"
        case .ollama: "localhost:11434"
        }
    }
}

struct Persona: Codable, Identifiable, Hashable {
    var handle: String
    var role: String
    var bio = ""
    var traits: [String: Double] = [:]
    var interests: [String] = []
    var goals: [String] = []
    var mood = 0.0
    var memories: [String] = []
    /// handle → relation ("coworker", "rivals"). Optional so older worlds still load.
    var ties: [String: String]?
    /// Knows the brief's insider facts (employees, partners, friends of the team).
    var insider: Bool?
    /// Chosen in the avatar editor; nil = the default face for this handle.
    var look: Look?
    /// Round they joined in, when someone invited them mid-run; nil = there from the start.
    var joined: Int?
    var id: String { handle }
}

/// What the world knows, fact by fact, and who knows each one.
struct Brief: Codable, Hashable {
    var title: String
    var tagline: String
    var facts: [Fact]

    struct Fact: Codable, Hashable, Identifiable {
        var id = UUID()
        var text: String
        var source: String
        var audience: Audience
    }

    enum Audience: String, Codable, CaseIterable {
        case everyone = "public", insider, hidden
        var next: Audience { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
    }
}

struct Post: Codable, Identifiable, Hashable {
    var id = UUID()
    var round: Int
    var author: String
    var replyTo: String?
    var text: String
    var mood: Double
    /// The post this one answers, when the model cited it by id.
    var replyToPost: UUID?
    var agree: Int?
    var disagree: Int?
}

/// Something a character did, not just said: "cancel Pro", "leave", "invite"…
struct Action: Codable, Identifiable, Hashable {
    var id = UUID()
    var round: Int
    var who: String
    var act: String
    var why: String
}

/// A question put to everyone at once, and what each person answered.
struct Poll: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Asked after this round.
    var round: Int
    var question: String
    var options: [String]
    var answers: [String: Answer] = [:]
    /// Public polls become an event and a memory; off the record (the default) changes nothing.
    var open = false
    /// Ask again every N rounds; nil = once.
    var every: Int?

    struct Answer: Codable, Hashable {
        var pick: String
        var why: String
    }

    func count(_ option: String) -> Int { answers.values.filter { $0.pick == option }.count }
}

struct WorldEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    var round: Int
    var text: String
}

struct Report: Codable, Hashable {
    var headline: String
    var divergence: String?
    var findings: [Finding]
    var questions: [String]
    var branches: [BranchSummary]?
    var updated: Date?
}

/// What a branch amounted to, in the scenario's own terms ("would pay 5 / 6").
struct BranchSummary: Codable, Hashable {
    var name: String
    var summary: String
    var metrics: [Metric]

    struct Metric: Codable, Hashable {
        var label: String
        var value: String
    }
}

/// A report finding plus the post ids ("A3", "B7") that back it up.
struct Finding: Codable, Hashable {
    var text: String
    var refs: [String] = []

    init(text: String, refs: [String] = []) {
        self.text = text
        self.refs = refs
    }

    // Older reports stored findings as plain strings.
    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            text = s
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        refs = try c.decodeIfPresent([String].self, forKey: .refs) ?? []
    }
}

struct Branch: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var parent: String?
    /// Short human label shown next to the letter: "B · $14 + offline".
    var label: String?
    var round = 0
    var characters: [Persona]
    var posts: [Post] = []
    var events: [WorldEvent] = []
    /// Average community mood after each round; index 0 = before round 1.
    var moodByRound: [Double] = []
    /// What people did, round by round. Optional so older worlds still load.
    var actions: [Action]?
    var polls: [Poll]?
}

struct Experiment: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var hypothesis: String
    var context: String
    var branches: [Branch]
    var report: Report?
    var created = Date()
    /// The community as summoned, before any round. Used to export a fresh scenario.
    var cast: [Persona]?
    /// Name of the community ("Lumen customers"), so it can be reused in other experiments.
    var community: String?
    /// Where the conversation happens: social feed, forum, group chat…
    var environment: String?
    var rounds: Int?
    /// Files and links the context was read from.
    var sources: [String]?
    var brief: Brief?
    /// What characters can do besides talking ("subscribe", "cancel"). nil = older experiments, no actions.
    var actions: [String]?
}

struct Settings: Codable, Equatable {
    var onboarded = false
    var characters = Provider.claude
    var reports = Provider.claude
    var chats = Provider.claude
    var ollamaModel = ""
    var maxRounds = 10
    /// Pause a run when a provider's usage window reaches this percent. nil = 90, 0 = never.
    var pauseAt: Int?
    /// Providers switched on in onboarding.
    var enabled: [Provider]?
    /// Slow rounds down so a run fits inside the usage window.
    var spread: Bool?
    /// Pause between rounds while running, in seconds: 12 (½×), 4 (1×) or 0 (max). nil = 4.
    var roundGap: Double?
    /// Provider → model id picked in settings; missing = the tool's default.
    var models: [String: String]?

    func model(for p: Provider) -> String {
        p == .ollama ? (models?[p.rawValue] ?? ollamaModel) : (models?[p.rawValue] ?? "")
    }
}

/// Subscription usage as reported by the provider (Claude Code reports it; others don't).
struct Usage: Hashable {
    var fiveHour: Double
    var sevenDay: Double?
    var resetsAt: Date
    var weekResetsAt: Date?
    var rejected = false
    var peak: Double { max(fiveHour, sevenDay ?? 0) }

    /// When every window over `limit` has reset: the weekly one can be days away.
    func resume(over limit: Double) -> Date {
        if let week = sevenDay, week >= limit, let w = weekResetsAt { return max(w, fiveHour >= limit ? resetsAt : w) }
        return resetsAt
    }
}

struct ChatLine: Hashable {
    var fromUser: Bool
    var text: String
}

let environments = ["social feed", "forum", "group chat", "town square", "workplace"]

struct Template: Identifiable {
    var tag: String
    var question: String
    var count: Int
    var archetypes: [String]
    var context: String
    var rounds = 10
    var environment = "social feed"
    var actions: [String] = []
    var id: String { tag }
    var title: String {
        ["product reactions": "Product reaction", "pricing · A/B": "Pricing A/B", "news spread": "News spread",
         "community rules": "Community rules", "fiction": "Fictional world"][tag] ?? tag
    }

    static let all = [
        Template(
            tag: "product reactions", question: "our customers saw this product tomorrow?", count: 8,
            archetypes: ["early adopters", "skeptics", "budget buyers", "power users"],
            context: "Describe your product here: what it does, who it is for, what it costs.",
            actions: ["sign up", "buy", "recommend it", "ask for a refund"]
        ),
        Template(
            tag: "pricing · A/B", question: "Lumen raised its plan from $9 to $14 a month?", count: 6,
            archetypes: ["freelancers", "power users", "students", "team leads", "skeptics", "early adopters"],
            context: """
            Lumen is a note-taking app that syncs across Mac, iPhone and the web.
            Plans today: Free, and Pro at $9 a month.
            Most users found Lumen through word of mouth; many compare it with free note apps.
            Faster sync is the most requested improvement.
            Insiders only: offline mode is in development, planned for the next release.
            """,
            actions: ["upgrade to Pro", "cancel Pro", "switch to a free app", "recommend Lumen"]
        ),
        Template(
            tag: "news spread", question: "this headline hit the group chat?", count: 8,
            archetypes: ["news junkies", "skeptics", "lurkers", "contrarians"],
            context: "Paste the headline and the article it links to.", rounds: 12, environment: "group chat",
            actions: ["share it", "fact-check it", "mute the chat"]
        ),
        Template(
            tag: "community rules", question: "the forum banned anonymous posts?", count: 8,
            archetypes: ["moderators", "long-time members", "lurkers", "privacy advocates"],
            context: "A mid-size hobby forum where about half the active posters use anonymous accounts.",
            rounds: 8, environment: "forum",
            actions: ["support the rule", "protest", "make a new account"]
        ),
        Template(
            tag: "fiction", question: "a dragon moved into the village?", count: 8,
            archetypes: ["farmers", "the mayor", "a blacksmith", "children", "a traveling bard"],
            context: "Riverside is a quiet village of 200 people by a river. Trade with the city is its lifeline.",
            rounds: 20, environment: "town square",
            actions: ["flee", "take up arms", "bring an offering", "call the guard"]
        ),
    ]
}
