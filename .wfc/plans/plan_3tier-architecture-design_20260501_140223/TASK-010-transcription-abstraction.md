# TASK-010: Design Transcription Backend Abstraction

## Overview
Create detailed protocol hierarchy for multiple transcription backends supporting both streaming (real-time) and batch (file-based) transcription.

## Design Output

### Protocol Hierarchy

```swift
// MARK: - Base Transcription Protocol

/// Base protocol for all transcription services
protocol TranscriptionService: Sendable {
    /// Unique identifier for this backend
    var backendID: BackendID { get }
    
    /// Backend display name
    var displayName: String { get }
    
    /// Whether the backend is available/online
    var isAvailable: Bool { get async }
    
    /// Backend capabilities
    var capabilities: TranscriptionCapabilities { get }
    
    /// Supported languages (ISO codes like "en", "es")
    var supportedLanguages: [String] { get }
    
    /// Current service status
    var status: TranscriptionServiceStatus { get async }
}

/// Service status
enum TranscriptionServiceStatus: Sendable {
    case ready
    case initializing
    case loadingModel(progress: Double)
    case busy
    case error(TranscriptionError)
    case offline
}

/// Capability flags for transcription services
struct TranscriptionCapabilities: OptionSet, Sendable {
    let rawValue: Int
    
    /// Supports real-time streaming transcription
    static let streaming = TranscriptionCapabilities(rawValue: 1 << 0)
    
    /// Supports batch file transcription
    static let batch = TranscriptionCapabilities(rawValue: 1 << 1)
    
    /// Supports speaker diarization
    static let speakerDiarization = TranscriptionCapabilities(rawValue: 1 << 2)
    
    /// Supports word-level timestamps
    static let wordTimestamps = TranscriptionCapabilities(rawValue: 1 << 3)
    
    /// Supports language detection
    static let languageDetection = TranscriptionCapabilities(rawValue: 1 << 4)
    
    /// Runs locally (no cloud dependency)
    static let localProcessing = TranscriptionCapabilities(rawValue: 1 << 5)
    
    /// Supports partial/incremental results
    static let partialResults = TranscriptionCapabilities(rawValue: 1 << 6)
    
    /// Supports vocabulary customization
    static let customVocabulary = TranscriptionCapabilities(rawValue: 1 << 7)
}

// MARK: - Streaming Transcription

/// Result from streaming transcription
struct TranscriptionSegment: Sendable, Identifiable {
    let id: UUID
    let text: String
    let startTime: Duration
    let endTime: Duration
    let confidence: Double
    let speakerID: SpeakerID?
    let isFinal: Bool
    let words: [WordTimestamp]?
}

/// Word-level timestamp
struct WordTimestamp: Sendable {
    let word: String
    let startTime: Duration
    let endTime: Duration
    let confidence: Double
}

/// Streaming transcription service protocol
protocol StreamingTranscriptionService: TranscriptionService {
    /// Start streaming transcription
    /// - Parameters:
    ///   - audioStream: Async stream of audio segments
    ///   - config: Transcription configuration
    /// - Returns: Stream of transcription segments
    func transcribeStream(
        audio: AsyncThrowingStream<AudioSegment, Error>,
        configuration: TranscriptionConfiguration
    ) async throws -> AsyncStream<TranscriptionSegment>
    
    /// Stop the current streaming session
    func stopStreaming() async
    
    /// Current streaming state
    var isStreaming: Bool { get }
    
    /// Flush pending audio and get final results
    func flush() async throws -> [TranscriptionSegment]
}

// MARK: - Batch Transcription

/// Batch transcription result
struct BatchTranscriptionResult: Sendable {
    let transcriptID: TranscriptID
    let segments: [TranscriptionSegment]
    let language: String
    let processingTime: Duration
    let speakers: [Speaker]?
}

/// Progress update for batch transcription
struct BatchProgress: Sendable {
    let phase: BatchPhase
    let progress: Double // 0.0 - 1.0
    let estimatedTimeRemaining: Duration?
}

enum BatchPhase: Sendable {
    case loadingAudio
    case preprocessing
    case transcribing
    case postprocessing
    case finalizing
}

/// Batch transcription service protocol
protocol BatchTranscriptionService: TranscriptionService {
    /// Transcribe an audio file
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - config: Transcription configuration
    /// - Returns: Transcription result with progress
    func transcribeFile(
        at audioURL: URL,
        configuration: TranscriptionConfiguration
    ) async throws -> BatchTranscriptionResult
    
    /// Transcribe with progress reporting
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - config: Transcription configuration
    /// - Returns: Async sequence of progress updates and final result
    func transcribeFileWithProgress(
        at audioURL: URL,
        configuration: TranscriptionConfiguration
    ) -> AsyncThrowingStream<BatchProgressUpdate, Error>
}

/// Union type for batch progress stream
enum BatchProgressUpdate: Sendable {
    case progress(BatchProgress)
    case result(BatchTranscriptionResult)
}

// MARK: - Configuration

/// Base configuration for all transcription backends
struct TranscriptionConfiguration: Sendable {
    /// Language code (ISO 639-1, e.g., "en", "es")
    let language: String
    
    /// Audio format information
    let audioFormat: AudioFormatInfo
    
    /// Enable speaker diarization
    let enableDiarization: Bool
    
    /// Number of speakers (if diarization enabled, nil = auto-detect)
    let speakerCount: Int?
    
    /// Enable word-level timestamps
    let wordTimestamps: Bool
    
    /// Vocabulary hints for better recognition
    let vocabularyHints: [String]
    
    /// Backend-specific overrides
    let backendSpecific: [String: SendableValue]
    
    /// Quality/speed tradeoff
    let quality: TranscriptionQuality
    
    /// Timeout for transcription operations
    let timeout: Duration
}

enum TranscriptionQuality: String, Sendable, CaseIterable {
    case fast       // Prioritize speed
    case balanced   // Default balance
    case accurate   // Prioritize accuracy
}

/// Type-erased sendable value for backend-specific config
struct SendableValue: Sendable {
    private let _value: Any
    private let _encode: (Encoder) throws -> Void
    
    init<T: Codable & Sendable>(_ value: T) {
        self._value = value
        self._encode = { encoder in
            try value.encode(to: encoder)
        }
    }
}

/// Audio format information
struct AudioFormatInfo: Sendable {
    let sampleRate: Double
    let channels: Int
    let bitsPerSample: Int
    let format: AudioCodec
}

enum AudioCodec: String, Sendable, Codable {
    case pcm
    case wav
    case aac
    case flac
    case mp3
    case ogg
}

// MARK: - Backend-Specific Configurations

/// MLX-specific configuration
struct MLXConfiguration: Sendable {
    /// Model to use (e.g., "whisper-tiny", "whisper-base")
    let modelName: String
    
    /// Quantization level for memory/performance tradeoff
    let quantization: MLXQuantization
    
    /// Compute device preference
    let computeDevice: MLXComputeDevice
    
    /// Batch size for processing
    let batchSize: Int
    
    /// Thread count (0 = auto)
    let threadCount: Int
}

enum MLXQuantization: String, Sendable, Codable {
    case none
    case q4_0
    case q4_1
    case q5_0
    case q5_1
    case q8_0
}

enum MLXComputeDevice: String, Sendable, Codable {
    case cpu
    case gpu
    case neuralEngine
    case auto
}

/// WhisperKit-specific configuration
struct WhisperKitConfiguration: Sendable {
    /// Model variant
    let model: WhisperModel
    
    /// Whether to use CoreML-optimized models
    let useCoreML: Bool
    
    /// Audio compression format
    let compression: AudioCompression?
}

enum WhisperModel: String, Sendable, Codable {
    case tiny
    case base
    case small
    case medium
    case large_v1
    case large_v2
    case large_v3
}

enum AudioCompression: String, Sendable, Codable {
    case none
    case aac
    case flac
    case opus
}

/// Cloud API configuration (AssemblyAI, etc.)
struct CloudConfiguration: Sendable {
    /// API endpoint URL
    let endpoint: URL
    
    /// API key (stored securely in Keychain)
    let apiKeyReference: String
    
    /// Polling interval for status checks
    let pollingInterval: Duration
    
    /// Maximum retry attempts
    let maxRetries: Int
    
    /// Webhook URL for completion (optional)
    let webhookURL: URL?
}

// MARK: - Backend Implementations (Protocol Conformance)

/// MLX streaming transcription implementation
protocol MLXStreamingTranscriptionService: StreamingTranscriptionService {
    var mlxConfig: MLXConfiguration { get set }
    
    /// Preload a model for faster startup
    func preloadModel(_ modelName: String) async throws
    
    /// Unload model to free memory
    func unloadModel() async
    
    /// Current loaded model
    var loadedModel: String? { get }
}

/// WhisperKit streaming transcription implementation
protocol WhisperKitStreamingTranscriptionService: StreamingTranscriptionService {
    var whisperKitConfig: WhisperKitConfiguration { get set }
    
    /// Switch to a different CoreML model
    func switchModel(_ model: WhisperModel) async throws
    
    /// Export CoreML model if not cached
    func exportCoreMLModel(_ model: WhisperModel) async throws -> URL
}

/// AssemblyAI streaming implementation
protocol AssemblyAIStreamingTranscriptionService: StreamingTranscriptionService {
    var assemblyConfig: CloudConfiguration { get set }
    
    /// Connect to real-time WebSocket endpoint
    func connectWebSocket() async throws
    
    /// Disconnect WebSocket
    func disconnectWebSocket() async
    
    /// Current WebSocket connection state
    var webSocketState: WebSocketState { get }
}

enum WebSocketState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(Error)
}

/// Parakeet batch transcription (local MLX-based)
protocol ParakeetBatchTranscriptionService: BatchTranscriptionService {
    var parakeetConfig: MLXConfiguration { get set }
    
    /// Transcribe multiple files in parallel
    func transcribeFiles(
        _ urls: [URL],
        configuration: TranscriptionConfiguration
    ) async throws -> [BatchTranscriptionResult]
}

// MARK: - Error Mapping

/// Maps backend-specific errors to domain errors
protocol TranscriptionErrorMapper: Sendable {
    func map(_ backendError: Error, backend: BackendID) -> TranscriptionError
}

// MARK: - Factory & Registration

/// Factory for creating transcription service instances
protocol TranscriptionServiceFactory: Sendable {
    /// Create a streaming service for the given backend
    func makeStreamingService(backend: BackendID) throws -> any StreamingTranscriptionService
    
    /// Create a batch service for the given backend
    func makeBatchService(backend: BackendID) throws -> any BatchTranscriptionService
    
    /// Register a custom backend implementation
    func registerStreaming(
        backend: BackendID,
        factory: @escaping () -> any StreamingTranscriptionService
    )
    
    /// Register a custom batch backend
    func registerBatch(
        backend: BackendID,
        factory: @escaping () -> any BatchTranscriptionService
    )
    
    /// Available backend IDs
    var availableBackends: [BackendID] { get }
}

// MARK: - Service Aggregator

/// Aggregates multiple transcription services for backend switching
protocol TranscriptionServiceAggregator: Sendable {
    /// All registered services
    var services: [any TranscriptionService] { get }
    
    /// Current primary service
    var primaryService: any TranscriptionService { get set }
    
    /// Fallback service chain (tried in order if primary fails)
    var fallbackChain: [any TranscriptionService] { get set }
    
    /// Get best available service based on criteria
    /// - Parameters:
    ///   - requiresStreaming: Whether streaming is required
    ///   - requiresDiarization: Whether diarization is required
    ///   - preferredLatency: Maximum acceptable latency
    /// - Returns: Best matching service, or nil if none match
    func bestService(
        streaming: Bool,
        diarization: Bool,
        maxLatency: Duration?
    ) async -> (any TranscriptionService)?
}

// MARK: - Metrics & Monitoring

/// Metrics for transcription operations
struct TranscriptionMetrics: Sendable {
    let backendID: BackendID
    let operationType: TranscriptionOperationType
    let duration: Duration
    let audioDuration: Duration?
    let confidence: Double?
    let error: TranscriptionError?
    let timestamp: Date
}

enum TranscriptionOperationType: String, Sendable {
    case streamingStart
    case streamingSegment
    case streamingStop
    case batchTranscribe
    case modelLoad
    case modelUnload
}

/// Protocol for metrics collection
protocol TranscriptionMetricsCollector: Sendable {
    func record(_ metrics: TranscriptionMetrics) async
    func averageLatency(backend: BackendID) async -> Duration?
    func errorRate(backend: BackendID, timeframe: Duration) async -> Double
}
```

## Backend Protocol Hierarchy Diagram

```
TranscriptionService (base)
├── StreamingTranscriptionService
│   ├── MLXStreamingTranscriptionService
│   ├── WhisperKitStreamingTranscriptionService
│   └── AssemblyAIStreamingTranscriptionService
├── BatchTranscriptionService
│   ├── MLXBatchTranscriptionService
│   ├── WhisperKitBatchTranscriptionService
│   └── ParakeetBatchTranscriptionService
```

## Key Design Decisions

### 1. Capability-Based Detection
Services advertise capabilities via `TranscriptionCapabilities` rather than type checking. This allows:
- Runtime capability detection
- Feature negotiation between layers
- Graceful degradation when features unavailable

### 2. AsyncStream for Streaming
Streaming transcription returns `AsyncStream<TranscriptionSegment>`:
- Natural Swift concurrency pattern
- Backpressure handling built-in
- Cancellation propagation
- No callback hell

### 3. Progress Reporting for Batch
Batch operations support progress streams:
- UI can show transcription progress
- Estimated time remaining
- Phase indicators (loading → transcribing → finalizing)

### 4. Backend-Specific Config Types
Each backend has its own strongly-typed configuration:
- MLXConfiguration for MLX-specific settings
- WhisperKitConfiguration for CoreML options
- CloudConfiguration for API endpoints

Base `TranscriptionConfiguration` contains common settings, backend-specific settings stored in type-safe extensions.

### 5. Factory Pattern for Creation
`TranscriptionServiceFactory` abstracts backend instantiation:
- Dependency injection support
- Easy to add new backends
- Test double injection for mocks

## Error Handling Strategy

```swift
// Backend errors are mapped to domain errors
let domainError = errorMapper.map(backendError, backend: .mlx)

// Domain errors are unified across backends
switch domainError {
case .backendFailed(let backend, let reason, let recoverable):
    if recoverable { retry() } else { showFatalError(reason) }
case .networkUnavailable:
    showOfflineError()
case .modelNotFound(let model):
    showModelDownloadPrompt(model)
}
```

## Formal Properties

- **SAFETY**: Backend failures don't crash the app - all errors map to domain errors
- **LIVENESS**: Backend switching doesn't lose in-progress transcription (state preserved)
- **INVARIANT**: All service protocols are Sendable-safe for Swift 6.2 concurrency

