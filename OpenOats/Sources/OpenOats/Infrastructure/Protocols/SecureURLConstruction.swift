import Foundation

// MARK: - URL Construction Errors

/// Errors for URL construction failures
/// - Note: This is the legacy error type. For new code, prefer using `SecureURLConstruction.Error`.
public enum URLConstructionError: Error, Sendable, LocalizedError {
    case invalidTranscriptID
    case invalidBaseURL
    case invalidPathComponent
    case invalidDomain
    case encodingFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidTranscriptID:
            return "Invalid transcript ID format"
        case .invalidBaseURL:
            return "Invalid base URL provided"
        case .invalidPathComponent:
            return "Path contains invalid characters or traversal attempts"
        case .invalidDomain:
            return "URL domain is not in the allowed list"
        case .encodingFailed:
            return "Failed to encode URL components"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .invalidTranscriptID:
            return "The transcript ID contains invalid characters or is malformed"
        case .invalidBaseURL:
            return "The base URL string could not be parsed as a valid URL"
        case .invalidPathComponent:
            return "Path traversal sequences (../, ..) were detected or encoding failed"
        case .invalidDomain:
            return "The URL's domain is not in the whitelist of allowed domains"
        case .encodingFailed:
            return "URL component encoding produced nil result"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .invalidTranscriptID:
            return "Verify the transcript ID is a valid UUID or identifier"
        case .invalidBaseURL:
            return "Check that the base URL includes scheme (https://) and valid domain"
        case .invalidPathComponent:
            return "Remove path traversal sequences and special characters from paths"
        case .invalidDomain:
            return "Use only approved domains for this operation"
        case .encodingFailed:
            return "Try using simpler path components without special characters"
        }
    }
}

// MARK: - Secure URL Construction Protocol

/// Protocol for secure URL construction with path traversal protection
/// 
/// This protocol defines the interface for building URLs safely,
/// preventing path traversal attacks and ensuring proper encoding.
/// 
/// ## Security Features
/// - Path traversal prevention (blocks `../` and `..` sequences)
/// - Proper URL encoding for path components
/// - Domain validation for external URLs
/// - Query parameter sanitization
///
/// ## Usage Example
/// ```swift
/// let url = try secureURLConstructor.assemblyAPIURL(path: "upload")
/// // Results in: https://api.assemblyai.com/v2/upload
/// ```
public protocol SecureURLConstructionProtocol: Sendable {
    
    /// Constructs a secure API URL with a path
    /// - Parameter path: The API path (e.g., "upload", "transcript")
    /// - Returns: Safe URL for the API endpoint
    /// - Throws: URLConstructionError if construction fails
    func assemblyAPIURL(path: String) throws -> URL
    
    /// Constructs a transcript polling URL with proper path encoding
    /// - Parameter transcriptID: The transcript ID to poll
    /// - Returns: Safe URL with properly encoded path
    /// - Throws: URLConstructionError if construction fails
    func pollURL(forTranscriptID transcriptID: String) throws -> URL
    
    /// Constructs a URL by safely appending path components
    /// - Parameters:
    ///   - baseURL: The base URL string
    ///   - pathComponents: Path components to append
    /// - Returns: Safe URL with properly encoded components
    /// - Throws: URLConstructionError if construction fails
    func url(baseURL: String, appendingPathComponents pathComponents: String...) throws -> URL
    
    /// Constructs a model download URL with path traversal protection
    /// - Parameters:
    ///   - baseURL: The base URL string
    ///   - filename: The filename to download
    /// - Returns: Safe URL with sanitized filename
    /// - Throws: URLConstructionError if construction fails
    func modelDownloadURL(baseURL: String, filename: String) throws -> URL
}

// MARK: - Unified Secure URL Construction (Static API)

/// A unified utility for constructing URLs safely with path traversal protection.
///
/// This type provides both static methods for direct use and supports the protocol-based
/// approach for dependency injection scenarios.
///
/// ## Security Features
/// - Path traversal prevention (detects `../` and `..`)
/// - Domain validation for external URLs
/// - Percent-encoding for query parameters
/// - No force unwraps - all operations return Result or throw
///
/// ## Usage Examples
///
/// ### Using the static throwing API (backwards compatible):
/// ```swift
/// let url = try SecureURLConstruction.assemblyAPIURL(path: "upload")
/// ```
///
/// ### Using the Result-based API (preferred for new code):
/// ```swift
/// let result = SecureURLConstruction.build(
///     baseURL: "https://api.example.com",
///     path: "/v1/embeddings"
/// )
///
/// switch result {
/// case .success(let url):
///     // Use the validated URL
/// case .failure(let error):
///     // Handle the error
/// }
/// ```
@available(macOS 15.0, *)
public enum SecureURLConstruction: SecureURLConstructionProtocol {
    
    // MARK: - Modern Error Type
    
    /// Modern error type with more detailed error cases
    public enum Error: Swift.Error, Sendable, LocalizedError {
        case invalidBaseURL
        case invalidPathComponent
        case invalidTranscriptID
        case invalidDomain
        case encodingFailed
        case pathTraversalDetected
        
        public var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "Invalid base URL provided"
            case .invalidPathComponent:
                return "Path contains invalid characters or traversal attempts"
            case .invalidTranscriptID:
                return "Invalid transcript ID format"
            case .invalidDomain:
                return "URL domain is not in the allowed list"
            case .encodingFailed:
                return "Failed to encode URL components"
            case .pathTraversalDetected:
                return "Path traversal sequence (../, ..) detected"
            }
        }
    }
    
    // MARK: - Configuration
    
    /// Allowed domains for model downloads
    public static let allowedDownloadDomains = ["huggingface.co", "cdn.huggingface.co"]
    
    /// AssemblyAI API base URL
    private static let assemblyAIBaseURL = "https://api.assemblyai.com/v2"
    
    // MARK: - Result-Based API (Preferred for new code)
    
    /// Builds a URL safely using URLComponents with path traversal protection.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL string (must include scheme)
    ///   - path: The path component to append
    ///   - queryItems: Optional query parameters (properly percent-encoded)
    /// - Returns: Result containing either the safe URL or a construction error
    public static func build(
        baseURL: String,
        path: String,
        queryItems: [URLQueryItem]? = nil
    ) -> Result<URL, Error> {
        // Parse base URL using URLComponents
        guard var components = URLComponents(string: baseURL) else {
            return .failure(.invalidBaseURL)
        }
        
        // Validate path for traversal attacks
        guard !containsPathTraversal(path) else {
            return .failure(.pathTraversalDetected)
        }
        
        // Build safe path
        let safePath = path.hasPrefix("/") ? path : "/" + path
        components.path = (components.path ?? "") + safePath
        
        // Add query items with proper encoding
        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        // Validate final URL
        guard let url = components.url else {
            return .failure(.encodingFailed)
        }
        
        return .success(url)
    }
    
    // MARK: - Protocol Implementation (Throwing API)
    
    /// Constructs a secure AssemblyAI API URL with a path.
    public static func assemblyAPIURL(path: String) throws -> URL {
        guard var components = URLComponents(string: assemblyAIBaseURL) else {
            throw URLConstructionError.invalidBaseURL
        }
        
        guard !path.contains("../"), !path.contains("..") else {
            throw URLConstructionError.invalidPathComponent
        }
        
        components.path = components.path + "/" + path
        
        guard let url = components.url else {
            throw URLConstructionError.invalidPathComponent
        }
        
        return url
    }
    
    /// Constructs a transcript polling URL with proper path encoding.
    public static func pollURL(forTranscriptID transcriptID: String) throws -> URL {
        guard var components = URLComponents(string: "https://api.assemblyai.com/v2/transcript") else {
            throw URLConstructionError.invalidBaseURL
        }
        
        let encodedID = transcriptID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? transcriptID
        
        guard !encodedID.contains("../"), !encodedID.contains("..") else {
            throw URLConstructionError.invalidTranscriptID
        }
        
        components.path = components.path + "/" + encodedID
        
        guard let url = components.url else {
            throw URLConstructionError.invalidTranscriptID
        }
        
        return url
    }
    
    /// Constructs a URL by safely appending path components.
    public static func url(
        baseURL: String,
        appendingPathComponents pathComponents: String...
    ) throws -> URL {
        guard let base = URL(string: baseURL) else {
            throw URLConstructionError.invalidBaseURL
        }
        
        var result = base
        for component in pathComponents {
            let sanitized = component
                .replacingOccurrences(of: "../", with: "")
                .replacingOccurrences(of: "..", with: "")
            
            let encoded = sanitized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? sanitized
            
            result = result.appendingPathComponent(encoded)
        }
        
        return result
    }
    
    /// Constructs a model download URL with path traversal protection.
    public static func modelDownloadURL(
        baseURL: String,
        filename: String
    ) throws -> URL {
        let sanitized = filename
            .replacingOccurrences(of: "../", with: "")
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "//", with: "/")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: ":", with: "")
        
        guard let base = URL(string: baseURL) else {
            throw URLConstructionError.invalidBaseURL
        }
        
        let encoded = sanitized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? sanitized
        
        let finalURL = base.appendingPathComponent(encoded)
        
        guard let host = finalURL.host, host.contains("huggingface.co") else {
            throw URLConstructionError.invalidPathComponent
        }
        
        return finalURL
    }
    
    // MARK: - ElevenLabs API URLs
    
    /// Constructs a secure ElevenLabs API URL with path validation.
    ///
    /// - Parameter path: API path (e.g., "/v1/voices", "/v1/speech-to-text")
    /// - Returns: Result containing safe URL or construction error
    public static func elevenLabsAPIURL(path: String) -> Result<URL, Error> {
        let baseURL = "https://api.elevenlabs.io"
        
        guard !containsPathTraversal(path) else {
            return .failure(.pathTraversalDetected)
        }
        
        let safePath = path.hasPrefix("/") ? path : "/" + path
        
        return build(baseURL: baseURL, path: safePath)
    }
    
    // MARK: - Validation Helpers
    
    /// Validates that a string is a safe URL path component.
    public static func isSafePath(_ path: String) -> Bool {
        !containsPathTraversal(path)
    }
    
    /// Checks if a string contains path traversal sequences.
    public static func containsPathTraversal(_ path: String) -> Bool {
        path.contains("../") || path.contains("..")
    }
    
    /// Sanitizes a path component by removing path traversal sequences.
    public static func sanitizePath(_ path: String) -> String {
        path.replacingOccurrences(of: "../", with: "")
            .replacingOccurrences(of: "..", with: "")
    }
}

// MARK: - Default Implementation (Instance-based)

/// Default implementation of secure URL construction
/// - Note: For static usage, prefer `SecureURLConstruction` directly
@available(macOS 15.0, *)
public struct SecureURLConstructor: SecureURLConstructionProtocol {
    
    private static let assemblyAIBaseURL = "https://api.assemblyai.com/v2"
    private static let allowedDownloadDomains = ["huggingface.co", "cdn.huggingface.co"]
    
    public init() {}
    
    public func assemblyAPIURL(path: String) throws -> URL {
        try SecureURLConstruction.assemblyAPIURL(path: path)
    }
    
    public func pollURL(forTranscriptID transcriptID: String) throws -> URL {
        try SecureURLConstruction.pollURL(forTranscriptID: transcriptID)
    }
    
    public func url(baseURL: String, appendingPathComponents pathComponents: String...) throws -> URL {
        try SecureURLConstruction.url(baseURL: baseURL, appendingPathComponents: pathComponents)
    }
    
    public func modelDownloadURL(baseURL: String, filename: String) throws -> URL {
        try SecureURLConstruction.modelDownloadURL(baseURL: baseURL, filename: filename)
    }
}

// MARK: - Secure String Interpolation Support

/// A type-safe wrapper for URL path components that ensures proper encoding
@available(macOS 15.0, *)
public struct SafePathComponent: ExpressibleByStringLiteral, Sendable {
    public let rawValue: String
    
    public init(stringLiteral value: String) {
        self.rawValue = value
            .replacingOccurrences(of: "../", with: "")
            .replacingOccurrences(of: "..", with: "")
    }
    
    public init(_ value: String) {
        self.rawValue = value
            .replacingOccurrences(of: "../", with: "")
            .replacingOccurrences(of: "..", with: "")
    }
    
    public var encoded: String {
        rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawValue
    }
}

// MARK: - String Extension for Secure URL Construction

@available(macOS 15.0, *)
extension String {
    /// Returns a safe path component with traversal protection
    public var safePath: SafePathComponent {
        SafePathComponent(self)
    }
    
    /// Validates that the string is a safe URL path component
    public var isSafePathComponent: Bool {
        !self.contains("../") && !self.contains("..")
    }
    
    /// Validates that this string contains no path traversal sequences.
    public var containsPathTraversal: Bool {
        self.contains("../") || self.contains("..")
    }
}

// MARK: - URL Extension for Security Validation

@available(macOS 15.0, *)
extension URL {
    /// Validates that this URL is within an allowed domain
    public func isInAllowedDomain(_ allowedDomains: [String]) -> Bool {
        guard let host = self.host else { return false }
        return allowedDomains.contains { host.contains($0) }
    }
    
    /// Checks if the URL contains path traversal sequences
    public var containsPathTraversal: Bool {
        let path = self.path
        return path.contains("../") || path.contains("..")
    }
    
    /// Checks if this URL uses a secure scheme (https).
    public var isSecureScheme: Bool {
        self.scheme?.lowercased() == "https"
    }
}
