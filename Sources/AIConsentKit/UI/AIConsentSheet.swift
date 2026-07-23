#if canImport(SwiftUI)
import SwiftUI

/// The disclosure-and-consent sheet.
///
/// Design constraints, all of them driven by what gets apps rejected:
///
/// - Both buttons are equally prominent. A giant "Allow" next to a grey
///   "Not now" is a dark pattern, and Apple has been reading consent UI
///   closely since guideline 5.1.2(i) named third-party AI in Nov 2025.
/// - The recipient is named as a legal entity, not a product. "Anthropic PBC"
///   is a disclosure; "powered by AI" is not.
/// - Nothing is pre-checked and nothing is dismissible-as-accept. Swiping the
///   sheet away is not consent — `isPresented` stays true until a button is hit.
/// - The decline path states what still works, so declining is a real choice
///   rather than a wall.
public struct AIConsentSheet: View {
    private let disclosure: AIDataDisclosure
    private let onGrant: () -> Void
    private let onDeny: () -> Void

    @Environment(\.openURL) private var openURL

    public init(
        disclosure: AIDataDisclosure,
        onGrant: @escaping () -> Void,
        onDeny: @escaping () -> Void
    ) {
        self.disclosure = disclosure
        self.onGrant = onGrant
        self.onDeny = onDeny
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    whatIsSent
                    whoReceivesIt
                    policyLinks
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { buttons }
            .navigationTitle("Before you continue")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .interactiveDismissDisabled(true)
        }
    }

    private var header: some View {
        Text("This feature sends some of your information to an AI service outside this app. Here's exactly what and to whom.")
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var whatIsSent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What gets sent", systemImage: "arrow.up.doc")
            ForEach(disclosure.categories) { category in
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.label)
                        .font(.subheadline.weight(.medium))
                    Text(category.purpose)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var whoReceivesIt: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Who receives it", systemImage: "building.2")
            ForEach(disclosure.recipients) { recipient in
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipient.legalName)
                        .font(.subheadline.weight(.medium))
                    Text("Operates \(recipient.productName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Label(
                        recipient.usedForModelTraining
                            ? "Your data may be used to train their models"
                            : "Your data is not used to train their models",
                        systemImage: recipient.usedForModelTraining ? "exclamationmark.triangle" : "checkmark.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(recipient.usedForModelTraining ? .orange : .green)

                    Text(recipient.retentionSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Read \(recipient.legalName)'s privacy policy") {
                        openURL(recipient.privacyPolicyURL)
                    }
                    .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var policyLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Our privacy policy") {
                openURL(disclosure.firstPartyPrivacyPolicyURL)
            }
            .font(.footnote)

            Text("You can change this any time in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Divider()

            // Equal weight by design. Do not make one of these a plain link.
            HStack(spacing: 12) {
                Button(action: onDeny) {
                    Text("Don't allow")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)

                Button(action: onGrant) {
                    Text("Allow")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)

            Text(disclosure.declineConsequence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(.bar)
    }
}

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}
#endif
