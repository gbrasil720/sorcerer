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
