# TASK-008: Migration Strategy from Big Ball of Mud

## 9-Week Phased Migration Plan

This document provides a detailed, step-by-step migration strategy to transform the OpenOats macOS transcription system from its current "Big Ball of Mud" architecture (36K lines, massive files) to a clean 3-tier architecture with protocol-based dependency injection.

---

## Executive Summary

| Metric | Current State | Target State |
|--------|--------------|--------------|
| Total Lines | 36,000 | ~45,000 (with tests) |
| Largest File | NotesView 3,700 lines | Max 300 lines per file |
| Largest Class | SessionRepository 2,100 lines | Max 15 methods per class |
| Cyclomatic Complexity | CCN 34 (writeMicBuffer) | Max CCN 15 per function |
| Data Races | 2 critical (C1, C2) | Zero @unchecked Sendable |
| Migration Duration | N/A | 9 weeks |

---

## Migration Phases Overview

```
Week 1-2: Extract Domain Layer
    |
Week 3-4: Extract Infrastructure Layer  
    |
Week 5-6: Extract Business Logic Layer
    |
Week 7-8: Refactor Presentation Layer
    |
Week 9: Clean Up & Final Verification
```

---

## Phase 1: Extract Domain Layer (Weeks 1-2)

### Goal
Create immutable, Sendable-safe domain types alongside existing models without breaking existing functionality.

### Week 1: Create Domain Types

**Days 1-2: Core Domain Entities**

Create `OpenOats/Sources/Domain/Entities/`:

```swift
// OpenOats/Sources/Domain/Entities/Meeting.swift
public struct Meeting: Sendable, Equatable, Hashable, Codable {
    public let id: MeetingID
    public let title: String
    public let createdAt: Date
    public let sessions: [SessionID]
    public let status: MeetingStatus
    
    public init(id: MeetingID, title: String, createdAt: Date, sessions: [SessionID], status: MeetingStatus) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.sessions = sessions
        self.status = status
    }
}

public enum MeetingStatus: String, Sendable, Codable {
    case scheduled, inProgress, completed, archived
}
```

```swift
// OpenOats/Sources/Domain/Entities/Session.swift
public struct Session: Sendable, Equatable, Hashable, Codable {
    public let id: SessionID
    public let meetingID: MeetingID
    public let startedAt: Date
    public let endedAt: Date?
    public let status: SessionStatus
    public let recordingURL: URL?
    
    public init(id: SessionID, meetingID: MeetingID, startedAt: Date, 
                endedAt: Date? = nil, status: SessionStatus, recordingURL: URL? = nil) {
        self.id = id
        self.meetingID = meetingID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.recordingURL = recordingURL
    }
}

public enum SessionStatus: String, Sendable, Codable {
    case preparing, recording, paused, transcribing, completed, error
}
```

```swift
// OpenOats/Sources/Domain/Entities/Transcript.swift
public struct Transcript: Sendable, Equatable, Hashable, Codable {
    public let id: TranscriptID
    public let sessionID: SessionID
    public let utterances: [Utterance]
    public let generatedAt: Date
    public let backend: BackendID
    
    public init(id: TranscriptID, sessionID: SessionID, utterances: [Utterance], 
                generatedAt: Date, backend: BackendID) {
        self.id = id
        self.sessionID = sessionID
        self.utterances = utterances
        self.generatedAt = generatedAt
        self.backend = backend
    }
    
    public var fullText: String {
        utterances.map(\.text).joined(separator: " ")
    }
}
```

```swift
// OpenOats/Sources/Domain/Entities/Utterance.swift
public struct Utterance: Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public let speakerID: SpeakerID
    public let text: String
    public let startTime: Duration
    public let endTime: Duration
    public let confidence: Double
    
    public init(id: UUID = UUID(), speakerID: SpeakerID, text: String, 
                startTime: Duration, endTime: Duration, confidence: Double) {
        self.id = id
        self.speakerID = speakerID
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}
```

```swift
// OpenOats/Sources/Domain/Entities/Speaker.swift
public struct Speaker: Sendable, Equatable, Hashable, Codable {
    public let id: SpeakerID
    public let name: String?
    public let voiceSignature: VoiceSignature?
    public let appearanceCount: Int
    
    public init(id: SpeakerID, name: String? = nil, 
                voiceSignature: VoiceSignature? = nil, appearanceCount: Int = 1) {
        self.id = id
        self.name = name
        self.voiceSignature = voiceSignature
        self.appearanceCount = appearanceCount
    }
}

public struct VoiceSignature: Sendable, Equatable, Hashable, Codable {
    public let embedding: [Float]
    public let sampleCount: Int
    
    public init(embedding: [Float], sampleCount: Int) {
        self.embedding = embedding
        self.sampleCount = sampleCount
    }
}
```

```swift
// OpenOats/Sources/Domain/Entities/Note.swift
public struct Note: Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public let meetingID: MeetingID
    public let content: String
    public let type: NoteType
    public let generatedAt: Date
    public let aiModel: String
    
    public init(id: UUID = UUID(), meetingID: MeetingID, content: String, 
                type: NoteType, generatedAt: Date, aiModel: String) {
        self.id = id
        self.meetingID = meetingID
        self.content = content
        self.type = type
        self.generatedAt = generatedAt
        self.aiModel = aiModel
    }
}

public enum NoteType: String, Sendable, Codable {
    case summary, actionItems, keyDecisions, fullNotes, custom
}
```

```swift
// OpenOats/Sources/Domain/Entities/AudioSegment.swift
public struct AudioSegment: Sendable, Equatable, Hashable {
    public let id: UUID
    public let sessionID: SessionID
    public let buffer: AudioBuffer  // Reference to buffer pool, not owned data
    public let timestamp: Duration
    public let sampleRate: Double
    
    public init(id: UUID = UUID(), sessionID: SessionID, buffer: AudioBuffer, 
                timestamp: Duration, sampleRate: Double) {
        self.id = id
        self.sessionID = sessionID
        self.buffer = buffer
        self.timestamp = timestamp
        self.sampleRate = sampleRate
    }
}
```

**Days 3-4: Domain Error Types**

Create `OpenOats/Sources/Domain/Errors/`:

```swift
// OpenOats/Sources/Domain/Errors/TranscriptionError.swift
public enum TranscriptionError: Error, Sendable, LocalizedError {
    case backendFailed(backend: BackendID, reason: String, recoverable: Bool)
    case audioFormatUnsupported(format: String)
    case timeout(duration: Duration)
    case partialResultLost(segmentID: UUID)
    case noSpeechDetected
    
    public var errorDescription: String? {
        switch self {
        case .backendFailed(let backend, let reason, _):
            return "Transcription backend '\(backend)' failed: \(reason)"
        case .audioFormatUnsupported(let format):
            return "Audio format '\(format)' is not supported"
        case .timeout(let duration):
            return "Transcription timed out after \(duration)"
        case .partialResultLost(let segmentID):
            return "Partial transcription result lost for segment \(segmentID)"
        case .noSpeechDetected:
            return "No speech detected in audio"
        }
    }
    
    public var isRecoverable: Bool {
        switch self {
        case .backendFailed(_, _, let recoverable): return recoverable
        case .audioFormatUnsupported: return false
        case .timeout: return true
        case .partialResultLost: return true
        case .noSpeechDetected: return true
        }
    }
}
```

```swift
// OpenOats/Sources/Domain/Errors/StorageError.swift
public enum StorageError: Error, Sendable, LocalizedError {
    case persistenceFailed(entity: String, underlying: Error)
    case corruptionDetected(entity: String)
    case migrationFailed(fromVersion: Int, toVersion: Int)
    case quotaExceeded(used: Int64, limit: Int64)
    case fileNotFound(path: String)
    
    public var errorDescription: String? {
        switch self {
        case .persistenceFailed(let entity, _):
            return "Failed to persist \(entity)"
        case .corruptionDetected(let entity):
            return "Data corruption detected in \(entity)"
        case .migrationFailed(let from, let to):
            return "Migration failed from version \(from) to \(to)"
        case .quotaExceeded(let used, let limit):
            return "Storage quota exceeded (\(used)/\(limit) bytes)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}
```

```swift
// OpenOats/Sources/Domain/Errors/ValidationError.swift
public enum ValidationError: Error, Sendable, LocalizedError {
    case invalidInput(field: String, value: String, constraint: String)
    case malformedData(entity: String, reason: String)
    case outOfRange(field: String, value: Double, min: Double, max: Double)
    case missingRequiredField(field: String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let field, let value, let constraint):
            return "Invalid input for '\(field)': '\(value)' (must satisfy: \(constraint))"
        case .malformedData(let entity, let reason):
            return "Malformed data in \(entity): \(reason)"
        case .outOfRange(let field, let value, let min, let max):
            return "Field '\(field)' value \(value) is outside range [\(min), \(max)]"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        }
    }
}
```

```swift
// OpenOats/Sources/Domain/Errors/NetworkError.swift
public enum NetworkError: Error, Sendable, LocalizedError {
    case connectivityFailed(endpoint: String)
    case apiError(endpoint: String, statusCode: Int, message: String)
    case rateLimited(retryAfter: Duration)
    case authenticationFailed
    
    public var errorDescription: String? {
        switch self {
        case .connectivityFailed(let endpoint):
            return "Failed to connect to \(endpoint)"
        case .apiError(let endpoint, let status, let message):
            return "API error at \(endpoint): \(status) - \(message)"
        case .rateLimited(let retryAfter):
            return "Rate limited. Retry after \(retryAfter)"
        case .authenticationFailed:
            return "Authentication failed. Please check credentials."
        }
    }
}
```

```swift
// OpenOats/Sources/Domain/Errors/AudioError.swift
public enum AudioError: Error, Sendable, LocalizedError {
    case captureFailed(device: String, reason: String)
    case permissionDenied
    case formatConversionFailed(from: String, to: String)
    case bufferOverflow(maxSize: Int)
    case deviceDisconnected(device: String)
    
    public var errorDescription: String? {
        switch self {
        case .captureFailed(let device, let reason):
            return "Audio capture failed on '\(device)': \(reason)"
        case .permissionDenied:
            return "Microphone permission denied. Please enable in System Settings."
        case .formatConversionFailed(let from, let to):
            return "Failed to convert audio from \(from) to \(to)"
        case .bufferOverflow(let maxSize):
            return "Audio buffer overflow (max: \(maxSize) samples)"
        case .deviceDisconnected(let device):
            return "Audio device '\(device)' disconnected"
        }
    }
}
```

**Days 5-7: Strongly-Typed Identifiers**

Create `OpenOats/Sources/Domain/Identifiers/`:

```swift
// OpenOats/Sources/Domain/Identifiers/MeetingID.swift
public struct MeetingID: RawRepresentable, Sendable, Hashable, Codable, Comparable {
    public let rawValue: UUID
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID()
    }
    
    public static func < (lhs: MeetingID, rhs: MeetingID) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }
}

extension MeetingID: CustomStringConvertible {
    public var description: String {
        "MeetingID(\(rawValue.uuidString.prefix(8)))"
    }
}
```

```swift
// OpenOats/Sources/Domain/Identifiers/SessionID.swift
public struct SessionID: RawRepresentable, Sendable, Hashable, Codable, Comparable {
    public let rawValue: UUID
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID()
    }
    
    public static func < (lhs: SessionID, rhs: SessionID) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }
}

extension SessionID: CustomStringConvertible {
    public var description: String {
        "SessionID(\(rawValue.uuidString.prefix(8)))"
    }
}
```

```swift
// OpenOats/Sources/Domain/Identifiers/SpeakerID.swift
public struct SpeakerID: RawRepresentable, Sendable, Hashable, Codable, Comparable {
    public let rawValue: UUID
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID()
    }
    
    public static func < (lhs: SpeakerID, rhs: SpeakerID) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }
}

extension SpeakerID: CustomStringConvertible {
    public var description: String {
        "SpeakerID(\(rawValue.uuidString.prefix(8)))"
    }
}
```

```swift
// OpenOats/Sources/Domain/Identifiers/TranscriptID.swift
public struct TranscriptID: RawRepresentable, Sendable, Hashable, Codable, Comparable {
    public let rawValue: UUID
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID()
    }
    
    public static func < (lhs: TranscriptID, rhs: TranscriptID) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }
}

extension TranscriptID: CustomStringConvertible {
    public var description: String {
        "TranscriptID(\(rawValue.uuidString.prefix(8)))"
    }
}
```

```swift
// OpenOats/Sources/Domain/Identifiers/BackendID.swift
public struct BackendID: RawRepresentable, Sendable, Hashable, Codable, Comparable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public static let mlx = BackendID(rawValue: "mlx")
    public static let whisperKit = BackendID(rawValue: "whisperKit")
    public static let assemblyAI = BackendID(rawValue: "assemblyAI")
    public static let parakeet = BackendID(rawValue: "parakeet")
    
    public static func < (lhs: BackendID, rhs: BackendID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension BackendID: CustomStringConvertible {
    public var description: String {
        "BackendID(\(rawValue))"
    }
}
```

### Week 1 Deliverables & Validation

- [ ] All 7 domain entity structs created with Sendable conformance
- [ ] All 5 error enums created with LocalizedError conformance
- [ ] All 5 identifier types created with RawRepresentable
- [ ] Zero compiler warnings for Sendable conformance
- [ ] Unit tests for all entity initialization and equality

### Week 2: Domain Layer Integration

**Days 8-10: Mapper Layer (Old Model → Domain)**

Create `OpenOats/Sources/Domain/Mappers/`:

```swift
// OpenOats/Sources/Domain/Mappers/MeetingMapper.swift
public enum MeetingMapper {
    /// Maps legacy MeetingModel to new domain Meeting
    public static func toDomain(_ legacy: MeetingModel) -> Meeting {
        Meeting(
            id: MeetingID(rawValue: legacy.id),
            title: legacy.title,
            createdAt: legacy.createdAt,
            sessions: legacy.sessionIDs.map(SessionID.init(rawValue:)),
            status: mapStatus(legacy.status)
        )
    }
    
    /// Maps domain Meeting back to legacy model for gradual migration
    public static func toLegacy(_ domain: Meeting) -> MeetingModel {
        MeetingModel(
            id: domain.id.rawValue,
            title: domain.title,
            createdAt: domain.createdAt,
            sessionIDs: domain.sessions.map(\.rawValue),
            status: mapStatus(domain.status)
        )
    }
    
    private static func mapStatus(_ status: MeetingModel.Status) -> MeetingStatus {
        // Mapping implementation
    }
}
```

**Days 11-12: Feature Flags for Gradual Rollout**

```swift
// OpenOats/Sources/Core/FeatureFlags.swift
public enum FeatureFlags {
    /// Enable new domain layer entities
    public static var useDomainEntities: Bool {
        UserDefaults.standard.bool(forKey: "useDomainEntities")
    }
    
    /// Enable new error handling
    public static var useDomainErrors: Bool {
        UserDefaults.standard.bool(forKey: "useDomainErrors")
    }
    
    /// Enable new infrastructure protocols
    public static var useProtocolInfrastructure: Bool {
        UserDefaults.standard.bool(forKey: "useProtocolInfrastructure")
    }
    
    /// Enable new use cases
    public static var useUseCases: Bool {
        UserDefaults.standard.bool(forKey: "useUseCases")
    }
    
    /// Reset all feature flags (for testing)
    public static func resetAll() {
        UserDefaults.standard.removeObject(forKey: "useDomainEntities")
        UserDefaults.standard.removeObject(forKey: "useDomainErrors")
        UserDefaults.standard.removeObject(forKey: "useProtocolInfrastructure")
        UserDefaults.standard.removeObject(forKey: "useUseCases")
    }
}
```

**Days 13-14: Phase 1 Testing & Validation**

- [ ] Unit tests for all mappers (roundtrip testing)
- [ ] Integration tests with feature flags
- [ ] Performance benchmarks (domain types vs legacy types)
- [ ] Memory profiling (ensure no leaks in mappers)

---

## Phase 2: Extract Infrastructure Layer (Weeks 3-4)

### Goal
Create protocol-based infrastructure layer with clean separation and Sendable-safe implementations.

### Week 3: Repository Protocols

**Days 15-17: Session Repository Protocol**

```swift
// OpenOats/Sources/Infrastructure/Protocols/SessionRepositoryProtocol.swift
public protocol SessionRepositoryProtocol: Sendable {
    /// Save a session
    func save(_ session: Session) async throws(StorageError)
    
    /// Load a session by ID
    func load(id: SessionID) async throws(StorageError) -> Session?
    
    /// Load all sessions for a meeting
    func loadAll(for meetingID: MeetingID) async throws(StorageError) -> [Session]
    
    /// Delete a session
    func delete(id: SessionID) async throws(StorageError)
    
    /// Check if session exists
    func exists(id: SessionID) async -> Bool
}

/// Factory for creating repository implementations
public enum SessionRepositoryFactory {
    /// Creates the production Core Data implementation
    public static func makeCoreDataRepository() -> any SessionRepositoryProtocol {
        CoreDataSessionRepository()
    }
    
    /// Creates an in-memory implementation for testing
    public static func makeInMemoryRepository() -> any SessionRepositoryProtocol {
        InMemorySessionRepository()
    }
}
```

**Days 18-19: Transcript Repository Protocol**

```swift
// OpenOats/Sources/Infrastructure/Protocols/TranscriptRepositoryProtocol.swift
public protocol TranscriptRepositoryProtocol: Sendable {
    /// Save a transcript
    func save(_ transcript: Transcript) async throws(StorageError)
    
    /// Load a transcript by ID
    func load(id: TranscriptID) async throws(StorageError) -> Transcript?
    
    /// Load transcript for a specific session
    func load(for sessionID: SessionID) async throws(StorageError) -> Transcript?
    
    /// Search transcripts by text content
    func search(query: String, limit: Int) async throws(StorageError) -> [Transcript]
    
    /// Delete a transcript
    func delete(id: TranscriptID) async throws(StorageError)
}
```

**Days 20-21: Settings Repository Protocol**

```swift
// OpenOats/Sources/Infrastructure/Protocols/SettingsRepositoryProtocol.swift
public protocol SettingsRepositoryProtocol: Sendable {
    /// Get a setting value
    func get<T: Codable & Sendable>(_ key: SettingKey<T>) async -> T?
    
    /// Set a setting value
    func set<T: Codable & Sendable>(_ value: T, for key: SettingKey<T>) async throws(StorageError)
    
    /// Remove a setting
    func remove<T>(_ key: SettingKey<T>) async
    
    /// Clear all settings
    func clearAll() async
}

/// Type-safe setting keys
public struct SettingKey<T: Codable & Sendable>: Sendable {
    public let rawValue: String
    public let defaultValue: T?
    
    public init(_ key: String, defaultValue: T? = nil) {
        self.rawValue = key
        self.defaultValue = defaultValue
    }
}

// Predefined keys
public extension SettingKey {
    static var selectedBackend: SettingKey<BackendID> {
        SettingKey("selectedBackend", defaultValue: .mlx)
    }
    
    static var transcriptionQuality: SettingKey<String> {
        SettingKey("transcriptionQuality", defaultValue: "high")
    }
    
    static var autoGenerateNotes: SettingKey<Bool> {
        SettingKey("autoGenerateNotes", defaultValue: true)
    }
}
```

### Week 4: Service Protocols

**Days 22-24: Transcription Service Protocol**

```swift
// OpenOats/Sources/Infrastructure/Protocols/TranscriptionServiceProtocol.swift

/// Base protocol for all transcription services
public protocol TranscriptionServiceProtocol: Sendable {
    /// Unique identifier for this backend
    var backendID: BackendID { get }
    
    /// Check if the service is available and ready
    var isAvailable: Bool { get async }
    
    /// Get supported languages
    func supportedLanguages() async -> [LanguageCode]
    
    /// Configure the service
    func configure(_ configuration: TranscriptionConfiguration) async
}

/// Streaming transcription service for real-time transcription
public protocol StreamingTranscriptionServiceProtocol: TranscriptionServiceProtocol {
    /// Start a streaming transcription session
    /// Returns an AsyncStream that yields transcription segments as they arrive
    func startStreaming(
        language: LanguageCode,
        options: StreamingOptions
    ) async throws(TranscriptionError) -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError>
    
    /// Feed audio data to the streaming session
    func feedAudio(_ buffer: AudioBuffer) async throws(TranscriptionError)
    
    /// Stop the streaming session
    func stopStreaming() async
    
    /// Current streaming state
    var isStreaming: Bool { get }
}

/// Batch transcription service for file-based transcription
public protocol BatchTranscriptionServiceProtocol: TranscriptionServiceProtocol {
    /// Transcribe an entire audio file
    func transcribeFile(
        at url: URL,
        language: LanguageCode,
        options: BatchOptions
    ) async throws(TranscriptionError) -> Transcript
    
    /// Transcribe with progress updates
    func transcribeFileWithProgress(
        at url: URL,
        language: LanguageCode,
        options: BatchOptions
    ) -> AsyncThrowingStream<BatchProgress, TranscriptionError>
}

/// Transcription segment from streaming
public struct TranscriptionSegment: Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let confidence: Double
    public let isFinal: Bool
    public let speakerID: SpeakerID?
    public let timestamp: Duration
    
    public init(id: UUID = UUID(), text: String, confidence: Double, 
                isFinal: Bool, speakerID: SpeakerID? = nil, timestamp: Duration) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.isFinal = isFinal
        self.speakerID = speakerID
        self.timestamp = timestamp
    }
}

/// Batch transcription progress
public enum BatchProgress: Sendable {
    case loading(progress: Double)
    case transcribing(progress: Double, partialText: String)
    case completed(Transcript)
}
```

**Days 25-26: Audio Capture Service Protocol**

```swift
// OpenOats/Sources/Infrastructure/Protocols/AudioCaptureServiceProtocol.swift

/// Protocol for audio capture services (microphone, system audio)
public protocol AudioCaptureServiceProtocol: Sendable {
    /// Check if capture is available and permitted
    var isAuthorized: Bool { get async }
    
    /// Request microphone permission
    func requestAuthorization() async -> Bool
    
    /// Start capturing audio
    /// Returns an AsyncStream of audio buffers
    func startCapture(
        format: AudioFormat,
        bufferSize: Int
    ) async throws(AudioError) -> AsyncThrowingStream<AudioBuffer, AudioError>
    
    /// Stop capturing audio
    func stopCapture() async
    
    /// Current capture state
    var isCapturing: Bool { get }
    
    /// Get available audio devices
    func availableDevices() async -> [AudioDevice]
}

/// Audio device information
public struct AudioDevice: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let type: AudioDeviceType
    public let isDefault: Bool
    
    public init(id: String, name: String, type: AudioDeviceType, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.isDefault = isDefault
    }
}

public enum AudioDeviceType: Sendable {
    case microphone
    case systemAudio
    case external
}

/// Audio format specification
public struct AudioFormat: Sendable, Equatable {
    public let sampleRate: Double
    public let channels: Int
    public let bitDepth: Int
    
    public static let `default` = AudioFormat(sampleRate: 48000, channels: 1, bitDepth: 16)
    public static let highQuality = AudioFormat(sampleRate: 48000, channels: 2, bitDepth: 24)
}
```

**Days 27-28: LLM and AI Service Protocols**

```swift
// OpenOats/Sources/Infrastructure/Protocols/LLMServiceProtocol.swift

/// Protocol for LLM service integration (OpenRouter, Ollama)
public protocol LLMServiceProtocol: Sendable {
    /// Generate notes from a transcript
    func generateNotes(
        from transcript: Transcript,
        type: NoteType,
        options: LLMOptions
    ) async throws(NetworkError) -> Note
    
    /// Generate a completion from a prompt
    func complete(
        prompt: String,
        options: LLMOptions
    ) async throws(NetworkError) -> String
    
    /// Stream a completion (for longer generations)
    func streamCompletion(
        prompt: String,
        options: LLMOptions
    ) -> AsyncThrowingStream<String, NetworkError>
}

/// LLM request options
public struct LLMOptions: Sendable {
    public let model: String
    public let temperature: Double
    public let maxTokens: Int
    public let systemPrompt: String?
    
    public init(
        model: String = "openrouter/anthropic/claude-3-haiku",
        temperature: Double = 0.7,
        maxTokens: Int = 4000,
        systemPrompt: String? = nil
    ) {
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
    }
}
```

### Phase 2 Deliverables

- [ ] All repository protocols defined
- [ ] All service protocols defined
- [ ] Implementation factories created
- [ ] Mock implementations for testing
- [ ] Protocol conformance tests

---

## Phase 3: Extract Business Logic Layer (Weeks 5-6)

### Goal
Extract use cases from NotesView (3.7K lines) and SessionRepository (2.1K lines) into focused, single-responsibility use cases.

### Week 5: Core Use Cases

**Days 29-31: Session Use Cases**

```swift
// OpenOats/Sources/BusinessLogic/UseCases/StartSessionUseCase.swift

/// Input parameters for starting a session
public struct StartSessionInput: Sendable {
    public let meetingTitle: String
    public let audioSource: AudioSource
    public let transcriptionBackend: BackendID
    
    public init(meetingTitle: String, audioSource: AudioSource, transcriptionBackend: BackendID) {
        self.meetingTitle = meetingTitle
        self.audioSource = audioSource
        self.transcriptionBackend = transcriptionBackend
    }
}

public enum AudioSource: Sendable {
    case microphone
    case systemAudio
    case both
}

/// Use case for starting a new recording session
public protocol StartSessionUseCaseProtocol: Sendable {
    func execute(input: StartSessionInput) async throws -> Session
}

/// Implementation of the start session use case
public actor StartSessionUseCase: StartSessionUseCaseProtocol {
    private let sessionRepository: any SessionRepositoryProtocol
    private let audioCapture: any AudioCaptureServiceProtocol
    private let transcriptionService: any StreamingTranscriptionServiceProtocol
    
    public init(
        sessionRepository: any SessionRepositoryProtocol,
        audioCapture: any AudioCaptureServiceProtocol,
        transcriptionService: any StreamingTranscriptionServiceProtocol
    ) {
        self.sessionRepository = sessionRepository
        self.audioCapture = audioCapture
        self.transcriptionService = transcriptionService
    }
    
    public func execute(input: StartSessionInput) async throws -> Session {
        // 1. Check authorization
        guard await audioCapture.isAuthorized else {
            throw AudioError.permissionDenied
        }
        
        // 2. Check transcription service availability
        guard await transcriptionService.isAvailable else {
            throw TranscriptionError.backendFailed(
                backend: input.transcriptionBackend,
                reason: "Service not available",
                recoverable: false
            )
        }
        
        // 3. Create the session
        let meetingID = MeetingID()
        let sessionID = SessionID()
        
        let meeting = Meeting(
            id: meetingID,
            title: input.meetingTitle,
            createdAt: Date(),
            sessions: [sessionID],
            status: .inProgress
        )
        
        let session = Session(
            id: sessionID,
            meetingID: meetingID,
            startedAt: Date(),
            status: .recording,
            recordingURL: nil
        )
        
        // 4. Save the session
        try await sessionRepository.save(session)
        
        // 5. Start transcription (returns immediately, runs in background)
        Task {
            try await startTranscription(for: session, source: input.audioSource)
        }
        
        return session
    }
    
    private func startTranscription(for session: Session, source: AudioSource) async throws {
        // Implementation that coordinates audio capture and transcription
        // This runs as a background task
    }
}
```

```swift
// OpenOats/Sources/BusinessLogic/UseCases/StopSessionUseCase.swift

public struct StopSessionInput: Sendable {
    public let sessionID: SessionID
    public let shouldGenerateNotes: Bool
    
    public init(sessionID: SessionID, shouldGenerateNotes: Bool = false) {
        self.sessionID = sessionID
        self.shouldGenerateNotes = shouldGenerateNotes
    }
}

public protocol StopSessionUseCaseProtocol: Sendable {
    func execute(input: StopSessionInput) async throws -> Session
}

public actor StopSessionUseCase: StopSessionUseCaseProtocol {
    private let sessionRepository: any SessionRepositoryProtocol
    private let transcriptRepository: any TranscriptRepositoryProtocol
    private let audioCapture: any AudioCaptureServiceProtocol
    
    public init(
        sessionRepository: any SessionRepositoryProtocol,
        transcriptRepository: any TranscriptRepositoryProtocol,
        audioCapture: any AudioCaptureServiceProtocol
    ) {
        self.sessionRepository = sessionRepository
        self.transcriptRepository = transcriptRepository
        self.audioCapture = audioCapture
    }
    
    public func execute(input: StopSessionInput) async throws -> Session {
        // 1. Load the session
        guard let session = try await sessionRepository.load(id: input.sessionID) else {
            throw StorageError.fileNotFound(path: "session:\(input.sessionID)")
        }
        
        // 2. Stop audio capture
        await audioCapture.stopCapture()
        
        // 3. Finalize the session
        let finalizedSession = Session(
            id: session.id,
            meetingID: session.meetingID,
            startedAt: session.startedAt,
            endedAt: Date(),
            status: .completed,
            recordingURL: session.recordingURL
        )
        
        // 4. Save finalized session
        try await sessionRepository.save(finalizedSession)
        
        return finalizedSession
    }
}
```

**Days 32-33: Transcription Use Cases**

```swift
// OpenOats/Sources/BusinessLogic/UseCases/ExportTranscriptUseCase.swift

public struct ExportTranscriptInput: Sendable {
    public let transcriptID: TranscriptID
    public let format: ExportFormat
    public let destinationURL: URL
    
    public init(transcriptID: TranscriptID, format: ExportFormat, destinationURL: URL) {
        self.transcriptID = transcriptID
        self.format = format
        self.destinationURL = destinationURL
    }
}

public enum ExportFormat: String, Sendable, CaseIterable {
    case txt, json, srt, vtt, markdown
}

public protocol ExportTranscriptUseCaseProtocol: Sendable {
    func execute(input: ExportTranscriptInput) async throws
}

public actor ExportTranscriptUseCase: ExportTranscriptUseCaseProtocol {
    private let transcriptRepository: any TranscriptRepositoryProtocol
    
    public init(transcriptRepository: any TranscriptRepositoryProtocol) {
        self.transcriptRepository = transcriptRepository
    }
    
    public func execute(input: ExportTranscriptInput) async throws {
        // 1. Load the transcript
        guard let transcript = try await transcriptRepository.load(id: input.transcriptID) else {
            throw StorageError.fileNotFound(path: "transcript:\(input.transcriptID)")
        }
        
        // 2. Format according to requested format
        let content = format(transcript, as: input.format)
        
        // 3. Write to destination
        try content.write(to: input.destinationURL, atomically: true, encoding: .utf8)
    }
    
    private func format(_ transcript: Transcript, as format: ExportFormat) -> String {
        switch format {
        case .txt:
            return transcript.fullText
        case .json:
            return formatAsJSON(transcript)
        case .srt:
            return formatAsSRT(transcript)
        case .vtt:
            return formatAsVTT(transcript)
        case .markdown:
            return formatAsMarkdown(transcript)
        }
    }
    
    // Private formatting helpers...
}
```

### Week 6: AI-Powered Use Cases

**Days 34-36: Note Generation Use Cases**

```swift
// OpenOats/Sources/BusinessLogic/UseCases/GenerateNotesUseCase.swift

public struct GenerateNotesInput: Sendable {
    public let transcriptID: TranscriptID
    public let noteTypes: [NoteType]
    public let aiModel: String?
    
    public init(transcriptID: TranscriptID, noteTypes: [NoteType], aiModel: String? = nil) {
        self.transcriptID = transcriptID
        self.noteTypes = noteTypes
        self.aiModel = aiModel
    }
}

public struct GenerateNotesOutput: Sendable {
    public let notes: [Note]
    public let generationTime: Duration
    public let aiModel: String
}

public protocol GenerateNotesUseCaseProtocol: Sendable {
    func execute(input: GenerateNotesInput) async throws(NetworkError) -> GenerateNotesOutput
}

public actor GenerateNotesUseCase: GenerateNotesUseCaseProtocol {
    private let transcriptRepository: any TranscriptRepositoryProtocol
    private let llmService: any LLMServiceProtocol
    
    public init(
        transcriptRepository: any TranscriptRepositoryProtocol,
        llmService: any LLMServiceProtocol
    ) {
        self.transcriptRepository = transcriptRepository
        self.llmService = llmService
    }
    
    public func execute(input: GenerateNotesInput) async throws(NetworkError) -> GenerateNotesOutput {
        let startTime = Date()
        
        // 1. Load the transcript
        guard let transcript = try await transcriptRepository.load(id: input.transcriptID) else {
            // Convert to network error or add proper error handling
            throw NetworkError.apiError(endpoint: "transcript", statusCode: 404, message: "Not found")
        }
        
        // 2. Generate notes for each requested type (parallel)
        var notes: [Note] = []
        
        await withTaskGroup(of: Note.self) { group in
            for noteType in input.noteTypes {
                group.addTask {
                    try await self.generateNote(for: transcript, type: noteType, aiModel: input.aiModel)
                }
            }
            
            for await note in group {
                notes.append(note)
            }
        }
        
        let generationTime = Date().timeIntervalSince(startTime)
        
        return GenerateNotesOutput(
            notes: notes,
            generationTime: .seconds(generationTime),
            aiModel: input.aiModel ?? "default"
        )
    }
    
    private func generateNote(for transcript: Transcript, type: NoteType, aiModel: String?) async throws(NetworkError) -> Note {
        let prompt = buildPrompt(for: type, transcript: transcript)
        
        let options = LLMOptions(model: aiModel ?? "default")
        let content = try await llmService.complete(prompt: prompt, options: options)
        
        return Note(
            meetingID: transcript.sessionID.meetingID,
            content: content,
            type: type,
            generatedAt: Date(),
            aiModel: aiModel ?? "default"
        )
    }
    
    private func buildPrompt(for type: NoteType, transcript: Transcript) -> String {
        switch type {
        case .summary:
            return "Summarize the following meeting transcript:\n\n\(transcript.fullText)"
        case .actionItems:
            return "Extract action items from the following meeting transcript:\n\n\(transcript.fullText)"
        case .keyDecisions:
            return "Identify key decisions from the following meeting transcript:\n\n\(transcript.fullText)"
        default:
            return transcript.fullText
        }
    }
}
```

**Days 37-38: Import and Backend Switch Use Cases**

```swift
// OpenOats/Sources/BusinessLogic/UseCases/ImportAudioUseCase.swift

public struct ImportAudioInput: Sendable {
    public let sourceURL: URL
    public let meetingTitle: String
    public let transcriptionBackend: BackendID
    
    public init(sourceURL: URL, meetingTitle: String, transcriptionBackend: BackendID) {
        self.sourceURL = sourceURL
        self.meetingTitle = meetingTitle
        self.transcriptionBackend = transcriptionBackend
    }
}

public protocol ImportAudioUseCaseProtocol: Sendable {
    func execute(input: ImportAudioInput) async throws -> Transcript
}

public actor ImportAudioUseCase: ImportAudioUseCaseProtocol {
    private let batchTranscriptionService: any BatchTranscriptionServiceProtocol
    
    public init(batchTranscriptionService: any BatchTranscriptionServiceProtocol) {
        self.batchTranscriptionService = batchTranscriptionService
    }
    
    public func execute(input: ImportAudioInput) async throws -> Transcript {
        // 1. Validate the audio file
        guard FileManager.default.fileExists(atPath: input.sourceURL.path) else {
            throw AudioError.captureFailed(device: "file", reason: "File not found: \(input.sourceURL)")
        }
        
        // 2. Transcribe the file
        let transcript = try await batchTranscriptionService.transcribeFile(
            at: input.sourceURL,
            language: LanguageCode.en,
            options: BatchOptions.default
        )
        
        return transcript
    }
}
```

```swift
// OpenOats/Sources/BusinessLogic/UseCases/SwitchBackendUseCase.swift

public struct SwitchBackendInput: Sendable {
    public let newBackend: BackendID
    public let preserveExistingTranscriptions: Bool
    
    public init(newBackend: BackendID, preserveExistingTranscriptions: Bool = true) {
        self.newBackend = newBackend
        self.preserveExistingTranscriptions = preserveExistingTranscriptions
    }
}

public protocol SwitchBackendUseCaseProtocol: Sendable {
    func execute(input: SwitchBackendInput) async throws(TranscriptionError)
}

public actor SwitchBackendUseCase: SwitchBackendUseCaseProtocol {
    private let settingsRepository: any SettingsRepositoryProtocol
    private let transcriptionFactory: any TranscriptionServiceFactoryProtocol
    
    public init(
        settingsRepository: any SettingsRepositoryProtocol,
        transcriptionFactory: any TranscriptionServiceFactoryProtocol
    ) {
        self.settingsRepository = settingsRepository
        self.transcriptionFactory = transcriptionFactory
    }
    
    public func execute(input: SwitchBackendInput) async throws(TranscriptionError) {
        // 1. Verify the new backend is available
        let newService = transcriptionFactory.makeService(for: input.newBackend)
        
        guard await newService.isAvailable else {
            throw TranscriptionError.backendFailed(
                backend: input.newBackend,
                reason: "Backend not available",
                recoverable: false
            )
        }
        
        // 2. Save the new backend preference
        try await settingsRepository.set(input.newBackend, for: .selectedBackend)
        
        // 3. If we need to preserve existing transcriptions, migrate them
        if input.preserveExistingTranscriptions {
            // Migration logic would go here
        }
    }
}
```

**Days 39-42: Phase 3 Testing & Validation**

- [ ] Unit tests for each use case
- [ ] Integration tests with mock repositories
- [ ] Performance tests (measure execution time)
- [ ] Actor isolation tests (verify no data races)

---

## Phase 4: Refactor Presentation Layer (Weeks 7-8)

### Goal
Create view models to replace direct model access in NotesView (3.7K lines) and other views.

### Week 7: View Models

**Days 43-46: SessionViewModel**

```swift
// OpenOats/Sources/Presentation/ViewModels/SessionViewModel.swift

import SwiftUI
import Combine

@MainActor
public class SessionViewModel: ObservableObject {
    // MARK: - Published State
    @Published public private(set) var currentSession: Session?
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var recordingDuration: Duration = .zero
    @Published public private(set) var audioLevels: [Float] = []
    @Published public private(set) var error: Error?
    @Published public var showError: Bool = false
    
    // MARK: - Dependencies
    private let startSessionUseCase: any StartSessionUseCaseProtocol
    private let stopSessionUseCase: any StopSessionUseCaseProtocol
    private var recordingTimer: Timer?
    
    // MARK: - Initialization
    public init(
        startSessionUseCase: any StartSessionUseCaseProtocol,
        stopSessionUseCase: any StopSessionUseCaseProtocol
    ) {
        self.startSessionUseCase = startSessionUseCase
        self.stopSessionUseCase = stopSessionUseCase
    }
    
    // MARK: - Actions
    public func startRecording(title: String, audioSource: AudioSource) async {
        error = nil
        
        do {
            let input = StartSessionInput(
                meetingTitle: title,
                audioSource: audioSource,
                transcriptionBackend: .mlx
            )
            
            let session = try await startSessionUseCase.execute(input: input)
            
            currentSession = session
            isRecording = true
            recordingDuration = .zero
            
            // Start recording duration timer
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingDuration += .seconds(1)
                }
            }
            
        } catch {
            self.error = error
            self.showError = true
        }
    }
    
    public func stopRecording(shouldGenerateNotes: Bool = false) async {
        guard let session = currentSession else { return }
        
        error = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        do {
            let input = StopSessionInput(
                sessionID: session.id,
                shouldGenerateNotes: shouldGenerateNotes
            )
            
            let finalizedSession = try await stopSessionUseCase.execute(input: input)
            
            currentSession = finalizedSession
            isRecording = false
            
        } catch {
            self.error = error
            self.showError = true
        }
    }
    
    public func cancelRecording() async {
        // Implementation for canceling a recording without saving
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        currentSession = nil
    }
}
```

**Days 47-49: TranscriptViewModel**

```swift
// OpenOats/Sources/Presentation/ViewModels/TranscriptViewModel.swift

@MainActor
public class TranscriptViewModel: ObservableObject {
    @Published public private(set) var transcript: Transcript?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var exportProgress: Double = 0
    @Published public var searchQuery: String = ""
    @Published public private(set) var searchResults: [Utterance] = []
    
    private let transcriptRepository: any TranscriptRepositoryProtocol
    private let exportUseCase: any ExportTranscriptUseCaseProtocol
    
    public init(
        transcriptRepository: any TranscriptRepositoryProtocol,
        exportUseCase: any ExportTranscriptUseCaseProtocol
    ) {
        self.transcriptRepository = transcriptRepository
        self.exportUseCase = exportUseCase
    }
    
    public func loadTranscript(id: TranscriptID) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            transcript = try await transcriptRepository.load(id: id)
        } catch {
            // Handle error
        }
    }
    
    public func exportTranscript(format: ExportFormat, to destinationURL: URL) async {
        guard let transcript = transcript else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let input = ExportTranscriptInput(
                transcriptID: transcript.id,
                format: format,
                destinationURL: destinationURL
            )
            
            try await exportUseCase.execute(input: input)
            exportProgress = 1.0
            
        } catch {
            // Handle error
        }
    }
    
    public func performSearch() {
        guard let transcript = transcript, !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        
        searchResults = transcript.utterances.filter { utterance in
            utterance.text.localizedCaseInsensitiveContains(searchQuery)
        }
    }
}
```

### Week 8: SwiftUI Integration

**Days 50-52: Refactored NotesView**

```swift
// OpenOats/Sources/Presentation/Views/NotesView.swift
// Target: < 300 lines (down from 3,700)

import SwiftUI

struct NotesView: View {
    @StateObject private var viewModel: NotesViewModel
    @StateObject private var sessionViewModel: SessionViewModel
    
    init(viewModel: NotesViewModel, sessionViewModel: SessionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _sessionViewModel = StateObject(wrappedValue: sessionViewModel)
    }
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .alert("Error", isPresented: $sessionViewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = sessionViewModel.error {
                Text(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Subviews (extracted for clarity)
    
    private var sidebar: some View {
        List {
            recordingSection
            meetingsSection
            settingsSection
        }
        .listStyle(.sidebar)
    }
    
    private var recordingSection: some View {
        Section("Recording") {
            if sessionViewModel.isRecording {
                RecordingProgressView(
                    duration: sessionViewModel.recordingDuration,
                    audioLevels: sessionViewModel.audioLevels
                )
                
                Button("Stop Recording") {
                    Task {
                        await sessionViewModel.stopRecording(shouldGenerateNotes: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button("Start Recording") {
                    Task {
                        await sessionViewModel.startRecording(
                            title: "New Meeting",
                            audioSource: .microphone
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var meetingsSection: some View {
        Section("Meetings") {
            ForEach(viewModel.meetings) { meeting in
                NavigationLink(value: meeting) {
                    MeetingRowView(meeting: meeting)
                }
            }
        }
    }
    
    private var settingsSection: some View {
        Section("Settings") {
            NavigationLink("Transcription Backend") {
                BackendSettingsView()
            }
            NavigationLink("AI Model") {
                AIModelSettingsView()
            }
        }
    }
    
    private var detailView: some View {
        Group {
            if let selectedMeeting = viewModel.selectedMeeting {
                MeetingDetailView(meeting: selectedMeeting)
            } else {
                ContentUnavailableView("Select a Meeting", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }
}
```

**Days 53-54: MeetingDetailView (Extracted)**

```swift
// OpenOats/Sources/Presentation/Views/MeetingDetailView.swift

struct MeetingDetailView: View {
    let meeting: Meeting
    @StateObject private var transcriptViewModel: TranscriptViewModel
    @StateObject private var notesViewModel: GeneratedNotesViewModel
    
    var body: some View {
        TabView {
            TranscriptTab()
                .tabItem { Label("Transcript", systemImage: "text.bubble") }
            
            NotesTab()
                .tabItem { Label("Notes", systemImage: "note.text") }
            
            ExportTab()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .task {
            if let sessionID = meeting.sessions.first {
                await transcriptViewModel.loadTranscript(for: sessionID)
                await notesViewModel.loadNotes(for: meeting.id)
            }
        }
    }
}

// MARK: - Subviews

private struct TranscriptTab: View {
    @EnvironmentObject var viewModel: TranscriptViewModel
    
    var body: some View {
        VStack {
            SearchBar(text: $viewModel.searchQuery)
            
            if viewModel.isLoading {
                ProgressView()
            } else if let transcript = viewModel.transcript {
                TranscriptListView(utterances: viewModel.searchResults.isEmpty 
                    ? transcript.utterances 
                    : viewModel.searchResults)
            }
        }
    }
}
```

**Days 55-56: Phase 4 Testing**

- [ ] UI tests for refactored views
- [ ] View model unit tests
- [ ] Preview tests for SwiftUI views
- [ ] Accessibility tests

---

## Phase 5: Clean Up & Final Verification (Week 9)

### Goal
Remove old code paths, verify all tests pass, and ensure backward compatibility.

### Days 57-59: Remove Legacy Code

**Step 1: Remove Old Model Types**

Once all code has migrated to new domain types:

```swift
// MARK: - Deprecated
// These types will be removed after Phase 5
// Use corresponding domain types instead:
// - MeetingModel → Meeting
// - SessionModel → Session
// - TranscriptModel → Transcript
@available(*, deprecated, renamed: "Meeting")
public typealias MeetingModel = Meeting  // Temporary alias
```

**Step 2: Remove Direct Repository Access**

- Remove direct `SessionRepository` access from views
- Ensure all access goes through use cases

**Step 3: Clean Up Feature Flags**

```swift
// Once migration is complete, remove feature flags:
public enum FeatureFlags {
    // All flags now return true - remove after verification
    public static var useDomainEntities: Bool { true }
    public static var useDomainErrors: Bool { true }
    public static var useProtocolInfrastructure: Bool { true }
    public static var useUseCases: Bool { true }
}
```

### Days 60-61: Final Verification

**Testing Checklist:**

- [ ] Unit test suite passes (100% pass rate)
- [ ] Integration tests pass
- [ ] UI tests pass
- [ ] Performance benchmarks meet targets
- [ ] Memory leak tests pass
- [ ] Data race detection passes

**Metrics Validation:**

Run AST-based hotpoint detection (from TASK-012):

```bash
# Run queries to validate migration success

# High fan-out functions (>8 calls) should be zero
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.source_id = s.id AND e.kind = 'calls' GROUP BY s.id HAVING COUNT(e.id) > 8);"
# Expected: 0

# Blast radius symbols (>10 dependents) should be zero
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.target_id = s.id GROUP BY s.id HAVING COUNT(e.id) > 10);"
# Expected: 0

# Circular dependencies should be zero
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM edges e1 JOIN edges e2 ON e2.source_id = e1.target_id AND e2.target_id = e1.source_id WHERE e1.kind = 'imports';"
# Expected: 0

# Large classes (>15 methods) should be zero
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM symbols c JOIN symbols m ON m.file = c.file WHERE c.kind = 'class' GROUP BY c.name HAVING COUNT(m.id) > 15;"
# Expected: 0
```

### Day 62: Sign-off

**Final Deliverables:**

- [ ] Architecture documentation updated
- [ ] API documentation generated
- [ ] CHANGELOG.md updated with migration details
- [ ] Rollback plan archived
- [ ] Sign-off from Lead Developer
- [ ] Sign-off from Product Owner

---

## Rollback Strategy

### Per-Phase Rollback Plans

**Phase 1 Rollback (Domain Layer):**

If domain types cause issues:

```swift
// Re-enable legacy types by flipping feature flag
FeatureFlags.resetAll()
UserDefaults.standard.set(false, forKey: "useDomainEntities")
```

**Phase 2 Rollback (Infrastructure):**

If protocols cause issues:

```swift
// Fall back to concrete implementations
if !FeatureFlags.useProtocolInfrastructure {
    // Use old concrete SessionRepository instead of protocol
    let repository = SessionRepository()  // Old concrete class
}
```

**Phase 3 Rollback (Use Cases):**

If use cases cause issues:

```swift
// Direct view-to-repository access as fallback
if !FeatureFlags.useUseCases {
    // Old direct access pattern
    repository.save(model)
}
```

**Phase 4 Rollback (Presentation):**

If view models cause issues:

```bash
# Git revert to restore old NotesView
git revert HEAD -- OpenOats/Sources/Presentation/Views/NotesView.swift
```

### Emergency Rollback

```bash
# Full rollback to pre-migration state
git checkout pre-migration-branch
# Or restore from tag
git checkout -b rollback tags/v1.0-stable
```

---

## Risk Mitigation Summary

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Compiler errors from Sendable | Medium | Medium | Feature flags, gradual rollout |
| Performance regression | Low | High | Benchmarks at each phase |
| UI regression | Medium | High | Comprehensive UI tests |
| Data loss | Low | Critical | Backups before each phase |
| Third-party API changes | Low | Medium | Adapter pattern isolation |
| Team capacity issues | Medium | Medium | Phased approach allows pausing |
| Swift 6.2 compatibility | Medium | Medium | Compiler version checks |

---

## Success Metrics

### Code Quality Targets

| Metric | Before | After (Target) |
|--------|--------|----------------|
| Largest file (lines) | 3,700 (NotesView) | < 300 |
| Largest class (methods) | 2,100 (SessionRepository) | < 15 |
| Cyclomatic complexity (max) | 34 | < 15 |
| Data races | 2 critical | 0 |
| Circular dependencies | > 0 | 0 |
| God functions (>8 calls) | Unknown | 0 |
| High blast radius (>10 deps) | Unknown | 0 |

### Performance Targets

| Metric | Before | After (Target) |
|--------|--------|----------------|
| Memory usage (2hr recording) | ~2.6GB | < 768KB |
| Transcription latency | 200-500ms stalls | < 100ms (non-blocking) |
| VAD loop blocking | Yes | No |
| DSP optimization | Scalar | vDSP |
| Task cancellation | Unstructured | Full structured |

---

## Next Steps

After this migration strategy is approved:

1. **wfc-implement** will execute the implementation phase
2. Each phase can be implemented independently or in parallel (per phase)
3. Feature flags allow gradual rollout to beta users
4. Full production rollout after all phases pass QA

---

**Formal Properties Verification:**

- [x] SAFETY: Each migration phase preserves existing functionality (via feature flags)
- [x] LIVENESS: Users can use app throughout migration (backward compatible)
- [x] INVARIANT: No phase can be started until previous phase is verified
- [x] INVARIANT: Rollback plan exists for every phase
- [x] INVARIANT: Testing gates exist at each milestone

**Status**: Ready for implementation phase
