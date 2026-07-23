import Foundation

public enum AIRole: String, Codable, Hashable, Sendable {
    case user
    case assistant
}

public struct AIMessage: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let role: AIRole
    public var text: String

    public init(id: UUID = UUID(), role: AIRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// Provider-neutral request.
///
/// Nothing vendor-specific lives here. That is the point: swapping Anthropic
/// for OpenAI, or swapping a direct call for your own proxy, should not touch
/// a single call site.
public struct AIRequest: Hashable, Sendable {
    public var system: String?
    public var messages: [AIMessage]
    public var maxTokens: Int
    public var temperature: Double?
    /// Opaque model identifier. Interpreted by the provider, not by callers.
    public var model: String?

    public init(
        system: String? = nil,
        messages: [AIMessage],
        maxTokens: Int = 1024,
        temperature: Double? = nil,
        model: String? = nil
    ) {
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.model = model
    }
}

public struct AIUsage: Hashable, Sendable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    public static func + (lhs: AIUsage, rhs: AIUsage) -> AIUsage {
        AIUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens
        )
    }
}

public struct AIResponse: Hashable, Sendable {
    public var text: String
    public var usage: AIUsage
    public var stopReason: String?

    public init(text: String, usage: AIUsage, stopReason: String? = nil) {
        self.text = text
        self.usage = usage
        self.stopReason = stopReason
    }
}

/// Events emitted while streaming.
public enum AIStreamEvent: Hashable, Sendable {
    /// The request was accepted and the model has begun. Carries input token count.
    case started(AIUsage)
    /// An incremental chunk of text. Append it; do not replace.
    case delta(String)
    /// Terminal event with final cumulative usage.
    case completed(AIUsage)
}

/// Everything the app talks to. One protocol, four implementations in this kit:
/// proxy (recommended), Anthropic direct, OpenAI direct, and mock.
public protocol AIProviding: Sendable {
    func send(_ request: AIRequest) async throws -> AIResponse
    func stream(_ request: AIRequest) async throws -> AsyncThrowingStream<AIStreamEvent, Error>
}

public extension AIProviding {
    /// Convenience: collect a stream into a single response.
    func collect(_ request: AIRequest) async throws -> AIResponse {
        var text = ""
        var usage = AIUsage()
        for try await event in try await stream(request) {
            switch event {
            case .started(let u): usage = u
            case .delta(let chunk): text += chunk
            case .completed(let u): usage = u
            }
        }
        return AIResponse(text: text, usage: usage)
    }
}
