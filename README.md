# AIConsentKit

Ship an AI feature that passes App Review.

Swift package for iOS 17+ that makes Apple's guideline 5.1.2(i) disclosure and
consent requirements structurally hard to get wrong, and bundles the streaming,
error-handling, redaction, and cost-metering pieces that AI features need
anyway.

## Why this exists

On 13 November 2025 Apple revised guideline 5.1.2(i) to add:

> You must clearly disclose where personal data will be shared with third
> parties, including with third-party AI, and obtain explicit permission
> before doing so.

First time third-party AI was named as its own regulated category. Effective
immediately. Rejections under it are live and usually arrive paired with
5.1.1(i), listing four requirements: disclose what data is sent, specify who
it goes to, get permission before sending, and reflect all of it in the
privacy policy.

Teams get rejected here after adding a consent screen, because the screen
alone is not the requirement — the consent, the privacy policy, and the App
Privacy questionnaire all have to describe the same reality.

## What's in the box

```
Consent/     Disclosure model, versioned consent records, storage, the gate
Providers/   Neutral request/response types, SSE parser, Anthropic, proxy, mock
Policy/      PII redaction, token metering, cost estimation, budget caps
Errors/      Exhaustive error taxonomy with user-facing copy, retry + jitter
UI/          Consent sheet, gated view wrapper, settings row, reference VM
Docs/        Pre-submission checklist, nutrition label mapping, review notes
```

## The core idea

`ConsentGate` wraps your provider and refuses to forward anything without a
valid decision. Call sites hold gates, never providers — so "did we check
consent here?" stops being a per-call-site question.

Consent is bound to a **fingerprint** of the disclosure, not a boolean. Add a
data category or a new vendor and prior consent is automatically invalid, so
the user is re-asked instead of being silently opted into something broader
than what they agreed to. That is the failure mode the design exists to
prevent, and it is tested:

```swift
func testConsentDoesNotCarryOverToWiderDisclosure()
```

## Quick start

```swift
let disclosure = AIDataDisclosure(
    version: 1,
    categories: [.promptText, .documentContent],
    recipients: [.anthropic],
    firstPartyPrivacyPolicyURL: URL(string: "https://example.com/privacy")!,
    declineConsequence: "Everything else in the app keeps working."
)

let controller = AIConsentController(disclosure: disclosure)

let gate = ConsentGate(
    upstream: ProxyProvider(configuration: .init(
        baseURL: URL(string: "https://api.example.com")!
    )),
    isConsentGranted: { MainActor.assumeIsolated { controller.state == .granted } },
    redaction: .standard,
    budget: BudgetGuard()
)

// In your view tree:
AIGatedView(controller: controller) {
    AssistantScreen(viewModel: AssistantViewModel(gate: gate))
} declined: {
    ContentUnavailableView("AI features are off", systemImage: "sparkles.slash")
}
```

## API keys

`AnthropicProvider` talks to the vendor directly and puts your API key in the
app binary, where `strings` on an extracted IPA will find it. It is here so you
can develop before standing up a backend, and so the wire format is documented.

**Wrap it in `#if DEBUG` and ship `ProxyProvider`.** A reference Express handler
that translates Anthropic's SSE events into this kit's neutral ones is in
`Docs/INTEGRATION.md`.

## Before you submit

`Docs/COMPLIANCE_CHECKLIST.md`. The three that catch people:

1. The privacy policy must itself name the AI vendor.
2. The App Privacy questionnaire must list every category in your disclosure.
3. The App Review notes must tell the reviewer how to reach the consent screen,
   with a demo account that is not rate limited.

## Status

Written against the Anthropic Messages API streaming format and Apple's
guidelines as of July 2026. **Builds clean on Swift 6.3 (iOS 17+ / macOS 14+)
with all 31 tests passing** (`swift test`). Tests are the place to start:
`SSEParserTests` and `ConsentGateTests` cover the logic that actually matters.

Verify vendor retention and training claims in `AIRecipient.anthropic` and
`.openAI` against current terms before shipping. A stale disclosure is a false
disclosure.

## License

MIT. See LICENSE.
