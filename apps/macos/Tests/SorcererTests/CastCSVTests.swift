@testable import Sorcerer
import XCTest

final class CastCSVTests: XCTestCase {
    private func parse(_ text: String) throws -> [Persona] { try CastCSV.parse(Data(text.utf8)) }
    private let simple = "handle,role,bio\nada,student,Uses free notes\nben,freelancer,Wants faster sync"

    func testExampleBackgroundReachesRoundsPollsAndChats() throws {
        let cast = try parse(CastCSV.example)
        let b = Branch(name: "A", characters: cast)
        let e = Experiment(name: "CSV", hypothesis: "A new plan?", context: "", branches: [b])
        for prompt in [Engine.roundPrompt(e, b), Engine.pollPrompt(e, b, question: "Why?", options: ["yes", "no"]),
                       Engine.chatPrompt(e, cast[0], history: [], question: "Why?")] {
            XCTAssertTrue(prompt.contains("Uses free notes, compares every price"))
            XCTAssertTrue(prompt.contains("notes, music"))
            XCTAssertTrue(prompt.contains("save money"))
        }
    }

    func testRequiredColumnsAndDefaults() throws {
        let cast = try parse(simple)
        XCTAssertEqual(cast.map(\.handle), ["ada", "ben"])
        XCTAssertEqual(cast[0].role, "student")
        XCTAssertEqual(cast[0].bio, "Uses free notes")
        XCTAssertTrue(cast[0].traits.isEmpty)
        XCTAssertTrue(cast[0].memories.isEmpty)
        XCTAssertTrue(cast[0].goals.isEmpty)
        XCTAssertNil(cast[0].ties)
        XCTAssertNil(cast[0].insider)
        XCTAssertEqual(cast[0].mood, 0)
    }

    func testQuotedFieldsBOMCRLFAndOptionalColumns() throws {
        let cast = try parse("\u{FEFF}BIO,handle,role,interests,goals,mood,insider\r\n\"Says \"\"hello, world\"\"\r\nUses notes\",@ADA,student,notes | music,save money,-0.5,TRUE\r\nWriter,Ben,freelancer,,,1,false\r\n")
        XCTAssertEqual(cast[0].handle, "ada")
        XCTAssertEqual(cast[0].bio, "Says \"hello, world\"\r\nUses notes")
        XCTAssertEqual(cast[0].interests, ["notes", "music"])
        XCTAssertEqual(cast[0].goals, ["save money"])
        XCTAssertEqual(cast[0].mood, -0.5)
        XCTAssertEqual(cast[0].insider, true)
        XCTAssertNil(cast[1].insider)
    }

    func testUnicodeAndBlankLines() throws {
        let cast = try parse("\nhandle,role,bio\n\njosé,estudante,Usa notas\nlin,writer,中文笔记\n\n")
        XCTAssertEqual(cast.map(\.handle), ["josé", "lin"])
    }

    func testRejectsBadHeadersAndFieldCounts() {
        for csv in ["", "name,role,bio\na,b,c\nd,e,f", "handle,role,bio,role\na,b,c,d\ne,f,g,h",
                    "handle,role,bio,email\na,b,c,d\ne,f,g,h", simple + ",extra"] {
            XCTAssertThrowsError(try parse(csv), csv)
        }
    }

    func testRejectsMalformedQuotes() {
        for row in ["ada,student,\"unclosed", "ada,student,has\"quote", "ada,student,\"bio\"oops"] {
            XCTAssertThrowsError(try parse("handle,role,bio\n" + row + "\nben,writer,Bio"))
        }
    }

    func testRejectsDuplicateOrInvalidHandlesAndEmptyDetails() {
        for row in ["@ADA,writer,Bio", "two words,writer,Bio", "bad@name,writer,Bio", ",writer,Bio", "ben,,Bio", "ben,writer,"] {
            XCTAssertThrowsError(try parse("handle,role,bio\nada,student,Bio\n" + row), row)
        }
    }

    func testRejectsInvalidMoodAndInsider() {
        for mood in ["nan", "inf", "-1.1", "1.1", "happy"] {
            XCTAssertThrowsError(try parse(simple.replacingOccurrences(of: "handle,role,bio", with: "handle,role,bio,mood")
                .replacingOccurrences(of: "Uses free notes", with: "Uses free notes," + mood)
                .replacingOccurrences(of: "Wants faster sync", with: "Wants faster sync,0")))
        }
        XCTAssertThrowsError(try parse("handle,role,bio,insider\nada,student,Bio,yes\nben,writer,Bio,false"))
    }

    func testCastSizeAndByteLimits() throws {
        XCTAssertThrowsError(try parse("handle,role,bio\nada,student,Bio"))
        let rows = (1...17).map { "person\($0),role,Bio" }
        XCTAssertEqual(try parse("handle,role,bio\n" + rows.prefix(16).joined(separator: "\n")).count, 16)
        XCTAssertThrowsError(try parse("handle,role,bio\n" + rows.joined(separator: "\n")))
        XCTAssertThrowsError(try CastCSV.parse(Data(repeating: 65, count: CastCSV.maxBytes + 1)))
        XCTAssertThrowsError(try CastCSV.parse(Data([0xff, 0xfe])))
    }

    func testFileImportAndExperimentRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(simple.utf8).write(to: file)
        let cast = try CastCSV.read(file)
        let e = Experiment(name: "CSV", hypothesis: "A new plan?", context: "", branches: [Branch(name: "A", characters: cast)], cast: cast)
        let loaded = try JSONDecoder().decode(Experiment.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(loaded.cast, cast)
        XCTAssertTrue(Engine.roundPrompt(loaded, loaded.branches[0]).contains("ada"))
    }
}
