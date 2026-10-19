@testable import Sorcerer
import XCTest

final class UpdaterTests: XCTestCase {
    func testVersionOrder() {
        XCTAssertTrue(Updater.newer("0.2.0", than: "0.1.0"))
        XCTAssertTrue(Updater.newer("0.10.0", than: "0.9.1"))
        XCTAssertTrue(Updater.newer("1.0", than: "0.99.9"))
        XCTAssertFalse(Updater.newer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(Updater.newer("0.1", than: "0.1.0"))
        XCTAssertFalse(Updater.newer("0.1.0", than: "0.2.0"))
    }

    func testReadsAGitHubRelease() throws {
        let json = #"""
        {"tag_name":"v0.2.0","body":"## What's Changed\n* Replay","html_url":"https://github.com/gbrasil720/sorcerer/releases/tag/v0.2.0",
         "assets":[{"name":"Sorcerer.dmg","browser_download_url":"https://x/Sorcerer.dmg"},
                   {"name":"Sorcerer.dmg.sha256","browser_download_url":"https://x/Sorcerer.dmg.sha256"}]}
        """#
        let r = try JSONDecoder().decode(Updater.Release.self, from: Data(json.utf8))
        XCTAssertEqual(r.version, "0.2.0")
        XCTAssertEqual(r.asset("Sorcerer.dmg")?.absoluteString, "https://x/Sorcerer.dmg")
        XCTAssertNil(r.asset("other.zip"))
    }
}
