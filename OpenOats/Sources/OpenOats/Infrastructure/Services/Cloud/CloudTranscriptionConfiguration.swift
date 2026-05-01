import Foundation
import Security
import os

// MARK: - Cloud Provider Enumeration

/// Supported cloud transcription providers.
public enum CloudProvider: String, Sendable, Equatable, Codable, CaseIterable {
    case assemblyAI = "assemblyai"
    case deepgram = "deepgram"
    case revAI = "revai"
    
    /// Human-readable display name for the provider.
    public var displayName: String {
        switch self {
        case .assemblyAI:
            return "AssemblyAI"
        case .deepgram:
            return "Deepgram"
        case .revAI:
            return "Rev.ai"
        }
    }
    
    /// Default API endpoint for the provider.
    public var defaultEndpoint: URL {
        switch self {
        case .assemblyAI:
            return URL(string: "https://api.assemblyai.com/v2")!
        case .deepgram:
            return URL(string: "https://api.deepgram.com/v1")!
        case .revAI:
            return URL(string: "https://api.rev.ai/speechtotext/v1")!
        }
    }
    
    /// Keychain key for storing the API key.
    public var apiKeyKeychainKey: String {
        return "\(rawValue).api_key"
    }
    
    /// Keychain key for storing custom endpoint.
    public var endpointKeychainKey: String {
        return "\(rawValue).endpoint"
    }
}

// MARK: - Cloud Transcription Configuration

/// Configuration for cloud-based transcription services.
/// Manages API keys securely in the Keychain.
public actor CloudTranscriptionConfiguration: Sendable {
    
    // MARK: - Properties
    
    /// The cloud transcription provider.
    public let provider: CloudProvider
    
    /// The API endpoint URL (optional, uses provider default if nil).
    public let endpoint: URL
    
    /// Request timeout duration.
    public let timeout: Duration
    
    /// Retry policy for failed requests.
    public let retryPolicy: RetryPolicy
    
    /// API key (loaded from Keychain on demand, not cached in memory).
    public var apiKey: String? {
        // Always load from Keychain, never cache in memory
        return loadAPIKey()
    }
    
    /// Keychain service identifier.
    private let keychainService: String
    
    /// Logger for configuration operations.
    private static let log = Logger(
        subsystem: "com.openoats.app",
        category: "CloudTranscriptionConfiguration"
    )
    
    // MARK: - Initialization
    
    /// Creates a new cloud transcription configuration.
    /// - Parameters:
    ///   - provider: The cloud transcription provider (default: AssemblyAI).
    ///   - endpoint: Custom API endpoint (optional).
    ///   - timeout: Request timeout (default: 30 seconds).
    ///   - retryPolicy: Retry policy for failed requests.
    public init(
        provider: CloudProvider = .assemblyAI,
        endpoint: URL? = nil,
        timeout: Duration = .seconds(30),
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.provider = provider
        self.endpoint = endpoint ?? provider.defaultEndpoint
        self.timeout = timeout
        self.retryPolicy = retryPolicy
        self.keychainService = "com.openoats.app.cloud.\(provider.rawValue)"
    }
    
    // MARK: - API Key Management
    
    /// Saves the API key to the Keychain.
    /// - Parameter apiKey: The API key to save.
    public func saveAPIKey(_ apiKey: String) {
        guard !apiKey.isEmpty else {
            clearAPIKey()
            return
        }
        
        guard let data = apiKey.data(using: .utf8) else {
            Self.log.error("Failed to encode API key")
            return
        }
        
        // Delete any existing key first
        deleteExistingKey()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.apiKeyKeychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            Self.log.info("API key saved to Keychain for \(self.provider.displayName)")
        } else {
            Self.log.error("Failed to save API key to Keychain: \(status)")
        }
    }
    
    /// Loads the API key from the Keychain.
    /// - Returns: The API key, or nil if not found.
    public func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.apiKeyKeychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return apiKey
    }
    
    /// Clears the API key from the Keychain.
    public func clearAPIKey() {
        deleteExistingKey()
        Self.log.info("API key cleared from Keychain for \(self.provider.displayName)")
    }
    
    /// Checks if an API key exists in the Keychain.
    /// - Returns: true if an API key exists.
    public func hasAPIKey() -> Bool {
        return loadAPIKey() != nil
    }
    
    // MARK: - Private Helpers
    
    private func deleteExistingKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.apiKeyKeychainKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Convenience Extensions

extension CloudTranscriptionConfiguration {
    /// Creates a configuration with the API key loaded from the Keychain.
    /// - Parameters:
    ///   - provider: The cloud transcription provider.
    ///   - endpoint: Custom API endpoint (optional).
    ///   - timeout: Request timeout.
    ///   - retryPolicy: Retry policy.
    /// - Returns: A configured instance with API key loaded from Keychain.
    public static func loadFromKeychain(
        provider: CloudProvider = .assemblyAI,
        endpoint: URL? = nil,
        timeout: Duration = .seconds(30),
        retryPolicy: RetryPolicy = RetryPolicy()
    ) async -> CloudTranscriptionConfiguration {
        let config = CloudTranscriptionConfiguration(
            provider: provider,
            endpoint: endpoint,
            timeout: timeout,
            retryPolicy: retryPolicy
        )
        return config
    }
}
