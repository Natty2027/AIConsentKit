import Foundation

/// The provider you should actually ship.
///
/// Talks to *your* backend, which holds the vendor API key and forwards to
/// Anthropic or OpenAI. Three things this buys you beyond key safety:
///
/// 1. You can switch model vendors without shipping an app update.
/// 2. You can enforce per-user rate limits server-side, where they cannot be
///    bypassed by a modified client.
/// 3. Your backend can strip or hash identifiers before they reach the vendor,
///    which narrows what you have to disclose under 5.1.2(i).
///
/// Expects the backend to emit the same SSE shape as this kit's neutral events:
///   event: started      data: {"input_tokens": 12}
///   event: delta        data: {"text": "..."}
///   event: completed    data: {"input_tokens": 12, "output_tokens": 340}
///   event: error        data: {"message": "...", "type": "rate_limit"}
///
/// A reference Express handler is in Docs/INTEGRATION.md.
public struct ProxyProvider: AIProviding {

    public struct Configuration: Sendable {
        public var baseURL: URL
        /// Your own auth, e.g. a Clerk session token. Never a vendor API key.
        public var authTokenProvider: @Sendable () async throws -> String?
        public var session: URLSession
        public var retryPolicy: RetryPolicy

        public init(
            baseURL: URL,
            authTokenProvider: @escaping @Sendable () async throws -> String? = { nil },
            session: URLSession = .shared,
            retryPolicy: RetryPolicy = .default
        ) {
            self.baseURL = baseURL
            self.authTokenProvider = authTokenProvider
            self.session = session
            self.retryPolicy = retryPolicy
        }
    }

    private let config: Configuration

    public init(configuration: Configuration) {
        self.config = configuration
    }

    public func send(_ request: AIRequest) async throws -> AIResponse {
        try await config.retryPolicy.run {
            let urlRequest = try await makeRequest(request, path: "v1/chat")
            let (data, response) = try await config.session.data(for: urlRequest)
            try Self.validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            return AIResponse(
                text: decoded.text,
                usage: AIUsage(inputTokens: decoded.inputTokens, outputTokens: decoded.outputTokens)
            )
        }
    }

    public func stream(_ request: AIRequest) async throws -> AsyncThrowingStream<AIStreamEvent, Error> {
        let urlRequest = try await makeRequest(request, path: "v1/chat/stream")
        let (bytes, response) = try await config.session.bytes(for: urlRequest)
        try Self.validate(response: response, data: nil)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                do {
                    for try await line in bytes.lines {
                        for event in parser.consume(line + "\n") {
                            if let emitted = try Self.translate(event) {
                                continuation.yield(emitted)
                            }
                        }
                    }
                    if let trailing = parser.finish(), let emitted = try Self.translate(trailing) {
                        continuation.yield(emitted)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func translate(_ event: SSEEvent) throws -> AIStreamEvent? {
        guard let name = event.name else { return nil }
        let data = Data(event.data.utf8)

        switch name {
        case "started":
            let payload = try JSONDecoder().decode(UsageEnvelope.self, from: data)
            return .started(AIUsage(inputTokens: payload.inputTokens, outputTokens: payload.outputTokens))
        case "delta":
            let payload = try JSONDecoder().decode(DeltaEnvelope.self, from: data)
            return .delta(payload.text)
        case "completed":
            let payload = try JSONDecoder().decode(UsageEnvelope.self, from: data)
            return .completed(AIUsage(inputTokens: payload.inputTokens, outputTokens: payload.outputTokens))
        case "error":
            let payload = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw AIError.providerError(
                message: payload?.message ?? "Unknown proxy error",
                type: payload?.type
            )
        default:
            return nil
        }
    }

    private func makeRequest(_ request: AIRequest, path: String) async throws -> URLRequest {
        var urlRequest = URLRequest(url: config.baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token = try await config.authTokenProvider() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }

        var body: [String: Any] = [
            "max_tokens": request.maxTokens,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        ]
        if let system = request.system { body["system"] = system }
        if let temperature = request.temperature { body["temperature"] = temperature }
        if let model = request.model { body["model"] = model }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private static func validate(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = data.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }
            throw AIError.http(
                status: http.statusCode,
                message: envelope?.message,
                retryAfter: http.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
            )
        }
    }

    private struct ChatResponse: Decodable {
        let text: String
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case text
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    private struct UsageEnvelope: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
            outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        }
    }

    private struct DeltaEnvelope: Decodable {
        let text: String
    }

    private struct ErrorEnvelope: Decodable {
        let message: String
        let type: String?
    }
}
