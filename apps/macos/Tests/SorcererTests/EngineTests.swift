@testable import Sorcerer
import XCTest

final class EngineTests: XCTestCase {
    private func branch() -> Branch {
        Branch(name: "A", characters: [
            Persona(handle: "ada", role: "designer", mood: -0.4),
            Persona(handle: "bruno", role: "power user", mood: 0.8),
        ])
    }

    func testApplyRoundFromMessyReply() throws {
        var b = branch()
        let reply = """
        Sure! Here's round 1:
        ```json
        {"posts":[
          {"author":"@Ada","replyTo":null,"text":"$14? I'll wait.","mood":-3},
          {"author":"bruno","replyTo":"ada","text":"Faster sync and I'm in.","mood":0.9},
          {"author":"ghost","text":"I don't exist","mood":1},
          {"author":"bruno","replyTo":"bruno","text":"Self reply","mood":0.9}
        ],"memories":{"ADA":"r1: price went up","nobody":"x"}}
        ```
        """
        try Engine.apply(reply, to: &b)

        XCTAssertEqual(b.round, 1)
        XCTAssertEqual(b.posts.map(\.author), ["ada", "bruno", "bruno"])
        XCTAssertEqual(b.posts[0].mood, -1) // clamped
        XCTAssertEqual(b.posts[1].replyTo, "ada")
        XCTAssertNil(b.posts[2].replyTo) // can't reply to yourself
        XCTAssertEqual(b.characters[0].mood, -1)
        XCTAssertEqual(b.characters[0].memories, ["r1: price went up"])
        XCTAssertEqual(b.moodByRound.count, 2) // before + after round 1
        XCTAssertEqual(b.moodByRound[1], -0.05, accuracy: 0.001)
    }

    func testRewindRestoresAnEarlierRound() throws {
        var b = branch()
        try Engine.apply(#"{"posts":[{"author":"ada","text":"meh","mood":-0.8}],"memories":{"ada":"price up"}}"#, to: &b)
        b.events.append(WorldEvent(round: 2, text: "outage"))
        try Engine.apply(#"{"posts":[{"author":"ada","text":"fine","mood":0.6}],"memories":{"ada":"outage fixed"}}"#, to: &b)

        let r1 = Engine.rewind(b, to: 1, start: branch().characters)
        XCTAssertEqual(r1.round, 1)
        XCTAssertEqual(r1.posts.map(\.text), ["meh"])
        XCTAssertTrue(r1.events.isEmpty)
        XCTAssertEqual(r1.moodByRound.count, 2)
        XCTAssertEqual(r1.characters[0].mood, -0.8)
        XCTAssertEqual(r1.characters[0].memories, ["r1: price up"])

        let r0 = Engine.rewind(b, to: 0, start: branch().characters)
        XCTAssertTrue(r0.posts.isEmpty)
        XCTAssertEqual(r0.characters[0].mood, -0.4)
        XCTAssertEqual(Engine.rewind(b, to: 5, start: nil), b) // past the end: unchanged
    }

    func testNoJSONThrowsAndLeavesBranchAlone() {
        var b = branch()
        XCTAssertThrowsError(try Engine.apply("I can't do that.", to: &b))
        XCTAssertEqual(b.round, 0)
    }

    func testSummonDedupesAndClamps() throws {
        let cast = try Engine.parseSummon("""
        {"characters":[{"handle":"Eli","role":"tech writer","traits":{"skepticism":1.4},"mood":-2},
                       {"handle":"@eli","role":"dup"},{"handle":"  "}]}
        """)
        XCTAssertEqual(cast.map(\.handle), ["eli"])
        XCTAssertEqual(cast[0].traits["skepticism"], 1)
        XCTAssertEqual(cast[0].mood, -1)
    }

    func testSummonKeepsOnlyRealTies() throws {
        let cast = try Engine.parseSummon("""
        {"characters":[{"handle":"ada","ties":{"@Bruno":"coworker","ghost":"x","ada":"self"}},
                       {"handle":"bruno","ties":{}}]}
        """)
        XCTAssertEqual(cast[0].ties, ["bruno": "coworker"])
        XCTAssertNil(cast[1].ties)
    }

    func testResolveCitations() {
        var b = branch()
        b.posts = [Post(round: 1, author: "ada", text: "one", mood: 0), Post(round: 2, author: "bruno", text: "two", mood: 0)]
        let e = Experiment(name: "x", hypothesis: "h", context: "", branches: [b])
        XCTAssertEqual(Engine.resolve("A2", in: e)?.post.text, "two")
        XCTAssertEqual(Engine.resolve("[a1]", in: e)?.post.text, "one")
        XCTAssertNil(Engine.resolve("A3", in: e))
        XCTAssertNil(Engine.resolve("B1", in: e))
        XCTAssertNil(Engine.resolve("A0", in: e))
    }

    func testOldWorldsStillLoad() throws {
        // Saved before ties, cast and cited findings existed.
        let old = """
        {"id":"\(UUID())","name":"x","hypothesis":"h","context":"","created":0,
         "report":{"headline":"h","findings":["plain finding"],"questions":[]},
         "branches":[{"id":"\(UUID())","name":"A","round":0,"posts":[],"events":[],"moodByRound":[],
           "characters":[{"handle":"ada","role":"r","bio":"","traits":{},"interests":[],"goals":[],"mood":0,"memories":[]}]}]}
        """
        let e = try JSONDecoder().decode(Experiment.self, from: Data(old.utf8))
        XCTAssertEqual(e.report?.findings.first?.text, "plain finding")
        XCTAssertNil(e.branches[0].characters[0].ties)
    }

    func testClaudeStreamCarriesUsage() throws {
        let out = """
        {"type":"system","subtype":"init"}
        {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{"five_hour":{"utilization":0.35,"resetsAt":1792381800},"seven_day":{"utilization":0.46,"resetsAt":1792548000}}}}
        {"type":"result","is_error":false,"result":"{\\"ok\\":true}"}
        """
        let r = try AI.parseClaude(out, err: "")
        XCTAssertEqual(r.text, #"{"ok":true}"#)
        XCTAssertEqual(r.usage?.fiveHour, 0.35)
        XCTAssertEqual(r.usage?.peak, 0.46)
        XCTAssertEqual(r.usage?.resetsAt, Date(timeIntervalSince1970: 1792381800))
    }

    func testLimitErrorsAreRecognized() {
        XCTAssertThrowsError(try AI.parseClaude(#"{"type":"result","is_error":true,"result":"Claude AI usage limit reached"}"#, err: "")) {
            XCTAssertTrue(($0 as? AIError)?.isLimit == true)
        }
        XCTAssertFalse(AIError(message: "Claude: not logged in").isLimit)
    }

    func testPauseWaitsForTheWindowThatRanOut() {
        let fiveReset = Date(timeIntervalSince1970: 1000), weekReset = Date(timeIntervalSince1970: 9000)
        let weekly = Usage(fiveHour: 0.1, sevenDay: 0.95, resetsAt: fiveReset, weekResetsAt: weekReset)
        XCTAssertEqual(weekly.resume(over: 0.9), weekReset)
        let hourly = Usage(fiveHour: 0.95, sevenDay: 0.4, resetsAt: fiveReset, weekResetsAt: weekReset)
        XCTAssertEqual(hourly.resume(over: 0.9), fiveReset)
    }

    func testRepliesByPostIdAndReactions() throws {
        var b = branch()
        try Engine.apply(#"{"posts":[{"author":"ada","text":"first","mood":0}]}"#, to: &b)
        try Engine.apply(#"""
        {"posts":[{"author":"bruno","replyTo":"A1","text":"answering ada","mood":0.5},
                  {"author":"ada","replyTo":"A1","text":"replying to myself","mood":0}],
         "reactions":{"A1":{"agree":2,"disagree":-4},"Z9":{"agree":1}}}
        """#, to: &b)
        XCTAssertEqual(b.posts[1].replyTo, "ada")
        XCTAssertEqual(b.posts[1].replyToPost, b.posts[0].id)
        XCTAssertNil(b.posts[2].replyToPost) // no self replies
        XCTAssertEqual(b.posts[0].agree, 2)
        XCTAssertEqual(b.posts[0].disagree, 0) // negatives ignored
    }

    func testResolveOnEmptyBranchDoesNotCrash() {
        let e = Experiment(name: "x", hypothesis: "h", context: "", branches: [branch()])
        XCTAssertNil(Engine.resolve("A1", in: e))
    }

    func testSummonNamesTheCommunity() throws {
        let r = try Engine.parseCommunity(#"{"community":"Lumen customers","characters":[{"handle":"ada"}]}"#)
        XCTAssertEqual(r.name, "Lumen customers")
        XCTAssertEqual(r.cast.map(\.handle), ["ada"])
    }

    func testMoodSeriesCarriesOverSilentRounds() {
        var b = branch() // ada -0.4, bruno 0.8
        b.round = 3
        b.posts = [Post(round: 1, author: "ada", text: "x", mood: -0.2),
                   Post(round: 1, author: "ada", text: "y", mood: 0.1),
                   Post(round: 3, author: "bruno", text: "z", mood: 0.5)]
        let start = [Persona(handle: "ada", role: "r", mood: -0.6), Persona(handle: "bruno", role: "r", mood: 0.9)]
        let s = Engine.moodSeries(b, start: start)
        XCTAssertEqual(s["ada"], [-0.6, 0.1, 0.1, 0.1]) // last post of round 1 wins, then carries
        XCTAssertEqual(s["bruno"], [0.9, 0.9, 0.9, 0.5])
    }

    func testPartialRoundWhileStreaming() {
        let full = #"{"posts":[{"author":"@Ada","replyTo":null,"text":"$14? I \"ll wait.","mood":-0.3},{"author":"bruno","replyTo":"A1","text":"Faster sync and I'm in","mood":0.8}],"memories":{}}"#
        // Nothing yet.
        XCTAssertEqual(Engine.partialRound("{\"po"), Engine.Partial())
        // First post mid-sentence.
        let cut1 = String(full.prefix(full.distance(from: full.startIndex, to: full.range(of: "wait")!.lowerBound)))
        let p1 = Engine.partialRound(cut1)
        XCTAssertTrue(p1.done.isEmpty)
        XCTAssertEqual(p1.typing, "ada")
        XCTAssertEqual(p1.draft, "$14? I \"ll ")
        // First done, second author known, no text yet.
        let cut2 = String(full.prefix(full.distance(from: full.startIndex, to: full.range(of: "\"replyTo\":\"A1")!.lowerBound)))
        let p2 = Engine.partialRound(cut2)
        XCTAssertEqual(p2.done.map(\.author), ["ada"])
        XCTAssertEqual(p2.typing, "bruno")
        XCTAssertEqual(p2.draft, "")
        // Whole thing: both done, nobody typing, braces inside text don't confuse it.
        let p3 = Engine.partialRound(full.replacingOccurrences(of: "I'm in", with: "I'm in {really}"))
        XCTAssertEqual(p3.done.count, 2)
        XCTAssertNil(p3.typing)
    }

    func testClaudeDeltaLines() {
        XCTAssertEqual(AI.delta(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}}"#), "hi")
        XCTAssertNil(AI.delta(#"{"type":"result","result":"x"}"#))
    }
}
