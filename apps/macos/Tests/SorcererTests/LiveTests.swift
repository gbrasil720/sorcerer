@testable import Sorcerer
import XCTest

/// Hits the real CLI. Run with: SORCERER_LIVE=claude swift test --filter LiveTests
final class LiveTests: XCTestCase {
    func testSummonAndOneRound() async throws {
        guard let raw = ProcessInfo.processInfo.environment["SORCERER_LIVE"], let p = Provider(rawValue: raw) else {
            throw XCTSkip("set SORCERER_LIVE=claude|codex|ollama")
        }
        let t = Template.all[1]
        let cast = try Engine.parseSummon(try await AI.complete(
            Engine.summonPrompt(hypothesis: t.question, context: t.context, count: 3, archetypes: t.archetypes, temper: 0.5),
            with: p, ollamaModel: ""
        ).text)
        XCTAssertEqual(cast.count, 3)
        var b = Branch(name: "A", characters: cast)
        let e = Experiment(name: "live", hypothesis: t.question, context: t.context, branches: [b])
        try Engine.apply(try await AI.complete(Engine.roundPrompt(e, b), with: p, ollamaModel: "").text, to: &b)
        XCTAssertEqual(b.round, 1)
        XCTAssertFalse(b.posts.isEmpty)
        for post in b.posts { print("r\(post.round) @\(post.author) [\(post.mood)]: \(post.text)") }
        print("ties:", cast.map { "\($0.handle) → \($0.ties ?? [:])" })

        // Chat and a cited report on the same world.
        let chat = try await AI.complete(
            Engine.chatPrompt(e, b.characters[0], history: [], question: "What would change your mind?"), with: p, ollamaModel: ""
        ).text
        XCTAssertFalse(chat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        print("chat:", chat)
        var done = e
        done.branches = [b]
        let report = try Engine.json(Report.self, from: try await AI.complete(Engine.reportPrompt(done), with: p, ollamaModel: "").text)
        XCTAssertEqual(report.findings.count, 3)
        XCTAssertTrue(report.findings.allSatisfy { !$0.refs.isEmpty && $0.refs.allSatisfy { Engine.resolve($0, in: done) != nil } })
        print("report:", report.headline, report.findings.map(\.refs))
    }
}

final class LiveBriefTests: XCTestCase {
    /// Reads this repo as a local folder and writes a brief from it.
    func testBriefFromLocalFolder() async throws {
        guard let raw = ProcessInfo.processInfo.environment["SORCERER_LIVE"], let p = Provider(rawValue: raw) else {
            throw XCTSkip("set SORCERER_LIVE=claude|codex|ollama")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../..").standardized
        let reading = Sources.readFolder(root)
        XCTAssertFalse(reading.docs.isEmpty)
        XCTAssertFalse(reading.docs.contains { Sources.isSecret($0.name) })
        print("read:", reading.docs.map(\.name), "entries:", reading.entries.map { "\($0.path) \($0.status.rawValue)" })
        let brief = try Engine.parseBrief(try await AI.complete(
            Engine.briefPrompt(hypothesis: "Sorcerer launched a Windows version?", material: reading.docs), with: p, ollamaModel: ""
        ).text)
        XCTAssertGreaterThanOrEqual(brief.facts.count, 5)
        print("brief:", brief.title, "—", brief.tagline)
        for f in brief.facts { print(" [\(f.audience.rawValue)] \(f.text) ↳ \(f.source)") }
    }
}

final class LiveActionTests: XCTestCase {
    /// Plays a few rounds of the pricing template with actions and an event that should move people.
    func testCharactersAct() async throws {
        guard let raw = ProcessInfo.processInfo.environment["SORCERER_LIVE"], let p = Provider(rawValue: raw) else {
            throw XCTSkip("set SORCERER_LIVE=claude|codex|ollama")
        }
        let t = Template.all[1]
        let suggested = try Engine.parseActions(try await AI.complete(
            Engine.suggestActionsPrompt(hypothesis: t.question, context: t.context), with: p, ollamaModel: ""
        ).text)
        print("suggested:", suggested)
        XCTAssertFalse(suggested.isEmpty)
        let cast = try Engine.parseSummon(try await AI.complete(
            Engine.summonPrompt(hypothesis: t.question, context: t.context, count: 5, archetypes: t.archetypes, temper: 0.5),
            with: p, ollamaModel: ""
        ).text)
        var e = Experiment(name: "live", hypothesis: t.question, context: t.context, branches: [])
        e.actions = t.actions
        var b = Branch(name: "A", characters: cast)
        b.events = [WorldEvent(round: 2, text: "Lumen raises Pro to $14 today, with no new features.")]
        for _ in 1...3 {
            let invites = try Engine.apply(try await AI.complete(Engine.roundPrompt(e, b), with: p, ollamaModel: "").text,
                                           to: &b, actions: e.actions)
            print("r\(b.round) invites:", invites)
        }
        for a in b.actions ?? [] { print("r\(a.round) @\(a.who) \(a.act): \(a.why)") }
        print("tally:", Engine.tally(b, t.actions), "away:", Engine.away(b))
        XCTAssertFalse((b.actions ?? []).isEmpty, "nobody acted in 3 rounds")
        XCTAssertTrue((b.actions ?? []).allSatisfy { (t.actions + [Engine.leave, Engine.comeBack, Engine.invite]).contains($0.act) })
    }
}

final class LivePollTests: XCTestCase {
    func testEveryoneAnswers() async throws {
        guard let raw = ProcessInfo.processInfo.environment["SORCERER_LIVE"], let p = Provider(rawValue: raw) else {
            throw XCTSkip("set SORCERER_LIVE=claude|codex|ollama")
        }
        let t = Template.all[1]
        let cast = try Engine.parseSummon(try await AI.complete(
            Engine.summonPrompt(hypothesis: t.question, context: t.context, count: 5, archetypes: t.archetypes, temper: 0.6),
            with: p, ollamaModel: ""
        ).text)
        var b = Branch(name: "A", characters: cast)
        let e = Experiment(name: "live", hypothesis: t.question, context: t.context, branches: [b])
        try Engine.apply(try await AI.complete(Engine.roundPrompt(e, b), with: p, ollamaModel: "").text, to: &b)
        let options = Engine.pollOptions("yes, no, only if offline mode ships")
        let answers = try Engine.parsePoll(try await AI.complete(
            Engine.pollPrompt(e, b, question: "Would you pay $14 a month for Lumen Pro?", options: options), with: p, ollamaModel: ""
        ).text, options: options, in: b)
        for (who, a) in answers.sorted(by: { $0.key < $1.key }) { print("@\(who): \(a.pick) — \(a.why)") }
        XCTAssertEqual(answers.count, cast.count)
    }
}
