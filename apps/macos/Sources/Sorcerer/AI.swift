import Foundation

struct AIError: LocalizedError {
    var message: String
    var usage: Usage?
    var errorDescription: String? { message }

    /// The provider said no because of a usage or rate limit.
    var isLimit: Bool {
        usage?.rejected == true
            || message.range(of: #"usage limit|rate limit|limit reached|quota|429|too many requests"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

struct Reply {
    var text: String
    var usage: Usage?
}

/// Talks to the AI tools the user is already signed in to. Sorcerer never sees
/// a token: it runs the official CLIs (or a local Ollama) and reads the reply.
enum AI {
    /// Runs through a login shell so a Finder-launched app sees the same PATH as the terminal.
    static func shell(_ command: String, stdin: String? = nil,
                      onLine: (@Sendable (String) -> Void)? = nil) async throws -> (out: String, err: String, code: Int32) {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", command]
                p.currentDirectoryURL = FileManager.default.temporaryDirectory
                let out = Pipe(), err = Pipe(), inp = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = inp
                do { try p.run() } catch {
                    cont.resume(throwing: error)
                    return
                }
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                if let stdin { inp.fileHandleForWriting.write(Data(stdin.utf8)) }
                try? inp.fileHandleForWriting.close()
                var outData = Data()
                if let onLine {
                    // Read as it arrives and hand over each complete line, for live progress.
                    var pending = Data()
                    let h = out.fileHandleForReading
                    while true {
                        let chunk = h.availableData
                        if chunk.isEmpty { break }
                        outData.append(chunk)
                        pending.append(chunk)
                        while let nl = pending.firstIndex(of: 0x0A) {
                            onLine(String(decoding: pending[pending.startIndex..<nl], as: UTF8.self))
                            pending.removeSubrange(pending.startIndex...nl)
                        }
                    }
                } else {
                    outData = out.fileHandleForReading.readDataToEndOfFile()
                }
                group.wait()
                p.waitUntilExit()
                cont.resume(returning: (
                    String(decoding: outData, as: UTF8.self),
                    String(decoding: errData, as: UTF8.self),
                    p.terminationStatus
                ))
            }
        }
    }

    static func installed(_ binary: String) async -> Bool {
        (try? await shell("command -v \(binary)"))?.code == 0
    }

    struct ModelOption: Hashable, Identifiable {
        var id: String
        var name: String
        var detail: String
    }

    /// Models the user can pick for a provider. "" = the tool's own default.
    static func models(for p: Provider) async -> [ModelOption] {
        let auto = ModelOption(id: "", name: "default", detail: "whatever \(p == .claude ? "Claude Code" : p == .codex ? "Codex" : "Ollama") uses")
        switch p {
        case .claude:
            return [auto,
                    ModelOption(id: "haiku", name: "Haiku", detail: "fastest, lightest on your limit"),
                    ModelOption(id: "sonnet", name: "Sonnet", detail: "balanced"),
                    ModelOption(id: "opus", name: "Opus", detail: "most capable, uses your limit fastest")]
        case .codex:
            // Codex keeps the list of models this account can use; only its non-secret cache is read.
            struct Cache: Decodable {
                struct M: Decodable { var slug: String; var display_name: String?; var description: String?; var visibility: String? }
                var models: [M]
            }
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
            let listed = (try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: url)))?.models.filter { $0.visibility != "hide" } ?? []
            return [auto] + listed.map { ModelOption(id: $0.slug, name: $0.display_name ?? $0.slug, detail: $0.description ?? "") }
        case .ollama:
            return (await ollamaModels() ?? []).map { ModelOption(id: $0, name: $0, detail: "local") }
        }
    }

    /// Asks the CLI itself whether it has a login; never reads its credentials.
    static func signedIn(_ p: Provider) async -> Bool {
        switch p {
        case .claude: (try? await shell("claude auth status"))?.out.contains(#""loggedIn": true"#) == true
        case .codex:
            // codex prints its status on stderr.
            if let r = try? await shell("codex login status") { r.code == 0 && (r.out + r.err).localizedCaseInsensitiveContains("logged in") } else { false }
        case .ollama: await ollamaModels() != nil
        }
    }

    static func ollamaModels() async -> [String]? {
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "http://localhost:11434/api/tags")!)
        else { return nil }
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        return (try? JSONDecoder().decode(Tags.self, from: data))?.models.map(\.name)
    }

    /// `model` empty = whatever the tool itself defaults to.
    /// `onText` receives the answer so far, as it's written (Claude and Ollama stream; ChatGPT doesn't).
    static func complete(_ prompt: String, with provider: Provider, ollamaModel: String, model: String = "",
                         onText: (@Sendable (String) -> Void)? = nil) async throws -> Reply {
        let pick = model.isEmpty ? "" : " \(provider == .codex ? "-m" : "--model") \(Sources.quoted(model))"
        switch provider {
        case .claude:
            // No tools, no session file, no user settings. stream-json because it carries the
            // subscription's usage windows alongside the answer.
            let so = Accumulator()
            let r = try await shell(
                "claude -p --tools '' --no-session-persistence --setting-sources '' --output-format stream-json --verbose\(pick)"
                    + (onText == nil ? "" : " --include-partial-messages"),
                stdin: prompt,
                onLine: onText.map { send in { line in
                    if let d = delta(line) { send(so.add(d)) }
                } }
            )
            return try parseClaude(r.out, err: r.err)
        case .codex:
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("sorcerer-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: file) }
            let r = try await shell(
                "codex exec --skip-git-repo-check --ephemeral -s read-only\(pick) -o '\(file.path)' -", stdin: prompt
            )
            guard r.code == 0, let text = try? String(contentsOf: file, encoding: .utf8) else {
                throw AIError(message: "ChatGPT: " + tail(r.err))
            }
            return Reply(text: text)
        case .ollama:
            var req = URLRequest(url: URL(string: "http://localhost:11434/api/generate")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 600
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model.isEmpty ? ollamaModel : model, "prompt": prompt, "stream": true,
            ])
            // One JSON object per line: {"response":"…","done":false}
            struct Chunk: Decodable { let response: String?; let error: String? }
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            var text = ""
            for try await line in bytes.lines {
                guard let c = try? JSONDecoder().decode(Chunk.self, from: Data(line.utf8)) else { continue }
                if let e = c.error { throw AIError(message: "Ollama: " + e) }
                text += c.response ?? ""
                onText?(text)
            }
            return Reply(text: text)
        }
    }

    /// Text added by one `stream_event` line of Claude's partial output, if any.
    static func delta(_ line: String) -> String? {
        guard line.contains("content_block_delta"),
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let event = obj["event"] as? [String: Any],
              let d = event["delta"] as? [String: Any] else { return nil }
        return d["text"] as? String
    }

    /// Thread-safe running total of streamed text.
    final class Accumulator: @unchecked Sendable {
        private var text = ""
        private let lock = NSLock()
        func add(_ s: String) -> String { lock.lock(); defer { lock.unlock() }; text += s; return text }
    }

    /// Reads Claude Code's stream-json: the `result` line is the answer, `rate_limit_event` the usage.
    static func parseClaude(_ out: String, err: String) throws -> Reply {
        var usage: Usage?
        var text: String?
        var failure: String?
        for line in out.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "rate_limit_event":
                let info = obj["rate_limit_info"] as? [String: Any]
                let windows = info?["unifiedWindows"] as? [String: Any]
                let five = windows?["five_hour"] as? [String: Any]
                let seven = windows?["seven_day"] as? [String: Any]
                if let u = five?["utilization"] as? Double, let reset = five?["resetsAt"] as? Double {
                    usage = Usage(
                        fiveHour: u, sevenDay: seven?["utilization"] as? Double,
                        resetsAt: Date(timeIntervalSince1970: reset),
                        weekResetsAt: (seven?["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) },
                        rejected: info?["status"] as? String == "rejected"
                    )
                }
            case "result":
                if obj["is_error"] as? Bool == true {
                    failure = obj["result"] as? String ?? "error"
                } else {
                    text = obj["result"] as? String
                }
            default: break
            }
        }
        if let text { return Reply(text: text, usage: usage) }
        throw AIError(message: "Claude: " + tail(failure ?? (err.isEmpty ? out : err)), usage: usage)
    }

    private static func tail(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "no output" : String(t.suffix(300))
    }
}
