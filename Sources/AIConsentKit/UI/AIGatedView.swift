#if canImport(SwiftUI)
import SwiftUI

/// Wraps any AI-dependent view so the consent sheet is presented automatically
/// and the feature is genuinely unreachable until a decision is made.
///
/// Usage:
/// ```swift
/// AIGatedView(controller: consentController) {
///     AssistantScreen()
/// } declined: {
///     ContentUnavailableView(
///         "AI features are off",
///         systemImage: "sparkles.slash",
///         description: Text("Turn them on in Settings.")
///     )
/// }
/// ```
public struct AIGatedView<Content: View, Declined: View>: View {
    @State private var controller: AIConsentController
    private let content: () -> Content
    private let declined: () -> Declined

    public init(
        controller: AIConsentController,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder declined: @escaping () -> Declined
    ) {
        self._controller = State(initialValue: controller)
        self.content = content
        self.declined = declined
    }

    public var body: some View {
        Group {
            switch controller.state {
            case .granted:
                content()
            case .denied:
                declined()
            case .needsDecision:
                // Placeholder behind the sheet. Never render `content()` here —
                // a view that fires a request in `.task` would fire it before
                // the user has answered.
                Color.clear
            }
        }
        .sheet(isPresented: .constant(controller.state == .needsDecision)) {
            AIConsentSheet(
                disclosure: controller.disclosure,
                onGrant: { controller.grant() },
                onDeny: { controller.deny() }
            )
        }
    }
}

/// Settings row for withdrawing or granting consent after the fact.
public struct AIConsentSettingsRow: View {
    @State private var controller: AIConsentController
    @State private var showingSheet = false

    public init(controller: AIConsentController) {
        self._controller = State(initialValue: controller)
    }

    public var body: some View {
        Section {
            HStack {
                Text("AI features")
                Spacer()
                Text(statusText)
                    .foregroundStyle(.secondary)
            }

            switch controller.state {
            case .granted:
                Button("Turn off and stop sending data", role: .destructive) {
                    controller.deny()
                }
            case .denied, .needsDecision:
                Button("Review and turn on") {
                    showingSheet = true
                }
            }
        } footer: {
            Text("Controls whether your information is sent to an outside AI service.")
        }
        .sheet(isPresented: $showingSheet) {
            AIConsentSheet(
                disclosure: controller.disclosure,
                onGrant: {
                    controller.grant()
                    showingSheet = false
                },
                onDeny: {
                    controller.deny()
                    showingSheet = false
                }
            )
        }
    }

    private var statusText: String {
        switch controller.state {
        case .granted: return "On"
        case .denied: return "Off"
        case .needsDecision: return "Not set"
        }
    }
}
#endif
