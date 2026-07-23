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

    /// Thread-safe mirror of `state == .granted`, updated on every state change.
    ///
    /// `ConsentGate` is an actor, so the `isConsentGranted` closure it holds runs
    /// off the main actor. Reading the `@MainActor` `state` from there is illegal;
    /// reading this snapshot is not. Wire the gate to `{ controller.isGranted }`.
    @ObservationIgnored private let grantedSnapshot = GrantedSnapshot()

    public init(disclosure: AIDataDisclosure, store: AIConsentStoring = UserDefaultsConsentStore()) {
        self.disclosure = disclosure
        self.store = store
        refresh()
    }

    /// Whether consent is currently granted. Safe to read from any executor,
    /// including inside a `ConsentGate.isConsentGranted` closure.
    public nonisolated var isGranted: Bool {
        grantedSnapshot.value
    }

    /// Re-reads storage and recomputes state against the current disclosure.
    public func refresh() {
        guard let record = try? store.load() else {
            setState(.needsDecision)
            return
        }
        if record.isValid(for: disclosure) {
            setState(.granted)
        } else if record.decision == .denied
            && record.disclosureVersion == disclosure.version
            && record.disclosureFingerprint == disclosure.fingerprint {
            // They said no to *this* disclosure. Respect it; don't re-nag.
            setState(.denied)
        } else {
            // Stored decision predates a disclosure change. Ask again.
            setState(.needsDecision)
        }
    }

    /// Single funnel for state changes so the thread-safe snapshot stays in sync.
    private func setState(_ newState: State) {
        state = newState
        grantedSnapshot.value = (newState == .granted)
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
        setState(.needsDecision)
    }

    private func record(_ decision: ConsentRecord.Decision) {
        let record = ConsentRecord(
            decision: decision,
            disclosureVersion: disclosure.version,
            disclosureFingerprint: disclosure.fingerprint
        )
        try? store.save(record)
        setState(decision == .granted ? .granted : .denied)
    }
}

/// Lock-guarded boolean shared between the `@MainActor` controller and the
/// off-actor `ConsentGate` closure that reads it. Immutable reference, so it is
/// safe to capture in a `@Sendable` closure.
private final class GrantedSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var granted = false

    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return granted }
        set { lock.lock(); granted = newValue; lock.unlock() }
    }
}
