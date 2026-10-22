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

/// Uses official CLI sessions or a configured HTTP endpoint.
enum AI {
    /// The PATH your Terminal has. A login shell alone misses what ~/.zshrc adds (~/.local/bin, where
    /// the claude installer puts it; nvm, bun…), so ask an interactive shell once and remember it.
    static let userPath: String = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", #"printf '\n__SORCERER_PATH__%s' "$PATH""#]
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        var found = ""
        if (try? p.run()) != nil {
            // An interactive shell can hang on a prompt or plugin; don't wait for it forever.
            let deadline = DispatchTime.now() + 5
            DispatchQueue.global().asyncAfter(deadline: deadline) { if p.isRunning { p.terminate() } }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            found = String(decoding: data, as: UTF8.self).components(separatedBy: "__SORCERER_PATH__").last ?? ""
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Where the CLIs usually live, in case the shell didn't say.
        let usual = ["\(home)/.local/bin", "\(home)/.claude/local", "\(home)/.bun/bin", "\(home)/.npm-global/bin",
                     "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        return (found.split(separator: ":").map(String.init) + usual)
            .filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }()

    /// Runs through a login shell with your Terminal's PATH, so a Finder-launched app finds the same CLIs.
    static func shell(_ command: String, stdin: String? = nil, directory: URL = FileManager.default.temporaryDirectory,
                      onLine: (@Sendable (String) -> Void)? = nil) async throws -> (out: String, err: String, code: Int32) {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", "export PATH=\(Sources.quoted(userPath)); \(command)"]
                p.currentDirectoryURL = directory
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
    static func models(for p: Provider, settings: Settings = Settings()) async -> [ModelOption] {
        let auto = ModelOption(id: "", name: "default", detail: "whatever \(p.label) uses")
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
        case .gemini:
            return [auto, ModelOption(id: "auto", name: "Auto", detail: "Gemini CLI automatic selection"),
                    ModelOption(id: "pro", name: "Pro", detail: "Gemini CLI Pro alias"),
                    ModelOption(id: "flash", name: "Flash", detail: "Gemini CLI Flash alias")]
        case .compatible:
            return (try? await compatibleModels(settings: settings)) ?? []
        case .ollama:
            return (await ollamaModels(host: settings.ollamaHost) ?? []).map { ModelOption(id: $0, name: $0, detail: "Ollama server") }
        }
    }

    /// Detects CLI login or server availability; Gemini checks its non-secret login choice.
    static func signedIn(_ p: Provider, settings: Settings = Settings()) async -> Bool {
        switch p {
        case .claude: return (try? await shell("claude auth status"))?.out.contains(#""loggedIn": true"#) == true
        case .codex:
            // codex prints its status on stderr.
            if let r = try? await shell("codex login status") { return r.code == 0 && (r.out + r.err).localizedCaseInsensitiveContains("logged in") } else { return false }
        case .ollama: return await ollamaModels(host: settings.ollamaHost) != nil
        case .compatible: return (try? await compatibleModels(settings: settings)) != nil
        case .gemini:
            // Only read the non-secret login choice; the test button verifies the session.
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/settings.json")
            let obj = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let auth = (obj?["security"] as? [String: Any])?["auth"] as? [String: Any]
            return auth?["selectedType"] as? String != nil
                || ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.isEmpty == false
                || ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]?.isEmpty == false
        }
    }

    static func ollamaModels(host: String? = nil) async -> [String]? {
        guard let url = try? endpoint(ollamaBase(host), path: "api/tags"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        return (try? JSONDecoder().decode(Tags.self, from: data))?.models.map(\.name)
    }

    /// `model` empty = whatever the tool itself defaults to.
    /// `onText` receives the answer so far, as it's written (Claude and Ollama stream; ChatGPT doesn't).
    static func complete(_ prompt: String, with provider: Provider, ollamaModel: String, model: String = "", settings: Settings = Settings(),
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
            if let m = missing(r, "claude") { throw AIError(message: m) }
            return try parseClaude(r.out, err: r.err)
        case .codex:
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("sorcerer-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: file) }
            let r = try await shell(
                "codex exec --skip-git-repo-check --ephemeral -s read-only\(pick) -o '\(file.path)' -", stdin: prompt
            )
            guard r.code == 0, let text = try? String(contentsOf: file, encoding: .utf8) else {
                throw AIError(message: missing(r, "codex") ?? "ChatGPT: " + tail(r.err))
            }
            return Reply(text: text)
        case .gemini:
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sorcerer-gemini-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let config = directory.appendingPathComponent("settings.json")
            try JSONSerialization.data(withJSONObject: geminiSettings).write(to: config)
            let r = try await shell(geminiCommand(model: model, config: config), stdin: prompt, directory: directory)
            if let m = missing(r, "gemini") { throw AIError(message: m) }
            return try parseGemini(r.out, err: r.err, code: r.code)
        case .compatible:
            return try await compatibleComplete(prompt, model: model, settings: settings)
        case .ollama:
            var req = URLRequest(url: try endpoint(ollamaBase(settings.ollamaHost), path: "api/generate"))
            req.httpMethod = "POST"
            req.timeoutInterval = 600
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model.isEmpty ? ollamaModel : model, "prompt": prompt, "stream": true,
            ])
            // One JSON object per line: {"response":"…","done":false}
            struct Chunk: Decodable { let response: String?; let error: String? }
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            try checkHTTP(response)
            var text = ""
            for try await line in bytes.lines {
                guard let c = try? JSONDecoder().decode(Chunk.self, from: Data(line.utf8)) else { continue }
                if let e = c.error { throw AIError(message: "Ollama: " + e) }
                text += c.response ?? ""
                onText?(text)
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError(message: "Ollama returned no text. Check the model in Settings › Providers.") }
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

    /// A readable message when the CLI itself can't be found, instead of zsh's "command not found".
    static func missing(_ r: (out: String, err: String, code: Int32), _ binary: String) -> String? {
        guard r.code == 127 || r.err.contains("command not found: \(binary)") else { return nil }
        return "Couldn't find the \(binary) CLI. Install it and sign in, or pick another AI in Settings › Providers. Looked in: \(userPath.split(separator: ":").prefix(4).joined(separator: ", "))…"
    }

    private static func tail(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "no output" : String(t.suffix(300))
    }
}
