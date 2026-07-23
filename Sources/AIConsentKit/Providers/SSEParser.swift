import Foundation

/// One decoded Server-Sent Event.
public struct SSEEvent: Hashable, Sendable {
    /// Value of the `event:` field, if present.
    public let name: String?
    /// Concatenated `data:` field values, newline-joined per the SSE spec.
    public let data: String

    public init(name: String?, data: String) {
        self.name = name
        self.data = data
    }
}

/// Incremental SSE parser.
///
/// Written as a plain value type so it can be unit tested without a network.
/// Feed it bytes as they arrive; it emits whole events only. Handles the two
/// things naive implementations get wrong: an event split across chunk
/// boundaries, and CRLF line endings.
public struct SSEParser {
    private var buffer = ""
    private var currentEventName: String?
    private var currentData: [String] = []

    public init() {}

    /// Feed a chunk. Returns any events completed by this chunk.
    public mutating func consume(_ chunk: String) -> [SSEEvent] {
        buffer += chunk
        var events: [SSEEvent] = []

        // Normalize CRLF and lone CR to LF before splitting.
        buffer = buffer.replacingOccurrences(of: "\r\n", with: "\n")
        buffer = buffer.replacingOccurrences(of: "\r", with: "\n")

        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])

            if line.isEmpty {
                if let event = flush() {
                    events.append(event)
                }
                continue
            }

            // Comment / heartbeat line.
            if line.hasPrefix(":") { continue }

            guard let colon = line.firstIndex(of: ":") else {
                // Field with no value. Spec says treat as field with empty value.
                continue
            }

            let field = String(line[line.startIndex..<colon])
            var value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }

            switch field {
            case "event": currentEventName = value
            case "data": currentData.append(value)
            default: break // id, retry — not needed here
            }
        }

        return events
    }

    /// Emit any event still buffered. Call when the connection closes cleanly.
    public mutating func finish() -> SSEEvent? {
        flush()
    }

    private mutating func flush() -> SSEEvent? {
        guard !currentData.isEmpty || currentEventName != nil else { return nil }
        let event = SSEEvent(name: currentEventName, data: currentData.joined(separator: "\n"))
        currentEventName = nil
        currentData.removeAll()
        return event
    }
}
