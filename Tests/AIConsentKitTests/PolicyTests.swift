import XCTest
@testable import AIConsentKit

final class RedactionPolicyTests: XCTestCase {

    func testRemovesEmail() {
        let out = RedactionPolicy.standard.apply(to: "reach me at a.b+c@example.co.uk please")
        XCTAssertFalse(out.contains("@example.co.uk"))
        XCTAssertTrue(out.contains("[email removed]"))
    }

    func testRemovesSSN() {
        let out = RedactionPolicy.standard.apply(to: "SSN 123-45-6789")
        XCTAssertTrue(out.contains("[SSN removed]"))
    }

    func testRemovesCardNumber() {
        let out = RedactionPolicy.standard.apply(to: "card 4111 1111 1111 1111 exp 12/29")
        XCTAssertFalse(out.contains("4111 1111 1111 1111"))
    }

    func testNonePolicyIsIdentity() {
        let input = "email me at x@y.com"
        XCTAssertEqual(RedactionPolicy.none.apply(to: input), input)
    }

    func testAuditReportsCountsWithoutLeakingMatches() {
        let counts = RedactionPolicy.standard.audit("a@b.com and c@d.com")
        XCTAssertEqual(counts["email"], 2)
    }

    func testAppliesAcrossAllMessages() {
        let request = AIRequest(messages: [
            AIMessage(role: .user, text: "a@b.com"),
            AIMessage(role: .assistant, text: "noted"),
            AIMessage(role: .user, text: "c@d.com")
        ])
        let cleaned = RedactionPolicy.standard.apply(to: request)
        XCTAssertFalse(cleaned.messages.contains { $0.text.contains("@") })
        XCTAssertEqual(cleaned.messages.count, 3)
    }
}

final class UsageMeterTests: XCTestCase {

    func testAccumulatesUsage() async {
        let meter = UsageMeter()
        await meter.record(AIUsage(inputTokens: 100, outputTokens: 50))
        await meter.record(AIUsage(inputTokens: 20, outputTokens: 10))
        let total = await meter.total
        XCTAssertEqual(total.inputTokens, 120)
        XCTAssertEqual(total.outputTokens, 60)
        let count = await meter.requestCount
        XCTAssertEqual(count, 2)
    }

    func testCostCalculation() async {
        let pricing = ModelPricing(inputPerMillion: 3, outputPerMillion: 15)
        let meter = UsageMeter(pricing: pricing)
        await meter.record(AIUsage(inputTokens: 1_000_000, outputTokens: 1_000_000))
        let cost = await meter.estimatedCost
        XCTAssertEqual(cost, 18)
    }

    func testNoPricingMeansNoCost() async {
        let meter = UsageMeter()
        await meter.record(AIUsage(inputTokens: 100, outputTokens: 100))
        let cost = await meter.estimatedCost
        XCTAssertNil(cost)
    }
}

final class RetryPolicyTests: XCTestCase {

    func testRetriesRetryableErrors() async throws {
        let counter = AttemptCounter()
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.001, maxDelay: 0.002)

        let result: String = try await policy.run {
            let n = await counter.increment()
            if n < 3 { throw AIError.timeout }
            return "succeeded on \(n)"
        }

        XCTAssertEqual(result, "succeeded on 3")
    }

    func testDoesNotRetryNonRetryableErrors() async {
        let counter = AttemptCounter()
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.001)

        do {
            _ = try await policy.run { () -> String in
                _ = await counter.increment()
                throw AIError.consentNotGranted
            }
            XCTFail("Should have thrown")
        } catch {
            let attempts = await counter.value
            XCTAssertEqual(attempts, 1, "Consent failures must not be retried")
        }
    }

    func testJitterStaysWithinBounds() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 4)
        for attempt in 1...5 {
            let d = policy.delay(forAttempt: attempt)
            XCTAssertGreaterThanOrEqual(d, 0)
            XCTAssertLessThanOrEqual(d, 4)
        }
    }

    func testServerHintOverridesBackoff() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 30)
        XCTAssertEqual(policy.delay(forAttempt: 1, serverHint: 7), 7)
    }
}

private actor AttemptCounter {
    private(set) var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}
