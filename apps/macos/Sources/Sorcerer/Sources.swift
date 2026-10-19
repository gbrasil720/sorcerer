import Foundation

/// Where the world's context comes from: a GitHub repo (via the user's own `gh` login),
/// a local folder, a web page, or files. Only docs are read; secrets and code never are.
enum Sources {
    struct Entry: Identifiable, Hashable {
        enum Status: String { case read = "✓ read", never = "✗ never read", ignored = "✗ ignored", skipped = "○ not read" }
        var path: String
        var status: Status
        var id: String { path }
    }

    struct Reading {
        var name: String
        var kind: String
        var entries: [Entry]
        var docs: [(name: String, text: String)]
    }

    struct Repo: Identifiable, Decodable, Hashable {
        var nameWithOwner: String
        var updatedAt: Date
        var isPrivate: Bool
        var id: String { nameWithOwner }
    }

    // MARK: rules

    static let maxDocs = 12
    static let maxBytes = 60_000

    /// Secrets are never read, whatever the user picks.
    static func isSecret(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        return name.hasPrefix(".env") || name.contains("secret") || name.contains("credential")
            || ["pem", "key", "p12", "keystore"].contains((name as NSString).pathExtension)
            || name == ".npmrc" || name == "id_rsa"
    }

    static func isIgnored(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        return parts.contains { ["node_modules", ".git", "dist", "build", ".build", "vendor", "target", ".next", "Pods"].contains($0) }
    }

    /// Docs worth reading, best first: README, changelog, then markdown under docs/.
    static func docScore(_ path: String) -> Int? {
        let lower = path.lowercased()
        let name = (lower as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        guard ["md", "mdx", "txt", "rst"].contains(ext) || name == "readme" else { return nil }
        if !lower.contains("/") && name.hasPrefix("readme") { return 0 }
        if name.hasPrefix("changelog") || name.hasPrefix("roadmap") { return 1 }
        if lower.hasPrefix("docs/") || lower.contains("/docs/") { return 2 + lower.split(separator: "/").count }
        if !lower.contains("/") { return 3 }
        return nil
    }

    /// Splits a file list into what we read, skip, ignore and refuse.
    static func classify(_ paths: [String]) -> (entries: [Entry], toRead: [String]) {
        let docs = paths.filter { !isSecret($0) && !isIgnored($0) }
            .compactMap { p in docScore(p).map { (p, $0) } }
            .sorted { $0.1 < $1.1 }.prefix(maxDocs).map(\.0)
        var entries = docs.map { Entry(path: $0, status: .read) }
        entries += paths.filter(isSecret).prefix(3).map { Entry(path: $0, status: .never) }
        let top = Set(paths.compactMap { p in p.split(separator: "/").first.map(String.init) }.filter { p in paths.contains { $0.hasPrefix(p + "/") } })
        entries += top.sorted().filter { isIgnored($0) }.map { Entry(path: $0 + "/", status: .ignored) }
        entries += top.sorted().filter { dir in !isIgnored(dir) && !docs.contains { $0.hasPrefix(dir + "/") } }.prefix(4)
            .map { Entry(path: $0 + "/", status: .skipped) }
        return (entries, docs)
    }

    /// Single-quotes a value for the shell. Repo paths are untrusted: a file named `'; rm -rf ~` must stay a name.
    static func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    // MARK: GitHub via gh

    static func repos() async -> [Repo]? {
        guard let r = try? await AI.shell("gh repo list --limit 30 --json nameWithOwner,updatedAt,isPrivate"), r.code == 0 else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode([Repo].self, from: Data(r.out.utf8))
    }

    static func readRepo(_ repo: String) async throws -> Reading {
        let tree = try await AI.shell("gh api \(quoted("repos/\(repo)/git/trees/HEAD?recursive=1")) --jq '.tree[] | select(.type==\"blob\") | .path'")
        guard tree.code == 0 else { throw AIError(message: "gh couldn't list \(repo): \(tree.err.prefix(200))") }
        let paths = tree.out.split(separator: "\n").map(String.init)
        let (entries, toRead) = classify(paths)
        var docs: [(String, String)] = []
        for path in toRead {
            let raw = try? await AI.shell("gh api \(quoted("repos/\(repo)/contents/\(path)")) -H 'Accept: application/vnd.github.raw'")
            if let raw, raw.code == 0, !raw.out.isEmpty { docs.append((path, String(raw.out.prefix(maxBytes)))) }
        }
        return Reading(name: repo, kind: "repo · \(paths.count) files", entries: entries, docs: docs)
    }

    // MARK: local folder

    static func readFolder(_ url: URL) -> Reading {
        let fm = FileManager.default
        var paths: [String] = []
        if let walk = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsPackageDescendants]) {
            for case let file as URL in walk {
                let rel = String(file.path.dropFirst(url.path.count + 1))
                if isIgnored(rel) {
                    // Don't walk it, but keep a marker so it shows up as "ignored".
                    walk.skipDescendants()
                    paths.append(rel + "/…")
                    continue
                }
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { paths.append(rel) }
                if paths.count > 20_000 { break }
            }
        }
        let (entries, toRead) = classify(paths)
        let docs = toRead.compactMap { p -> (String, String)? in
            guard let text = try? String(contentsOf: url.appendingPathComponent(p), encoding: .utf8) else { return nil }
            return (p, String(text.prefix(maxBytes)))
        }
        return Reading(name: url.lastPathComponent, kind: "folder · \(paths.count) files", entries: entries, docs: docs)
    }
}
