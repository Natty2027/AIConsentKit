import Foundation

/// # AIConsentKit
///
/// Ships an AI feature that passes App Review.
///
/// The problem this solves: Apple revised guideline 5.1.2(i) on 13 November
/// 2025 to say you must clearly disclose where personal data will be shared
/// with third parties, *including with third-party AI*, and obtain explicit
/// permission before doing so. Apps are being rejected under it, usually
/// paired with 5.1.1(i). Adding a consent screen alone is not always enough —
/// the disclosure has to name what is sent and who receives it, the privacy
/// policy has to match, and the App Privacy questionnaire has to match both.
///
/// This kit makes the compliant path the path of least resistance:
///
/// - `AIDataDisclosure` forces you to enumerate what and who, and versions it
///   so widening the data set re-prompts instead of silently reusing consent.
/// - `ConsentGate` wraps the provider so a request cannot be made without a
///   valid decision. Call sites hold gates, never providers.
/// - `RedactionPolicy` narrows what leaves the device, which narrows what you
///   must disclose.
/// - `UsageMeter` and `BudgetGuard` answer "what will this cost me".
/// - `AIError` guarantees every failure has a user-facing message, so a
///   reviewer never sees a raw `NSError`.
///
/// ## Quick start
///
/// ```swift
/// let disclosure = AIDataDisclosure(
///     version: 1,
///     categories: [.promptText, .documentContent],
///     recipients: [.anthropic],
///     firstPartyPrivacyPolicyURL: URL(string: "https://example.com/privacy")!,
///     declineConsequence: "Everything else in the app keeps working."
/// )
///
/// let controller = AIConsentController(disclosure: disclosure)
///
/// let provider = ProxyProvider(configuration: .init(
///     baseURL: URL(string: "https://api.example.com")!,
///     authTokenProvider: { await session.token }
/// ))
///
/// let meter = UsageMeter()
/// let gate = ConsentGate(
///     upstream: provider,
///     isConsentGranted: { [weak controller] in
///         MainActor.assumeIsolated { controller?.state == .granted } ?? false
///     },
///     redaction: .standard,
///     budget: BudgetGuard(meter: meter)
/// )
/// ```
///
/// Then wrap the feature:
///
/// ```swift
/// AIGatedView(controller: controller) {
///     AssistantScreen(viewModel: AssistantViewModel(gate: gate, meter: meter))
/// } declined: {
///     ContentUnavailableView("AI features are off", systemImage: "sparkles.slash")
/// }
/// ```
///
/// ## Before you submit
///
/// Work through `Docs/COMPLIANCE_CHECKLIST.md`. The three that catch people:
/// the privacy policy must itself name the AI vendor, the App Privacy
/// questionnaire must list every category in your disclosure, and the App
/// Review notes must tell the reviewer how to reach the consent screen.
public enum AIConsentKit {
    public static let version = "1.0.0"
}

public extension AIRecipient {
    /// Verify these against the vendor's current terms before shipping.
    /// Retention and training policy change; a stale disclosure is a false one.
    static let anthropic = AIRecipient(
        id: "anthropic",
        legalName: "Anthropic PBC",
        productName: "Claude",
        privacyPolicyURL: URL(string: "https://www.anthropic.com/legal/privacy")!,
        usedForModelTraining: false,
        retentionSummary: "Retained briefly for abuse monitoring, then deleted. Confirm current terms before shipping."
    )

    static let openAI = AIRecipient(
        id: "openai",
        legalName: "OpenAI, L.L.C.",
        productName: "the OpenAI API",
        privacyPolicyURL: URL(string: "https://openai.com/policies/privacy-policy")!,
        usedForModelTraining: false,
        retentionSummary: "Retained briefly for abuse monitoring, then deleted. Confirm current terms before shipping."
    )
}
