import Foundation

/// Deterministic provider for tests, SwiftUI previews, and — importantly —
/// the App Review demo path.
///
/// If your AI feature depends on a paid backend, a reviewer with a throttled
/// account may see an error and reject for "app is incomplete". Wiring a demo
/// account to a scripted provider avoids that. Document it in the App Review
/// notes; see Docs/APP_REVIEW_NOTES.md.
public struct MockProvider: AIProviding {
    public enum Behavior: Sendable {
        case succeed(String)
        case fail(AIError)
        /// Emits chunks with a delay to exercise streaming UI.
        case stream([String], chunkDelay: Duration)
    }

    private let behavior: Behavior

    public init(behavior: Behavior = .succeed("This is a sample response.")) {
        self.behavior = behavior
    }

    public func send(_ request: AIRequest) async throws -> AIResponse {
        switch behavior {
        case .succeed(let text):
            return AIResponse(text: text, usage: AIUsage(inputTokens: 10, outputTokens: text.count / 4))
        case .fail(let error):
            throw error
        case .stream(let chunks, _):
            let text = chunks.joined()
            return AIResponse(text: text, usage: AIUsage(inputTokens: 10, outputTokens: text.count / 4))
        }
    }

    public func stream(_ request: AIRequest) async throws -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                switch behavior {
                case .fail(let error):
                    continuation.finish(throwing: error)

                case .succeed(let text):
                    continuation.yield(.started(AIUsage(inputTokens: 10)))
                    continuation.yield(.delta(text))
                    continuation.yield(.completed(AIUsage(inputTokens: 10, outputTokens: text.count / 4)))
                    continuation.finish()

                case .stream(let chunks, let delay):
                    continuation.yield(.started(AIUsage(inputTokens: 10)))
                    for chunk in chunks {
                        if Task.isCancelled { break }
                        try? await Task.sleep(for: delay)
                        continuation.yield(.delta(chunk))
                    }
                    let total = chunks.joined()
                    continuation.yield(.completed(AIUsage(inputTokens: 10, outputTokens: total.count / 4)))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
