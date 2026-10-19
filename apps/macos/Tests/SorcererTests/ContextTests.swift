@testable import Sorcerer
import XCTest

final class ContextTests: XCTestCase {
    func testSecretsAreNeverRead() {
        let paths = ["README.md", ".env", ".env.local", "config/secrets.yml", "docs/roadmap.md", "certs/server.pem",
                     "node_modules/x/README.md", "src/app.ts", "CHANGELOG.md"]
        let (entries, read) = Sources.classify(paths)
        XCTAssertEqual(read.first, "README.md")
        XCTAssertEqual(Set(read), ["README.md", "CHANGELOG.md", "docs/roadmap.md"])
        XCTAssertFalse(read.contains { Sources.isSecret($0) || Sources.isIgnored($0) })
        XCTAssertTrue(entries.contains { $0.path == ".env" && $0.status == .never })
        XCTAssertTrue(entries.contains { $0.path == "node_modules/" && $0.status == .ignored })
    }

    func testShellQuotingKeepsHostilePathsInert() {
        // Run the quoted value through a real shell: it must come back verbatim, not execute.
        let hostile = "a'; echo PWNED; echo '"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "printf %s " + Sources.quoted(hostile)]
        let out = Pipe()
        p.standardOutput = out
        try? p.run()
        p.waitUntilExit()
        XCTAssertEqual(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), hostile)
    }

    func testInsiderFactsReachOnlyInsiders() {
        var e = Experiment(name: "x", hypothesis: "h", context: "raw", branches: [])
        e.brief = Brief(title: "Lumen", tagline: "notes app", facts: [
            .init(text: "Pro costs $9", source: "README.md", audience: .everyone),
            .init(text: "Offline mode ships next month", source: "roadmap.md", audience: .insider),
            .init(text: "The $14 price is being considered", source: "hypothesis", audience: .hidden),
        ])
        let outsider = Persona(handle: "ada", role: "user")
        var staff = Persona(handle: "dara", role: "team lead")
        staff.insider = true

        let outside = Engine.knowledge(e, [outsider])
        XCTAssertTrue(outside.contains("Pro costs $9"))
        XCTAssertFalse(outside.contains("Offline mode"))
        XCTAssertFalse(outside.contains("$14 price"))

        let both = Engine.knowledge(e, [outsider, staff])
        XCTAssertTrue(both.contains("Only dara know"))
        XCTAssertTrue(both.contains("Offline mode"))
        XCTAssertFalse(both.contains("$14 price"))
    }

    func testBriefParsingDefaultsToPublic() throws {
        let b = try Engine.parseBrief(#"{"title":"Lumen","facts":[{"text":"a","audience":"insider"},{"text":"b","audience":"weird"}]}"#)
        XCTAssertEqual(b.facts.map(\.audience), [.insider, .everyone])
    }

    func testWithoutABriefTheRawContextIsCommonKnowledge() {
        let e = Experiment(name: "x", hypothesis: "h", context: "Lumen costs $9", branches: [])
        XCTAssertTrue(Engine.knowledge(e, []).contains("Lumen costs $9"))
    }
}
