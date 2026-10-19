import AppKit
import CryptoKit
import Foundation
import Observation
import SwiftUI

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
        if !quietly { showing = true }
        switch phase {
        case .downloading, .ready: return
        default: break
        }
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
            let (tmp, dmgResponse) = try await URLSession.shared.download(from: dmgURL)
            try Self.ok(dmgResponse)
            try fm.moveItem(at: tmp, to: dmg)

            let (sum, sumResponse) = try await URLSession.shared.data(from: sumURL)
            try Self.ok(sumResponse)
            let expected = String(data: sum, encoding: .utf8)?
                .split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
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
        // macOS refuses to quit while a sheet is open, so close it first.
        showing = false
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            NSApp.terminate(nil)
        }
    }

    /// URLSession treats a 404 page as a successful download; don't.
    private static func ok(_ r: URLResponse) throws {
        if let code = (r as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            throw AIError(message: "GitHub answered \(code) while downloading the update.")
        }
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


/// What's new, then download → confirm → restart. Opened from the sidebar, the app menu or About.
struct UpdateSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let u = store.updater
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Caps("software update")
                Spacer()
                Text("you have v\(Updater.current)").font(.mono(10)).foregroundStyle(Color.muted)
            }
            switch u.phase {
            case .idle, .checking:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("checking GitHub for a newer Sorcerer…").font(.mono(12)).foregroundStyle(Color.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            case .upToDate:
                Text("You're on the latest version.").font(.display(20))
                Text("Sorcerer v\(Updater.current) is the newest release.").font(.mono(11)).foregroundStyle(Color.muted)
            case .failed(let why):
                Text("Update didn't work").font(.display(20))
                Text(why).font(.mono(11)).foregroundStyle(Color.ember).textSelection(.enabled)
            case .available, .downloading, .ready:
                if let r = u.latest {
                    (Text("Sorcerer ") + Text("v\(r.version)").foregroundStyle(Color.ember) + Text(" is out")).font(.display(22))
                    let lines = (r.body ?? "").split(whereSeparator: \.isNewline).count
                    ScrollView { Changelog(text: r.body ?? "").frame(maxWidth: .infinity, alignment: .leading) }
                        // Short notes stay short; long ones scroll.
                        .frame(height: min(280, CGFloat(max(lines, 2)) * 26))
                        .card(padding: 14)
                }
            }
            footer(u)
        }
        .padding(24)
        .frame(width: 560)
        .background(Color.ink)
    }

    @ViewBuilder private func footer(_ u: Updater) -> some View {
        HStack(spacing: 10) {
            switch u.phase {
            case .downloading:
                ProgressView().controlSize(.small)
                Text("downloading and checking v\(u.latest?.version ?? "")…").font(.mono(11)).foregroundStyle(Color.muted)
                Spacer()
            case .ready:
                Text("Ready. Sorcerer will quit and reopen on v\(u.latest?.version ?? ""). Your experiments are saved.")
                    .font(.mono(11)).foregroundStyle(Color.paper.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("later") { dismiss() }.buttonStyle(SButton())
                Button("restart now") { u.restart() }.buttonStyle(SButton(primary: true)).keyboardShortcut(.defaultAction)
            case .available:
                if let r = u.latest { Link("release page ↗", destination: r.html_url).font(.mono(11)).foregroundStyle(Color.muted) }
                Spacer()
                Button("not now") { dismiss() }.buttonStyle(SButton())
                if u.canInstall {
                    Button("download & install") { Task { await u.download() } }
                        .buttonStyle(SButton(primary: true)).keyboardShortcut(.defaultAction)
                } else if let r = u.latest {
                    // A build run from source, or an app in a folder we can't write to.
                    Link("download from GitHub ↗", destination: r.html_url).buttonStyle(SButton(primary: true))
                }
            case .failed:
                Spacer()
                Button("close") { dismiss() }.buttonStyle(SButton())
                Button("try again") { Task { await u.check() } }.buttonStyle(SButton(primary: true))
            default:
                Spacer()
                Button("close") { dismiss() }.buttonStyle(SButton()).keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Release notes as GitHub writes them: "## headings", "* bullets", inline links and bold.
private struct Changelog: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    Caps(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)).padding(.top, 6)
                } else if line.hasPrefix("* ") || line.hasPrefix("- ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("·").foregroundStyle(Color.ember)
                        Text(Self.inline(String(line.dropFirst(2)))).font(.display(13, .regular))
                    }
                } else if !line.isEmpty {
                    Text(Self.inline(line)).font(.mono(11)).foregroundStyle(Color.paper.opacity(0.8))
                }
            }
        }
        .tint(.ember)
        .textSelection(.enabled)
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
