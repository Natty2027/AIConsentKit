import XCTest
@testable import AIConsentKit

final class ConsentTests: XCTestCase {

    private func makeDisclosure(version: Int = 1, categories: [DataCategory] = [.promptText]) -> AIDataDisclosure {
        AIDataDisclosure(
            version: version,
            categories: categories,
            recipients: [.anthropic],
            firstPartyPrivacyPolicyURL: URL(string: "https://example.com/privacy")!,
            declineConsequence: "The rest of the app still works."
        )
    }

    func testFingerprintChangesWhenCategoryAdded() {
        let narrow = makeDisclosure(categories: [.promptText])
        let wide = makeDisclosure(categories: [.promptText, .photoContent])
        XCTAssertNotEqual(narrow.fingerprint, wide.fingerprint)
    }

    func testFingerprintStableAcrossCategoryReordering() {
        let a = makeDisclosure(categories: [.promptText, .photoContent])
        let b = makeDisclosure(categories: [.photoContent, .promptText])
        XCTAssertEqual(a.fingerprint, b.fingerprint)
    }

    /// The whole point of the kit: consent for a narrow disclosure must not
    /// silently authorize a wider one.
    func testConsentDoesNotCarryOverToWiderDisclosure() {
        let narrow = makeDisclosure(categories: [.promptText])
        let record = ConsentRecord(
            decision: .granted,
            disclosureVersion: narrow.version,
            disclosureFingerprint: narrow.fingerprint
        )
        let wide = makeDisclosure(version: 1, categories: [.promptText, .photoContent])
        XCTAssertTrue(record.isValid(for: narrow))
        XCTAssertFalse(record.isValid(for: wide), "Adding a data category must invalidate prior consent")
    }

    func testVersionBumpInvalidatesConsent() {
        let v1 = makeDisclosure(version: 1)
        let record = ConsentRecord(
            decision: .granted,
            disclosureVersion: 1,
            disclosureFingerprint: v1.fingerprint
        )
        let v2 = makeDisclosure(version: 2)
        XCTAssertFalse(record.isValid(for: v2))
    }

    func testDeniedRecordIsNeverValid() {
        let disclosure = makeDisclosure()
        let record = ConsentRecord(
            decision: .denied,
            disclosureVersion: disclosure.version,
            disclosureFingerprint: disclosure.fingerprint
        )
        XCTAssertFalse(record.isValid(for: disclosure))
    }

    func testStoreRoundTrip() throws {
        let store = InMemoryConsentStore()
        let disclosure = makeDisclosure()
        let record = ConsentRecord(
            decision: .granted,
            disclosureVersion: disclosure.version,
            disclosureFingerprint: disclosure.fingerprint
        )
        try store.save(record)
        let loaded = try store.load()
        XCTAssertEqual(loaded?.decision, .granted)
        try store.clear()
        XCTAssertNil(try store.load())
    }
}
