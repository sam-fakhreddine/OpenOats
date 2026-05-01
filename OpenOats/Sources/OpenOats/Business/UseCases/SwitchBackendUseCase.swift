import Foundation

// MARK: - SwitchBackendUseCase

/// Protocol definition for SwitchBackendUseCase
public protocol SwitchBackendUseCase: Sendable {
    func execute(input: SwitchBackendInput) async throws -> SwitchBackendOutput
}

/// Input for switching backend
public struct SwitchBackendInput: Sendable {
    public let currentBackend: BackendID
    public let newBackend: BackendID
    public let preserveState: Bool
    
    public init(
        currentBackend: BackendID,
        newBackend: BackendID,
        preserveState: Bool = true
    ) {
        self.currentBackend = currentBackend
        self.newBackend = newBackend
        self.preserveState = preserveState
    }
}

/// Output from switching backend
public struct SwitchBackendOutput: Sendable {
    public let previousBackend: BackendID
    public let currentBackend: BackendID
    public let availableModels: [String]
    public let isOnline: Bool
    
    public init(
        previousBackend: BackendID,
        currentBackend: BackendID,
        availableModels: [String],
        isOnline: Bool
    ) {
        self.previousBackend = previousBackend
        self.currentBackend = currentBackend
        self.availableModels = availableModels
        self.isOnline = isOnline
    }
}

/// Backend availability info
public struct BackendAvailabilityInfo: Sendable {
    public let id: BackendID
    public let isAvailable: Bool
    public let models: [String]
    public let latency: Duration?
    public let isOnline: Bool
    
    public init(
        id: BackendID,
        isAvailable: Bool,
        models: [String],
        latency: Duration? = nil,
        isOnline: Bool
    ) {
        self.id = id
        self.isAvailable = isAvailable
        self.models = models
        self.latency = latency
        self.isOnline = isOnline
    }
}

// MARK: - SwitchBackendUseCase Implementation

/// Implementation of SwitchBackendUseCase
public actor SwitchBackendUseCaseImpl: SwitchBackendUseCase {
    private let backendRegistry: any BackendAvailabilityRegistry
    private let transcriptionServiceFactory: any ServiceFactory
    private let settingsRepository: (any SettingsRepository)?
    
    private var activeBackend: BackendID
    private var isSwitching = false
    
    public init(
        backendRegistry: any BackendAvailabilityRegistry,
        transcriptionServiceFactory: any ServiceFactory,
        settingsRepository: (any SettingsRepository)? = nil,
        initialBackend: BackendID = .mlxWhisper
    ) {
        self.backendRegistry = backendRegistry
        self.transcriptionServiceFactory = transcriptionServiceFactory
        self.settingsRepository = settingsRepository
        self.activeBackend = initialBackend
    }
    
    public func execute(input: SwitchBackendInput) async throws -> SwitchBackendOutput {
        // Check for cancellation
        try Task.checkCancellation()
        
        // Validate current backend matches
        guard input.currentBackend == activeBackend else {
            throw ValidationError.invalidInput(
                field: "currentBackend",
                value: input.currentBackend.rawValue,
                requirement: "Current backend mismatch. Expected: \(activeBackend.rawValue), got: \(input.currentBackend.rawValue)"
            )
        }
        
        // Check if already switching
        guard !isSwitching else {
            throw TranscriptionError.backendFailed(
                backend: input.newBackend.rawValue,
                reason: "Backend switch already in progress",
                recoverable: true
            )
        }
        
        isSwitching = true
        defer { isSwitching = false }
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Validate new backend exists and is available
        let availability = await backendRegistry.getAvailability(for: input.newBackend)
        
        guard availability.isAvailable else {
            throw TranscriptionError.modelUnavailable(
                model: input.newBackend.rawValue,
                reason: "Backend not available"
            )
        }
        
        // Check for cancellation before performing switch
        try Task.checkCancellation()
        
        // Perform the backend switch
        let previousBackend = activeBackend
        activeBackend = input.newBackend
        
        // Save preference if settings repository available
        if let settings = settingsRepository {
            settings.set(input.newBackend.rawValue, for: .defaultTranscriptionBackend)
        }
        
        return SwitchBackendOutput(
            previousBackend: previousBackend,
            currentBackend: input.newBackend,
            availableModels: availability.models,
            isOnline: availability.isOnline
        )
    }
    
    /// Get currently active backend
    public func getActiveBackend() async -> BackendID {
        activeBackend
    }
    
    /// Set active backend (internal use, testing)
    package func setActiveBackend(_ backend: BackendID) async {
        activeBackend = backend
    }
}

// MARK: - Backend Registry Protocol

/// Protocol for backend availability registry
public protocol BackendAvailabilityRegistry: Sendable {
    func getAvailability(for backendID: BackendID) async -> BackendAvailabilityInfo
    func setAvailability(_ availability: BackendAvailabilityInfo, for backendID: BackendID) async
    func listAvailableBackends() async -> [BackendAvailabilityInfo]
}
