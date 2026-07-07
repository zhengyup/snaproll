import Foundation

enum V2RepositoryError: LocalizedError, Sendable {
    case notConfigured(String)
    case authenticationRequired
    case forbidden(String)
    case notFound(String)
    case conflict(String)
    case invalidInput(String)
    case lifecycleViolation(String)
    case businessRuleViolation(String)
    case network(String)
    case decoding(String)
    case unsupportedOperation(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message),
             .forbidden(let message),
             .notFound(let message),
             .conflict(let message),
             .invalidInput(let message),
             .lifecycleViolation(let message),
             .businessRuleViolation(let message),
             .network(let message),
             .decoding(let message),
             .unsupportedOperation(let message),
             .unknown(let message):
            return message
        case .authenticationRequired:
            return "Authentication is required."
        }
    }
}
