import Foundation
import SwiftUI

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

/// Note export formats
enum NoteExportFormat: String, Sendable, CaseIterable {
    case plainText = "txt"
    case markdown = "md"
    case pdf = "pdf"
    case html = "html"
}

// MARK: - Session State

/// States for a recording session
enum SessionState: Sendable, Equatable {
    case idle
    case preparing
    case recording(startTime: Date)
    case paused(duration: Duration, startTime: Date)
    case finalizing
    case error(TranscriptionError)
}

// MARK: - Speaker Color

/// Color coding for speakers
enum SpeakerColor: Sendable, CaseIterable {
    case blue, green, orange, purple, pink, teal
}

// MARK: - View Model Protocols

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

// MARK: - Transcript View Model

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
    
    init(
        id: UtteranceID,
        speakerName: String,
        speakerColor: SpeakerColor,
        text: String,
        startTime: Duration,
        endTime: Duration,
        confidence: Double,
        isHighlighted: Bool = false
    ) {
        self.id = id
        self.speakerName = speakerName
        self.speakerColor = speakerColor
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isHighlighted = isHighlighted
    }
}

/// View model for a speaker in the UI
@MainActor
struct SpeakerViewModel: Sendable, Identifiable, Equatable {
    let id: SpeakerID
    let name: String
    let color: SpeakerColor
    let utteranceCount: Int
    
    init(
        id: SpeakerID,
        name: String,
        color: SpeakerColor,
        utteranceCount: Int
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.utteranceCount = utteranceCount
    }
}

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
    
    /// Current search result index
    var currentSearchIndex: Int? { get }
    
    /// Total search results count
    var searchResultCount: Int { get }
    
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

// MARK: - Settings View Model

/// Note generation styles
public enum NoteGenerationStyle: String, Sendable, CaseIterable, Codable {
    case concise = "concise"
    case detailed = "detailed"
    case bulletPoints = "bullets"
    case narrative = "narrative"
    case actionItems = "actions"
}

/// Audio recording formats
enum AudioRecordingFormat: String, Sendable, CaseIterable, Codable {
    case wav = "wav"
    case aac = "aac"
    case flac = "flac"
}

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
    
    /// LLM provider for note generation (uses existing LLMProvider type)
    var llmProvider: LLMProvider { get set }
    
    /// OpenRouter API key (securely stored)
    var openRouterAPIKey: String? { get set }
    
    /// Ollama endpoint URL
    var ollamaEndpoint: URL? { get set }
    
    /// Note generation style
    var noteStyle: NoteGenerationStyle { get set }
    
    // MARK: - UI State
    
    /// Whether settings have unsaved changes
    var hasUnsavedChanges: Bool { get }
    
    /// Whether the API key is valid
    var isAPIKeyValid: Bool { get }
    
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
    
    /// Marks settings as changed (triggers hasUnsavedChanges)
    func markAsChanged()
}

// MARK: - Idle Dashboard View Model

/// Calendar access states
enum CalendarAccessState: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case disabled
}

/// View model for idle dashboard (when no recording is active)
@MainActor
protocol IdleDashboardViewModel: ViewModelProtocol {
    // MARK: - Calendar State
    
    /// Current calendar access state
    var calendarAccessState: CalendarAccessState { get }
    
    /// Whether calendar integration is enabled in settings
    var isCalendarIntegrationEnabled: Bool { get set }
    
    /// Upcoming calendar events (uses existing CalendarEvent type)
    var upcomingEvents: [CalendarEvent] { get }
    
    /// Events from earlier today
    var earlierTodayEvents: [CalendarEvent] { get }
    
    /// Whether to show earlier today events
    var showsEarlierToday: Bool { get set }
    
    // MARK: - Session History State
    
    /// Session history for showing meeting readiness (uses existing SessionIndex type)
    var sessionHistory: [SessionIndex] { get }
    
    /// Recent sessions for quick access
    var recentSessions: [SessionIndex] { get }
    
    // MARK: - Quick Actions State
    
    /// Whether quick start is available
    var canQuickStart: Bool { get }
    
    /// Last used backend for quick start
    var lastUsedBackend: BackendID? { get }
    
    // MARK: - UI State
    
    /// Whether the create folder sheet is shown
    var isCreateFolderSheetPresented: Bool { get set }
    
    /// The event for which a folder is being created
    var folderCreationEvent: CalendarEvent? { get set }
    
    /// New folder path being entered
    var newFolderPath: String { get set }
    
    /// New folder color selection (uses existing NotesFolderColor type)
    var newFolderColor: NotesFolderColor { get set }
    
    // MARK: - Actions
    
    /// Refreshes calendar events and session history
    func refresh() async
    
    /// Starts recording for a specific event
    /// - Parameter event: The calendar event to record
    /// - Returns: The created session ID
    func startRecording(for event: CalendarEvent) async throws -> SessionID
    
    /// Starts a quick recording without an event
    /// - Returns: The created session ID
    func startQuickRecording() async throws -> SessionID
    
    /// Opens related notes for an event
    /// - Parameter event: The event to open notes for
    func openRelatedNotes(for event: CalendarEvent)
    
    /// Joins a meeting URL
    /// - Parameter event: The event with meeting URL
    func joinMeeting(for event: CalendarEvent)
    
    /// Requests calendar access permission
    func requestCalendarAccess() async
    
    /// Creates a new folder for meeting family
    /// - Parameters:
    ///   - path: The folder path
    ///   - color: The folder color
    ///   - event: The associated event
    func createFolder(path: String, color: NotesFolderColor, for event: CalendarEvent) async throws
    
    /// Changes the folder for a meeting family
    /// - Parameters:
    ///   - folderPath: The new folder path (nil for default)
    ///   - event: The event to change folder for
    ///   - moveExisting: Whether to move existing sessions
    func changeMeetingFolder(to folderPath: String?, for event: CalendarEvent, moveExisting: Bool) async throws
}

// MARK: - Backend Configuration

/// Backend capabilities
struct BackendCapabilities: OptionSet, Sendable {
    let rawValue: Int
    
    init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    static let streaming = BackendCapabilities(rawValue: 1 << 0)
    static let batch = BackendCapabilities(rawValue: 1 << 2)
    static let speakerDiarization = BackendCapabilities(rawValue: 1 << 3)
    static let realTimeProcessing = BackendCapabilities(rawValue: 1 << 4)
}

/// Backend configuration data
@MainActor
struct BackendConfiguration: Sendable, Identifiable, Equatable {
    let id: BackendID
    let name: String
    let description: String
    let isLocal: Bool
    let requiresAPIKey: Bool
    let supportedLanguages: [String]
    let capabilities: BackendCapabilities
    
    init(
        id: BackendID,
        name: String,
        description: String,
        isLocal: Bool,
        requiresAPIKey: Bool,
        supportedLanguages: [String],
        capabilities: BackendCapabilities
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isLocal = isLocal
        self.requiresAPIKey = requiresAPIKey
        self.supportedLanguages = supportedLanguages
        self.capabilities = capabilities
    }
}

/// Connection test result
enum ConnectionTestResult: Sendable {
    case success(latency: Duration)
    case failure(reason: String)
    case unknown
}

/// View model for backend configuration
@MainActor
protocol BackendConfigurationViewModel: ViewModelProtocol {
    /// Available backends
    var backends: [BackendConfiguration] { get }
    
    /// Currently selected backend
    var selectedBackend: BackendID { get set }
    
    /// Tests a backend connection
    /// - Parameter backend: Backend to test
    /// - Returns: Connection test result
    func testConnection(to backend: BackendID) async -> ConnectionTestResult
}
