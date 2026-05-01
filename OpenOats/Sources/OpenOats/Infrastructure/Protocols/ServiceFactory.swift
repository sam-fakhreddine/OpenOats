import Foundation

// MARK: - Service Factory

/// Factory for creating infrastructure service instances.
/// Provides a central point for dependency injection and service creation.
public protocol ServiceFactory: Sendable {
    // MARK: - Transcription Services
    
    /// Create a transcription service for the specified backend.
    func makeTranscriptionService(backend: BackendID) -> TranscriptionService?
    
    /// Create a streaming transcription service for the specified backend.
    func makeStreamingTranscriptionService(backend: BackendID) -> StreamingTranscriptionService?
    
    /// Create a batch transcription service for the specified backend.
    func makeBatchTranscriptionService(backend: BackendID) -> BatchTranscriptionService?
    
    // MARK: - Audio Services
    
    /// Create an audio capture service with the specified configuration.
    func makeAudioCaptureService(configuration: AudioCaptureConfiguration) -> AudioCaptureService
    
    /// Create an audio format service.
    func makeAudioFormatService() -> AudioFormatService
    
    // MARK: - Storage Services
    
    /// Create a session repository.
    func makeSessionRepository() -> SessionRepositoryProtocol
    
    /// Create a transcript repository.
    func makeTranscriptRepository() -> TranscriptRepository
    
    /// Create a settings repository.
    func makeSettingsRepository() -> SettingsRepository
    
    /// Create a meeting repository.
    func makeMeetingRepository() -> MeetingRepositoryProtocol
    
    // MARK: - AI Services
    
    /// Create an LLM service for the specified provider.
    func makeLLMService(provider: LLMProviderID) -> LLMService?
    
    /// Create an embedding service for the specified provider.
    func makeEmbeddingService(provider: EmbeddingProviderID) -> EmbeddingService?
    
    /// Create a suggestion service.
    func makeAISuggestionService() -> AISuggestionService
}

// MARK: - Service Registry

/// Registry for managing service instances.
/// Provides lifecycle management and caching for services.
public protocol ServiceRegistry: Sendable {
    /// Register a service instance.
    func register<T: Sendable>(_ service: T, for type: String)
    
    /// Resolve a service instance.
    func resolve<T: Sendable>(_ type: String) -> T?
    
    /// Unregister a service.
    func unregister(_ type: String)
    
    /// Clear all registered services.
    func clear()
}

// MARK: - Service Health

/// Protocol for services that can report their health status.
public protocol HealthCheckable: Sendable {
    /// Perform a health check.
    func checkHealth() async -> HealthStatus
}

/// Health status of a service.
public struct HealthStatus: Sendable {
    public let isHealthy: Bool
    public let message: String?
    public let lastError: Error?
    public let timestamp: Date
    
    public init(
        isHealthy: Bool,
        message: String? = nil,
        lastError: Error? = nil,
        timestamp: Date = Date()
    ) {
        self.isHealthy = isHealthy
        self.message = message
        self.lastError = lastError
        self.timestamp = timestamp
    }
    
    public static let healthy = HealthStatus(isHealthy: true, message: "Service is healthy")
    public static func unhealthy(_ message: String, error: Error? = nil) -> HealthStatus {
        HealthStatus(isHealthy: false, message: message, lastError: error)
    }
}

extension HealthStatus: Equatable {
    public static func == (lhs: HealthStatus, rhs: HealthStatus) -> Bool {
        lhs.isHealthy == rhs.isHealthy &&
        lhs.message == rhs.message &&
        lhs.timestamp == rhs.timestamp
        // Note: lastError is intentionally excluded from Equatable comparison
    }
}
