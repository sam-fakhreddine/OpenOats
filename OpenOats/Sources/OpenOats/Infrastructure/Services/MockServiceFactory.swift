import Foundation

// MARK: - Mock Service Factory

/// Mock implementation of ServiceFactory for testing.
@available(macOS 15.0, *)
public actor MockServiceFactory: ServiceFactory {
    
    // MARK: - Configuration
    
    private var configuredBackends: Set<BackendID>
    private var configuredLLMProviders: Set<LLMProviderID>
    private var defaultAudioConfiguration: AudioCaptureConfiguration
    
    // MARK: - Created Services (for verification)
    
    private(set) var createdTranscriptionServices: [BackendID: TranscriptionService] = [:]
    private(set) var createdStreamingServices: [BackendID: StreamingTranscriptionService] = [:]
    private(set) var createdBatchServices: [BackendID: BatchTranscriptionService] = [:]
    private(set) var createdAudioCaptureServices: [UUID: AudioCaptureService] = [:]
    private(set) var createdAudioFormatServices: [UUID: AudioFormatService] = [:]
    private(set) var createdLLMServices: [LLMProviderID: LLMService] = [:]
    private(set) var createdEmbeddingServices: [EmbeddingProviderID: EmbeddingService] = [:]
    
    // MARK: - Shared Repository Instances
    
    private let sessionRepo: MockSessionRepository
    private let transcriptRepo: MockTranscriptRepository
    private let settingsRepo: MockSettingsRepository
    private let meetingRepo: MockMeetingRepository
    private let suggestionService: MockAISuggestionService
    
    // MARK: - Initialization
    
    public init(
        configuredBackends: [BackendID] = [.whisperKit, .mlxWhisper, .assemblyAI],
        configuredLLMProviders: [LLMProviderID] = [.openRouter, .ollama],
        defaultAudioConfiguration: AudioCaptureConfiguration = AudioCaptureConfiguration()
    ) {
        self.configuredBackends = Set(configuredBackends)
        self.configuredLLMProviders = Set(configuredLLMProviders)
        self.defaultAudioConfiguration = defaultAudioConfiguration
        
        // Create shared repository instances
        self.sessionRepo = MockSessionRepository()
        self.transcriptRepo = MockTranscriptRepository()
        self.settingsRepo = MockSettingsRepository()
        self.meetingRepo = MockMeetingRepository()
        self.suggestionService = MockAISuggestionService()
    }
    
    // MARK: - Transcription Services
    
    public func makeTranscriptionService(backend: BackendID) -> TranscriptionService? {
        guard configuredBackends.contains(backend) else { return nil }
        
        let service = MockTranscriptionService(
            backendID: backend,
            displayName: "Mock \(backend.rawValue)"
        )
        createdTranscriptionServices[backend] = service
        return service
    }
    
    public func makeStreamingTranscriptionService(backend: BackendID) -> StreamingTranscriptionService? {
        guard configuredBackends.contains(backend) else { return nil }
        
        let service = MockStreamingTranscriptionService(
            backendID: backend,
            displayName: "Mock Streaming \(backend.rawValue)"
        )
        createdStreamingServices[backend] = service
        return service
    }
    
    public func makeBatchTranscriptionService(backend: BackendID) -> BatchTranscriptionService? {
        guard configuredBackends.contains(backend) else { return nil }
        
        let service = MockBatchTranscriptionService(
            backendID: backend,
            displayName: "Mock Batch \(backend.rawValue)"
        )
        createdBatchServices[backend] = service
        return service
    }
    
    // MARK: - Audio Services
    
    public func makeAudioCaptureService(configuration: AudioCaptureConfiguration) -> AudioCaptureService {
        let service = MockAudioCaptureService(configuration: configuration)
        createdAudioCaptureServices[UUID()] = service
        return service
    }
    
    public func makeAudioFormatService() -> AudioFormatService {
        let service = MockAudioFormatService()
        createdAudioFormatServices[UUID()] = service
        return service
    }
    
    // MARK: - Storage Services
    
    public func makeSessionRepository() -> SessionRepositoryProtocol {
        return sessionRepo
    }
    
    public func makeTranscriptRepository() -> TranscriptRepository {
        return transcriptRepo
    }
    
    public func makeSettingsRepository() -> SettingsRepository {
        return settingsRepo
    }
    
    public func makeMeetingRepository() -> MeetingRepositoryProtocol {
        return meetingRepo
    }
    
    // MARK: - AI Services
    
    public func makeLLMService(provider: LLMProviderID) -> LLMService? {
        guard configuredLLMProviders.contains(provider) else { return nil }
        
        let service = MockLLMService()
        createdLLMServices[provider] = service
        return service
    }
    
    public func makeEmbeddingService(provider: EmbeddingProviderID) -> EmbeddingService? {
        let service = MockEmbeddingService()
        createdEmbeddingServices[provider] = service
        return service
    }
    
    public func makeAISuggestionService() -> AISuggestionService {
        return suggestionService
    }
    
    // MARK: - Test Helpers
    
    public func getSessionRepository() -> MockSessionRepository {
        return sessionRepo
    }
    
    public func getTranscriptRepository() -> MockTranscriptRepository {
        return transcriptRepo
    }
    
    public func getSettingsRepository() -> MockSettingsRepository {
        return settingsRepo
    }
    
    public func getMeetingRepository() -> MockMeetingRepository {
        return meetingRepo
    }
    
    public func getSuggestionService() -> MockAISuggestionService {
        return suggestionService
    }
    
    public func addConfiguredBackend(_ backend: BackendID) {
        configuredBackends.insert(backend)
    }
    
    public func removeConfiguredBackend(_ backend: BackendID) {
        configuredBackends.remove(backend)
    }
    
    public func addConfiguredLLMProvider(_ provider: LLMProviderID) {
        configuredLLMProviders.insert(provider)
    }
    
    public func removeConfiguredLLMProvider(_ provider: LLMProviderID) {
        configuredLLMProviders.remove(provider)
    }
    
    public func reset() {
        createdTranscriptionServices.removeAll()
        createdStreamingServices.removeAll()
        createdBatchServices.removeAll()
        createdAudioCaptureServices.removeAll()
        createdAudioFormatServices.removeAll()
        createdLLMServices.removeAll()
        createdEmbeddingServices.removeAll()
    }
}

// MARK: - Mock Service Registry

/// Mock implementation of ServiceRegistry for testing.
@available(macOS 15.0, *)
public actor MockServiceRegistry: ServiceRegistry {
    private var services: [String: Any] = [:]
    
    public init() {}
    
    public func register<T: Sendable>(_ service: T, for type: String) {
        services[type] = service
    }
    
    public func resolve<T: Sendable>(_ type: String) -> T? {
        return services[type] as? T
    }
    
    public func unregister(_ type: String) {
        services.removeValue(forKey: type)
    }
    
    public func clear() {
        services.removeAll()
    }
    
    // MARK: - Test Helpers
    
    public func registeredTypes() -> [String] {
        return Array(services.keys)
    }
    
    public func isRegistered(_ type: String) -> Bool {
        return services[type] != nil
    }
}
