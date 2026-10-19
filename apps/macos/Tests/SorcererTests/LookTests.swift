@testable import Sorcerer
import XCTest

@MainActor
final class LookTests: XCTestCase {
    func testLookAppliesToEveryBranchAndResetClearsIt() {
        let s = Store()
        let ada = Persona(handle: "ada", role: "r")
        var e = Experiment(name: "x", hypothesis: "h", context: "",
                           branches: [Branch(name: "A", characters: [ada]), Branch(name: "B", characters: [ada])])
        e.cast = [ada]
        s.experiments = [e]
        s.selected = e.id
        s.branchID = e.branches[0].id

        var look = Look.derived(from: "ada")
        look.hair = look.hair == .bun ? .curly : .bun
        look.accessories.insert(.headphones)
        s.setLook("ada", look)
        XCTAssertEqual(s.look(of: "ada"), look)
        XCTAssertTrue(s.experiment!.branches.allSatisfy { $0.characters[0].look == look })
        XCTAssertEqual(s.experiment!.cast?.first?.look, look)

        s.setLook("ada", .derived(from: "ada")) // reset stores nothing
        XCTAssertNil(s.look(of: "ada"))
        s.delete(e.id) // don't leave a test world in ~/Sorcerer
    }

    func testDerivedLookIsStableAndPersonasWithoutOneStillDecode() throws {
        XCTAssertEqual(Look.derived(from: "marina"), Look.derived(from: "marina"))
        let p = try JSONDecoder().decode(Persona.self, from: Data(#"{"handle":"ada","role":"r","bio":"","traits":{},"interests":[],"goals":[],"mood":0,"memories":[]}"#.utf8))
        XCTAssertNil(p.look)
    }
}
