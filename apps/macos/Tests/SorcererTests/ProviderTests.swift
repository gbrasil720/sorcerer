@testable import Sorcerer
import XCTest

final class ProviderTests: XCTestCase {
    func testOllamaDefaultAndPrecedence() throws {
        XCTAssertEqual(AI.ollamaBase(nil, environment: [:]), "http://localhost:11434")
        XCTAssertEqual(AI.ollamaBase("", environment: ["OLLAMA_HOST": "http://mac.local:11435"]), "http://mac.local:11435")
        let saved = AI.ollamaBase("http://localhost:11436/", environment: ["OLLAMA_HOST": "http://other:11434"])
        XCTAssertEqual(try AI.endpoint(saved, path: "api/tags").absoluteString, "http://localhost:11436/api/tags")
        XCTAssertEqual(try AI.endpoint(saved, path: "api/generate").absoluteString, "http://localhost:11436/api/generate")
    }

    func testRejectsInvalidAndCredentialURLs() {
        for base in ["", "localhost:11434", "ftp://host", "https://", "https://user:secret@host/v1", "https://host/v1?key=x", "https://host/#x", "http://host:70000"] {
            XCTAssertThrowsError(try AI.endpoint(base, path: "models"), base)
        }
    }

    func testSettingsPreserveExistingFilesAndNeverEncodeKeys() throws {
        let old = Data(#"{"onboarded":true,"characters":"claude","reports":"codex","chats":"ollama","ollamaModel":"test","maxRounds":10}"#.utf8)
        var settings = try JSONDecoder().decode(Settings.self, from: old)
        XCTAssertNil(settings.ollamaHost)
        XCTAssertNil(settings.compatibleURL)
        settings.ollamaHost = "http://mac.local:11435"
        settings.compatibleURL = "https://example.com/v1"
        settings.characters = .gemini
        settings.models = ["compatible": "custom-model"]
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("apiKey"))
    }

    func testCompatibleRequestAndResponse() throws {
        var settings = Settings()
        settings.compatibleURL = "https://example.com/api/v1/"
        let req = try AI.compatibleRequest(settings: settings, path: "chat/completions", key: "fixture-key")
        XCTAssertEqual(req.url?.absoluteString, "https://example.com/api/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        XCTAssertNil(try AI.compatibleRequest(settings: settings, path: "models", key: nil).value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try AI.parseCompatible(Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8)).text, "ok")
        for body in ["{}", #"{"choices":[]}"#, #"{"choices":[{"message":{"content":null}}]}"#, "broken"] {
            XCTAssertThrowsError(try AI.parseCompatible(Data(body.utf8)))
        }
        for code in [301, 401, 429, 500] {
            XCTAssertThrowsError(try AI.checkHTTP(HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)) { error in
                XCTAssertTrue(error.localizedDescription.contains("\(code)"))
                if code == 429 { XCTAssertTrue((error as? AIError)?.isLimit == true) }
            }
        }
    }

    func testKeysAreBoundToEndpoint() throws {
        XCTAssertNotEqual(try EndpointKey.account("https://one.example/v1"), try EndpointKey.account("https://two.example/v1"))
        XCTAssertEqual(try EndpointKey.account("https://one.example/v1/"), try EndpointKey.account("https://one.example/v1"))
    }

    func testGeminiParsingAndCommandEscaping() throws {
        XCTAssertEqual(try AI.parseGemini(#"{"response":"ok","stats":{}}"#).text, "ok")
        for out in ["bad", "{}", #"{"response":""}"#, #"{"error":{"message":"quota exhausted"}}"#] {
            XCTAssertThrowsError(try AI.parseGemini(out))
        }
        XCTAssertThrowsError(try AI.parseGemini(#"{"error":{"message":"quota exhausted"}}"#, code: 1)) { error in
            XCTAssertTrue((error as? AIError)?.isLimit == true)
        }
        let config = URL(fileURLWithPath: "/tmp/test config.json")
        let command = AI.geminiCommand(model: "model'; touch /tmp/unwanted; '", config: config)
        XCTAssertTrue(command.contains(Sources.quoted(config.path)))
        XCTAssertTrue(command.contains(Sources.quoted("model'; touch /tmp/unwanted; '")))
        XCTAssertFalse(command.contains("--yolo"))
        XCTAssertEqual((AI.geminiSettings["tools"] as? [String: Any])?["core"] as? [String], [])
    }

    func testEndpointTransportAndKeychain() async throws {
        let base = "https://" + UUID().uuidString.lowercased() + ".example/v1"
        var settings = Settings()
        settings.compatibleURL = base
        try EndpointKey.save("test-fixture", base: base)
        defer { try? EndpointKey.save("", base: base) }
        XCTAssertEqual(try EndpointKey.read(base: base), "test-fixture")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EndpointProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let models = try await AI.compatibleModels(settings: settings, session: session)
        XCTAssertEqual(models.map(\.id), ["fixture-model"])
        let reply = try await AI.compatibleComplete("hello", model: "fixture-model", settings: settings, session: session)
        XCTAssertEqual(reply.text, "ok")
        try EndpointKey.save("updated-fixture", base: base)
        XCTAssertEqual(try EndpointKey.read(base: base), "updated-fixture")
        try EndpointKey.save("", base: base)
        XCTAssertNil(try EndpointKey.read(base: base))
    }

    func testRedirectIsRefused() {
        let url = URL(string: "https://first.example")!
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let task = URLSession.shared.dataTask(with: url)
        var called = false
        AI.NoRedirect().urlSession(.shared, task: task, willPerformHTTPRedirection: response,
                                  newRequest: URLRequest(url: URL(string: "https://other.example")!)) { request in
            called = true
            XCTAssertNil(request)
        }
        XCTAssertTrue(called)
    }
}

private final class EndpointProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-fixture")
        let body: String
        if request.url!.path.hasSuffix("/models") {
            XCTAssertEqual(request.httpMethod, "GET")
            body = #"{"data":[{"id":"fixture-model"}]}"#
        } else {
            XCTAssertTrue(request.url!.path.hasSuffix("/chat/completions"))
            XCTAssertEqual(request.httpMethod, "POST")
            // URLSession may promote the body to an input stream.
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = stream.read(&bytes, maxLength: bytes.count)
                let obj = try? JSONSerialization.jsonObject(with: Data(bytes.prefix(max(0, count)))) as? [String: Any]
                XCTAssertEqual(obj?["model"] as? String, "fixture-model")
                XCTAssertEqual(obj?["stream"] as? Bool, false)
                XCTAssertEqual((obj?["messages"] as? [[String: String]])?.first?["content"], "hello")
            } else {
                XCTFail("expected request body stream")
            }
            body = #"{"choices":[{"message":{"content":"ok"}}]}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
