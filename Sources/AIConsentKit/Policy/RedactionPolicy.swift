import Foundation

/// Strips obvious personal identifiers from outbound text.
///
/// Two reasons this matters beyond good manners. First, the narrower the data
/// you actually send, the shorter your 5.1.2(i) disclosure and the fewer
/// nutrition-label categories you have to check. Second, users paste things
/// into text fields that they did not think through — an email thread, a
/// screenshot's OCR, a card number.
///
/// This is a mitigation, not a guarantee. Regex cannot understand context, and
/// free-form prose will always be able to carry identifiers past it. Disclose
/// what you send; do not claim redaction makes the data anonymous.
public struct RedactionPolicy: Sendable {

    public struct Rule: Sendable {
        public let name: String
        public let pattern: String
        public let replacement: String

        public init(name: String, pattern: String, replacement: String) {
            self.name = name
            self.pattern = pattern
            self.replacement = replacement
        }
    }

    public let rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    public static let none = RedactionPolicy(rules: [])

    /// Conservative default set. Extend for your domain — a health app should
    /// add MRN patterns, a finance app should add account number patterns.
    public static let standard = RedactionPolicy(rules: [
        Rule(
            name: "email",
            pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            replacement: "[email removed]"
        ),
        Rule(
            name: "us_phone",
            pattern: #"(\+1[-. ]?)?\(?\d{3}\)?[-. ]?\d{3}[-. ]?\d{4}\b"#,
            replacement: "[phone removed]"
        ),
        Rule(
            name: "ssn",
            pattern: #"\b\d{3}-\d{2}-\d{4}\b"#,
            replacement: "[SSN removed]"
        ),
        Rule(
            // Catches 13–16 digit runs with optional separators. Deliberately
            // broad; a false positive costs nothing, a leak costs a lot.
            name: "card_number",
            pattern: #"\b(?:\d[ -]?){13,16}\b"#,
            replacement: "[card number removed]"
        ),
        Rule(
            name: "ipv4",
            pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,
            replacement: "[IP removed]"
        )
    ])

    public func apply(to text: String) -> String {
        rules.reduce(text) { partial, rule in
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return partial }
            let range = NSRange(partial.startIndex..<partial.endIndex, in: partial)
            return regex.stringByReplacingMatches(
                in: partial,
                options: [],
                range: range,
                withTemplate: rule.replacement
            )
        }
    }

    public func apply(to request: AIRequest) -> AIRequest {
        guard !rules.isEmpty else { return request }
        var copy = request
        copy.messages = request.messages.map { message in
            var m = message
            m.text = apply(to: message.text)
            return m
        }
        return copy
    }

    /// Reports which rules fired, without returning the matched text.
    /// Useful for a "we removed 2 items before sending" affordance in the UI.
    public func audit(_ text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let n = regex.numberOfMatches(in: text, options: [], range: range)
            if n > 0 { counts[rule.name] = n }
        }
        return counts
    }
}
