import Foundation
import os

// MARK: - Backend Availability Checker

/// Checks the availability of various transcription backends based on:
/// - Hardware requirements (Apple Silicon for MLX)
/// - Network connectivity (for cloud backends)
/// - Model download status (for local backends)
public actor BackendAvailabilityChecker: BackendAvailabilityChecking {
    
    private static let log = Logger(subsystem: "com.openoats.app", category: "BackendAvailabilityChecker")
    
    /// Model storage for checking local model existence
    private let modelStorage: ModelStorageChecking?
    
    /// Network connectivity checker
    private let networkChecker: NetworkChecking?
    
    public init(
        modelStorage: ModelStorageChecking? = nil,
        networkChecker: NetworkChecking? = nil
    ) {
        self.modelStorage = modelStorage
        self.networkChecker = networkChecker
    }
    
    /// Check availability with specific environment parameters
    public func checkAvailability(
        for backendID: BackendID,
        isAppleSilicon: Bool,
        networkConnected: Bool,
        modelExists: Bool
    ) async -> BackendAvailability {
        
        // Determine backend type and requirements
        let requiresAppleSilicon = backendRequiresAppleSilicon(backendID)
        let requiresNetwork = backendRequiresNetwork(backendID)
        
        // Check hardware requirements
        if requiresAppleSilicon && !isAppleSilicon {
            return BackendAvailability(
                backendID: backendID,
                isAvailable: false,
                requiresNetwork: requiresNetwork,
                networkConnected: networkConnected,
                requiresAppleSilicon: requiresAppleSilicon,
                isAppleSilicon: isAppleSilicon,
                localModelExists: modelExists,
                reason: "Requires Apple Silicon hardware"
            )
        }
        
        // Check network requirements
        if requiresNetwork && !networkConnected {
            return BackendAvailability(
                backendID: backendID,
                isAvailable: false,
                requiresNetwork: requiresNetwork,
                networkConnected: networkConnected,
                requiresAppleSilicon: requiresAppleSilicon,
                isAppleSilicon: isAppleSilicon,
                localModelExists: modelExists,
                reason: "Requires network connectivity"
            )
        }
        
        // Check model download for local backends
        if !requiresNetwork && !modelExists {
            return BackendAvailability(
                backendID: backendID,
                isAvailable: false,
                requiresNetwork: requiresNetwork,
                networkConnected: networkConnected,
                requiresAppleSilicon: requiresAppleSilicon,
                isAppleSilicon: isAppleSilicon,
                localModelExists: modelExists,
                reason: "Model not downloaded"
            )
        }
        
        // All checks passed - backend is available
        return BackendAvailability(
            backendID: backendID,
            isAvailable: true,
            requiresNetwork: requiresNetwork,
            networkConnected: networkConnected,
            requiresAppleSilicon: requiresAppleSilicon,
            isAppleSilicon: isAppleSilicon,
            localModelExists: modelExists
        )
    }
    
    /// Check availability using current environment
    public func checkAvailability(for backendID: BackendID) async -> BackendAvailability {
        let isAppleSilicon = await detectAppleSilicon()
        let networkConnected = await checkNetworkConnectivity()
        let modelExists = await checkModelExists(for: backendID)
        
        return await checkAvailability(
            for: backendID,
            isAppleSilicon: isAppleSilicon,
            networkConnected: networkConnected,
            modelExists: modelExists
        )
    }
    
    // MARK: - Private Methods
    
    /// Check if backend requires Apple Silicon hardware
    private func backendRequiresAppleSilicon(_ backendID: BackendID) -> Bool {
        // MLX Whisper requires Apple Silicon (Metal GPU)
        return backendID == .mlxWhisper
    }
    
    /// Check if backend requires network connectivity
    private func backendRequiresNetwork(_ backendID: BackendID) -> Bool {
        // Cloud backends require network
        return backendID == .assemblyAI || backendID == .elevenLabsScribe
    }
    
    /// Detect if running on Apple Silicon
    private func detectAppleSilicon() async -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    
    /// Check network connectivity
    private func checkNetworkConnectivity() async -> Bool {
        // If network checker provided, use it
        if let checker = networkChecker {
            return await checker.isConnected()
        }
        
        // Default to true - let actual network requests fail if needed
        return true
    }
    
    /// Check if model exists for local backend
    private func checkModelExists(for backendID: BackendID) async -> Bool {
        // If model storage provided, use it
        if let storage = modelStorage {
            return await storage.modelExists(for: backendID)
        }
        
        // Default to checking via backend status
        let model = backendIDToModel(backendID)
        let backend = model?.makeBackend()
        return backend?.checkStatus() == .ready
    }
    
    /// Convert BackendID to TranscriptionModel
    private func backendIDToModel(_ backendID: BackendID) -> TranscriptionModel? {
        switch backendID {
        case .mlxWhisper:
            return .mlxWhisperGLMASR
        case .whisperKit:
            // Default to whisperSmall for WhisperKit
            return .whisperSmall
        case .assemblyAI:
            return .assemblyAI
        case .elevenLabsScribe:
            return .elevenLabsScribe
        case .parakeet:
            return .parakeetV3
        case .qwen3:
            return .qwen3ASR06B
        default:
            return nil
        }
    }
}

// MARK: - Supporting Protocols

/// Protocol for checking model storage
public protocol ModelStorageChecking: Sendable {
    func modelExists(for backendID: BackendID) async -> Bool
}

/// Protocol for network connectivity checking
public protocol NetworkChecking: Sendable {
    func isConnected() async -> Bool
}
