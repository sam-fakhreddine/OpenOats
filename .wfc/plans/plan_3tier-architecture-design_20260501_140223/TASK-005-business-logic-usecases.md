# TASK-005: Design Business Logic Layer (Use Cases)

## Overview
Define use case protocols for core operations that orchestrate between presentation and infrastructure layers while maintaining business rule integrity.

## Design Output

```swift
// MARK: - Base Use Case Protocol

/// Base protocol for all use cases
protocol UseCaseProtocol: Sendable {
    /// Unique identifier for this use case type
    static var useCaseID: String { get }
    
    /// Description of what this use case does
    static var description: String { get }
}

/// Input type marker protocol
protocol UseCaseInput: Sendable {}

/// Output type marker protocol
protocol UseCaseOutput: Sendable {}

// MARK: - Session Use Cases

// MARK: Start Session Use Case

/// Input for starting a recording session
struct StartSessionInput: UseCaseInput {
    let name: String?
    let backend: BackendID
    let captureMicrophone: Bool
    let captureSystemAudio: Bool
    let enableTranscription: Bool
    let language: String
}

/// Output from starting a session
struct StartSessionOutput: UseCaseOutput {
    let sessionID: SessionID
    let session: Session
}

/// Use case for beginning a recording session
protocol StartSessionUseCase: UseCaseProtocol {
    func execute(input: StartSessionInput) async throws -> StartSessionOutput
}

// MARK: Stop Session Use Case

/// Input for stopping a session
struct StopSessionInput: UseCaseInput {
    let sessionID: SessionID
    let saveRecording: Bool
}

/// Output from stopping a session
struct StopSessionOutput: UseCaseOutput {
    let session: Session
    let transcript: Transcript?
    let recordingURL: URL?
}

/// Use case for ending a recording session
protocol StopSessionUseCase: UseCaseProtocol {
    func execute(input: StopSessionInput) async throws -> StopSessionOutput
}

// MARK: Pause/Resume Session Use Cases

struct PauseSessionInput: UseCaseInput {
    let sessionID: SessionID
}

struct ResumeSessionInput: UseCaseInput {
    let sessionID: SessionID
}

protocol PauseSessionUseCase: UseCaseProtocol {
    func execute(input: PauseSessionInput) async throws -> Session
}

protocol ResumeSessionUseCase: UseCaseProtocol {
    func execute(input: ResumeSessionInput) async throws -> Session
}

// MARK: - Transcription Use Cases

// MARK: Real-time Transcription Use Case

/// Real-time transcription input
struct StreamTranscriptionInput: UseCaseInput {
    let sessionID: SessionID
    let audioStream: AsyncThrowingStream<AudioSegment, Error>
    let backend: BackendID
}

/// Real-time transcription output (streaming)
struct StreamTranscriptionOutput: UseCaseOutput {
    let transcriptID: TranscriptID
    let segmentStream: AsyncStream<TranscriptionSegment>
}

/// Use case for streaming real-time transcription
protocol StreamTranscriptionUseCase: UseCaseProtocol {
    func execute(input: StreamTranscriptionInput) async throws -> StreamTranscriptionOutput
}

// MARK: Batch Transcription Use Case

/// Batch transcription input
struct BatchTranscriptionInput: UseCaseInput {
    let audioURL: URL
    let backend: BackendID
    let language: String
    let enableDiarization: Bool
}

/// Batch transcription output
struct BatchTranscriptionOutput: UseCaseOutput {
    let transcript: Transcript
    let processingTime: Duration
}

/// Use case for transcribing audio files
protocol BatchTranscriptionUseCase: UseCaseProtocol {
    func execute(input: BatchTranscriptionInput) async throws -> BatchTranscriptionOutput
}

// MARK: Cancel Transcription Use Case

struct CancelTranscriptionInput: UseCaseInput {
    let transcriptID: TranscriptID
}

protocol CancelTranscriptionUseCase: UseCaseProtocol {
    func execute(input: CancelTranscriptionInput) async throws
}

// MARK: - Note Generation Use Cases

// MARK: Generate Notes Use Case

/// Input for AI note generation
struct GenerateNotesInput: UseCaseInput {
    let transcriptID: TranscriptID
    let sections: [NoteSectionType]
    let style: NoteGenerationStyle
    let llmProvider: LLMProvider
    let customPrompt: String?
}

/// Output from note generation
struct GenerateNotesOutput: UseCaseOutput {
    let note: Note
    let generatedAt: Date
    let processingTime: Duration
    let tokenCount: Int
}

/// Use case for AI-powered note generation
protocol GenerateNotesUseCase: UseCaseProtocol {
    func execute(input: GenerateNotesInput) async throws -> GenerateNotesOutput
}

// MARK: Regenerate Note Section Use Case

struct RegenerateSectionInput: UseCaseInput {
    let transcriptID: TranscriptID
    let existingNoteID: NoteID?
    let section: NoteSectionType
    let style: NoteGenerationStyle
}

struct RegenerateSectionOutput: UseCaseOutput {
    let section: NoteSection
    let processingTime: Duration
}

protocol RegenerateSectionUseCase: UseCaseProtocol {
    func execute(input: RegenerateSectionInput) async throws -> RegenerateSectionOutput
}

// MARK: - Export Use Cases

// MARK: Export Transcript Use Case

/// Export input
struct ExportTranscriptInput: UseCaseInput {
    let transcriptID: TranscriptID
    let format: ExportFormat
    let destination: URL
    let includeSpeakers: Bool
    let includeTimestamps: Bool
}

/// Export output
struct ExportTranscriptOutput: UseCaseOutput {
    let exportedURL: URL
    let bytesWritten: Int
}

/// Use case for exporting transcripts
protocol ExportTranscriptUseCase: UseCaseProtocol {
    func execute(input: ExportTranscriptInput) async throws -> ExportTranscriptOutput
}

// MARK: Export Notes Use Case

struct ExportNotesInput: UseCaseInput {
    let noteID: NoteID
    let format: NoteExportFormat
    let destination: URL
}

struct ExportNotesOutput: UseCaseOutput {
    let exportedURL: URL
}

protocol ExportNotesUseCase: UseCaseProtocol {
    func execute(input: ExportNotesInput) async throws -> ExportNotesOutput
}

// MARK: - Audio Import Use Cases

// MARK: Import Audio Use Case

/// Import input
struct ImportAudioInput: UseCaseInput {
    let sourceURL: URL
    let targetSessionName: String?
    let autoTranscribe: Bool
    let backend: BackendID?
}

/// Import output
struct ImportAudioOutput: UseCaseOutput {
    let session: Session
    let transcript: Transcript?
    let importedAt: Date
}

/// Use case for importing external audio files
protocol ImportAudioUseCase: UseCaseProtocol {
    func execute(input: ImportAudioInput) async throws -> ImportAudioOutput
}

// MARK: Validate Audio File Use Case

struct ValidateAudioInput: UseCaseInput {
    let url: URL
}

struct ValidateAudioOutput: UseCaseOutput {
    let isValid: Bool
    let format: AudioFormat?
    let duration: Duration?
    let sampleRate: Int?
    let error: AudioError?
}

protocol ValidateAudioUseCase: UseCaseProtocol {
    func execute(input: ValidateAudioInput) async -> ValidateAudioOutput
}

// MARK: - Backend Use Cases

// MARK: Switch Backend Use Case

/// Backend switch input
struct SwitchBackendInput: UseCaseInput {
    let currentBackend: BackendID
    let newBackend: BackendID
    let preserveState: Bool
}

/// Backend switch output
struct SwitchBackendOutput: UseCaseOutput {
    let previousBackend: BackendID
    let currentBackend: BackendID
    let availableModels: [String]
    let isOnline: Bool
}

/// Use case for changing transcription backend
protocol SwitchBackendUseCase: UseCaseProtocol {
    func execute(input: SwitchBackendInput) async throws -> SwitchBackendOutput
}

// MARK: List Backends Use Case

struct ListBackendsInput: UseCaseInput {}

struct ListBackendsOutput: UseCaseOutput {
    let backends: [BackendInfo]
}

struct BackendInfo: Sendable {
    let id: BackendID
    let name: String
    let isAvailable: Bool
    let isLocal: Bool
    let latency: Duration?
    let supportedLanguages: [String]
}

protocol ListBackendsUseCase: UseCaseProtocol {
    func execute(input: ListBackendsInput) async -> ListBackendsOutput
}

// MARK: - Settings Use Cases

// MARK: Load Settings Use Case

struct LoadSettingsInput: UseCaseInput {}

struct LoadSettingsOutput: UseCaseOutput {
    let settings: UserSettings
}

protocol LoadSettingsUseCase: UseCaseProtocol {
    func execute(input: LoadSettingsInput) async throws -> LoadSettingsOutput
}

// MARK: Save Settings Use Case

struct SaveSettingsInput: UseCaseInput {
    let settings: UserSettings
}

struct SaveSettingsOutput: UseCaseOutput {}

protocol SaveSettingsUseCase: UseCaseProtocol {
    func execute(input: SaveSettingsInput) async throws -> SaveSettingsOutput
}

// MARK: - Search Use Cases

// MARK: Search Transcripts Use Case

/// Search input
struct SearchTranscriptsInput: UseCaseInput {
    let query: String
    let dateRange: ClosedRange<Date>?
    let speakerFilter: SpeakerID?
    let limit: Int
}

/// Search result
struct TranscriptSearchResult: Sendable {
    let transcriptID: TranscriptID
    let sessionName: String
    let matchedUtterances: [Utterance]
    let relevanceScore: Double
}

/// Search output
struct SearchTranscriptsOutput: UseCaseOutput {
    let results: [TranscriptSearchResult]
    let totalMatches: Int
    let queryTime: Duration
}

/// Use case for searching transcripts
protocol SearchTranscriptsUseCase: UseCaseProtocol {
    func execute(input: SearchTranscriptsInput) async throws -> SearchTranscriptsOutput
}

// MARK: - Session Management Use Cases

// MARK: List Sessions Use Case

struct ListSessionsInput: UseCaseInput {
    let dateRange: ClosedRange<Date>?
    let status: SessionStatusFilter?
    let limit: Int?
}

enum SessionStatusFilter: Sendable {
    case all
    case completed
    case inProgress
    case failed
}

struct ListSessionsOutput: UseCaseOutput {
    let sessions: [SessionSummary]
    let totalCount: Int
}

struct SessionSummary: Sendable {
    let id: SessionID
    let name: String
    let createdAt: Date
    let duration: Duration?
    let status: SessionStatus
    let hasTranscript: Bool
    let hasNotes: Bool
}

protocol ListSessionsUseCase: UseCaseProtocol {
    func execute(input: ListSessionsInput) async throws -> ListSessionsOutput
}

// MARK: Delete Session Use Case

struct DeleteSessionInput: UseCaseInput {
    let sessionID: SessionID
    let deleteAudio: Bool
    let deleteTranscript: Bool
}

struct DeleteSessionOutput: UseCaseOutput {
    let deletedSessionID: SessionID
    let deletedTranscriptID: TranscriptID?
    let deletedNoteID: NoteID?
}

protocol DeleteSessionUseCase: UseCaseProtocol {
    func execute(input: DeleteSessionInput) async throws -> DeleteSessionOutput
}

// MARK: - Use Case Orchestrator (Complex Operations)

/// Orchestrates multiple use cases for complex flows
protocol UseCaseOrchestrator: Sendable {
    /// Executes a list of use cases in sequence
    /// - Parameters:
    ///   - useCases: Array of use case executions to perform
    ///   - continueOnError: Whether to continue if one use case fails
    /// - Returns: Array of results (success or failure for each)
    func executeSequence<U: UseCaseProtocol, I: UseCaseInput, O: UseCaseOutput>(
        _ useCases: [(U, I)],
        continueOnError: Bool
    ) async -> [Result<O, Error>]
    
    /// Executes use cases in parallel
    /// - Parameter useCases: Array of use case executions
    /// - Returns: Array of results when all complete
    func executeParallel<U: UseCaseProtocol, I: UseCaseInput, O: UseCaseOutput>(
        _ useCases: [(U, I)]
    ) async -> [Result<O, Error>]
}

// MARK: - Transaction Support

/// Marks a use case as requiring transactional consistency
protocol TransactionalUseCase: UseCaseProtocol {
    /// Whether this use case supports rollback
    var supportsRollback: Bool { get }
    
    /// Rollback the operation if possible
    /// - Parameter context: Context needed for rollback
    func rollback(context: RollbackContext) async throws
}

/// Context for rollback operations
struct RollbackContext: Sendable {
    let operationID: UUID
    let originalState: Data?
    let affectedIDs: [String]
    let timestamp: Date
}

// MARK: - Cancellable Use Cases

/// Use cases that support cancellation during execution
protocol CancellableUseCase: UseCaseProtocol {
    /// Unique ID for this execution
    var executionID: UUID { get }
    
    /// Cancel the current execution
    func cancel() async
    
    /// Whether the use case is currently executing
    var isExecuting: Bool { get }
}

/// Progress-reporting use case
protocol ProgressReportingUseCase: UseCaseProtocol {
    /// Progress stream (0.0 - 1.0)
    var progressStream: AsyncStream<Double> { get }
}

// MARK: - Use Case Factories

/// Factory for creating use case instances with dependencies
protocol UseCaseFactory: Sendable {
    func makeStartSessionUseCase() -> any StartSessionUseCase
    func makeStopSessionUseCase() -> any StopSessionUseCase
    func makeStreamTranscriptionUseCase() -> any StreamTranscriptionUseCase
    func makeBatchTranscriptionUseCase() -> any BatchTranscriptionUseCase
    func makeGenerateNotesUseCase() -> any GenerateNotesUseCase
    func makeExportTranscriptUseCase() -> any ExportTranscriptUseCase
    func makeImportAudioUseCase() -> any ImportAudioUseCase
    func makeSwitchBackendUseCase() -> any SwitchBackendUseCase
    func makeSearchTranscriptsUseCase() -> any SearchTranscriptsUseCase
    func makeListSessionsUseCase() -> any ListSessionsUseCase
    func makeDeleteSessionUseCase() -> any DeleteSessionUseCase
    func makeLoadSettingsUseCase() -> any LoadSettingsUseCase
    func makeSaveSettingsUseCase() -> any SaveSettingsUseCase
}
```

## Design Decisions

### Single Responsibility
Each use case has exactly one responsibility:
- `StartSessionUseCase` only starts sessions
- `ExportTranscriptUseCase` only exports transcripts
- No "god" use cases that do multiple unrelated things

### Input/Output Pattern
All use cases use explicit input/output structs:
- Clear contract for what data is needed
- Type-safe boundaries
- Easy to test with mock inputs

### Async-First Design
All use cases use async/await:
- Natural fit for I/O operations
- Structured concurrency support
- Cancellation support via `CancellableUseCase`

### Protocol Composition
Use cases can compose capabilities:
- `TransactionalUseCase` for rollback support
- `CancellableUseCase` for cancellation
- `ProgressReportingUseCase` for UI feedback

### Dependency Direction
```
Use Case → Domain (entities, errors)
         → Infrastructure Protocols (service boundaries only)
         ↓
    Never depends on concrete implementations
```

## Formal Properties Verification

- **SAFETY**: Use cases maintain transactional consistency (via `TransactionalUseCase`)
- **LIVENESS**: Long-running operations are cancellable (via `CancellableUseCase`)
- **INVARIANT**: All input/output types are `Sendable` for Swift 6.2

## Relationship to Infrastructure

Use cases depend on infrastructure **protocols** (not implementations):
- `StartSessionUseCase` needs `AudioCaptureService`, `SessionRepository`
- `GenerateNotesUseCase` needs `LLMService`, `TranscriptRepository`
- All dependencies injected via initializer

