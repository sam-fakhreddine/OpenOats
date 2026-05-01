import Foundation

// MARK: - Backend Availability Types

/// Represents the availability status of a transcription backend
public struct BackendAvailability: Sendable, Equatable {
    public let backendID: BackendID
    public let isAvailable: Bool
    public let requiresNetwork: Bool
    public let requiresAppleSilicon: Bool
    public let localModelExists: Bool
    public let networkConnected: Bool
    public let isAppleSilicon: Bool
    public let reason: String?
    
    public init(
        backendID: BackendID,
        isAvailable: Bool,
        requiresNetwork: Bool = false,
        networkConnected: Bool = true,
        requiresAppleSilicon: Bool = false,
        isAppleSilicon: Bool = true,
        localModelExists: Bool = false,
        reason: String? = nil
    ) {
        self.backendID = backendID
        self.isAvailable = isAvailable
        self.requiresNetwork = requiresNetwork
        self.networkConnected = networkConnected
        self.requiresAppleSilicon = requiresAppleSilicon
        self.isAppleSilicon = isAppleSilicon
        self.localModelExists = localModelExists
        self.reason = reason
    }
}

// MARK: - Backend Selection Result

/// Result of backend selection operation
public struct BackendSelectionResult: Sendable, Equatable {
    public let selectedBackend: BackendID?
    public let wasFallback: Bool
    public let fallbackChain: [BackendID]
    public let reason: String
    public let error: BackendSelectionError?
    
    public init(
        selectedBackend: BackendID?,
        wasFallback: Bool,
        fallbackChain: [BackendID] = [],
        reason: String,
        error: BackendSelectionError? = nil
    ) {
        self.selectedBackend = selectedBackend
        self.wasFallback = wasFallback
        self.fallbackChain = fallbackChain
        self.reason = reason
        self.error = error
    }
    
    /// Successful selection with preferred backend
    public static func preferred(_ backend: BackendID) -> BackendSelectionResult {
        BackendSelectionResult(
            selectedBackend: backend,
            wasFallback: false,
            fallbackChain: [],
            reason: "User preference satisfied"
        )
    }
    
    /// Successful selection with fallback backend
    public static func fallback(_ backend: BackendID, chain: [BackendID], reason: String) -> BackendSelectionResult {
        BackendSelectionResult(
            selectedBackend: backend,
            wasFallback: true,
            fallbackChain: chain,
            reason: reason
        )
    }
    
    /// Failed selection with no available backends
    public static func failure(reason: String, attempted: [BackendID] = []) -> BackendSelectionResult {
        BackendSelectionResult(
            selectedBackend: nil,
            wasFallback: true,
            fallbackChain: attempted,
            reason: reason,
            error: .noBackendAvailable(reason: reason)
        )
    }
}

// MARK: - Backend Selection Error

/// Errors that can occur during backend selection
public enum BackendSelectionError: Error, Sendable, Equatable {
    case noBackendAvailable(reason: String)
    case invalidBackend(backendID: String)
    case hardwareRequirementNotMet(backend: BackendID, requirement: String)
    case networkRequiredButUnavailable(backend: BackendID)
    case modelNotDownloaded(backend: BackendID)
    
    public var localizedDescription: String {
        switch self {
        case .noBackendAvailable(let reason):
            return "No transcription backend available: \(reason)"
        case .invalidBackend(let id):
            return "Invalid backend identifier: \(id)"
        case .hardwareRequirementNotMet(let backend, let requirement):
            return "Backend '\(backend.rawValue)' requires \(requirement)"
        case .networkRequiredButUnavailable(let backend):
            return "Backend '\(backend.rawValue)' requires network connectivity"
        case .modelNotDownloaded(let backend):
            return "Backend '\(backend.rawValue)' model not downloaded"
        }
    }
}

// MARK: - Backend Availability Checking Protocol

/// Protocol for checking backend availability
public protocol BackendAvailabilityChecking: Sendable {
    /// Check availability with specific environment parameters
    func checkAvailability(
        for backendID: BackendID,
        isAppleSilicon: Bool,
        networkConnected: Bool,
        modelExists: Bool
    ) async -> BackendAvailability
    
    /// Check availability using current environment
    func checkAvailability(for backendID: BackendID) async -> BackendAvailability
}

// MARK: - Backend Fallback Chain Protocol

/// Protocol for managing backend fallback chain
public protocol BackendFallbackChaining: Sendable {
    /// Priority order of backends for fallback
    var priorities: [BackendID] { get }
    
    /// Filter chain to only available backends
    func filterAvailable(using checker: any BackendAvailabilityChecking) async -> [BackendID]
    
    /// Get first available backend from chain
    func firstAvailable(using checker: any BackendAvailabilityChecking) async -> BackendID?
}

// MARK: - Backend Selection Configuration

/// Configuration for backend selection behavior
public struct BackendSelectionConfiguration: Sendable, Equatable {
    public let preferLocalOverCloud: Bool
    public let allowCloudFallback: Bool
    public let requireUserPreference: Bool
    public let maxFallbackAttempts: Int
    
    public init(
        preferLocalOverCloud: Bool = true,
        allowCloudFallback: Bool = true,
        requireUserPreference: Bool = false,
        maxFallbackAttempts: Int = 5
    ) {
        self.preferLocalOverCloud = preferLocalOverCloud
        self.allowCloudFallback = allowCloudFallback
        self.requireUserPreference = requireUserPreference
        self.maxFallbackAttempts = maxFallbackAttempts
    }
    
    /// Default configuration
    public static let `default` = BackendSelectionConfiguration()
    
    /// Offline-only configuration (no cloud fallback)
    public static let offlineOnly = BackendSelectionConfiguration(
        preferLocalOverCloud: true,
        allowCloudFallback: false,
        requireUserPreference: false,
        maxFallbackAttempts: 3
    )
}
