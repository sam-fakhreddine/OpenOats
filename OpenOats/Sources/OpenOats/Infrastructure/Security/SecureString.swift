import Foundation

// MARK: - Secure String Type

/// A secure, non-copyable wrapper for sensitive strings (API keys, tokens, etc.).
/// Uses `~Copyable` to prevent accidental copies and zeroes memory on destruction.
/// - Important: Always use `withSecureAccess` to temporarily access the string value.
@available(macOS 15.0, *)
public struct SecureString: ~Copyable, Sendable {
    
    // MARK: - Properties
    
    /// Raw byte storage using ContiguousArray for predictable memory layout
    private var buffer: ContiguousArray<UInt8>
    
    /// XOR key for simple memory obfuscation (not encryption, just anti-dump)
    private static let obfuscationKey: UInt8 = 0xA5
    
    // MARK: - Initialization
    
    /// Creates a new SecureString from a plain string.
    /// - Parameter string: The string to secure (typically an API key or token)
    public init(_ string: String) {
        // Convert to bytes and apply XOR obfuscation
        buffer = ContiguousArray(string.utf8.map { $0 ^ Self.obfuscationKey })
    }
    
    /// Creates a SecureString from raw UTF-8 data.
    /// - Parameter data: The UTF-8 encoded data to secure
    public init(data: Data) {
        buffer = ContiguousArray(data.map { $0 ^ Self.obfuscationKey })
    }
    
    // MARK: - Access Pattern
    
    /// Provides temporary access to the decrypted string within a closure.
    /// The string is only decrypted for the duration of the operation.
    /// - Parameter operation: A closure that receives the plain string
    /// - Returns: The result of the operation
    /// - Throws: Any error thrown by the operation
    public borrowing func withSecureAccess<T>(_ operation: (String) throws -> T) rethrows -> T {
        // Deobfuscate bytes temporarily
        var temp = buffer.map { $0 ^ Self.obfuscationKey }
        defer {
            // Zero out temporary buffer
            for i in temp.indices { temp[i] = 0 }
        }
        
        // Create string from deobfuscated bytes
        guard let string = String(bytes: temp, encoding: .utf8) else {
            fatalError("SecureString: Invalid UTF-8 data")
        }
        
        return try operation(string)
    }
    
    /// Consumes the SecureString and provides the plain string (for one-time use).
    /// This is a consuming operation - the SecureString cannot be used after.
    /// - Returns: The decrypted string
    public consuming func reveal() -> String {
        // Deobfuscate and clear buffer
        var temp = buffer
        for i in temp.indices {
            temp[i] = temp[i] ^ Self.obfuscationKey
        }
        
        // Zero original buffer
        for i in buffer.indices { buffer[i] = 0 }
        
        guard let string = String(bytes: temp, encoding: .utf8) else {
            fatalError("SecureString: Invalid UTF-8 data")
        }
        
        // Zero temp buffer
        for i in temp.indices { temp[i] = 0 }
        
        return string
    }
    
    // MARK: - Destruction
    
    deinit {
        // Zero memory on destruction to prevent exposure in crash dumps
        for i in buffer.indices { buffer[i] = 0 }
    }
}

// MARK: - SecureString Extensions

@available(macOS 15.0, *)
extension SecureString {
    
    /// Creates a SecureString from an optional string.
    /// - Parameter string: Optional string to secure
    /// - Returns: SecureString if input was non-nil, nil otherwise
    public init?(_ string: String?) {
        guard let string = string, !string.isEmpty else { return nil }
        self.init(string)
    }
    
    /// Returns true if the secure string is empty.
    public var isEmpty: Bool {
        // Check obfuscated buffer length
        buffer.isEmpty
    }
}

// MARK: - CloudTranscriptionConfiguration Extension

@available(macOS 15.0, *)
extension CloudTranscriptionConfiguration {
    
    /// Returns the API key as a SecureString (never exposes raw String).
    /// Use `withSecureAccess` pattern for API calls:
    /// ```
    /// apiKey?.withSecureAccess { key in
    ///     request.setValue(key, forHTTPHeaderField: "Authorization")
    /// }
    /// ```
    public var secureAPIKey: SecureString? {
        guard let key = loadAPIKey(), !key.isEmpty else { return nil }
        return SecureString(key)
    }
}

// MARK: - URL Security Helpers

/// Errors for URL construction failures
public enum URLConstructionError: Error, Sendable {
    case invalidTranscriptID
    case invalidBaseURL
    case invalidPathComponent
}

/// Secure URL construction helpers for AssemblyAI API
@available(macOS 15.0, *)
public enum SecureURLConstruction {
    
    /// AssemblyAI API base URL
    private static let assemblyAIBaseURL = "https://api.assemblyai.com/v2"
    
    /// Constructs a secure AssemblyAI API URL with a path.
    /// - Parameter path: The API path (e.g., "upload", "transcript")
    /// - Returns: Safe URL for the AssemblyAI API endpoint
    /// - Throws: URLConstructionError if construction fails
    public static func assemblyAPIURL(path: String) throws -> URL {
        guard var components = URLComponents(string: assemblyAIBaseURL) else {
            throw URLConstructionError.invalidBaseURL
        }
        
        // Validate no path traversal
        guard !path.contains("../"), !path.contains("..") else {
            throw URLConstructionError.invalidPathComponent
        }
        
        components.path.append("/" + path)
        
        guard let url = components.url else {
            throw URLConstructionError.invalidPathComponent
        }
        
        return url
    }
    
    /// Constructs a transcript polling URL with proper path encoding.
    /// - Parameter transcriptID: The transcript ID to poll
    /// - Returns: Safe URL with properly encoded path
    /// - Throws: URLConstructionError if construction fails
    public static func pollURL(forTranscriptID transcriptID: String) throws -> URL {
        guard var components = URLComponents(string: "https://api.assemblyai.com/v2/transcript") else {
            throw URLConstructionError.invalidBaseURL
        }
        
        // Properly encode the transcript ID for URL path
        let encodedID = transcriptID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? transcriptID
        
        // Validate no path traversal sequences
        guard !encodedID.contains("../"), !encodedID.contains("..") else {
            throw URLConstructionError.invalidTranscriptID
        }
        
        components.path.append("/" + encodedID)
        
        guard let url = components.url else {
            throw URLConstructionError.invalidTranscriptID
        }
        
        return url
    }
    
    /// Constructs a URL by safely appending path components.
    /// - Parameters:
    ///   - baseURL: The base URL string
    ///   - pathComponents: Path components to append
    /// - Returns: Safe URL with properly encoded components
    /// - Throws: URLConstructionError if construction fails
    public static func url(
        baseURL: String,
        appendingPathComponents pathComponents: String...
    ) throws -> URL {
        guard let base = URL(string: baseURL) else {
            throw URLConstructionError.invalidBaseURL
        }
        
        var result = base
        for component in pathComponents {
            // Sanitize component
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
    /// - Parameters:
    ///   - baseURL: The base URL string
    ///   - filename: The filename to download
    /// - Returns: Safe URL with sanitized filename
    /// - Throws: URLConstructionError if construction fails
    public static func modelDownloadURL(
        baseURL: String,
        filename: String
    ) throws -> URL {
        // Aggressive path traversal sanitization for untrusted filenames
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
        
        // Final validation - ensure URL is still within expected domain
        guard let host = finalURL.host, host.contains("huggingface.co") else {
            throw URLConstructionError.invalidPathComponent
        }
        
        return finalURL
    }
}
