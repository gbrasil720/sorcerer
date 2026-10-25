@testable import Sorcerer
import XCTest

@MainActor
final class PlanningTests: XCTestCase {
    private var root: URL!
    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sorcerer-plans-" + UUID().uuidString)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func store(round: Int = 0) -> Store {
        let s = Store(root: root)
        let p = Persona(handle: "ada", role: "user")
        var b = Branch(name: "A", characters: [p])
        b.round = round
        let e = Experiment(name: "test", hypothesis: "a new product?", context: "", branches: [b], cast: [p], rounds: 10)
        s.experiments = [e]
        s.open(e.id)
        return s
    }

    func testEventsAppearOnlyWhenDueAndPersist() throws {
        let s = store()
        XCTAssertTrue(s.schedule("  price rises  ", at: 3))
        XCTAssertEqual(s.branch?.events.first?.text, "price rises")
        let e = s.experiment!
        var b = s.branch!
        XCTAssertFalse(Engine.roundPrompt(e, b).contains("price rises"))
        XCTAssertFalse(Engine.reportPrompt(e).contains("price rises"))
        b.round = 2
        XCTAssertTrue(Engine.roundPrompt(e, b).contains("Happening this round: price rises"))
        b.round = 3
        XCTAssertTrue(Engine.roundPrompt(e, b).contains("r3: price rises"))
        let loaded = Store(root: root)
        XCTAssertEqual(loaded.experiments.first?.branches.first?.events, s.branch?.events)
    }

    func testFutureEventsCanBeEditedAndRemovedButPlayedEventsCannot() {
        let s = store(round: 2)
        XCTAssertFalse(s.schedule("past", at: 2))
        XCTAssertFalse(s.schedule("too late", at: 11))
        XCTAssertFalse(s.schedule(" ", at: 3))
        XCTAssertTrue(s.schedule("first", at: 4))
        let id = s.branch!.events[0].id
        XCTAssertTrue(s.schedule("revised", at: 6, replacing: id))
        XCTAssertEqual(s.branch?.events.first?.id, id)
        XCTAssertEqual(s.branch?.events.first?.round, 6)
        s.experiments[0].branches[0].round = 6
        XCTAssertFalse(s.schedule("rewrite history", at: 7, replacing: id))
        s.removeScheduledEvent(id)
        XCTAssertEqual(s.branch?.events.count, 1)
        s.experiments[0].branches[0].round = 2
        s.removeScheduledEvent(id)
        XCTAssertTrue(s.branch!.events.isEmpty)
    }

    func testCannotChangePlansWhileBusyRunningOrReplaying() {
        let s = store(round: 2)
        for state in 0...2 {
            s.busy = state == 0 ? "writing" : nil
            s.running = state == 1
            s.replay = state == 2 ? 0 : nil
            XCTAssertFalse(s.schedule("event", at: 3))
        }
        XCTAssertTrue(s.branch!.events.isEmpty)
    }

    func testForksRetainPlansKnownAtTheirCheckpointAndStayIndependent() throws {
        let s = store()
        XCTAssertTrue(s.schedule("initial plan", at: 8))
        s.experiments[0].branches[0].round = 3
        XCTAssertTrue(s.schedule("later plan", at: 9))
        s.replay = 1
        s.fork()
        XCTAssertEqual(s.branch?.round, 1)
        XCTAssertEqual(s.branch?.events.map(\.text), ["initial plan"])
        s.removeScheduledEvent(s.branch!.events[0].id)
        XCTAssertEqual(s.experiments[0].branches[0].events.count, 2)
        XCTAssertTrue(s.branch!.events.isEmpty)
    }

    func testFreshScenarioKeepsInitialScheduleWithoutHistory() throws {
        let s = store()
        s.schedule("initial", at: 3)
        s.experiments[0].branches[0].round = 2
        s.schedule("later", at: 4)
        let fresh = try JSONDecoder().decode(Experiment.self, from: XCTUnwrap(s.exportData(fresh: true)))
        XCTAssertEqual(fresh.branches[0].round, 0)
        XCTAssertEqual(fresh.branches[0].events.map(\.text), ["initial"])
    }

    func testOldEventAndBranchDecodeWithoutNewFields() throws {
        let event = try JSONDecoder().decode(WorldEvent.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","round":2,"text":"legacy"}"#.utf8))
        XCTAssertNil(event.plannedAt)
        let s = store()
        let data = try JSONEncoder().encode(s.branch!)
        let b = try JSONDecoder().decode(Branch.self, from: data)
        XCTAssertNil(b.chats)
    }
}

@MainActor
final class SavedChatTests: XCTestCase {
    private var root: URL!
    override func setUp() { root = FileManager.default.temporaryDirectory.appendingPathComponent("sorcerer-chat-" + UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func store() -> Store {
        let s = Store(root: root)
        let p = Persona(handle: "ada", role: "user")
        s.experiments = ["one", "two"].map { Experiment(name: $0, hypothesis: "h", context: "", branches: [Branch(name: "A", characters: [p])]) }
        s.open(s.experiments[0].id)
        return s
    }

    func testLateReplyStaysInOriginAndSurvivesReload() {
        let s = store()
        let e = s.experiment!, b = s.branch!
        s.open(s.experiments[1].id)
        s.saveChatReply(" private answer ", to: "ada", experimentID: e.id, branchID: b.id, round: 0, question: "hello", inWorld: false)
        XCTAssertNil(s.branch?.chats)
        let saved = s.experiments[0].branches[0]
        XCTAssertEqual(saved.chats?["ada"]?.first?.text, "private answer")
        XCTAssertTrue(saved.characters[0].memories.isEmpty)
        let reload = Store(root: root)
        XCTAssertEqual(reload.experiments.first(where: { $0.id == e.id })?.branches[0].chats, saved.chats)
    }

    func testInWorldRepliesChangeOnlyOriginMemoryAndExportsOmitTranscripts() throws {
        let s = store()
        let e = s.experiment!, b = s.branch!
        s.saveChatReply("answer", to: "ada", experimentID: e.id, branchID: b.id, round: 0, question: "question", inWorld: true)
        XCTAssertEqual(s.branch?.characters[0].memories.count, 1)
        let exported = try JSONDecoder().decode(Experiment.self, from: XCTUnwrap(s.exportData(fresh: false)))
        XCTAssertNil(exported.branches[0].chats)
        XCTAssertEqual(exported.branches[0].characters[0].memories.count, 1)
        XCTAssertNotNil(s.branch?.chats)
        let fresh = try JSONDecoder().decode(Experiment.self, from: XCTUnwrap(s.exportData(fresh: true)))
        XCTAssertNil(fresh.branches[0].chats)
        XCTAssertTrue(fresh.branches[0].characters[0].memories.isEmpty)
    }

    func testForkFiltersLaterChatAndKeepsBranchCopiesIndependent() {
        let s = store()
        let e = s.experiment!, b = s.branch!
        s.saveChatReply("early", to: "ada", experimentID: e.id, branchID: b.id, round: 0, question: "hello", inWorld: false)
        s.saveChatReply("late", to: "ada", experimentID: e.id, branchID: b.id, round: 3, question: "hello", inWorld: false)
        s.experiments[0].branches[0].round = 3
        s.replay = 1
        s.fork()
        XCTAssertEqual(s.branch?.chats?["ada"]?.map(\.text), ["early"])
        let child = s.branch!
        s.saveChatReply("fork reply", to: "ada", experimentID: e.id, branchID: child.id, round: 1, question: "hello", inWorld: false)
        XCTAssertEqual(s.experiments[0].branches[0].chats?["ada"]?.map(\.text), ["early", "late"])
    }

    func testOffRecordHistoryCannotInfluenceInWorldReplies() {
        let s = store()
        let history = [ChatLine(fromUser: true, text: "private interview", round: 0, inWorld: false),
                       ChatLine(fromUser: false, text: "world conversation", round: 0, inWorld: true)]
        let world = Engine.chatPrompt(s.experiment!, s.branch!.characters[0], history: history, question: "why?", inWorld: true)
        XCTAssertFalse(world.contains("private interview"))
        XCTAssertTrue(world.contains("world conversation"))
        let privateChat = Engine.chatPrompt(s.experiment!, s.branch!.characters[0], history: history, question: "why?")
        XCTAssertTrue(privateChat.contains("private interview"))
        XCTAssertFalse(privateChat.contains("world conversation"))
    }

    func testFailedChatSavesQuestionWithoutInventingReply() async {
        let s = store()
        s.settings.chats = .compatible
        s.settings.compatibleURL = "invalid"
        await s.chat(with: s.branch!.characters[0], "hello")
        XCTAssertNotNil(s.error)
        XCTAssertEqual(s.branch?.chats?["ada"]?.count, 1)
        XCTAssertEqual(s.branch?.chats?["ada"]?.first?.fromUser, true)
        XCTAssertEqual(Store(root: root).experiments[0].branches[0].chats?["ada"]?.count, 1)
    }
}
