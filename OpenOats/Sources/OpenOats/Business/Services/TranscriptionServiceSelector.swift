import Foundation
import os

// MARK: - Transcription Service Selector

/// Automatically selects the best transcription backend based on:
/// 1. User preference (highest priority)
/// 2. Hardware capabilities (Apple Silicon for MLX)
/// 3. Network connectivity (for cloud backends)
/// 4. Model download status
/// 5. Fallback chain execution
///
/// The selector follows this decision hierarchy:
/// - If user preference is set and available → Use preference
/// - If preference unavailable → Try fallback chain starting from preference
/// - If no preference → Use best available local backend
/// - If no local available → Use cloud (if network available)
/// - If nothing available → Return error
public actor TranscriptionServiceSelector {
    
    private static let log = Logger(subsystem: "com.openoats.app", category: "TranscriptionServiceSelector")
    
    /// Availability checker for backends
    private let availabilityChecker: any BackendAvailabilityChecking
    
    /// Fallback chain manager
    private let fallbackChain: any BackendFallbackChaining
    
    /// Configuration for selection behavior
    private let configuration: BackendSelectionConfiguration
    
    /// History of selections for telemetry/optimization
    private var selectionHistory: [BackendSelectionResult] = []
    
    /// Creates a new transcription service selector
    /// - Parameters:
    ///   - availabilityChecker: Checker for backend availability
    ///   - fallbackChain: Fallback chain manager
    ///   - configuration: Selection configuration
    public init(
        availabilityChecker: any BackendAvailabilityChecking,
        fallbackChain: any BackendFallbackChaining,
        configuration: BackendSelectionConfiguration = .default
    ) {
        self.availabilityChecker = availabilityChecker
        self.fallbackChain = fallbackChain
        self.configuration = configuration
    }
    
    /// Select the best backend based on preference and availability
    /// - Parameters:
    ///   - preferred: User's preferred backend (nil if no preference)
    ///   - isAppleSilicon: Whether running on Apple Silicon (auto-detected if nil)
    ///   - networkConnected: Whether network is available (auto-detected if nil)
    ///   - localModels: List of backends with downloaded models
    /// - Returns: Selection result with chosen backend and metadata
    public func selectBackend(
        preferred: BackendID? = nil,
        isAppleSilicon: Bool? = nil,
        networkConnected: Bool? = nil,
        localModels: [BackendID] = []
    ) async -> BackendSelectionResult {
        
        // Detect environment if not provided
        let appleSilicon = isAppleSilicon ?? await detectAppleSilicon()
        let network = networkConnected ?? await checkNetworkConnectivity()
        
        Self.log.info("Selecting backend: preferred=\(preferred?.rawValue ?? "nil"), isAppleSilicon=\(appleSilicon), network=\(network)")
        
        // Strategy 1: Try user preference first
        if let preferred = preferred {
            let result = await tryPreferredBackend(
                preferred,
                isAppleSilicon: appleSilicon,
                networkConnected: network,
                localModels: localModels
            )
            
            await recordSelection(result)
            return result
        }
        
        // Strategy 2: No preference - use best available
        let result = await findBestAvailableBackend(
            isAppleSilicon: appleSilicon,
            networkConnected: network,
            localModels: localModels
        )
        
        await recordSelection(result)
        return result
    }
    
    /// Quick select without preferences (uses defaults)
    /// - Parameter preferred: Optional preferred backend
    /// - Returns: Selection result
    public func selectBackend(preferred: BackendID? = nil) async -> BackendSelectionResult {
        return await selectBackend(
            preferred: preferred,
            isAppleSilicon: nil,
            networkConnected: nil,
            localModels: []
        )
    }
    
    /// Get selection history for analysis
    public func getSelectionHistory() async -> [BackendSelectionResult] {
        return selectionHistory
    }
    
    /// Clear selection history
    public func clearHistory() async {
        selectionHistory.removeAll()
    }
    
    // MARK: - Private Selection Logic
    
    /// Try to use the user's preferred backend with fallback
    private func tryPreferredBackend(
        _ preferred: BackendID,
        isAppleSilicon: Bool,
        networkConnected: Bool,
        localModels: [BackendID]
    ) async -> BackendSelectionResult {
        
        // Check if preferred is available
        let availability = await checkAvailability(
            for: preferred,
            isAppleSilicon: isAppleSilicon,
            networkConnected: networkConnected,
            localModels: localModels
        )
        
        if availability.isAvailable {
            Self.log.info("Using preferred backend: \(preferred.rawValue)")
            return .preferred(preferred)
        }
        
        // Preferred not available - try fallback chain starting from preference
        Self.log.info("Preferred backend \(preferred.rawValue) unavailable: \(availability.reason ?? "unknown"), trying fallback")
        
        let chain = await fallbackChain.fallbackChain(
            startingFrom: preferred,
            using: availabilityChecker
        )
        
        // Filter chain to only include available backends
        let availableChain = await filterAvailable(
            chain,
            isAppleSilicon: isAppleSilicon,
            networkConnected: networkConnected,
            localModels: localModels
        )
        
        // Remove the preferred backend (already known unavailable)
        let filteredChain = availableChain.filter { $0 != preferred }
        
        if let fallback = filteredChain.first {
            let reason = "Preferred backend unavailable: \(availability.reason ?? "unknown")"
            Self.log.info("Selected fallback: \(fallback.rawValue) (reason: \(reason))")
            return .fallback(fallback, chain: [preferred] + filteredChain, reason: reason)
        }
        
        // No fallback available
        let reason = "Preferred backend unavailable and no fallbacks available: \(availability.reason ?? "unknown")"
        Self.log.error("Backend selection failed: \(reason)")
        return .failure(reason: reason, attempted: [preferred])
    }
    
    /// Find best available backend when no preference set
    private func findBestAvailableBackend(
        isAppleSilicon: Bool,
        networkConnected: Bool,
        localModels: [BackendID]
    ) async -> BackendSelectionResult {
        
        // Try local backends first (if configured to prefer local)
        if configuration.preferLocalOverCloud {
            let localChain = fallbackChain.localBackends()
            let availableLocal = await filterAvailable(
                localChain,
                isAppleSilicon: isAppleSilicon,
                networkConnected: networkConnected,
                localModels: localModels
            )
            
            if let bestLocal = availableLocal.first {
                let reason = "No preference set, selected best local backend"
                Self.log.info("\(reason): \(bestLocal.rawValue)")
                return BackendSelectionResult(
                    selectedBackend: bestLocal,
                    wasFallback: false,
                    fallbackChain: availableLocal,
                    reason: reason
                )
            }
        }
        
        // Try cloud backends if allowed and network available
        if configuration.allowCloudFallback && networkConnected {
            let cloudChain = fallbackChain.cloudBackends()
            let availableCloud = await filterAvailable(
                cloudChain,
                isAppleSilicon: isAppleSilicon,
                networkConnected: networkConnected,
                localModels: localModels
            )
            
            if let cloud = availableCloud.first {
                let reason = "No local backends available, using cloud"
                Self.log.info("\(reason): \(cloud.rawValue)")
                return BackendSelectionResult(
                    selectedBackend: cloud,
                    wasFallback: true,
                    fallbackChain: availableCloud,
                    reason: reason
                )
            }
        }
        
        // Nothing available
        let reason = "No transcription backends available"
        Self.log.error(reason)
        return .failure(reason: reason)
    }
    
    // MARK: - Helper Methods
    
    /// Check availability for a specific backend with context
    private func checkAvailability(
        for backendID: BackendID,
        isAppleSilicon: Bool,
        networkConnected: Bool,
        localModels: [BackendID]
    ) async -> BackendAvailability {
        
        let modelExists = localModels.contains(backendID)
        
        return await availabilityChecker.checkAvailability(
            for: backendID,
            isAppleSilicon: isAppleSilicon,
            networkConnected: networkConnected,
            modelExists: modelExists
        )
    }
    
    /// Filter chain to only available backends
    private func filterAvailable(
        _ chain: [BackendID],
        isAppleSilicon: Bool,
        networkConnected: Bool,
        localModels: [BackendID]
    ) async -> [BackendID] {
        
        var available: [BackendID] = []
        
        for backendID in chain {
            let availability = await checkAvailability(
                for: backendID,
                isAppleSilicon: isAppleSilicon,
                networkConnected: networkConnected,
                localModels: localModels
            )
            
            if availability.isAvailable {
                available.append(backendID)
            }
        }
        
        return available
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
        // Simple reachability check
        // In production, this could use NWPathMonitor or similar
        return true
    }
    
    /// Record selection for history/telemetry
    private func recordSelection(_ result: BackendSelectionResult) async {
        selectionHistory.append(result)
        
        // Keep history bounded
        if selectionHistory.count > 100 {
            selectionHistory.removeFirst(selectionHistory.count - 100)
        }
    }
}

// MARK: - Convenience Extensions

extension TranscriptionServiceSelector {
    /// Select backend for offline-only operation
    /// - Parameter preferred: Optional preferred backend
    /// - Returns: Selection result with local backend only
    public func selectLocalBackend(preferred: BackendID? = nil) async -> BackendSelectionResult {
        return await selectBackend(
            preferred: preferred,
            isAppleSilicon: nil,
            networkConnected: false, // Force offline
            localModels: []
        )
    }
    
    /// Check if a specific backend would be selected
    /// - Parameter backendID: Backend to check
    /// - Returns: True if this backend would be selected
    public func wouldSelect(_ backendID: BackendID) async -> Bool {
        let result = await selectBackend(preferred: backendID)
        return result.selectedBackend == backendID && !result.wasFallback
    }
}
