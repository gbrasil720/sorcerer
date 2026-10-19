import AppKit
import CryptoKit
import Foundation
import Observation

/// Finds a newer Sorcerer on GitHub Releases, downloads it, checks it against the published
/// checksum and swaps it in on restart. Same files the website's installer uses; no server.
@MainActor @Observable
final class Updater {
    struct Release: Decodable, Equatable {
        var tag_name: String
        var body: String?
        var html_url: URL
        var assets: [Asset]

        struct Asset: Decodable, Equatable {
            var name: String
            var browser_download_url: URL
        }

        var version: String { String(tag_name.drop { $0 == "v" }) }
        func asset(_ name: String) -> URL? { assets.first { $0.name == name }?.browser_download_url }
    }

    enum Phase: Equatable {
        case idle, checking, upToDate, available, downloading
        /// Downloaded and checked; restarting swaps it in.
        case ready(URL)
        case failed(String)
    }

    var latest: Release?
    var phase = Phase.idle
    /// The update sheet is open.
    var showing = false

    static let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    private static let api = URL(string: "https://api.github.com/repos/gbrasil720/sorcerer/releases/latest")!

    var available: Bool { latest.map { Self.newer($0.version, than: Self.current) } ?? false }

    /// Only an installed .app in a folder we can write to can replace itself (`swift run` can't).
    var canInstall: Bool {
        let app = Bundle.main.bundleURL
        return app.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Quiet checks (on launch) only light up the sidebar; asking from a menu opens the sheet.
    func check(quietly: Bool = false) async {
        switch phase {
        case .downloading, .ready: return
        default: break
        }
        if !quietly { showing = true }
        phase = .checking
        do {
            var req = URLRequest(url: Self.api)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            latest = try JSONDecoder().decode(Release.self, from: data)
            phase = available ? .available : .upToDate
        } catch {
            phase = quietly ? .idle : .failed("Couldn't reach GitHub: \(error.localizedDescription)")
        }
    }

    func download() async {
        guard let r = latest, let dmgURL = r.asset("Sorcerer.dmg"), let sumURL = r.asset("Sorcerer.dmg.sha256") else {
            phase = .failed("This release has no Sorcerer.dmg to install.")
            return
        }
        phase = .downloading
        do {
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("sorcerer-update-\(r.version)")
            try? fm.removeItem(at: dir)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dmg = dir.appendingPathComponent("Sorcerer.dmg")
            let (tmp, _) = try await URLSession.shared.download(from: dmgURL)
            try fm.moveItem(at: tmp, to: dmg)

            let (sum, _) = try await URLSession.shared.data(from: sumURL)
            let expected = String(decoding: sum, as: UTF8.self).split(separator: " ").first.map(String.init) ?? ""
            let actual = SHA256.hash(data: try Data(contentsOf: dmg)).map { String(format: "%02x", $0) }.joined()
            guard !expected.isEmpty, expected == actual else {
                throw AIError(message: "The download didn't match its checksum, so it wasn't installed.")
            }

            let mnt = dir.appendingPathComponent("mnt").path, app = dir.appendingPathComponent("Sorcerer.app").path
            let q = Sources.quoted
            let out = try await AI.shell("""
                hdiutil attach -quiet -nobrowse -readonly -mountpoint \(q(mnt)) \(q(dmg.path)) || exit 1
                ditto \(q(mnt + "/Sorcerer.app")) \(q(app)); s=$?
                hdiutil detach -quiet \(q(mnt)); exit $s
                """)
            guard out.code == 0 else { throw AIError(message: "Couldn't open the update. \(out.err)") }
            phase = .ready(URL(fileURLWithPath: app))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Quits, and a tiny script waits for this process to end, puts the new app where this one is
    /// and opens it. The old app is only removed once the new copy is fully in place.
    func restart() {
        guard case .ready(let new) = phase else { return }
        let dest = Bundle.main.bundleURL.path
        guard dest.hasSuffix(".app") else { return }
        let script = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            rm -rf "$2.new" && ditto "$3" "$2.new" && rm -rf "$2" && mv "$2.new" "$2"
            xattr -dr com.apple.quarantine "$2" 2>/dev/null
            open "$2"
            """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), dest, new.path]
        do { try p.run() } catch {
            phase = .failed("Couldn't restart: \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }

    /// "0.10.0" is newer than "0.9.1"; missing parts count as 0.
    nonisolated static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
