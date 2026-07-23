import XCTest
@testable import AIConsentKit

final class ConsentGateTests: XCTestCase {

    private let request = AIRequest(messages: [AIMessage(role: .user, text: "hello")])

    func testBlocksWhenConsentNotGranted() async {
        let gate = ConsentGate(
            upstream: MockProvider(behavior: .succeed("should never be reached")),
            isConsentGranted: { false }
        )

        do {
            _ = try await gate.send(request)
            XCTFail("Gate must refuse to forward without consent")
        } catch let error as AIError {
            XCTAssertEqual(error, .consentNotGranted)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testBlocksStreamingWhenConsentNotGranted() async {
        let gate = ConsentGate(
            upstream: MockProvider(behavior: .succeed("nope")),
            isConsentGranted: { false }
        )

        do {
            _ = try await gate.stream(request)
            XCTFail("Gate must refuse to open a stream without consent")
        } catch let error as AIError {
            XCTAssertEqual(error, .consentNotGranted)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testForwardsWhenConsentGranted() async throws {
        let gate = ConsentGate(
            upstream: MockProvider(behavior: .succeed("hi there")),
            isConsentGranted: { true }
        )
        let response = try await gate.send(request)
        XCTAssertEqual(response.text, "hi there")
    }

    // Regression: the gate is an actor, so `isConsentGranted` runs off the main
    // actor. Reading the controller's @MainActor state from there used to trap.
    // `controller.isGranted` is a thread-safe snapshot that is safe to read here.
    @MainActor
    func testReadsControllerSnapshotFromGateActorContext() async throws {
        let disclosure = AIDataDisclosure(
            version: 1,
            categories: [.promptText],
            recipients: [AIRecipient(
                id: "vendor",
                legalName: "Vendor Inc",
                productName: "Vendor",
                privacyPolicyURL: URL(string: "https://example.com")!,
                usedForModelTraining: false,
                retentionSummary: "none"
            )],
            firstPartyPrivacyPolicyURL: URL(string: "https://example.com/privacy")!,
            declineConsequence: "ok"
        )
        let controller = AIConsentController(disclosure: disclosure, store: InMemoryConsentStore())
        controller.grant()

        let gate = ConsentGate(
            upstream: MockProvider(behavior: .succeed("ok")),
            isConsentGranted: { controller.isGranted }
        )

        let response = try await gate.send(request)
        XCTAssertEqual(response.text, "ok")

        controller.withdraw()
        do {
            _ = try await gate.send(request)
            XCTFail("Withdrawn consent must block")
        } catch let error as AIError {
            XCTAssertEqual(error, .consentNotGranted)
        }
    }

    func testAppliesRedactionBeforeForwarding() async throws {
        let capture = CapturingProvider()
        let gate = ConsentGate(
            upstream: capture,
            isConsentGranted: { true },
            redaction: .standard
        )

        let dirty = AIRequest(messages: [
            AIMessage(role: .user, text: "email me at nathan@example.com about it")
        ])
        _ = try await gate.send(dirty)

        let seen = await capture.lastRequest?.messages.first?.text ?? ""
        XCTAssertFalse(seen.contains("nathan@example.com"), "Redaction must run before the request leaves the gate")
        XCTAssertTrue(seen.contains("[email removed]"))
    }

    func testBudgetExhaustionBlocks() async throws {
        let budget = BudgetGuard(maxTokensPerWindow: 5)
        await budget.record(AIUsage(inputTokens: 10, outputTokens: 0))

        let gate = ConsentGate(
            upstream: MockProvider(behavior: .succeed("x")),
            isConsentGranted: { true },
            budget: budget
        )

        do {
            _ = try await gate.send(request)
            XCTFail("Exhausted budget must block")
        } catch let error as AIError {
            XCTAssertEqual(error, .budgetExhausted)
        }
    }
}

private actor CapturingProvider: AIProviding {
    private(set) var lastRequest: AIRequest?

    func send(_ request: AIRequest) async throws -> AIResponse {
        lastRequest = request
        return AIResponse(text: "ok", usage: AIUsage())
    }

    func stream(_ request: AIRequest) async throws -> AsyncThrowingStream<AIStreamEvent, Error> {
        lastRequest = request
        return AsyncThrowingStream { $0.finish() }
    }
}
