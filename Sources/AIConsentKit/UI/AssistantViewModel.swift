#if canImport(SwiftUI)
import Foundation
import Observation

/// Reference view model wiring the gate, streaming, usage meter, and errors.
///
/// The parts worth copying rather than the parts worth using verbatim:
/// cancellation on deinit, the error surface, and the fact that a failed
/// stream leaves the partial text in place instead of blanking the screen.
@MainActor
@Observable
public final class AssistantViewModel {
    public private(set) var messages: [AIMessage] = []
    public private(set) var streamingText: String = ""
    public private(set) var isStreaming = false
    public private(set) var error: AIError?
    public private(set) var displayedUsage = AIUsage()
    public private(set) var formattedCost: String?

    private let gate: AIProviding
    private let meter: UsageMeter
    // nonisolated(unsafe) so `deinit` (which is nonisolated in Swift 6) can
    // cancel it. `Task` is Sendable and `cancel()` is safe from any context;
    // the property is only mutated on the main actor.
    nonisolated(unsafe) private var streamTask: Task<Void, Never>?

    public init(gate: AIProviding, meter: UsageMeter = UsageMeter()) {
        self.gate = gate
        self.meter = meter
    }

    public func send(_ text: String, system: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        error = nil
        messages.append(AIMessage(role: .user, text: trimmed))
        streamingText = ""
        isStreaming = true

        let request = AIRequest(system: system, messages: messages)

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in try await gate.stream(request) {
                    if Task.isCancelled { break }
                    switch event {
                    case .started(let usage):
                        self.displayedUsage = usage
                    case .delta(let chunk):
                        self.streamingText += chunk
                    case .completed(let usage):
                        self.displayedUsage = usage
                        await self.meter.record(usage)
                        self.formattedCost = await self.meter.formattedCost
                    }
                }
                self.finishStream()
            } catch {
                self.failStream(with: AIError.from(error))
            }
        }
    }

    public func cancel() {
        streamTask?.cancel()
        streamTask = nil
        finishStream()
    }

    public func retryLast() {
        guard let last = messages.last(where: { $0.role == .user }) else { return }
        // Drop the failed turn before resending so history stays coherent.
        if messages.last?.role == .assistant { messages.removeLast() }
        if messages.last?.id == last.id { messages.removeLast() }
        send(last.text)
    }

    private func finishStream() {
        if !streamingText.isEmpty {
            messages.append(AIMessage(role: .assistant, text: streamingText))
        }
        streamingText = ""
        isStreaming = false
    }

    private func failStream(with error: AIError) {
        // Keep whatever streamed successfully. Blanking it on failure loses
        // real work and reads as a crash to the user.
        if !streamingText.isEmpty {
            messages.append(AIMessage(role: .assistant, text: streamingText))
        }
        streamingText = ""
        isStreaming = false
        self.error = error == .cancelled ? nil : error
    }

    deinit {
        streamTask?.cancel()
    }
}
#endif
