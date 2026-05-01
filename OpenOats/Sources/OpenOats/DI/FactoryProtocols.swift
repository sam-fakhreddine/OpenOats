import Foundation

// MARK: - UseCase Factory

/// Factory for creating business logic use cases.
/// Provides a central point for dependency injection and use case creation.
protocol UseCaseFactory: Sendable {
    // MARK: - Session Use Cases
    
    /// Create a use case for starting a recording session.
    func makeStartSessionUseCase() -> any StartSessionUseCase
    
    /// Create a use case for stopping a recording session.
    func makeStopSessionUseCase() -> any StopSessionUseCase
    
    // MARK: - Transcription Use Cases
    
    /// Create a use case for exporting transcripts.
    func makeExportTranscriptUseCase() -> any ExportTranscriptUseCase
    
    /// Create a use case for importing audio files.
    func makeImportAudioUseCase() -> any ImportAudioUseCase
    
    // MARK: - AI Use Cases
    
    /// Create a use case for generating meeting notes.
    func makeGenerateNotesUseCase() -> any GenerateNotesUseCase
    
    /// Create a use case for switching transcription backends.
    func makeSwitchBackendUseCase() -> any SwitchBackendUseCase
}

// MARK: - ViewModel Factory

/// Factory for creating presentation view models.
/// Provides a central point for dependency injection and view model creation.
@MainActor
protocol ViewModelFactory: Sendable {
    // MARK: - Main View Models
    
    /// Create a view model for the recording session screen.
    func makeSessionViewModel() -> any SessionViewModel
    
    /// Create a view model for the transcript display screen.
    func makeTranscriptViewModel() -> any TranscriptViewModel
    
    /// Create a view model for the settings screen.
    func makeSettingsViewModel() -> any SettingsViewModel
    
    /// Create a view model for the idle dashboard (home screen).
    func makeIdleDashboardViewModel() -> any IdleDashboardViewModel
    
    /// Create a view model for backend configuration.
    func makeBackendConfigurationViewModel() -> any BackendConfigurationViewModel
}