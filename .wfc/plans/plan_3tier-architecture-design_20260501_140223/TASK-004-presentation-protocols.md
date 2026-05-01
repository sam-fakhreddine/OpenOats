# TASK-004: Design Presentation Layer Protocols

## Overview
Define protocols for SwiftUI views to interact with business logic through clean, protocol-based boundaries.

## Design Output

### ViewModel Protocols

```swift
// MARK: - Base ViewModel Protocol

/// Base protocol for all view models in the presentation layer
@MainActor
protocol ViewModelProtocol: ObservableObject, Sendable {
    /// Unique identifier for this view model instance
    var id: UUID { get }
    
    /// Current loading state
    var isLoading: Bool { get }
    
    /// Current error state (nil if no error)
    var error: PresentationError? { get }
    
    /// Clears the current error
    func clearError()
}

// MARK: - Session View Model

/// View model for session recording and management
@MainActor
protocol SessionViewModel: ViewModelProtocol {
    // MARK: - Published State
    
    /// Current session state
    var sessionState: SessionState { get }
    
    /// Recording status
    var isRecording: Bool { get }
    
    /// Current recording duration
    var recordingDuration: Duration { get }
    
    /// Audio level for UI visualization (0.0 - 1.0)
    var audioLevel: Double { get }
    
    /// Selected transcription backend
    var selectedBackend: BackendID { get set }
    
    /// Available transcription backends
    var availableBackends: [BackendConfiguration] { get }
    
    // MARK: - Actions
    
    /// Starts a new recording session
    /// - Returns: The ID of the created session
    /// - Throws: PresentationError if session cannot be started
    func startRecording() async throws -> SessionID
    
    /// Stops the current recording session
    /// - Returns: The finalized session
    /// - Throws: PresentationError if stop fails
    func stopRecording() async throws -> Session
    
    /// Pauses the current recording (keeps session alive)
    func pauseRecording() async throws
    
    /// Resumes a paused recording
    func resumeRecording() async throws
    
    /// Switches to a different transcription backend
    /// - Parameter backend: The backend to switch to
    /// - Throws: PresentationError if switch fails
    func switchBackend(to backend: BackendID) async throws
    
    /// Cancels the current session without saving
    func cancelSession() async
}

/// States for a recording session
enum SessionState: Sendable, Equatable {
    case idle
    case preparing
    case recording(startTime: Date)
    case paused(duration: Duration, startTime: Date)
    case finalizing
    case error(TranscriptionError)
}

// MARK: - Transcript View Model

/// View model for transcript display and interaction
@MainActor
protocol TranscriptViewModel: ViewModelProtocol {
    // MARK: - Published State
    
    /// Current transcript being displayed
    var transcript: Transcript? { get }
    
    /// All utterances for the current transcript
    var utterances: [UtteranceViewModel] { get }
    
    /// Whether transcription is in progress
    var isTranscribing: Bool { get }
    
    /// Search query for filtering utterances
    var searchQuery: String { get set }
    
    /// Filtered utterances based on search
    var filteredUtterances: [UtteranceViewModel] { get }
    
    /// Selected speaker for filtering (nil = all speakers)
    var selectedSpeaker: SpeakerID? { get set }
    
    /// All speakers in the transcript
    var speakers: [SpeakerViewModel] { get }
    
    // MARK: - Actions
    
    /// Loads a transcript by ID
    /// - Parameter id: The transcript ID to load
    func loadTranscript(id: TranscriptID) async throws
    
    /// Searches for text in the transcript
    /// - Parameter query: Search string
    func search(_ query: String)
    
    /// Navigates to the next search result
    func nextSearchResult()
    
    /// Navigates to the previous search result
    func previousSearchResult()
    
    /// Exports the transcript to a file
    /// - Parameters:
    ///   - format: Export format (txt, srt, vtt, json)
    ///   - url: Destination URL
    func export(to format: ExportFormat, at url: URL) async throws
    
    /// Edits an utterance text
    /// - Parameters:
    ///   - utteranceId: The utterance to edit
    ///   - newText: Updated text
    func editUtterance(_ utteranceId: UtteranceID, newText: String) async throws
    
    /// Jumps to a specific timestamp
    /// - Parameter timestamp: Target time in the transcript
    func jumpTo(_ timestamp: Duration)
}

/// View model for an utterance in the UI
@MainActor
struct UtteranceViewModel: Sendable, Identifiable, Equatable {
    let id: UtteranceID
    let speakerName: String
    let speakerColor: SpeakerColor
    let text: String
    let startTime: Duration
    let endTime: Duration
    let confidence: Double
    let isHighlighted: Bool
}

/// Color coding for speakers
enum SpeakerColor: Sendable, CaseIterable {
    case blue, green, orange, purple, pink, teal
}

// MARK: - Settings View Model

/// View model for application settings
@MainActor
protocol SettingsViewModel: ViewModelProtocol {
    // MARK: - General Settings
    
    /// Default transcription backend
    var defaultBackend: BackendID { get set }
    
    /// Default language code (e.g., "en", "es")
    var defaultLanguage: String { get set }
    
    /// Auto-export enabled
    var autoExportEnabled: Bool { get set }
    
    /// Auto-export format
    var autoExportFormat: ExportFormat { get set }
    
    /// Auto-export location
    var autoExportLocation: URL? { get set }
    
    // MARK: - Audio Settings
    
    /// Sample rate for recording
    var sampleRate: Int { get set }
    
    /// System audio capture enabled
    var captureSystemAudio: Bool { get set }
    
    /// Microphone capture enabled
    var captureMicrophone: Bool { get set }
    
    /// Audio format (wav, aac, flac)
    var audioFormat: AudioRecordingFormat { get set }
    
    // MARK: - AI Settings
    
    /// LLM provider for note generation
    var llmProvider: LLMProvider { get set }
    
    /// OpenRouter API key (securely stored)
    var openRouterAPIKey: String? { get set }
    
    /// Ollama endpoint URL
    var ollamaEndpoint: URL? { get set }
    
    /// Note generation style
    var noteStyle: NoteGenerationStyle { get set }
    
    // MARK: - Actions
    
    /// Saves all settings to persistent storage
    func saveSettings() async throws
    
    /// Resets settings to defaults
    func resetToDefaults() async throws
    
    /// Validates an API key
    /// - Parameter key: The API key to validate
    /// - Returns: Whether the key is valid
    func validateAPIKey(_ key: String) async -> Bool
    
    /// Exports settings to a file
    /// - Parameter url: Destination URL
    func exportSettings(to url: URL) async throws
    
    /// Imports settings from a file
    /// - Parameter url: Source URL
    func importSettings(from url: URL) async throws
}

/// LLM provider options
enum LLMProvider: String, Sendable, CaseIterable, Codable {
    case openRouter = "openrouter"
    case ollama = "ollama"
    case localMLX = "mlx"
}

/// Note generation styles
enum NoteGenerationStyle: String, Sendable, CaseIterable, Codable {
    case concise = "concise"
    case detailed = "detailed"
    case bulletPoints = "bullets"
    case narrative = "narrative"
    case actionItems = "actions"
}

// MARK: - Coordinator Protocols

/// Protocol for navigation and flow coordination
@MainActor
protocol CoordinatorProtocol: Sendable {
    /// Unique identifier for this coordinator
    var id: UUID { get }
    
    /// Parent coordinator (nil if root)
    var parentCoordinator: (any CoordinatorProtocol)? { get }
    
    /// Child coordinators
    var childCoordinators: [any CoordinatorProtocol] { get }
    
    /// Starts the coordinator's flow
    func start()
    
    /// Finishes the coordinator's flow
    /// - Parameter completion: Callback when finish is complete
    func finish(completion: (() -> Void)?)
    
    /// Adds a child coordinator
    /// - Parameter coordinator: Child to add
    func addChild(_ coordinator: any CoordinatorProtocol)
    
    /// Removes a child coordinator
    /// - Parameter coordinator: Child to remove
    func removeChild(_ coordinator: any CoordinatorProtocol)
}

/// Main app coordinator
@MainActor
protocol AppCoordinator: CoordinatorProtocol {
    /// Shows the main recording interface
    func showRecordingInterface()
    
    /// Shows transcript detail for a session
    /// - Parameter sessionId: The session to display
    func showTranscript(for sessionId: SessionID)
    
    /// Shows the settings screen
    func showSettings()
    
    /// Shows the backend selection screen
    func showBackendSelection()
    
    /// Shows export options for a session
    /// - Parameter sessionId: The session to export
    func showExportOptions(for sessionId: SessionID)
}

// MARK: - Notes View Model

/// View model for AI-generated notes
@MainActor
protocol NotesViewModel: ViewModelProtocol {
    // MARK: - Published State
    
    /// Current notes (nil if not generated yet)
    var notes: Note? { get }
    
    /// Whether note generation is in progress
    var isGeneratingNotes: Bool { get }
    
    /// Progress of note generation (0.0 - 1.0)
    var generationProgress: Double { get }
    
    /// Available note sections
    var availableSections: [NoteSectionType] { get }
    
    /// Selected sections for generation
    var selectedSections: Set<NoteSectionType> { get set }
    
    // MARK: - Actions
    
    /// Generates notes for a transcript
    /// - Parameter transcriptId: The transcript to summarize
    func generateNotes(for transcriptId: TranscriptID) async throws
    
    /// Regenerates specific sections
    /// - Parameter sections: Sections to regenerate
    func regenerateSections(_ sections: [NoteSectionType]) async throws
    
    /// Copies notes to clipboard
    func copyToClipboard()
    
    /// Exports notes to a file
    /// - Parameters:
    ///   - format: Export format
    ///   - url: Destination URL
    func exportNotes(to format: NoteExportFormat, at url: URL) async throws
    
    /// Updates the note generation style
    /// - Parameter style: New style to use
    func updateStyle(_ style: NoteGenerationStyle) async throws
}

/// Types of note sections
enum NoteSectionType: String, Sendable, CaseIterable {
    case summary = "summary"
    case keyPoints = "key_points"
    case actionItems = "action_items"
    case decisions = "decisions"
    case questions = "questions"
    case timestamps = "timestamps"
}

// MARK: - Presentation Error

/// Error type for presentation layer
enum PresentationError: Error, LocalizedError, Sendable {
    case sessionStartFailed(reason: String)
    case sessionStopFailed(reason: String)
    case transcriptLoadFailed(id: TranscriptID, reason: String)
    case exportFailed(format: ExportFormat, reason: String)
    case backendSwitchFailed(from: BackendID, to: BackendID, reason: String)
    case validationFailed(field: String, reason: String)
    case networkUnavailable
    case unknown(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .sessionStartFailed(let reason):
            return "Failed to start recording: \(reason)"
        case .sessionStopFailed(let reason):
            return "Failed to stop recording: \(reason)"
        case .transcriptLoadFailed(let id, let reason):
            return "Failed to load transcript \(id): \(reason)"
        case .exportFailed(let format, let reason):
            return "Failed to export as \(format): \(reason)"
        case .backendSwitchFailed(let from, let to, let reason):
            return "Failed to switch from \(from) to \(to): \(reason)"
        case .validationFailed(let field, let reason):
            return "Validation failed for \(field): \(reason)"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .unknown(let underlying):
            return "Unknown error: \(underlying.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .sessionStartFailed:
            return "Check microphone permissions and try again."
        case .sessionStopFailed:
            return "Wait a moment and try again."
        case .transcriptLoadFailed:
            return "The transcript may have been deleted."
        case .exportFailed:
            return "Check that the destination folder exists and you have write permission."
        case .backendSwitchFailed:
            return "The selected backend may be unavailable. Try a different one."
        case .validationFailed:
            return "Please correct the indicated field and try again."
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .unknown:
            return "If this persists, please contact support."
        }
    }
}

// MARK: - Export Formats

/// Supported export formats
enum ExportFormat: String, Sendable, CaseIterable, Codable {
    case plainText = "txt"
    case subtitles = "srt"
    case webVTT = "vtt"
    case json = "json"
    case markdown = "md"
    case pdf = "pdf"
    
    var displayName: String {
        switch self {
        case .plainText: return "Plain Text"
        case .subtitles: return "SubRip Subtitles"
        case .webVTT: return "WebVTT"
        case .json: return "JSON"
        case .markdown: return "Markdown"
        case .pdf: return "PDF"
        }
    }
    
    var fileExtension: String {
        rawValue
    }
}

enum NoteExportFormat: String, Sendable, CaseIterable {
    case plainText = "txt"
    case markdown = "md"
    case pdf = "pdf"
    case html = "html"
}

// MARK: - Backend Configuration View Model

/// View model for backend configuration
@MainActor
protocol BackendConfigurationViewModel: ViewModelProtocol {
    /// Available backends
    var backends: [BackendConfiguration] { get }
    
    /// Currently selected backend
    var selectedBackend: BackendID { get set }
    
    /// Backend-specific configuration views
    func configurationView(for backend: BackendID) -> AnyView
    
    /// Tests a backend connection
    /// - Parameter backend: Backend to test
    /// - Returns: Connection test result
    func testConnection(to backend: BackendID) async -> ConnectionTestResult
}

/// Backend configuration data
struct BackendConfiguration: Sendable, Identifiable, Equatable {
    let id: BackendID
    let name: String
    let description: String
    let isLocal: Bool
    let requiresAPIKey: Bool
    let supportedLanguages: [String]
    let capabilities: BackendCapabilities
}

struct BackendCapabilities: OptionSet, Sendable {
    let rawValue: Int
    static let streaming = BackendCapabilities(rawValue: 1 << 0)
    static let batch = BackendCapabilities(rawValue: 1 << 2)
    static let speakerDiarization = BackendCapabilities(rawValue: 1 << 3)
    static let realTimeProcessing = BackendCapabilities(rawValue: 1 << 4)
}

/// Connection test result
enum ConnectionTestResult: Sendable {
    case success(latency: Duration)
    case failure(reason: String)
    case unknown
}
```

## Summary

### Design Decisions

1. **@MainActor for all ViewModels**: All view models are annotated with `@MainActor` to ensure UI updates happen on the main thread, preventing data races in SwiftUI.

2. **ObservableObject Protocol**: View models conform to `ObservableObject` for SwiftUI observation patterns, with `@Published` properties driving UI updates.

3. **Separate State Enums**: Complex state is modeled using enums (SessionState, PresentationError) rather than booleans for clarity and exhaustiveness.

4. **ViewModel Pattern for Complex Entities**: Entities like Utterance have corresponding ViewModels (UtteranceViewModel) that add presentation-specific properties (colors, formatting) without polluting domain types.

5. **Coordinator Pattern**: Navigation is handled via coordinator protocols that manage view flow, keeping views focused on display logic only.

6. **Error Localization**: PresentationError conforms to LocalizedError with user-friendly descriptions and recovery suggestions.

### Safety Properties

- **SAFETY**: ViewModels never perform direct I/O - all operations go through use cases
- **LIVENESS**: UI updates delivered on MainActor via @MainActor annotation
- **INVARIANT**: All published properties are Sendable-safe for Swift 6.2

### Protocol Boundaries

```
SwiftUI View → ViewModel (protocol) → UseCase (protocol) → Service (protocol)
     ↑              ↑                      ↑                    ↑
  @MainActor    @MainActor            Any Actor          Sendable
```

