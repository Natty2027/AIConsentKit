import Foundation
import Observation

/// Owns the consent state for the app.
///
/// Inject one of these at the root and read it wherever you need to know
/// whether AI features are available.
@MainActor
@Observable
public final class AIConsentController {
    public enum State: Equatable {
        /// Not yet asked, or the disclosure changed since they were asked.
        case needsDecision
        case granted
        case denied
    }

    public private(set) var state: State = .needsDecision
    public let disclosure: AIDataDisclosure

    private let store: AIConsentStoring

    public init(disclosure: AIDataDisclosure, store: AIConsentStoring = UserDefaultsConsentStore()) {
        self.disclosure = disclosure
        self.store = store
        refresh()
    }

    /// Re-reads storage and recomputes state against the current disclosure.
    public func refresh() {
        guard let record = try? store.load() else {
            state = .needsDecision
            return
        }
        if record.isValid(for: disclosure) {
            state = .granted
        } else if record.decision == .denied
            && record.disclosureVersion == disclosure.version
            && record.disclosureFingerprint == disclosure.fingerprint {
            // They said no to *this* disclosure. Respect it; don't re-nag.
            state = .denied
        } else {
            // Stored decision predates a disclosure change. Ask again.
            state = .needsDecision
        }
    }

    public func grant() {
        record(.granted)
    }

    public func deny() {
        record(.denied)
    }

    /// Full withdrawal. Wire this to a Settings row — users expect to be able
    /// to take consent back, and reviewers look for it.
    public func withdraw() {
        try? store.clear()
        state = .needsDecision
    }

    private func record(_ decision: ConsentRecord.Decision) {
        let record = ConsentRecord(
            decision: decision,
            disclosureVersion: disclosure.version,
            disclosureFingerprint: disclosure.fingerprint
        )
        try? store.save(record)
        state = decision == .granted ? .granted : .denied
    }
}
