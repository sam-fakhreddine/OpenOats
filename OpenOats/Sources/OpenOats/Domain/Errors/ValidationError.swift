import Foundation

// MARK: - Validation Error

/// Errors that occur when domain validation fails.
public enum ValidationError: Error, Sendable, Equatable {
    /// Input value is invalid.
    /// - Parameters:
    ///   - field: The field name.
    ///   - value: The invalid value.
    ///   - requirement: What was expected.
    case invalidInput(field: String, value: String, requirement: String)
    
    /// Required value is missing.
    /// - Parameter field: The missing field name.
    case missingRequiredField(field: String)
    
    /// Value is out of allowed range.
    /// - Parameters:
    ///   - field: The field name.
    ///   - value: The actual value.
    ///   - min: Minimum allowed value.
    ///   - max: Maximum allowed value.
    case outOfRange(field: String, value: Double, min: Double, max: Double)
    
    /// String value has incorrect length.
    /// - Parameters:
    ///   - field: The field name.
    ///   - length: Actual length.
    ///   - min: Minimum allowed length.
    ///   - max: Maximum allowed length.
    case invalidLength(field: String, length: Int, min: Int, max: Int)
    
    /// Value doesn't match expected pattern.
    /// - Parameters:
    ///   - field: The field name.
    ///   - value: The invalid value.
    ///   - pattern: Expected pattern description.
    case patternMismatch(field: String, value: String, pattern: String)
    
    /// Data format is invalid.
    /// - Parameters:
    ///   - field: The field name.
    ///   - expected: Expected format.
    case invalidFormat(field: String, expected: String)
}

extension ValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let field, let value, let requirement):
            return "Invalid input for '\(field)': '\(value)' - \(requirement)"
            
        case .missingRequiredField(let field):
            return "Required field '\(field)' is missing"
            
        case .outOfRange(let field, let value, let min, let max):
            return "Value \(value) for '\(field)' is out of range [\(min), \(max)]"
            
        case .invalidLength(let field, let length, let min, let max):
            return "Length \(length) for '\(field)' is out of range [\(min), \(max)]"
            
        case .patternMismatch(let field, let value, let pattern):
            return "Value '\(value)' for '\(field)' doesn't match pattern: \(pattern)"
            
        case .invalidFormat(let field, let expected):
            return "Invalid format for '\(field)' - expected: \(expected)"
        }
    }
}
