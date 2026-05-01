import Foundation

// MARK: - UseCaseFactory Implementation

/// Default implementation of UseCaseFactory.
/// Creates use cases with their required dependencies from a ServiceFactory.
@available(macOS 15.0, *)
struct UseCaseFactoryImpl: UseCaseFactory {
    
    // MARK: - Dependencies
    
    private let serviceFactory: any ServiceFactory
    
    // MARK: - Initialization
    
    /// Creates a new UseCaseFactory with the specified service factory.
    /// - Parameter serviceFactory: Factory for creating infrastructure services.
    init(serviceFactory: any ServiceFactory) {
        self.serviceFactory = serviceFactory
    }
    
    // MARK: - Session Use Cases
    
    /// Creates a use case for starting a recording session.
    func makeStartSessionUseCase() -> any StartSessionUseCase {
        let sessionRepository = serviceFactory.makeSessionRepository()
        let transcriptionService = serviceFactory.makeStreamingTranscriptionService(backend: .mlxWhisper)
        let audioCaptureService = serviceFactory.makeAudioCaptureService(configuration: AudioCaptureConfiguration())
        
        return StartSessionUseCaseImpl(
            sessionRepository: sessionRepository,
            transcriptionService: transcriptionService,
            audioCaptureService: audioCaptureService
        )
    }
    
    /// Creates a use case for stopping a recording session.
    func makeStopSessionUseCase() -> any StopSessionUseCase {
        let sessionRepository = serviceFactory.makeSessionRepository()
        let transcriptRepository = serviceFactory.makeTranscriptRepository()
        // Note: AudioStorageService not yet available in protocols, using nil
        
        return StopSessionUseCaseImpl(
            sessionRepository: sessionRepository,
            transcriptRepository: transcriptRepository,
            audioStorage: nil
        )
    }
    
    // MARK: - Transcription Use Cases
    
    /// Creates a use case for exporting transcripts.
    func makeExportTranscriptUseCase() -> any ExportTranscriptUseCase {
        let transcriptRepository = serviceFactory.makeTranscriptRepository()
        // Create a mock file export service since it's not in ServiceFactory yet
        let fileExportService = MockFileExportService()
        
        return ExportTranscriptUseCaseImpl(
            transcriptRepository: transcriptRepository,
            fileExporter: fileExportService,
            utteranceRepository: nil
        )
    }
    
    /// Creates a use case for importing audio files.
    func makeImportAudioUseCase() -> any ImportAudioUseCase {
        let sessionRepository = serviceFactory.makeSessionRepository()
        let transcriptRepository = serviceFactory.makeTranscriptRepository()
        let audioValidationService = MockAudioValidationService()
        let batchTranscriptionService = serviceFactory.makeBatchTranscriptionService(backend: .mlxWhisper)
        
        return ImportAudioUseCaseImpl(
            sessionRepository: sessionRepository,
            transcriptRepository: transcriptRepository,
            audioValidationService: audioValidationService,
            batchTranscriptionService: batchTranscriptionService,
            audioStorage: nil
        )
    }
    
    // MARK: - AI Use Cases
    
    /// Creates a use case for generating meeting notes.
    func makeGenerateNotesUseCase() -> any GenerateNotesUseCase {
        let transcriptRepository = serviceFactory.makeTranscriptRepository()
        let llmService = serviceFactory.makeLLMService(provider: .openRouter)
        // Note: NoteRepository not yet available in protocols, using nil
        
        return GenerateNotesUseCaseImpl(
            transcriptRepository: transcriptRepository,
            llmService: llmService ?? MockLLMService(),
            noteRepository: nil
        )
    }
    
    /// Creates a use case for switching transcription backends.
    func makeSwitchBackendUseCase() -> any SwitchBackendUseCase {
        let backendRegistry = MockBackendAvailabilityRegistry()
        let settingsRepository = serviceFactory.makeSettingsRepository()
        
        return SwitchBackendUseCaseImpl(
            backendRegistry: backendRegistry,
            transcriptionServiceFactory: serviceFactory,
            settingsRepository: settingsRepository,
            initialBackend: .mlxWhisper
        )
    }
}

// MARK: - Mock Implementations for DI

/// Mock file export service for DI container
@available(macOS 15.0, *)
private struct MockFileExportService: FileExportService {
    func export(content: String, to url: URL) async -> Result<Int, StorageError> {
        do {
            let data = content.data(using: .utf8) ?? Data()
            try data.write(to: url)
            return .success(data.count)
        } catch {
            return .failure(.writeFailed(path: url.path, underlying: error))
        }
    }
}

/// Mock audio validation service for DI container
@available(macOS 15.0, *)
private struct MockAudioValidationService: AudioValidationService {
    func validate(url: URL) async -> ImportAudioValidationServiceResult {
        // Mock validation - always valid for testing
        return ImportAudioValidationServiceResult(
            isValid: true,
            duration: .seconds(60),
            sampleRate: 16000,
            error: nil
        )
    }
}

/// Mock backend availability registry for DI container
@available(macOS 15.0, *)
private actor MockBackendAvailabilityRegistry: BackendAvailabilityRegistry {
    private var availabilityMap: [BackendID: BackendAvailabilityInfo] = [
        .mlxWhisper: BackendAvailabilityInfo(
            id: .mlxWhisper,
            isAvailable: true,
            models: ["mlx-whisper-base", "mlx-whisper-large"],
            latency: .milliseconds(100),
            isOnline: false
        ),
        .whisperKit: BackendAvailabilityInfo(
            id: .whisperKit,
            isAvailable: true,
            models: ["whisper-small", "whisper-large-v3"],
            latency: .milliseconds(150),
            isOnline: false
        ),
        .assemblyAI: BackendAvailabilityInfo(
            id: .assemblyAI,
            isAvailable: true,
            models: ["assembly-ai-default"],
            latency: .milliseconds(500),
            isOnline: true
        )
    ]
    
    func getAvailability(for backendID: BackendID) async -> BackendAvailabilityInfo {
        return availabilityMap[backendID] ?? BackendAvailabilityInfo(
            id: backendID,
            isAvailable: false,
            models: [],
            isOnline: false
        )
    }
    
    func setAvailability(_ availability: BackendAvailabilityInfo, for backendID: BackendID) async {
        availabilityMap[backendID] = availability
    }
    
    func listAvailableBackends() async -> [BackendAvailabilityInfo] {
        return Array(availabilityMap.values).filter { $0.isAvailable }
    }
}