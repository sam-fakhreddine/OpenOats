import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - Backend Selection Tests (Standalone Version)
// Stream 6E: Backend Selector Implementation Agent

/// Tests for TranscriptionServiceSelector
@Suite("TranscriptionServiceSelector Tests")
struct TranscriptionServiceSelectorTests {
    
    @Test("User preference respected when backend available")
    func userPreferenceRespectedWhenAvailable() async throws {
        let mockChecker = MockBackendAvailabilityChecker()
        let fallbackChain = BackendFallbackChain()
        let selector = TranscriptionServiceSelector(
            availabilityChecker: mockChecker,
            fallbackChain: fallbackChain
        )
        
        // Make MLX backend available on Apple Silicon
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .mlxWhisper,
                isAvailable: true,
                requiresNetwork: false,
                requiresAppleSilicon: true,
                localModelExists: true
            )
        )
        
        let result = await selector.selectBackend(
            preferred: .mlxWhisper,
            isAppleSilicon: true,
            networkConnected: true,
            localModels: [.mlxWhisper]
        )
        
        #expect(result.selectedBackend == .mlxWhisper)
        #expect(result.wasFallback == false)
    }
    
    @Test("Falls back when preferred backend unavailable")
    func fallbackWhenPreferredUnavailable() async throws {
        let mockChecker = MockBackendAvailabilityChecker()
        let fallbackChain = BackendFallbackChain()
        let selector = TranscriptionServiceSelector(
            availabilityChecker: mockChecker,
            fallbackChain: fallbackChain
        )
        
        // MLX unavailable (Intel Mac)
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .mlxWhisper,
                isAvailable: false,
                requiresNetwork: false,
                requiresAppleSilicon: true,
                isAppleSilicon: false,
                localModelExists: false,
                reason: "Requires Apple Silicon hardware"
            )
        )
        
        // WhisperKit available
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .whisperKit,
                isAvailable: true,
                requiresNetwork: false,
                requiresAppleSilicon: false,
                localModelExists: true
            )
        )
        
        let result = await selector.selectBackend(
            preferred: .mlxWhisper,
            isAppleSilicon: false, // Intel Mac
            networkConnected: true,
            localModels: [.whisperKit]
        )
        
        #expect(result.selectedBackend == .whisperKit)
        #expect(result.wasFallback == true)
    }
    
    @Test("Cloud backends require network connectivity")
    func cloudBackendsRequireNetwork() async throws {
        let mockChecker = MockBackendAvailabilityChecker()
        let fallbackChain = BackendFallbackChain()
        let selector = TranscriptionServiceSelector(
            availabilityChecker: mockChecker,
            fallbackChain: fallbackChain
        )
        
        // AssemblyAI available but no network
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .assemblyAI,
                isAvailable: false, // Marked unavailable due to no network
                requiresNetwork: true,
                networkConnected: false,
                requiresAppleSilicon: false,
                localModelExists: true,
                reason: "Requires network connectivity"
            )
        )
        
        // WhisperKit available locally
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .whisperKit,
                isAvailable: true,
                requiresNetwork: false,
                requiresAppleSilicon: false,
                localModelExists: true
            )
        )
        
        let result = await selector.selectBackend(
            preferred: .assemblyAI,
            isAppleSilicon: true,
            networkConnected: false, // No network
            localModels: [.whisperKit]
        )
        
        // Should fall back to WhisperKit due to no network
        #expect(result.selectedBackend == .whisperKit)
        #expect(result.wasFallback == true)
    }
    
    @Test("Fallback chain executes in correct order")
    func fallbackChainOrder() async throws {
        let mockChecker = MockBackendAvailabilityChecker()
        let fallbackChain = BackendFallbackChain()
        let selector = TranscriptionServiceSelector(
            availabilityChecker: mockChecker,
            fallbackChain: fallbackChain
        )
        
        // MLX unavailable (no model)
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .mlxWhisper,
                isAvailable: false,
                requiresNetwork: false,
                requiresAppleSilicon: true,
                localModelExists: false,
                reason: "Model not downloaded"
            )
        )
        
        // WhisperKit unavailable (no model)
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .whisperKit,
                isAvailable: false,
                requiresNetwork: false,
                requiresAppleSilicon: false,
                localModelExists: false,
                reason: "Model not downloaded"
            )
        )
        
        // Cloud available with network
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .assemblyAI,
                isAvailable: true,
                requiresNetwork: true,
                networkConnected: true,
                requiresAppleSilicon: false,
                localModelExists: true
            )
        )
        
        let result = await selector.selectBackend(
            preferred: .mlxWhisper,
            isAppleSilicon: true,
            networkConnected: true,
            localModels: []
        )
        
        // Should end up at cloud after trying MLX and WhisperKit
        #expect(result.selectedBackend == .assemblyAI)
        #expect(result.fallbackChain.count >= 2)
    }
    
    @Test("Local models preferred over cloud when no preference")
    func localPreferredOverCloud() async throws {
        let mockChecker = MockBackendAvailabilityChecker()
        let fallbackChain = BackendFallbackChain()
        let selector = TranscriptionServiceSelector(
            availabilityChecker: mockChecker,
            fallbackChain: fallbackChain
        )
        
        // WhisperKit available locally
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .whisperKit,
                isAvailable: true,
                requiresNetwork: false,
                requiresAppleSilicon: false,
                localModelExists: true
            )
        )
        
        // AssemblyAI available
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .assemblyAI,
                isAvailable: true,
                requiresNetwork: true,
                networkConnected: true,
                requiresAppleSilicon: false,
                localModelExists: true
            )
        )
        
        let result = await selector.selectBackend(
            preferred: nil, // No preference
            isAppleSilicon: true,
            networkConnected: true,
            localModels: [.whisperKit]
        )
        
        // Should prefer local (WhisperKit) over cloud
        #expect(result.selectedBackend == .whisperKit)
    }
    
    @Test("Returns error when no backends available")
    func errorWhenNoBackendsAvailable() async throws {
        let mockChecker = MockBackendAvailabilityChecker()
        let fallbackChain = BackendFallbackChain()
        let selector = TranscriptionServiceSelector(
            availabilityChecker: mockChecker,
            fallbackChain: fallbackChain
        )
        
        // Nothing available - simulate offline without models
        mockChecker.setAllUnavailable()
        
        let result = await selector.selectBackend(
            preferred: .mlxWhisper,
            isAppleSilicon: true,
            networkConnected: false,
            localModels: []
        )
        
        #expect(result.error != nil)
        #expect(result.selectedBackend == nil)
    }
}

// MARK: - BackendAvailabilityChecker Tests

@Suite("BackendAvailabilityChecker Tests")
struct BackendAvailabilityCheckerTests {
    
    @Test("Checker identifies MLX availability on Apple Silicon")
    func checkerIdentifiesMLXOnAppleSilicon() async throws {
        let checker = BackendAvailabilityChecker()
        
        // On Apple Silicon with model
        let mlxAvailability = await checker.checkAvailability(
            for: .mlxWhisper,
            isAppleSilicon: true,
            networkConnected: true,
            modelExists: true
        )
        
        #expect(mlxAvailability.isAvailable == true)
        #expect(mlxAvailability.requiresAppleSilicon == true)
    }
    
    @Test("Checker rejects MLX on Intel Macs")
    func checkerRejectsMLXOnIntel() async throws {
        let checker = BackendAvailabilityChecker()
        
        // On Intel Mac with model
        let mlxAvailability = await checker.checkAvailability(
            for: .mlxWhisper,
            isAppleSilicon: false,
            networkConnected: true,
            modelExists: true
        )
        
        #expect(mlxAvailability.isAvailable == false)
        #expect(mlxAvailability.reason?.contains("Apple Silicon") ?? false)
    }
    
    @Test("Checker requires model file for local backends")
    func checkerRequiresModelFile() async throws {
        let checker = BackendAvailabilityChecker()
        
        // WhisperKit without model
        let noModelAvailability = await checker.checkAvailability(
            for: .whisperKit,
            isAppleSilicon: false,
            networkConnected: true,
            modelExists: false
        )
        
        #expect(noModelAvailability.isAvailable == false)
        #expect(noModelAvailability.reason?.contains("model") ?? false)
        
        // WhisperKit with model
        let withModelAvailability = await checker.checkAvailability(
            for: .whisperKit,
            isAppleSilicon: false,
            networkConnected: true,
            modelExists: true
        )
        
        #expect(withModelAvailability.isAvailable == true)
    }
    
    @Test("Checker requires network for cloud backends")
    func checkerRequiresNetworkForCloud() async throws {
        let checker = BackendAvailabilityChecker()
        
        // AssemblyAI without network
        let noNetworkAvailability = await checker.checkAvailability(
            for: .assemblyAI,
            isAppleSilicon: false,
            networkConnected: false,
            modelExists: true
        )
        
        #expect(noNetworkAvailability.isAvailable == false)
        #expect(noNetworkAvailability.requiresNetwork == true)
        
        // AssemblyAI with network
        let withNetworkAvailability = await checker.checkAvailability(
            for: .assemblyAI,
            isAppleSilicon: false,
            networkConnected: true,
            modelExists: true
        )
        
        #expect(withNetworkAvailability.isAvailable == true)
    }
}

// MARK: - BackendFallbackChain Tests

@Suite("BackendFallbackChain Tests")
struct BackendFallbackChainTests {
    
    @Test("Chain follows correct priority order")
    func chainFollowsPriorityOrder() async throws {
        let chain = BackendFallbackChain()
        
        let priorities = chain.priorities
        
        // MLX should be first priority
        #expect(priorities[0] == .mlxWhisper)
        // WhisperKit should be second
        #expect(priorities[1] == .whisperKit)
    }
    
    @Test("Chain filters unavailable backends")
    func chainFiltersUnavailable() async throws {
        let chain = BackendFallbackChain()
        let mockChecker = MockBackendAvailabilityChecker()
        
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .mlxWhisper,
                isAvailable: false,
                requiresNetwork: false,
                requiresAppleSilicon: true,
                localModelExists: false
            )
        )
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .whisperKit,
                isAvailable: true,
                requiresNetwork: false,
                requiresAppleSilicon: false,
                localModelExists: true
            )
        )
        
        let availableChain = await chain.filterAvailable(using: mockChecker)
        
        #expect(availableChain.contains(.whisperKit))
        #expect(!availableChain.contains(.mlxWhisper))
    }
    
    @Test("Chain returns first available backend")
    func chainReturnsFirstAvailable() async throws {
        let chain = BackendFallbackChain()
        let mockChecker = MockBackendAvailabilityChecker()
        
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .mlxWhisper,
                isAvailable: false,
                requiresNetwork: false,
                requiresAppleSilicon: true,
                localModelExists: false
            )
        )
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .whisperKit,
                isAvailable: true,
                requiresNetwork: false,
                requiresAppleSilicon: false,
                localModelExists: true
            )
        )
        
        let result = await chain.firstAvailable(using: mockChecker)
        
        #expect(result == .whisperKit)
    }
    
    @Test("Chain returns nil when nothing available")
    func chainReturnsNilWhenNothingAvailable() async throws {
        let chain = BackendFallbackChain()
        let mockChecker = MockBackendAvailabilityChecker()
        
        mockChecker.setAllUnavailable()
        
        let result = await chain.firstAvailable(using: mockChecker)
        
        #expect(result == nil)
    }
    
    @Test("Chain respects network requirements for cloud")
    func chainRespectsNetwork() async throws {
        let chain = BackendFallbackChain()
        let mockChecker = MockBackendAvailabilityChecker()
        
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .mlxWhisper,
                isAvailable: false,
                requiresNetwork: false,
                requiresAppleSilicon: true,
                localModelExists: false
            )
        )
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .whisperKit,
                isAvailable: false,
                requiresNetwork: false,
                requiresAppleSilicon: false,
                localModelExists: false
            )
        )
        mockChecker.setAvailability(
            BackendAvailability(
                backendID: .assemblyAI,
                isAvailable: true,
                requiresNetwork: true,
                networkConnected: false, // No network!
                requiresAppleSilicon: false,
                localModelExists: true
            )
        )
        
        let result = await chain.firstAvailable(using: mockChecker)
        
        // Cloud not available without network
        #expect(result == nil)
    }
    
    @Test("Chain localBackends returns only local backends")
    func chainLocalBackends() async throws {
        let chain = BackendFallbackChain()
        
        let local = chain.localBackends()
        
        // Should not contain cloud backends
        #expect(!local.contains(.assemblyAI))
        #expect(!local.contains(.elevenLabsScribe))
        // Should contain local backends
        #expect(local.contains(.mlxWhisper))
        #expect(local.contains(.whisperKit))
    }
    
    @Test("Chain cloudBackends returns only cloud backends")
    func chainCloudBackends() async throws {
        let chain = BackendFallbackChain()
        
        let cloud = chain.cloudBackends()
        
        // Should contain cloud backends
        #expect(cloud.contains(.assemblyAI) || cloud.contains(.elevenLabsScribe))
    }
}

// MARK: - Integration Tests

@Suite("Integration Tests")
struct BackendSelectionIntegrationTests {
    
    @Test("Full integration - real components work together")
    func fullIntegration() async throws {
        let checker = BackendAvailabilityChecker()
        let chain = BackendFallbackChain()
        let selector = TranscriptionServiceSelector(
            availabilityChecker: checker,
            fallbackChain: chain
        )
        
        // Simulate Apple Silicon environment with MLX model
        let result = await selector.selectBackend(
            preferred: .mlxWhisper,
            isAppleSilicon: true,
            networkConnected: true,
            localModels: [.mlxWhisper]
        )
        
        #expect(result.selectedBackend == .mlxWhisper)
        #expect(result.wasFallback == false)
    }
    
    @Test("Integration - network failure falls back to local")
    func integrationNetworkFailure() async throws {
        let checker = BackendAvailabilityChecker()
        let chain = BackendFallbackChain()
        let selector = TranscriptionServiceSelector(
            availabilityChecker: checker,
            fallbackChain: chain
        )
        
        // Simulate: prefer cloud, no network, but WhisperKit model available
        let result = await selector.selectBackend(
            preferred: .assemblyAI,
            isAppleSilicon: true,
            networkConnected: false, // No network
            localModels: [.whisperKit]
        )
        
        #expect(result.selectedBackend == .whisperKit)
        #expect(result.wasFallback == true)
    }
    
    @Test("Integration - offline only mode")
    func integrationOfflineMode() async throws {
        let checker = BackendAvailabilityChecker()
        let chain = BackendFallbackChain(configuration: .offlineOnly)
        let selector = TranscriptionServiceSelector(
            availabilityChecker: checker,
            fallbackChain: chain,
            configuration: .offlineOnly
        )
        
        let result = await selector.selectBackend(
            preferred: nil,
            isAppleSilicon: true,
            networkConnected: false, // Offline
            localModels: [.whisperKit]
        )
        
        // Should select local backend, not cloud
        #expect(result.selectedBackend != .assemblyAI)
        #expect(result.selectedBackend != .elevenLabsScribe)
    }
}

// MARK: - Mock Implementations for Testing

/// Mock backend availability checker for testing
actor MockBackendAvailabilityChecker: BackendAvailabilityChecking {
    private var availabilities: [BackendID: BackendAvailability] = [:]
    
    func setAvailability(_ availability: BackendAvailability) {
        availabilities[availability.backendID] = availability
    }
    
    func setAllUnavailable() {
        for key in availabilities.keys {
            availabilities[key] = BackendAvailability(
                backendID: key,
                isAvailable: false,
                requiresNetwork: availabilities[key]?.requiresNetwork ?? false,
                requiresAppleSilicon: availabilities[key]?.requiresAppleSilicon ?? false,
                localModelExists: false,
                reason: "Mock: unavailable"
            )
        }
    }
    
    func checkAvailability(
        for backendID: BackendID,
        isAppleSilicon: Bool,
        networkConnected: Bool,
        modelExists: Bool
    ) async -> BackendAvailability {
        if let availability = availabilities[backendID] {
            // Recalculate availability based on passed parameters
            var isAvailable = availability.isAvailable
            var reason = availability.reason
            
            // Re-check hardware requirement
            if availability.requiresAppleSilicon && !isAppleSilicon {
                isAvailable = false
                reason = "Requires Apple Silicon hardware"
            }
            
            // Re-check network requirement
            if availability.requiresNetwork && !networkConnected {
                isAvailable = false
                reason = "Requires network connectivity"
            }
            
            // Re-check model requirement for local backends
            if !availability.requiresNetwork && !modelExists {
                isAvailable = false
                reason = "Model not downloaded"
            }
            
            return BackendAvailability(
                backendID: backendID,
                isAvailable: isAvailable,
                requiresNetwork: availability.requiresNetwork,
                networkConnected: networkConnected,
                requiresAppleSilicon: availability.requiresAppleSilicon,
                isAppleSilicon: isAppleSilicon,
                localModelExists: modelExists,
                reason: reason
            )
        }
        
        return BackendAvailability(
            backendID: backendID,
            isAvailable: false,
            requiresNetwork: false,
            requiresAppleSilicon: false,
            localModelExists: false,
            reason: "Not configured in mock"
        )
    }
    
    func checkAvailability(for backendID: BackendID) async -> BackendAvailability {
        return availabilities[backendID] ?? BackendAvailability(
            backendID: backendID,
            isAvailable: false,
            requiresNetwork: false,
            requiresAppleSilicon: false,
            localModelExists: false,
            reason: "Not configured in mock"
        )
    }
}
