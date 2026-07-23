import Foundation

/// Storage for the consent decision.
public protocol AIConsentStoring: Sendable {
    func load() throws -> ConsentRecord?
    func save(_ record: ConsentRecord) throws
    func clear() throws
}

/// Default store backed by `UserDefaults`.
///
/// Deliberately *not* the Keychain. Consent is not a secret, and Keychain items
/// survive app deletion — a user who deletes the app and reinstalls should be
/// asked again rather than silently inheriting a decision they may not remember
/// making. If you have a reason to persist across reinstall, write your own
/// conforming type; do not change this one.
public struct UserDefaultsConsentStore: AIConsentStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "AIConsentKit.consentRecord") {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> ConsentRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder.aiConsentKit.decode(ConsentRecord.self, from: data)
    }

    public func save(_ record: ConsentRecord) throws {
        let data = try JSONEncoder.aiConsentKit.encode(record)
        defaults.set(data, forKey: key)
    }

    public func clear() throws {
        defaults.removeObject(forKey: key)
    }
}

/// In-memory store for tests and previews.
public final class InMemoryConsentStore: AIConsentStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var record: ConsentRecord?

    public init(record: ConsentRecord? = nil) {
        self.record = record
    }

    public func load() throws -> ConsentRecord? {
        lock.lock(); defer { lock.unlock() }
        return record
    }

    public func save(_ newRecord: ConsentRecord) throws {
        lock.lock(); defer { lock.unlock() }
        record = newRecord
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        record = nil
    }
}

extension JSONDecoder {
    static var aiConsentKit: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    static var aiConsentKit: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
