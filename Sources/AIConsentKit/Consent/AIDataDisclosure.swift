import Foundation

/// A category of personal data that leaves the device.
///
/// Apple's guideline 5.1.2(i) requires the app to disclose *what* is sent and
/// *who* it is sent to before the send occurs. `DataCategory` is the "what".
public struct DataCategory: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    /// Plain-language label shown to the user. Avoid jargon: a reviewer reads this too.
    public let label: String
    /// One sentence explaining why this leaves the device.
    public let purpose: String
    /// Maps to an entry in the App Privacy questionnaire (nutrition labels).
    /// See Docs/PRIVACY_NUTRITION_LABELS.md for the mapping table.
    public let nutritionLabelKey: String

    public init(id: String, label: String, purpose: String, nutritionLabelKey: String) {
        self.id = id
        self.label = label
        self.purpose = purpose
        self.nutritionLabelKey = nutritionLabelKey
    }
}

public extension DataCategory {
    static let promptText = DataCategory(
        id: "prompt_text",
        label: "The text you type into the assistant",
        purpose: "Sent so the model can generate a reply.",
        nutritionLabelKey: "UserContent.OtherUserContent"
    )

    static let documentContent = DataCategory(
        id: "document_content",
        label: "Contents of documents you choose to attach",
        purpose: "Sent so the model can summarize or answer questions about them.",
        nutritionLabelKey: "UserContent.OtherUserContent"
    )

    static let photoContent = DataCategory(
        id: "photo_content",
        label: "Images you choose to attach",
        purpose: "Sent so the model can describe or analyze them.",
        nutritionLabelKey: "UserContent.PhotosOrVideos"
    )

    static let accountIdentifier = DataCategory(
        id: "account_identifier",
        label: "An anonymous account identifier",
        purpose: "Used to apply your usage limits. Not linked to your name or email.",
        nutritionLabelKey: "Identifiers.UserID"
    )
}

/// The "who" half of the 5.1.2(i) disclosure.
///
/// One `AIRecipient` per third party that receives personal data. If you route
/// through your own backend and your backend forwards to a model vendor, you
/// must disclose the vendor too — the user's data still reaches them.
public struct AIRecipient: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    /// Legal entity name, not a product name. "Anthropic PBC", not "Claude".
    public let legalName: String
    /// Product name the user may recognize.
    public let productName: String
    /// Vendor's own privacy policy. Reviewers follow this link.
    public let privacyPolicyURL: URL
    /// Whether the vendor trains on data received through this API path.
    /// State this plainly; users ask and reviewers check it against your policy.
    public let usedForModelTraining: Bool
    /// Retention window in plain language, e.g. "up to 30 days for abuse monitoring".
    public let retentionSummary: String

    public init(
        id: String,
        legalName: String,
        productName: String,
        privacyPolicyURL: URL,
        usedForModelTraining: Bool,
        retentionSummary: String
    ) {
        self.id = id
        self.legalName = legalName
        self.productName = productName
        self.privacyPolicyURL = privacyPolicyURL
        self.usedForModelTraining = usedForModelTraining
        self.retentionSummary = retentionSummary
    }
}

/// The complete disclosure presented to the user before any request is made.
///
/// `version` is the important field. Bump it whenever you add a data category,
/// add or change a recipient, or change retention. Bumping invalidates stored
/// consent and re-prompts. Silently widening what you send under a consent the
/// user gave for something narrower is the failure mode this type exists to stop.
public struct AIDataDisclosure: Codable, Hashable, Sendable {
    public let version: Int
    public let categories: [DataCategory]
    public let recipients: [AIRecipient]
    /// Your own privacy policy URL. Must itself name the AI recipients.
    public let firstPartyPrivacyPolicyURL: URL
    /// Optional: shown when the user declines, explaining what still works.
    public let declineConsequence: String

    public init(
        version: Int,
        categories: [DataCategory],
        recipients: [AIRecipient],
        firstPartyPrivacyPolicyURL: URL,
        declineConsequence: String
    ) {
        self.version = version
        self.categories = categories
        self.recipients = recipients
        self.firstPartyPrivacyPolicyURL = firstPartyPrivacyPolicyURL
        self.declineConsequence = declineConsequence
    }

    /// Stable fingerprint of the disclosure's substance.
    ///
    /// Used as a backstop in case someone edits categories or recipients and
    /// forgets to bump `version`. Consent is only valid if both match.
    public var fingerprint: String {
        let categoryPart = categories.map(\.id).sorted().joined(separator: ",")
        let recipientPart = recipients.map(\.id).sorted().joined(separator: ",")
        return "v\(version)|c:\(categoryPart)|r:\(recipientPart)"
    }
}
