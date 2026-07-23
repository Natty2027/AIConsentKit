import Foundation

/// Exponential backoff with full jitter.
///
/// Jitter is not decoration. Without it, every client that hit a 429 at the
/// same moment retries at the same moment, and you re-create the overload you
/// were backing off from. Full jitter — a random wait in `[0, computed]` —
/// spreads them out.
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 8) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public static let `default` = RetryPolicy()
    public static let none = RetryPolicy(maxAttempts: 1)

    /// Delay before attempt `attempt` (1-indexed). Honors a server hint if given.
    public func delay(forAttempt attempt: Int, serverHint: TimeInterval? = nil) -> TimeInterval {
        if let hint = serverHint { return min(hint, maxDelay) }
        let exponential = baseDelay * pow(2, Double(attempt - 1))
        let capped = min(exponential, maxDelay)
        return Double.random(in: 0...capped)
    }

    /// Runs `operation`, retrying retryable failures.
    public func run<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: AIError = .timeout

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                let aiError = AIError.from(error)
                lastError = aiError

                guard aiError.isRetryable, attempt < maxAttempts else {
                    throw aiError
                }

                let wait = delay(forAttempt: attempt, serverHint: aiError.retryAfter)
                try await Task.sleep(for: .seconds(wait))
            }
        }

        throw lastError
    }
}
