import Foundation
import Security

extension AI {
    static func ollamaBase(_ saved: String?, environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let saved = saved?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? (environment["OLLAMA_HOST"].flatMap { $0.isEmpty ? nil : $0 } ?? "http://localhost:11434") : saved
    }

    static func endpoint(_ base: String, path: String) throws -> URL {
        let raw = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: raw), ["http", "https"].contains(c.scheme?.lowercased() ?? ""),
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, let url = c.url,
              c.port.map({ (1...65535).contains($0) }) ?? true else {
            throw AIError(message: "Invalid server URL. Use an http:// or https:// address without credentials, query or fragment.")
        }
        return url.appendingPathComponent(path)
    }

    static func checkHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError(message: "Server returned HTTP \(code). Check the endpoint, API key and model in Settings › Providers.")
        }
    }

    // A redirect must never forward an API key to a different endpoint.
    final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    static let endpointSession = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)

    static func compatibleRequest(settings: Settings, path: String, key: String?) throws -> URLRequest {
        var req = URLRequest(url: try endpoint(settings.compatibleURL ?? "http://localhost:1234/v1", path: path))
        req.timeoutInterval = path == "models" ? 15 : 600
        if let key, !key.isEmpty { req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    static func compatibleModels(settings: Settings, session: URLSession = endpointSession) async throws -> [ModelOption] {
        let key = try EndpointKey.read(base: settings.compatibleURL)
        let req = try compatibleRequest(settings: settings, path: "models", key: key)
        let (data, response) = try await session.data(for: req)
        try checkHTTP(response)
        struct Models: Decodable { struct Model: Decodable { var id: String }; var data: [Model] }
        return try JSONDecoder().decode(Models.self, from: data).data.map { ModelOption(id: $0.id, name: $0.id, detail: "endpoint model") }
    }

    static func compatibleComplete(_ prompt: String, model: String, settings: Settings,
                                   session: URLSession = endpointSession) async throws -> Reply {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError(message: "Choose or enter a model for your endpoint in Settings › Providers.")
        }
        let key = try EndpointKey.read(base: settings.compatibleURL)
        var req = try compatibleRequest(settings: settings, path: "chat/completions", key: key)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": [["role": "user", "content": prompt]], "stream": false,
        ])
        let (data, response) = try await session.data(for: req)
        try checkHTTP(response)
        return try parseCompatible(data)
    }

    static func parseCompatible(_ data: Data) throws -> Reply {
        struct Completion: Decodable {
            struct Choice: Decodable { struct Message: Decodable { var content: String? }; var message: Message }
            var choices: [Choice]
        }
        guard let result = try? JSONDecoder().decode(Completion.self, from: data),
              let text = result.choices.first?.message.content, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError(message: "The endpoint returned no text. Check that the model supports Chat Completions.")
        }
        return Reply(text: text)
    }

    static let geminiSettings: [String: Any] = [
        "tools": ["core": [String](), "discoveryCommand": "", "callCommand": ""],
        "admin": ["mcp": ["enabled": false], "extensions": ["enabled": false], "skills": ["enabled": false]],
        "hooksConfig": ["enabled": false],
        "context": ["fileName": [String]()],
    ]

    static func geminiCommand(model: String, config: URL) -> String {
        "GEMINI_CLI_SYSTEM_SETTINGS_PATH=" + Sources.quoted(config.path) + " gemini -p '' --output-format json"
            + (model.isEmpty ? "" : " --model " + Sources.quoted(model))
    }

    static func parseGemini(_ out: String, err: String = "", code: Int32 = 0) throws -> Reply {
        struct Result: Decodable { var response: String?; var error: Failure? }
        struct Failure: Decodable { var message: String? }
        guard let result = try? JSONDecoder().decode(Result.self, from: Data(out.utf8)) else {
            throw AIError(message: code == 0 ? "Gemini returned invalid JSON. Update the CLI and try again." : "Gemini: " + String(err.suffix(300)))
        }
        if let error = result.error { throw AIError(message: "Gemini: " + (error.message ?? "request failed")) }
        guard code == 0 else { throw AIError(message: "Gemini: " + String(err.suffix(300))) }
        guard let text = result.response, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError(message: "Gemini returned no text. Run gemini in Terminal to check your login.")
        }
        return Reply(text: text)
    }
}

/// One key per endpoint; a host change cannot send the previous host's key.
enum EndpointKey {
    static func account(_ base: String?) throws -> String {
        try AI.endpoint(base ?? "http://localhost:1234/v1", path: "").absoluteString
    }
    private static func query(_ base: String?) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.sorcerer.endpoint",
         kSecAttrAccount as String: try account(base)]
    }
    static func read(base: String?) throws -> String? {
        var q = try query(base)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String, base: String?) throws {
        let q = try query(base)
        if value.isEmpty {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
            return
        }
        let values: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(q as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = q.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    private static func failure(_ status: OSStatus) -> AIError {
        AIError(message: "Keychain couldn't access the endpoint key (\(status)). Try saving it again in Settings › Providers.")
    }
}
