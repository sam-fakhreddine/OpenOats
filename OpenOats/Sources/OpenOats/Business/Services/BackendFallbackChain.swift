import Foundation
import os

// MARK: - Backend Fallback Chain

/// Manages the fallback chain for transcription backends.
/// Priority order: MLX → WhisperKit → Cloud (AssemblyAI, ElevenLabs)
///
/// This ensures optimal user experience by:
/// 1. First trying the highest quality local option (MLX on Apple Silicon)
/// 2. Falling back to WhisperKit for compatibility
/// 3. Using cloud services as last resort (requires network, has latency)
public actor BackendFallbackChain: BackendFallbackChaining {
    
    private static let log = Logger(subsystem: "com.openoats.app", category: "BackendFallbackChain")
    
    /// Priority order of backends for fallback
    /// - Index 0: Highest priority (MLX on Apple Silicon)
    /// - Index 1+: Fallback options
    public let priorities: [BackendID]
    
    /// Configuration for fallback behavior
    private let configuration: BackendSelectionConfiguration
    
    /// Creates a new fallback chain with specified configuration
    /// - Parameter configuration: Selection configuration (defaults to standard)
    public init(configuration: BackendSelectionConfiguration = .default) {
        self.configuration = configuration
        
        // Define priority order: Local high-quality → Local compatible → Cloud
        var priorities: [BackendID] = [
            .mlxWhisper,        // Highest quality on Apple Silicon
            .whisperKit,        // Compatible with all Macs
            .parakeet,          // Alternative local option
            .qwen3,             // Alternative local option
        ]
        
        // Add cloud options if allowed
        if configuration.allowCloudFallback {
            priorities.append(.assemblyAI)
            priorities.append(.elevenLabsScribe)
        }
        
        self.priorities = priorities
    }
    
    /// Filter chain to only available backends
    /// - Parameter checker: Availability checker to use
    /// - Returns: Array of available backend IDs in priority order
    public func filterAvailable(using checker: any BackendAvailabilityChecking) async -> [BackendID] {
        var available: [BackendID] = []
        
        for backendID in priorities {
            let availability = await checker.checkAvailability(for: backendID)
            if availability.isAvailable {
                available.append(backendID)
            } else {
                Self.log.debug("Backend \(backendID.rawValue) unavailable: \(availability.reason ?? "unknown reason")")
            }
        }
        
        Self.log.info("Found \(available.count) available backends out of \(priorities.count) total")
        return available
    }
    
    /// Get first available backend from chain
    /// - Parameter checker: Availability checker to use
    /// - Returns: First available backend ID, or nil if none available
    public func firstAvailable(using checker: any BackendAvailabilityChecking) async -> BackendID? {
        let available = await filterAvailable(using: checker)
        return available.first
    }
    
    /// Get fallback chain starting from a specific backend
    /// - Parameters:
    ///   - startingFrom: Backend to start from (included in chain)
    ///   - checker: Availability checker to use
    /// - Returns: Ordered array of fallback options including the starting point
    public func fallbackChain(
        startingFrom backendID: BackendID,
        using checker: any BackendAvailabilityChecking
    ) async -> [BackendID] {
        // Find index of starting backend
        guard let startIndex = priorities.firstIndex(of: backendID) else {
            Self.log.warning("Backend \(backendID.rawValue) not in priority list, using full chain")
            return await filterAvailable(using: checker)
        }
        
        // Get chain from starting point
        let chain = Array(priorities[startIndex...])
        
        // Filter to only available
        var available: [BackendID] = []
        for id in chain {
            let availability = await checker.checkAvailability(for: id)
            if availability.isAvailable {
                available.append(id)
            }
        }
        
        return available
    }
    
    /// Find next available backend after the specified one
    /// - Parameters:
    ///   - current: Current backend that failed
    ///   - checker: Availability checker to use
    /// - Returns: Next available backend ID, or nil if none available
    public func nextAfter(
        _ current: BackendID,
        using checker: any BackendAvailabilityChecking
    ) async -> BackendID? {
        guard let currentIndex = priorities.firstIndex(of: current) else {
            // Current not in priorities, return first available
            return await firstAvailable(using: checker)
        }
        
        // Search remaining priorities
        for i in (currentIndex + 1)..<priorities.count {
            let backendID = priorities[i]
            let availability = await checker.checkAvailability(for: backendID)
            if availability.isAvailable {
                Self.log.info("Found fallback: \(current.rawValue) → \(backendID.rawValue)")
                return backendID
            }
        }
        
        Self.log.warning("No fallback available after \(current.rawValue)")
        return nil
    }
    
    /// Get preferred local backend based on hardware
    /// - Parameter isAppleSilicon: Whether running on Apple Silicon
    /// - Returns: Best local backend for the hardware
    public func preferredLocalBackend(isAppleSilicon: Bool) -> BackendID {
        if isAppleSilicon {
            return .mlxWhisper
        } else {
            return .whisperKit
        }
    }
    
    /// Get all cloud backends in priority order
    /// - Returns: Array of cloud backend IDs
    public func cloudBackends() -> [BackendID] {
        priorities.filter { backendRequiresNetwork($0) }
    }
    
    /// Get all local backends in priority order
    /// - Returns: Array of local backend IDs
    public func localBackends() -> [BackendID] {
        priorities.filter { !backendRequiresNetwork($0) }
    }
    
    // MARK: - Private Methods
    
    /// Check if backend requires network connectivity
    private func backendRequiresNetwork(_ backendID: BackendID) -> Bool {
        return backendID == .assemblyAI || backendID == .elevenLabsScribe
    }
}

// MARK: - Fallback Chain Result

/// Result of executing a fallback chain
public struct FallbackChainResult: Sendable, Equatable {
    public let selectedBackend: BackendID?
    public let attemptedBackends: [BackendAttempt]
    public let wasSuccessful: Bool
    
    public init(
        selectedBackend: BackendID?,
        attemptedBackends: [BackendAttempt],
        wasSuccessful: Bool
    ) {
        self.selectedBackend = selectedBackend
        self.attemptedBackends = attemptedBackends
        self.wasSuccessful = wasSuccessful
    }
}

/// Record of a backend attempt
public struct BackendAttempt: Sendable, Equatable {
    public let backendID: BackendID
    public let wasAvailable: Bool
    public let reason: String?
    
    public init(
        backendID: BackendID,
        wasAvailable: Bool,
        reason: String? = nil
    ) {
        self.backendID = backendID
        self.wasAvailable = wasAvailable
        self.reason = reason
    }
}
