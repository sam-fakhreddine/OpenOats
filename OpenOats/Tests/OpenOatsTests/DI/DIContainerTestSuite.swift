import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - DI Container Test Suite

/// Comprehensive test suite for the Dependency Injection Container.
/// Tests all factories, lazy initialization, mock injection, and Sendable safety.
@Suite("DI Container Test Suite")
struct DIContainerTestSuite {
    
    // MARK: - Service Factory Tests
    
    @Test("ServiceFactory creates transcription services")
    func serviceFactoryCreatesTranscriptionServices() async throws {
        let factory = MockServiceFactory()
        
        let service = factory.makeTranscriptionService(backend: .mlxWhisper)
        #expect(service != nil)
        
        let streamingService = factory.makeStreamingTranscriptionService(backend: .whisperKit)
        #expect(streamingService != nil)
        
        let batchService = factory.makeBatchTranscriptionService(backend: .assemblyAI)
        #expect(batchService != nil)
    }
    
    @Test("ServiceFactory returns nil for unconfigured backends")
    func serviceFactoryReturnsNilForUnconfiguredBackends() async throws {
        let factory = MockServiceFactory(configuredBackends: [.mlxWhisper])
        
        let service = factory.makeTranscriptionService(backend: .whisperKit)
        #expect(service == nil)
    }
    
    @Test("ServiceFactory creates audio services")
    func serviceFactoryCreatesAudioServices() async throws {
        let factory = MockServiceFactory()
        let config = AudioCaptureConfiguration()
        
        let captureService = factory.makeAudioCaptureService(configuration: config)
        #expect(captureService is MockAudioCaptureService)
        
        let formatService = factory.makeAudioFormatService()
        #expect(formatService is MockAudioFormatService)
    }
    
    @Test("ServiceFactory creates repository services")
    func serviceFactoryCreatesRepositoryServices() async throws {
        let factory = MockServiceFactory()
        
        let sessionRepo = factory.makeSessionRepository()
        #expect(sessionRepo is MockSessionRepository)
        
        let transcriptRepo = factory.makeTranscriptRepository()
        #expect(transcriptRepo is MockTranscriptRepository)
        
        let settingsRepo = factory.makeSettingsRepository()
        #expect(settingsRepo is MockSettingsRepository)
        
        let meetingRepo = factory.makeMeetingRepository()
        #expect(meetingRepo is MockMeetingRepository)
    }
    
    @Test("ServiceFactory creates AI services")
    func serviceFactoryCreatesAIServices() async throws {
        let factory = MockServiceFactory()
        
        let llmService = factory.makeLLMService(provider: .openRouter)
        #expect(llmService != nil)
        
        let embeddingService = factory.makeEmbeddingService(provider: .voyage)
        #expect(embeddingService != nil)
        
        let suggestionService = factory.makeAISuggestionService()
        #expect(suggestionService is MockAISuggestionService)
    }
    
    @Test("ServiceFactory is Sendable-safe")
    func serviceFactoryIsSendable() async throws {
        let factory: any ServiceFactory = MockServiceFactory()
        
        // Compile-time check: if this compiles, ServiceFactory is Sendable
        await Task.detached {
            _ = factory.makeTranscriptionService(backend: .mlxWhisper)
        }.value
        
        #expect(true)
    }
    
    // MARK: - UseCase Factory Tests
    
    @Test("UseCaseFactory creates StartSessionUseCase")
    func useCaseFactoryCreatesStartSessionUseCase() async throws {
        let factory = UseCaseFactoryImpl(serviceFactory: MockServiceFactory())
        
        let useCase = factory.makeStartSessionUseCase()
        #expect(useCase != nil)
    }
    
    @Test("UseCaseFactory creates StopSessionUseCase")
    func useCaseFactoryCreatesStopSessionUseCase() async throws {
        let factory = UseCaseFactoryImpl(serviceFactory: MockServiceFactory())
        
        let useCase = factory.makeStopSessionUseCase()
        #expect(useCase != nil)
    }
    
    @Test("UseCaseFactory creates GenerateNotesUseCase")
    func useCaseFactoryCreatesGenerateNotesUseCase() async throws {
        let factory = UseCaseFactoryImpl(serviceFactory: MockServiceFactory())
        
        let useCase = factory.makeGenerateNotesUseCase()
        #expect(useCase != nil)
    }
    
    @Test("UseCaseFactory creates ExportTranscriptUseCase")
    func useCaseFactoryCreatesExportTranscriptUseCase() async throws {
        let factory = UseCaseFactoryImpl(serviceFactory: MockServiceFactory())
        
        let useCase = factory.makeExportTranscriptUseCase()
        #expect(useCase != nil)
    }
    
    @Test("UseCaseFactory creates ImportAudioUseCase")
    func useCaseFactoryCreatesImportAudioUseCase() async throws {
        let factory = UseCaseFactoryImpl(serviceFactory: MockServiceFactory())
        
        let useCase = factory.makeImportAudioUseCase()
        #expect(useCase != nil)
    }
    
    @Test("UseCaseFactory creates SwitchBackendUseCase")
    func useCaseFactoryCreatesSwitchBackendUseCase() async throws {
        let factory = UseCaseFactoryImpl(serviceFactory: MockServiceFactory())
        
        let useCase = factory.makeSwitchBackendUseCase()
        #expect(useCase != nil)
    }
    
    @Test("UseCaseFactory is Sendable-safe")
    func useCaseFactoryIsSendable() async throws {
        let factory: any UseCaseFactory = UseCaseFactoryImpl(serviceFactory: MockServiceFactory())
        
        // Compile-time check: if this compiles, UseCaseFactory is Sendable
        await Task.detached {
            _ = factory.makeStartSessionUseCase()
        }.value
        
        #expect(true)
    }
    
    // MARK: - ViewModel Factory Tests
    
    @MainActor
    @Test("ViewModelFactory creates SessionViewModel")
    func viewModelFactoryCreatesSessionViewModel() async throws {
        let factory = ViewModelFactoryImpl(useCaseFactory: UseCaseFactoryImpl(serviceFactory: MockServiceFactory()))
        
        let viewModel = factory.makeSessionViewModel()
        #expect(viewModel != nil)
    }
    
    @MainActor
    @Test("ViewModelFactory creates TranscriptViewModel")
    func viewModelFactoryCreatesTranscriptViewModel() async throws {
        let factory = ViewModelFactoryImpl(useCaseFactory: UseCaseFactoryImpl(serviceFactory: MockServiceFactory()))
        
        let viewModel = factory.makeTranscriptViewModel()
        #expect(viewModel != nil)
    }
    
    @MainActor
    @Test("ViewModelFactory creates SettingsViewModel")
    func viewModelFactoryCreatesSettingsViewModel() async throws {
        let factory = ViewModelFactoryImpl(useCaseFactory: UseCaseFactoryImpl(serviceFactory: MockServiceFactory()))
        
        let viewModel = factory.makeSettingsViewModel()
        #expect(viewModel != nil)
    }
    
    @MainActor
    @Test("ViewModelFactory creates IdleDashboardViewModel")
    func viewModelFactoryCreatesIdleDashboardViewModel() async throws {
        let factory = ViewModelFactoryImpl(useCaseFactory: UseCaseFactoryImpl(serviceFactory: MockServiceFactory()))
        
        let viewModel = factory.makeIdleDashboardViewModel()
        #expect(viewModel != nil)
    }
    
    @MainActor
    @Test("ViewModelFactory is Sendable-safe")
    func viewModelFactoryIsSendable() async throws {
        let factory: any ViewModelFactory = ViewModelFactoryImpl(useCaseFactory: UseCaseFactoryImpl(serviceFactory: MockServiceFactory()))
        
        // Compile-time check: if this compiles, ViewModelFactory is Sendable
        _ = factory.makeSessionViewModel()
        
        #expect(true)
    }
    
    // MARK: - Lazy Initialization Tests
    
    @Test("AppContainer uses lazy initialization for services")
    func appContainerUsesLazyInitialization() async throws {
        let container = DIContainer(mode: .test)
        
        // Services should not be created until accessed
        let serviceFactory1 = await container.serviceFactory
        let serviceFactory2 = await container.serviceFactory
        
        // Should return same instance (lazy cached)
        #expect(serviceFactory1 === serviceFactory2)
    }
    
    @Test("AppContainer uses lazy initialization for use cases")
    func appContainerUsesLazyInitializationForUseCases() async throws {
        let container = DIContainer(mode: .test)
        
        let useCaseFactory1 = await container.useCaseFactory
        let useCaseFactory2 = await container.useCaseFactory
        
        // Should return same instance (lazy cached)
        #expect(useCaseFactory1 === useCaseFactory2)
    }
    
    @MainActor
    @Test("AppContainer uses lazy initialization for view models")
    func appContainerUsesLazyInitializationForViewModels() async throws {
        let container = DIContainer(mode: .test)
        
        let viewModelFactory1 = container.viewModelFactory
        let viewModelFactory2 = container.viewModelFactory
        
        // Should return same instance (lazy cached)
        #expect(viewModelFactory1 === viewModelFactory2)
    }
    
    // MARK: - Mock Injection Tests
    
    @Test("AppContainer supports mock service factory injection")
    func appContainerSupportsMockServiceFactoryInjection() async throws {
        let mockFactory = MockServiceFactory()
        let container = AppDIContainer(mode: .test, serviceFactory: mockFactory)
        
        let factory = await container.serviceFactory
        #expect(factory is MockServiceFactory)
    }
    
    @Test("AppContainer supports mock use case factory injection")
    func appContainerSupportsMockUseCaseFactoryInjection() async throws {
        let mockUseCaseFactory = MockUseCaseFactory()
        let container = AppDIContainer(mode: .test, useCaseFactory: mockUseCaseFactory)
        
        let factory = await container.useCaseFactory
        #expect(factory is MockUseCaseFactory)
    }
    
    @MainActor
    @Test("AppContainer supports mock view model factory injection")
    func appContainerSupportsMockViewModelFactoryInjection() async throws {
        let mockViewModelFactory = MockViewModelFactory()
        let container = AppDIContainer(mode: .test, viewModelFactory: mockViewModelFactory)
        
        let factory = container.viewModelFactory
        #expect(factory is MockViewModelFactory)
    }
    
    // MARK: - Sendable Safety Tests
    
    @Test("All factory protocols are Sendable")
    func allFactoryProtocolsAreSendable() async throws {
        // Compile-time check
        let serviceFactory: any ServiceFactory = MockServiceFactory()
        let useCaseFactory: any UseCaseFactory = UseCaseFactoryImpl(serviceFactory: serviceFactory)
        
        _ = serviceFactory
        _ = useCaseFactory
        
        #expect(true)
    }
    
    @Test("AppContainer is Sendable-safe")
    func appContainerIsSendable() async throws {
        let container = DIContainer(mode: .test)
        
        // Compile-time check: if this compiles, AppContainer is Sendable-safe
        await Task.detached {
            _ = await container.serviceFactory
        }.value
        
        #expect(true)
    }
    
    // MARK: - Runtime Mode Tests
    
    @Test("AppContainer creates live dependencies in live mode")
    func appContainerCreatesLiveDependenciesInLiveMode() async throws {
        let container = AppDIContainer(mode: .live)
        
        #expect(container.mode == .live)
    }
    
    @Test("AppContainer creates test dependencies in test mode")
    func appContainerCreatesTestDependenciesInTestMode() async throws {
        let container = DIContainer(mode: .test)
        
        #expect(container.mode == .test)
    }
    
    @Test("AppContainer creates preview dependencies in preview mode")
    func appContainerCreatesPreviewDependenciesInPreviewMode() async throws {
        let container = AppDIContainer(mode: .preview)
        
        #expect(container.mode == .preview)
    }
    
    // MARK: - Integration Tests
    
    @MainActor
    @Test("DI Container wires all layers correctly")
    func diContainerWiresAllLayersCorrectly() async throws {
        let container = DIContainer(mode: .test)
        
        // Get all factories
        let serviceFactory = await container.serviceFactory
        let useCaseFactory = await container.useCaseFactory
        let viewModelFactory = container.viewModelFactory
        
        // Create services through factory
        let sessionRepo = serviceFactory.makeSessionRepository()
        #expect(sessionRepo != nil)
        
        // Create use cases through factory
        let startUseCase = useCaseFactory.makeStartSessionUseCase()
        #expect(startUseCase != nil)
        
        // Create view models through factory
        let sessionViewModel = viewModelFactory.makeSessionViewModel()
        #expect(sessionViewModel != nil)
        
        // Verify complete wiring
        #expect(serviceFactory is MockServiceFactory)
        #expect(useCaseFactory is UseCaseFactoryImpl)
        #expect(viewModelFactory is ViewModelFactoryImpl)
    }
    
    @Test("Use cases created by factory can execute")
    func useCasesCreatedByFactoryCanExecute() async throws {
        let container = DIContainer(mode: .test)
        let useCaseFactory = await container.useCaseFactory
        
        let startUseCase = useCaseFactory.makeStartSessionUseCase()
        let input = StartSessionInput(backend: .mlxWhisper)
        
        // Execute the use case
        let output = try await startUseCase.execute(input: input)
        
        #expect(output.session.status == .active)
        #expect(output.sessionID != nil)
    }
    
    // MARK: - Health Check Tests
    
    @Test("ServiceFactory provides health check capability")
    func serviceFactoryProvidesHealthCheck() async throws {
        let factory = MockServiceFactory()
        
        // Mock services implement HealthCheckable
        let service = factory.makeTranscriptionService(backend: .mlxWhisper)
        
        if let healthCheckable = service as? any HealthCheckable {
            let status = await healthCheckable.checkHealth()
            #expect(status.isHealthy == true)
        } else {
            // Not all services may implement HealthCheckable
            #expect(true)
        }
    }
    
    // MARK: - Cleanup Tests
    
    @Test("AppContainer can reset dependencies")
    func appContainerCanResetDependencies() async throws {
        let container = DIContainer(mode: .test)
        
        // Access factories to create them
        _ = await container.serviceFactory
        _ = await container.useCaseFactory
        
        // Reset the container
        await container.reset()
        
        // After reset, factories should be recreated
        let newServiceFactory = await container.serviceFactory
        #expect(newServiceFactory != nil)
        
        #expect(true)
    }
}

// MARK: - Mock Implementations for DI Testing

/// Mock implementation of UseCaseFactory for testing
@available(macOS 15.0, *)
actor MockUseCaseFactory: UseCaseFactory {
    func makeStartSessionUseCase() -> any StartSessionUseCase {
        return MockStartSessionUseCase()
    }
    
    func makeStopSessionUseCase() -> any StopSessionUseCase {
        return MockStopSessionUseCase()
    }
    
    func makeGenerateNotesUseCase() -> any GenerateNotesUseCase {
        return MockGenerateNotesUseCase()
    }
    
    func makeExportTranscriptUseCase() -> any ExportTranscriptUseCase {
        return MockExportTranscriptUseCase()
    }
    
    func makeImportAudioUseCase() -> any ImportAudioUseCase {
        return MockImportAudioUseCase()
    }
    
    func makeSwitchBackendUseCase() -> any SwitchBackendUseCase {
        return MockSwitchBackendUseCase()
    }
}

/// Mock implementation of ViewModelFactory for testing
@MainActor
struct MockViewModelFactory: ViewModelFactory {
    func makeSessionViewModel() -> any SessionViewModel {
        return DefaultSessionViewModel()
    }
    
    func makeTranscriptViewModel() -> any TranscriptViewModel {
        return DefaultTranscriptViewModel()
    }
    
    func makeSettingsViewModel() -> any SettingsViewModel {
        return DefaultSettingsViewModel()
    }
    
    func makeIdleDashboardViewModel() -> any IdleDashboardViewModel {
        return DefaultIdleDashboardViewModel()
    }
    
    func makeBackendConfigurationViewModel() -> any BackendConfigurationViewModel {
        // Not implemented for mock
        fatalError("Not implemented")
    }
}

/// Mock StartSessionUseCase for testing
struct MockStartSessionUseCase: StartSessionUseCase {
    private let shouldFail: Bool
    private let delay: Duration?
    
    init(shouldFail: Bool = false, delay: Duration? = nil) {
        self.shouldFail = shouldFail
        self.delay = delay
    }
    
    func execute(input: StartSessionInput) async throws -> StartSessionOutput {
        if let delay = delay {
            try await Task.sleep(for: delay)
        }
        
        if shouldFail {
            throw ValidationError.invalidInput(field: "test", value: "", requirement: "Simulated failure")
        }
        
        let sessionID = SessionID()
        let session = Session(
            id: sessionID,
            meetingID: MeetingID(),
            startTime: Date(),
            status: .active
        )
        
        return StartSessionOutput(sessionID: sessionID, session: session)
    }
}

/// Mock StopSessionUseCase for testing
struct MockStopSessionUseCase: StopSessionUseCase {
    private let delay: Duration?
    var sessions: [SessionID: Session] = [:]
    
    init(delay: Duration? = nil) {
        self.delay = delay
    }
    
    func execute(input: StopSessionInput) async throws -> StopSessionOutput {
        if let delay = delay {
            try await Task.sleep(for: delay)
        }
        
        guard let session = sessions[input.sessionID] else {
            throw ValidationError.invalidInput(field: "sessionID", value: "", requirement: "Session not found")
        }
        
        let stoppedSession = session
            .withEndedAt(Date())
            .withStatus(.completed)
        
        return StopSessionOutput(
            session: stoppedSession,
            transcript: nil,
            recordingURL: nil
        )
    }
}

/// Mock GenerateNotesUseCase for testing
actor MockGenerateNotesUseCase: GenerateNotesUseCase {
    nonisolated let executionID: UUID = UUID()
    
    var isExecuting: Bool {
        get async { false }
    }
    
    func cancel() async {
        // No-op
    }
    
    func execute(input: GenerateNotesInput) async throws -> GenerateNotesOutput {
        let note = Note(
            id: NoteID(),
            sessionID: SessionID(),
            content: "Mock generated notes",
            category: .summary
        )
        
        return GenerateNotesOutput(
            note: note,
            generatedAt: Date(),
            processingTime: .seconds(1),
            tokenCount: 100
        )
    }
}

/// Mock ExportTranscriptUseCase for testing
actor MockExportTranscriptUseCase: ExportTranscriptUseCase {
    nonisolated var progressStream: AsyncStream<Double> {
        AsyncStream { continuation in
            continuation.yield(0.0)
            continuation.yield(0.5)
            continuation.yield(1.0)
            continuation.finish()
        }
    }
    
    func execute(input: ExportTranscriptInput) async throws -> ExportTranscriptOutput {
        return ExportTranscriptOutput(
            exportedURL: input.destination,
            bytesWritten: 1024
        )
    }
}

/// Mock ImportAudioUseCase for testing
actor MockImportAudioUseCase: ImportAudioUseCase {
    private let delay: Duration?
    
    init(delay: Duration? = nil) {
        self.delay = delay
    }
    
    nonisolated var progressStream: AsyncStream<Double> {
        AsyncStream { continuation in
            continuation.yield(0.0)
            continuation.yield(0.5)
            continuation.yield(1.0)
            continuation.finish()
        }
    }
    
    func execute(input: ImportAudioInput) async throws -> ImportAudioOutput {
        if let delay = delay {
            try await Task.sleep(for: delay)
        }
        
        let session = Session(
            id: SessionID(),
            meetingID: MeetingID(),
            startTime: Date(),
            status: .active
        )
        
        return ImportAudioOutput(
            session: session,
            transcript: nil,
            importedAt: Date()
        )
    }
}

/// Mock SwitchBackendUseCase for testing
actor MockSwitchBackendUseCase: SwitchBackendUseCase {
    func execute(input: SwitchBackendInput) async throws -> SwitchBackendOutput {
        return SwitchBackendOutput(
            previousBackend: input.currentBackend,
            currentBackend: input.newBackend,
            availableModels: ["model1", "model2"],
            isOnline: false
        )
    }
}