import Foundation

/// The enforcement point.
///
/// `ConsentGate` wraps an `AIProviding` and refuses to forward anything unless
/// consent is currently valid. Every call site in the app should hold a gate,
/// never a bare provider. That way "did we check consent here?" is not a
/// question anyone has to answer per call site — it is structurally impossible
/// to skip.
///
/// The gate is an actor so the consent snapshot cannot be read on one thread
/// while being mutated on another.
public actor ConsentGate: AIProviding {

    /// Supplies the current decision. Kept as a closure so the gate does not
    /// need to be `@MainActor` just to read an observable controller.
    public typealias ConsentSnapshot = @Sendable () -> Bool

    private let upstream: AIProviding
    private let isConsentGranted: ConsentSnapshot
    private let redaction: RedactionPolicy
    private let budget: BudgetGuard?

    public init(
        upstream: AIProviding,
        isConsentGranted: @escaping ConsentSnapshot,
        redaction: RedactionPolicy = .none,
        budget: BudgetGuard? = nil
    ) {
        self.upstream = upstream
        self.isConsentGranted = isConsentGranted
        self.redaction = redaction
        self.budget = budget
    }

    public func send(_ request: AIRequest) async throws -> AIResponse {
        try await preflight()
        let cleaned = redaction.apply(to: request)
        let response = try await upstream.send(cleaned)
        await budget?.record(response.usage)
        return response
    }

    public func stream(_ request: AIRequest) async throws -> AsyncThrowingStream<AIStreamEvent, Error> {
        try await preflight()
        let cleaned = redaction.apply(to: request)
        let upstreamStream = try await upstream.stream(cleaned)
        let budget = self.budget

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in upstreamStream {
                        if case .completed(let usage) = event {
                            await budget?.record(usage)
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func preflight() async throws {
        guard isConsentGranted() else {
            throw AIError.consentNotGranted
        }
        if let budget, await budget.isExhausted {
            throw AIError.budgetExhausted
        }
    }
}
