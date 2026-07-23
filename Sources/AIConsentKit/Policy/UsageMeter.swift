import Foundation

/// Per-model token pricing, in dollars per million tokens.
///
/// Prices change. Do not hardcode these in a shipping build — fetch them from
/// your backend so a vendor price change does not require an app update.
/// The values you seed here are a fallback for offline launch only.
public struct ModelPricing: Hashable, Sendable, Codable {
    public let inputPerMillion: Decimal
    public let outputPerMillion: Decimal

    public init(inputPerMillion: Decimal, outputPerMillion: Decimal) {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
    }

    public func cost(for usage: AIUsage) -> Decimal {
        let input = Decimal(usage.inputTokens) * inputPerMillion / 1_000_000
        let output = Decimal(usage.outputTokens) * outputPerMillion / 1_000_000
        return input + output
    }
}

/// Running total of tokens and estimated spend.
///
/// Surface this in the UI. "How much is this costing me" is the single most
/// common anxiety from clients shipping an AI feature, and a visible meter is
/// the cheapest possible answer.
public actor UsageMeter {
    public private(set) var total = AIUsage()
    public private(set) var requestCount = 0
    private var pricing: ModelPricing?

    public init(pricing: ModelPricing? = nil) {
        self.pricing = pricing
    }

    public func updatePricing(_ newPricing: ModelPricing) {
        pricing = newPricing
    }

    public func record(_ usage: AIUsage) {
        total = total + usage
        requestCount += 1
    }

    public func reset() {
        total = AIUsage()
        requestCount = 0
    }

    public var estimatedCost: Decimal? {
        pricing?.cost(for: total)
    }

    public var formattedCost: String? {
        guard let cost = estimatedCost else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: cost as NSDecimalNumber)
    }
}

/// Stops runaway spend before it happens.
///
/// A budget is enforced by `ConsentGate` on every call. Set it generously; the
/// point is to catch a retry loop or a prompt-injection-driven token bomb, not
/// to nickel-and-dime normal use.
public actor BudgetGuard {
    private let meter: UsageMeter
    private let maxTokensPerWindow: Int
    private let window: TimeInterval
    private var windowStart = Date()
    private var tokensThisWindow = 0

    public init(
        meter: UsageMeter = UsageMeter(),
        maxTokensPerWindow: Int = 200_000,
        window: TimeInterval = 60 * 60 * 24
    ) {
        self.meter = meter
        self.maxTokensPerWindow = maxTokensPerWindow
        self.window = window
    }

    public func record(_ usage: AIUsage) async {
        rollWindowIfNeeded()
        tokensThisWindow += usage.inputTokens + usage.outputTokens
        await meter.record(usage)
    }

    public var isExhausted: Bool {
        rollWindowIfNeeded()
        return tokensThisWindow >= maxTokensPerWindow
    }

    public var remainingTokens: Int {
        rollWindowIfNeeded()
        return max(0, maxTokensPerWindow - tokensThisWindow)
    }

    public var resetsAt: Date {
        windowStart.addingTimeInterval(window)
    }

    private func rollWindowIfNeeded() {
        if Date().timeIntervalSince(windowStart) >= window {
            windowStart = Date()
            tokensThisWindow = 0
        }
    }
}
