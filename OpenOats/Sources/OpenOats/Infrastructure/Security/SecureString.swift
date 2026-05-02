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
    
    /// Optional initializer for optional strings (alias for init?)
    public static func optional(_ string: String?) -> SecureString? {
        guard let string = string, !string.isEmpty else { return nil }
        return SecureString(string)
    }
    
    /// Returns true if the secure string is empty.
    public var isEmpty: Bool {
        // Check obfuscated buffer length
        buffer.isEmpty
    }
}
