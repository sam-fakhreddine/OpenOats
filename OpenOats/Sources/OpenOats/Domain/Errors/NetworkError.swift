import Foundation

// MARK: - Network Error

/// Errors that occur during network operations.
public enum NetworkError: Error, Sendable, Equatable {
    /// No network connectivity.
    case noConnectivity
    
    /// API request failed.
    /// - Parameters:
    ///   - endpoint: The API endpoint.
    ///   - statusCode: HTTP status code.
    ///   - message: Error message from server.
    case apiFailure(endpoint: String, statusCode: Int, message: String)
    
    /// Request timed out.
    /// - Parameters:
    ///   - endpoint: The API endpoint.
    ///   - timeout: The timeout duration.
    case requestTimeout(endpoint: String, timeout: Duration)
    
    /// DNS resolution failed.
    /// - Parameter host: The hostname that couldn't be resolved.
    case dnsResolutionFailed(host: String)
    
    /// SSL/TLS error.
    /// - Parameter reason: The SSL error reason.
    case sslError(reason: String)
    
    /// Invalid URL.
    /// - Parameter url: The invalid URL string.
    case invalidURL(url: String)
    
    /// Response parsing failed.
    /// - Parameters:
    ///   - endpoint: The API endpoint.
    ///   - reason: Why parsing failed.
    case responseParsingFailed(endpoint: String, reason: String)
    
    /// Authentication failed.
    /// - Parameter reason: Why authentication failed.
    case authenticationFailed(reason: String)
}

extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noConnectivity:
            return "No network connectivity"
            
        case .apiFailure(let endpoint, let statusCode, let message):
            return "API error at '\(endpoint)' (HTTP \(statusCode)): \(message)"
            
        case .requestTimeout(let endpoint, let timeout):
            return "Request to '\(endpoint)' timed out after \(timeout)"
            
        case .dnsResolutionFailed(let host):
            return "Could not resolve hostname: '\(host)'"
            
        case .sslError(let reason):
            return "SSL error: \(reason)"
            
        case .invalidURL(let url):
            return "Invalid URL: '\(url)'"
            
        case .responseParsingFailed(let endpoint, let reason):
            return "Failed to parse response from '\(endpoint)': \(reason)"
            
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        }
    }
}
