import Foundation

// MARK: - Base Transcription Service

/// Base protocol for all transcription services.
/// Defines the common interface that all transcription backends must implement.
public protocol TranscriptionService: Sendable {
    /// Unique identifier for this transcription backend.
    var backendID: BackendID { get }
    
    /// Human-readable display name for UI presentation.
    var displayName: String { get }
    
    /// Check if the service is available for use.
    /// - Returns: true if backend is installed/configured and ready.
    func isAvailable() async -> Bool
    
    /// Get the list of supported audio formats.
    var supportedFormats: [AudioFormat] { get }
    
    /// Get the list of supported languages.
    var supportedLanguages: [LanguageCode] { get }
    
    /// Validate audio file format without transcribing.
    /// - Parameter audioURL: URL to the audio file.
    /// - Returns: Validation result indicating if the file is valid and its properties.
    func validateAudioFile(_ audioURL: URL) async -> ValidationResult
}

// MARK: - Streaming Transcription Service

/// Protocol for real-time streaming transcription.
/// Extends the base TranscriptionService with streaming capabilities.
public protocol StreamingTranscriptionService: TranscriptionService {
    /// Configuration for streaming behavior.
    var streamingConfiguration: StreamingConfiguration { get set }
    
    /// Start streaming transcription from an audio stream.
    /// - Parameters:
    ///   - audioStream: Async stream of audio buffers.
    ///   - language: Target language code (nil = auto-detect).
    /// - Returns: Async stream of transcription segments.
    func transcribeStream(
        _ audioStream: AsyncStream<AudioBuffer>,
        language: LanguageCode?
    ) -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError>
    
    /// Start streaming transcription from microphone (convenience method).
    /// - Parameters:
    ///   - audioCaptureService: Service providing microphone audio.
    ///   - language: Target language code.
    /// - Returns: Async stream of transcription segments.
    func transcribeFromMicrophone(
        using audioCaptureService: AudioCaptureService,
        language: LanguageCode?
    ) async throws -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError>
}

// MARK: - Batch Transcription Service

/// Protocol for file-based batch transcription.
/// Extends the base TranscriptionService with batch processing capabilities.
public protocol BatchTranscriptionService: TranscriptionService {
    /// Transcribe an audio file.
    /// - Parameters:
    ///   - audioURL: URL to the audio file.
    ///   - language: Target language code (nil = auto-detect).
    ///   - speakerDiarization: Whether to identify different speakers.
    ///   - progressHandler: Callback for progress updates (optional).
    /// - Returns: Full transcription result.
    func transcribeFile(
        at audioURL: URL,
        language: LanguageCode?,
        speakerDiarization: Bool,
        progressHandler: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> BatchTranscriptionResult
    
    /// Estimate transcription time for an audio file.
    /// - Parameter audioURL: URL to the audio file.
    /// - Returns: Estimated processing time.
    func estimateProcessingTime(for audioURL: URL) async -> Duration
    
    /// Check if speaker diarization is supported.
    var supportsSpeakerDiarization: Bool { get }
}

// MARK: - Supporting Types

/// Result of audio file validation.
public struct ValidationResult: Sendable, Equatable {
    public let isValid: Bool
    public let format: AudioFormat?
    public let duration: Duration?
    public let error: AudioError?
    
    public init(
        isValid: Bool,
        format: AudioFormat?,
        duration: Duration?,
        error: AudioError?
    ) {
        self.isValid = isValid
        self.format = format
        self.duration = duration
        self.error = error
    }
    
    public static let valid = ValidationResult(
        isValid: true,
        format: nil,
        duration: nil,
        error: nil
    )
    
    public static func invalid(error: AudioError) -> ValidationResult {
        ValidationResult(
            isValid: false,
            format: nil,
            duration: nil,
            error: error
        )
    }
}

/// ISO 639-1 language code wrapper.
public struct LanguageCode: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }
    
    public var description: String { rawValue }
    
    // Common languages
    public static let english = LanguageCode(rawValue: "en")
    public static let spanish = LanguageCode(rawValue: "es")
    public static let french = LanguageCode(rawValue: "fr")
    public static let german = LanguageCode(rawValue: "de")
    public static let italian = LanguageCode(rawValue: "it")
    public static let portuguese = LanguageCode(rawValue: "pt")
    public static let chinese = LanguageCode(rawValue: "zh")
    public static let japanese = LanguageCode(rawValue: "ja")
    public static let korean = LanguageCode(rawValue: "ko")
    public static let arabic = LanguageCode(rawValue: "ar")
    public static let hindi = LanguageCode(rawValue: "hi")
    public static let russian = LanguageCode(rawValue: "ru")
    public static let autoDetect = LanguageCode(rawValue: "auto")
}

/// A single transcription segment emitted during streaming.
public struct TranscriptionSegment: Sendable, Identifiable, Equatable {
    public let id: UtteranceID
    public let text: String
    public let startTime: Duration
    public let endTime: Duration
    public let confidence: Double
    public let isPartial: Bool
    public let speakerID: SpeakerID?
    public let language: LanguageCode?
    
    public init(
        id: UtteranceID,
        text: String,
        startTime: Duration,
        endTime: Duration,
        confidence: Double,
        isPartial: Bool,
        speakerID: SpeakerID? = nil,
        language: LanguageCode? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isPartial = isPartial
        self.speakerID = speakerID
        self.language = language
    }
    
    /// Mark this segment as finalized (no longer partial).
    public func finalized() -> TranscriptionSegment {
        TranscriptionSegment(
            id: id,
            text: text,
            startTime: startTime,
            endTime: endTime,
            confidence: confidence,
            isPartial: false,
            speakerID: speakerID,
            language: language
        )
    }
}

/// Result of batch transcription.
public struct BatchTranscriptionResult: Sendable, Equatable {
    public let transcriptID: TranscriptID
    public let segments: [TranscriptionSegment]
    public let fullText: String
    public let language: LanguageCode
    public let duration: Duration
    public let processingTime: Duration
    
    public init(
        transcriptID: TranscriptID,
        segments: [TranscriptionSegment],
        fullText: String,
        language: LanguageCode,
        duration: Duration,
        processingTime: Duration
    ) {
        self.transcriptID = transcriptID
        self.segments = segments
        self.fullText = fullText
        self.language = language
        self.duration = duration
        self.processingTime = processingTime
    }
    
    /// Get segments organized by speaker.
    public func segmentsBySpeaker() -> [SpeakerID: [TranscriptionSegment]] {
        var result: [SpeakerID: [TranscriptionSegment]] = [:]
        for segment in segments {
            if let speakerID = segment.speakerID {
                result[speakerID, default: []].append(segment)
            }
        }
        return result
    }
}

/// Progress update during batch transcription.
public struct TranscriptionProgress: Sendable, Equatable {
    public let audioProcessed: Duration
    public let totalDuration: Duration
    public let percentage: Double
    public let estimatedTimeRemaining: Duration?
    
    public init(
        audioProcessed: Duration,
        totalDuration: Duration,
        percentage: Double,
        estimatedTimeRemaining: Duration?
    ) {
        self.audioProcessed = audioProcessed
        self.totalDuration = totalDuration
        self.percentage = percentage
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
    
    public var isComplete: Bool { percentage >= 1.0 }
}

/// Configuration for streaming transcription.
public struct StreamingConfiguration: Sendable, Equatable {
    /// Minimum confidence threshold for emitting segments (0.0-1.0).
    public var confidenceThreshold: Double
    
    /// VAD (Voice Activity Detection) sensitivity.
    public var vadSensitivity: VADSensitivity
    
    /// Buffer size for streaming (in seconds of audio).
    public var bufferDuration: Duration
    
    /// Whether to emit partial results (may be lower confidence).
    public var enablePartialResults: Bool
    
    /// Maximum time to wait for a segment before emitting partial.
    public var maxSegmentWait: Duration
    
    /// Minimum audio length to trigger transcription.
    public var minAudioLength: Duration
    
    public init(
        confidenceThreshold: Double = 0.7,
        vadSensitivity: VADSensitivity = .medium,
        bufferDuration: Duration = .seconds(30),
        enablePartialResults: Bool = true,
        maxSegmentWait: Duration = .seconds(2),
        minAudioLength: Duration = .milliseconds(500)
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.vadSensitivity = vadSensitivity
        self.bufferDuration = bufferDuration
        self.enablePartialResults = enablePartialResults
        self.maxSegmentWait = maxSegmentWait
        self.minAudioLength = minAudioLength
    }
}

/// VAD sensitivity levels.
public enum VADSensitivity: String, Sendable, Equatable, Codable {
    case low      // Less sensitive, fewer false positives
    case medium   // Balanced
    case high     // More sensitive, catches quiet speech
}

// Note: AudioFormat is defined in Domain/Entities/AudioSegment.swift

/// LLM Provider identifiers.
public struct LLMProviderID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public static let openRouter = LLMProviderID("openrouter")
    public static let ollama = LLMProviderID("ollama")
    public static let openAI = LLMProviderID("openai")
    public static let anthropic = LLMProviderID("anthropic")
}

/// Embedding Provider identifiers.
public struct EmbeddingProviderID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public static let voyage = EmbeddingProviderID("voyage")
    public static let ollama = EmbeddingProviderID("ollama")
    public static let openAI = EmbeddingProviderID("openai")
}

/// Common configuration for all transcription backends.
/// Note: Named TranscriptionBackendConfiguration to avoid conflict with internal TranscriptionConfiguration.
public struct TranscriptionBackendConfiguration: Sendable, Equatable {
    public let language: LanguageCode
    public let model: String
    public let quality: TranscriptionQuality

    public init(
        language: LanguageCode = .autoDetect,
        model: String = "default",
        quality: TranscriptionQuality = .balanced
    ) {
        self.language = language
        self.model = model
        self.quality = quality
    }
}

/// Transcription quality levels.
public enum TranscriptionQuality: String, Sendable, Equatable, Codable {
    case fast     // Lower quality, faster processing
    case balanced // Default
    case accurate // Higher quality, slower processing
}

/// MLX-specific configuration.
public struct MLXConfiguration: Sendable, Equatable {
    public let modelPath: String
    public let quantization: MLXQuantization
    public let useGPU: Bool
    public let memoryLimitMB: Int?
    
    public init(
        modelPath: String,
        quantization: MLXQuantization = .q4,
        useGPU: Bool = true,
        memoryLimitMB: Int? = nil
    ) {
        self.modelPath = modelPath
        self.quantization = quantization
        self.useGPU = useGPU
        self.memoryLimitMB = memoryLimitMB
    }
}

/// MLX quantization levels.
public enum MLXQuantization: String, Sendable, Equatable, Codable {
    case q8 = "q8"
    case q4 = "q4"
    case q2 = "q2"
    case none = "none"
}

/// WhisperKit-specific configuration.
public struct WhisperKitConfiguration: Sendable, Equatable {
    public let model: String
    public let computeUnits: ComputeUnits
    public let enableTimestamps: Bool
    
    public init(
        model: String = "small",
        computeUnits: ComputeUnits = .cpuAndNeuralEngine,
        enableTimestamps: Bool = true
    ) {
        self.model = model
        self.computeUnits = computeUnits
        self.enableTimestamps = enableTimestamps
    }
}

/// Compute unit options.
public enum ComputeUnits: String, Sendable, Equatable, Codable {
    case cpuOnly = "cpuOnly"
    case cpuAndGPU = "cpuAndGPU"
    case cpuAndNeuralEngine = "cpuAndNeuralEngine"
    case all = "all"
}

/// Cloud API configuration.
public struct CloudConfiguration: Sendable, Equatable {
    public let apiKey: String
    public let endpoint: URL?
    public let timeout: Duration
    public let retryPolicy: RetryPolicy
    
    public init(
        apiKey: String,
        endpoint: URL? = nil,
        timeout: Duration = .seconds(30),
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.timeout = timeout
        self.retryPolicy = retryPolicy
    }
}

/// Retry policy configuration.
public struct RetryPolicy: Sendable, Equatable {
    public let maxRetries: Int
    public let retryDelay: Duration
    public let exponentialBackoff: Bool
    
    public init(
        maxRetries: Int = 3,
        retryDelay: Duration = .seconds(1),
        exponentialBackoff: Bool = true
    ) {
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.exponentialBackoff = exponentialBackoff
    }
}
