import Foundation

/// Direct-to-Anthropic provider.
///
/// **Ship this only behind `#if DEBUG`.** Talking to a model vendor straight
/// from the app means the API key is in the binary, and a key in a binary is a
/// key on the internet — `strings` on an extracted IPA finds it in seconds.
/// Use `ProxyProvider` in production. This type exists so you can develop
/// without standing up a backend first, and so the wire format is documented
/// somewhere readable.
///
/// Wire format reference: https://platform.claude.com/docs/en/build-with-claude/streaming
public struct AnthropicProvider: AIProviding {

    public struct Configuration: Sendable {
        public var apiKey: String
        public var baseURL: URL
        public var apiVersion: String
        public var defaultModel: String
        public var session: URLSession

        public init(
            apiKey: String,
            baseURL: URL = URL(string: "https://api.anthropic.com")!,
            apiVersion: String = "2023-06-01",
            defaultModel: String = "claude-sonnet-5",
            session: URLSession = .shared
        ) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.apiVersion = apiVersion
            self.defaultModel = defaultModel
            self.session = session
        }
    }

    private let config: Configuration

    public init(configuration: Configuration) {
        self.config = configuration
    }

    // MARK: - Non-streaming

    public func send(_ request: AIRequest) async throws -> AIResponse {
        let urlRequest = try makeRequest(request, stream: false)
        let (data, response) = try await config.session.data(for: urlRequest)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()

        return AIResponse(
            text: text,
            usage: AIUsage(
                inputTokens: decoded.usage.inputTokens,
                outputTokens: decoded.usage.outputTokens
            ),
            stopReason: decoded.stopReason
        )
    }

    // MARK: - Streaming

    public func stream(_ request: AIRequest) async throws -> AsyncThrowingStream<AIStreamEvent, Error> {
        let urlRequest = try makeRequest(request, stream: true)
        let (bytes, response) = try await config.session.bytes(for: urlRequest)
        try Self.validate(response: response, data: nil)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                var usage = AIUsage()
                do {
                    for try await line in bytes.lines {
                        // `bytes.lines` already splits on newlines, so re-add one
                        // to preserve SSE's blank-line event terminator.
                        for event in parser.consume(line + "\n") {
                            guard let emitted = try Self.translate(event, usage: &usage) else { continue }
                            continuation.yield(emitted)
                        }
                    }
                    if let trailing = parser.finish() {
                        if let emitted = try Self.translate(trailing, usage: &usage) {
                            continuation.yield(emitted)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Maps one Anthropic SSE event to a provider-neutral event.
    /// Returns nil for events the app does not need (ping, block boundaries).
    private static func translate(_ event: SSEEvent, usage: inout AIUsage) throws -> AIStreamEvent? {
        guard let name = event.name else { return nil }
        let data = Data(event.data.utf8)

        switch name {
        case "message_start":
            let payload = try JSONDecoder().decode(MessageStartEvent.self, from: data)
            usage.inputTokens = payload.message.usage.inputTokens
            return .started(usage)

        case "content_block_delta":
            let payload = try JSONDecoder().decode(ContentBlockDeltaEvent.self, from: data)
            guard payload.delta.type == "text_delta", let text = payload.delta.text else { return nil }
            return .delta(text)

        case "message_delta":
            // Usage on message_delta is cumulative, so assign rather than add.
            let payload = try JSONDecoder().decode(MessageDeltaEvent.self, from: data)
            if let output = payload.usage?.outputTokens {
                usage.outputTokens = output
            }
            return nil

        case "message_stop":
            return .completed(usage)

        case "error":
            let payload = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw AIError.providerError(
                message: payload?.error.message ?? "Unknown streaming error",
                type: payload?.error.type
            )

        default:
            // ping, content_block_start, content_block_stop
            return nil
        }
    }

    // MARK: - Request building

    private func makeRequest(_ request: AIRequest, stream: Bool) throws -> URLRequest {
        var urlRequest = URLRequest(url: config.baseURL.appendingPathComponent("v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(config.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": request.model ?? config.defaultModel,
            "max_tokens": request.maxTokens,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        ]
        if let system = request.system { body["system"] = system }
        if let temperature = request.temperature { body["temperature"] = temperature }
        if stream { body["stream"] = true }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private static func validate(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = data.flatMap { try? JSONDecoder().decode(APIErrorEnvelope.self, from: $0) }
            throw AIError.http(
                status: http.statusCode,
                message: envelope?.error.message,
                retryAfter: http.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
            )
        }
    }
}

// MARK: - Wire types

private extension AnthropicProvider {
    struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let usage: UsagePayload
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content, usage
            case stopReason = "stop_reason"
        }
    }

    /// Lenient on purpose. A missing or newly-added usage field should not
    /// abort an otherwise good stream mid-response.
    struct UsagePayload: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
            outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        }
    }

    struct PartialUsagePayload: Decodable {
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case outputTokens = "output_tokens"
        }
    }

    struct MessageStartEvent: Decodable {
        struct Message: Decodable { let usage: UsagePayload }
        let message: Message
    }

    struct ContentBlockDeltaEvent: Decodable {
        struct Delta: Decodable {
            let type: String
            let text: String?
        }
        let delta: Delta
    }

    struct MessageDeltaEvent: Decodable {
        let usage: PartialUsagePayload?
    }

    struct APIErrorEnvelope: Decodable {
        struct Payload: Decodable {
            let type: String?
            let message: String
        }
        let error: Payload
    }
}
