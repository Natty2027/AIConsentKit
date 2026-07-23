import Foundation

/// Every failure the app can surface, with a user-facing message for each.
///
/// The reason this is exhaustive rather than a thin wrapper around `Error`:
/// App Review rejects apps that show raw errors or dead-end states. Every case
/// here has a `userMessage` and a `recoverySuggestion`, so there is no path
/// where a reviewer sees "Error Domain=NSURLErrorDomain Code=-1009".
public enum AIError: Error, Hashable, Sendable {
    /// The gate blocked the call. Present the consent sheet.
    case consentNotGranted
    /// Local budget cap reached.
    case budgetExhausted
    /// Non-2xx from the server.
    case http(status: Int, message: String?, retryAfter: Double?)
    /// Structured error from the vendor or proxy.
    case providerError(message: String, type: String?)
    /// Device is offline or the request could not leave.
    case network(underlying: String)
    /// Request took too long.
    case timeout
    /// Response could not be parsed. Usually a proxy contract mismatch.
    case decoding(String)
    /// User or system cancelled.
    case cancelled

    public static func from(_ error: Error) -> AIError {
        if let aiError = error as? AIError { return aiError }
        if error is CancellationError { return .cancelled }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return .decoding(nsError.localizedDescription)
        }

        switch nsError.code {
        case NSURLErrorCancelled:
            return .cancelled
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost:
            return .network(underlying: nsError.localizedDescription)
        default:
            return .network(underlying: nsError.localizedDescription)
        }
    }

    /// Whether retrying the identical request could plausibly succeed.
    public var isRetryable: Bool {
        switch self {
        case .network, .timeout:
            return true
        case .http(let status, _, _):
            return status == 408 || status == 429 || (500...599).contains(status)
        case .providerError(_, let type):
            return type == "overloaded_error" || type == "rate_limit_error" || type == "api_error"
        case .consentNotGranted, .budgetExhausted, .decoding, .cancelled:
            return false
        }
    }

    /// Server-suggested wait, if any.
    public var retryAfter: TimeInterval? {
        if case .http(_, _, let retryAfter) = self { return retryAfter }
        return nil
    }

    public var userMessage: String {
        switch self {
        case .consentNotGranted:
            return "AI features are turned off."
        case .budgetExhausted:
            return "You've reached your usage limit for now."
        case .http(let status, _, _) where status == 429:
            return "Too many requests right now."
        case .http(let status, _, _) where (500...599).contains(status):
            return "The service is having trouble."
        case .http(let status, _, _) where status == 401 || status == 403:
            return "You're not signed in."
        case .http:
            return "That request didn't go through."
        case .providerError:
            return "The assistant couldn't finish that response."
        case .network:
            return "You appear to be offline."
        case .timeout:
            return "That took too long."
        case .decoding:
            return "Something came back in an unexpected format."
        case .cancelled:
            return "Cancelled."
        }
    }

    public var recoverySuggestion: String {
        switch self {
        case .consentNotGranted:
            return "Turn them on in Settings to continue."
        case .budgetExhausted:
            return "Try again later, or upgrade for a higher limit."
        case .http(let status, _, _) where status == 429:
            return "Wait a moment and try again."
        case .http(let status, _, _) where status == 401 || status == 403:
            return "Sign in and try again."
        case .http, .providerError:
            return "Try again in a moment."
        case .network:
            return "Check your connection and try again."
        case .timeout:
            return "Try again, or shorten your request."
        case .decoding:
            return "Try again. If it keeps happening, contact support."
        case .cancelled:
            return ""
        }
    }
}

extension AIError: LocalizedError {
    public var errorDescription: String? { userMessage }
    public var recoverySuggestionString: String? { recoverySuggestion }
}
