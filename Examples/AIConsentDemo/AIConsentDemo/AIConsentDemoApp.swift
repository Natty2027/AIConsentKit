import SwiftUI
import AIConsentKit

// A runnable demo app for AIConsentKit.
//
// It wires the real kit — AIGatedView, the consent sheet, ConsentGate,
// redaction, and the usage meter — to a MockProvider so it runs on a
// simulator with no API key and no backend. This is also the shape of the
// path you would hand an App Review demo account.

@main
struct AIConsentDemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - Disclosure

extension AIDataDisclosure {
    /// The demo's "what and to whom". Verify vendor retention/training claims
    /// against current terms before reusing this in a shipping app.
    static let demo = AIDataDisclosure(
        version: 1,
        categories: [.promptText, .documentContent],
        recipients: [
            AIRecipient(
                id: "anthropic",
                legalName: "Anthropic PBC",
                productName: "Claude",
                privacyPolicyURL: URL(string: "https://www.anthropic.com/legal/privacy")!,
                usedForModelTraining: false,
                retentionSummary: "Up to 30 days for abuse monitoring, then deleted."
            )
        ],
        firstPartyPrivacyPolicyURL: URL(string: "https://example.com/privacy")!,
        declineConsequence: "Everything else in the app keeps working — only the AI assistant is turned off."
    )
}

// MARK: - Root

struct RootView: View {
    // Setting DEMO_STATE=assistant in the launch environment starts already
    // granted (and auto-sends one message) so the assistant screen can be
    // captured without tapping. Unset, the consent sheet appears on every
    // launch. A shipping app would use the default UserDefaultsConsentStore.
    private static let demoAssistant = ProcessInfo.processInfo.environment["DEMO_STATE"] == "assistant"

    @State private var controller = AIConsentController(
        disclosure: .demo,
        store: RootView.demoAssistant
            ? InMemoryConsentStore(record: ConsentRecord(
                decision: .granted,
                disclosureVersion: AIDataDisclosure.demo.version,
                disclosureFingerprint: AIDataDisclosure.demo.fingerprint
            ))
            : InMemoryConsentStore()
    )

    var body: some View {
        AIGatedView(controller: controller) {
            AssistantScreen(
                controller: controller,
                autoSend: RootView.demoAssistant,
                initiallyGranted: RootView.demoAssistant
            )
        } declined: {
            DeclinedScreen(controller: controller)
        }
    }
}

// MARK: - Assistant

struct AssistantScreen: View {
    private let controller: AIConsentController
    private let autoSend: Bool
    // Thread-safe mirror of consent state. `ConsentGate` is an actor, so its
    // `isConsentGranted` closure runs off the main actor — reaching back into
    // the @MainActor controller from there (e.g. via MainActor.assumeIsolated)
    // traps. The flag is safe to read from any executor and is kept in sync
    // with the controller below.
    private let consentFlag: ConsentFlag
    @State private var viewModel: AssistantViewModel
    @State private var input = ""
    @State private var showingSettings = false

    init(controller: AIConsentController, autoSend: Bool = false, initiallyGranted: Bool = false) {
        self.controller = controller
        self.autoSend = autoSend
        let flag = ConsentFlag(initiallyGranted)
        self.consentFlag = flag

        // Every call site holds a gate, never a bare provider. The gate
        // refuses to forward anything unless consent is currently valid.
        let gate = ConsentGate(
            upstream: MockProvider(behavior: .stream(Self.demoReply, chunkDelay: .milliseconds(90))),
            isConsentGranted: { flag.value },
            redaction: .standard,
            budget: BudgetGuard()
        )

        _viewModel = State(initialValue: AssistantViewModel(
            gate: gate,
            meter: UsageMeter(pricing: ModelPricing(inputPerMillion: 3, outputPerMillion: 15))
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                composer
            }
            .navigationTitle("Assistant")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let cost = viewModel.formattedCost {
                        Label(cost, systemImage: "creditcard")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsScreen(controller: controller)
            }
            .task {
                if autoSend && viewModel.messages.isEmpty && !viewModel.isStreaming {
                    viewModel.send("Give me the one-line pitch for AIConsentKit.")
                }
            }
            .onChange(of: controller.state) { _, newState in
                consentFlag.set(newState == .granted)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        ContentUnavailableView(
                            "Ask the assistant something",
                            systemImage: "sparkles",
                            description: Text("Your text is sent to Claude only after you agreed on the previous screen.")
                        )
                        .padding(.top, 60)
                    }

                    ForEach(viewModel.messages) { message in
                        Bubble(role: message.role, text: message.text)
                            .id(message.id)
                    }

                    if viewModel.isStreaming {
                        Bubble(role: .assistant, text: viewModel.streamingText.isEmpty ? "…" : viewModel.streamingText)
                            .id("streaming")
                    }

                    if let error = viewModel.error {
                        Text(error.userMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.streamingText) { _, _ in
                withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit(sendMessage)

            if viewModel.isStreaming {
                Button(role: .destructive) {
                    viewModel.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private func sendMessage() {
        let text = input
        input = ""
        viewModel.send(text)
    }

    // A scripted reply, chunked so the streaming UI has something to animate.
    private static let demoReply: [String] = [
        "Sure — ", "here's the gist. ", "AIConsentKit ", "gates every request ",
        "behind a consent decision ", "that's bound to a fingerprint ", "of exactly ",
        "what you disclosed, ", "so widening the disclosure ", "re-asks the user ",
        "instead of silently ", "reusing old consent."
    ]
}

/// A lock-guarded boolean the `ConsentGate` closure can read from any executor.
/// Mirrors the @MainActor controller's granted state without touching it.
private final class ConsentFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var granted: Bool

    init(_ granted: Bool) {
        self.granted = granted
    }

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return granted
    }

    func set(_ newValue: Bool) {
        lock.lock(); defer { lock.unlock() }
        granted = newValue
    }
}

private struct Bubble: View {
    let role: AIRole
    let text: String

    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: 40) }
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(role == .user ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if role == .assistant { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Declined

struct DeclinedScreen: View {
    let controller: AIConsentController
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("AI features are off", systemImage: "sparkles.slash")
            } description: {
                Text(controller.disclosure.declineConsequence)
            } actions: {
                Button("Review and turn on") { showingSettings = true }
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Assistant")
            .sheet(isPresented: $showingSettings) {
                SettingsScreen(controller: controller)
            }
        }
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    let controller: AIConsentController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // The kit's own settings row: withdraw or re-grant after the fact.
                // Reviewers look for the ability to take consent back.
                AIConsentSettingsRow(controller: controller)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
