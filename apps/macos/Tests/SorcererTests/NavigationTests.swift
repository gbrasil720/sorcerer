@testable import Sorcerer
import XCTest

@MainActor
final class NavigationTests: XCTestCase {
    private func store() -> Store {
        let s = Store()
        let a = Experiment(name: "a", hypothesis: "h", context: "", branches: [Branch(name: "A", characters: [Persona(handle: "ada", role: "r")])])
        let b = Experiment(name: "b", hypothesis: "h", context: "", branches: [Branch(name: "A", characters: [Persona(handle: "bo", role: "r")])])
        s.experiments = [a, b]
        s.back = []
        s.forward = []
        s.open(a.id)
        s.back = []
        return s
    }

    func testBackAndForwardWalkScreensAndExperiments() {
        let s = store()
        let a = s.experiments[0].id, b = s.experiments[1].id
        s.go(.report)
        s.open(b)
        s.go(.character("bo"))
        XCTAssertEqual(s.back.count, 3)

        s.goBack()
        XCTAssertEqual(s.selected, b); XCTAssertEqual(s.route, .feed)
        s.goBack()
        XCTAssertEqual(s.selected, a); XCTAssertEqual(s.route, .report)
        s.goForward()
        XCTAssertEqual(s.selected, b); XCTAssertEqual(s.route, .feed)

        s.go(.context) // a new step clears forward history
        XCTAssertTrue(s.forward.isEmpty)
    }

    func testSamePlaceIsNotRecordedTwice() {
        let s = store()
        s.go(.feed)
        s.go(.feed)
        XCTAssertTrue(s.back.isEmpty)
    }

    func testCharactersTabReopensOnTheLastPerson() {
        let s = store()
        s.showCharacters()
        XCTAssertEqual(s.route, .character("ada"))
        s.go(.feed)
        s.showCharacters()
        XCTAssertEqual(s.route, .character("ada"))
    }

    func testDeletingAnExperimentScrubsItFromHistory() {
        let s = store()
        let a = s.experiments[0].id, b = s.experiments[1].id
        s.open(b)
        s.go(.report)
        s.delete(b)
        XCTAssertFalse(s.back.contains { $0.experiment == b })
        XCTAssertNil(s.selected)
        s.goBack()
        XCTAssertEqual(s.selected, a)
    }
}
