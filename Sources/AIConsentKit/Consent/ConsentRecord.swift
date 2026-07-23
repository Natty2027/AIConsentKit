import Foundation

/// What the user decided, and exactly what they were shown when they decided it.
///
/// Keep this. If App Review asks how consent is obtained, the shape of this
/// record is the answer, and it is also what lets you prove a user was never
/// silently opted in after a disclosure change.
public struct ConsentRecord: Codable, Hashable, Sendable {
    public enum Decision: String, Codable, Sendable {
        case granted
        case denied
    }

    public let decision: Decision
    public let disclosureVersion: Int
    public let disclosureFingerprint: String
    public let decidedAt: Date
    /// App version at time of decision. Useful when reconstructing history.
    public let appVersion: String

    public init(
        decision: Decision,
        disclosureVersion: Int,
        disclosureFingerprint: String,
        decidedAt: Date = Date(),
        appVersion: String = Bundle.main.shortVersionString
    ) {
        self.decision = decision
        self.disclosureVersion = disclosureVersion
        self.disclosureFingerprint = disclosureFingerprint
        self.decidedAt = decidedAt
        self.appVersion = appVersion
    }

    /// Consent applies only to the disclosure the user actually saw.
    public func isValid(for disclosure: AIDataDisclosure) -> Bool {
        decision == .granted
            && disclosureVersion == disclosure.version
            && disclosureFingerprint == disclosure.fingerprint
    }
}

public extension Bundle {
    var shortVersionString: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }
}
