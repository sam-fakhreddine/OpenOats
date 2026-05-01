# MLX Backend Implementation Findings

**Agent**: Stream 6B: MLX Backend Implementation Agent  
**Date**: 2026-05-01

## Codebase Structure

### TranscriptionService Protocol (Infrastructure/Protocols/TranscriptionService.swift)
```swift
public protocol TranscriptionService: Sendable {
    var backendID: BackendID { get }
    var displayName: String { get }
    func isAvailable() async -> Bool
    var supportedFormats: [AudioFormat] { get }
    var supportedLanguages: [LanguageCode] { get }
    func validateAudioFile(_ audioURL: URL) async -> ValidationResult
}

public protocol StreamingTranscriptionService: TranscriptionService {
    var streamingConfiguration: StreamingConfiguration { get set }
    func transcribeStream(_ audioStream: AsyncStream<AudioBuffer>, language: LanguageCode?) 
        -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError>
    func transcribeFromMicrophone(using audioCaptureService: AudioCaptureService, language: LanguageCode?) 
        async throws -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError>
}

public protocol BatchTranscriptionService: TranscriptionService {
    func transcribeFile(at audioURL: URL, language: LanguageCode?, speakerDiarization: Bool, 
        progressHandler: (@Sendable (TranscriptionProgress) -> Void)?) async throws -> BatchTranscriptionResult
    func estimateProcessingTime(for audioURL: URL) async -> Duration
    var supportsSpeakerDiarization: Bool { get }
}
```

### MLXConfiguration (from protocol)
```swift
public struct MLXConfiguration: Sendable, Equatable {
    public let modelPath: String
    public let quantization: MLXQuantization
    public let useGPU: Bool
    public let memoryLimitMB: Int?
}

public enum MLXQuantization: String, Sendable, Equatable, Codable {
    case q8 = "q8"
    case q4 = "q4"
    case q2 = "q2"
    case none = "none"
}
```

### Existing MLX Code (feat/mlx-audio-and-model-storage)
From MLXWhisperBackend.swift:
- Uses `mlx-community/GLM-ASR-Nano-2512-4bit` model
- Model loading via `GLMASRModel.fromPretrained()`
- Transcription via `model.generate(audio: mlxArray)`
- MLXArray conversion from Float samples

### Domain Errors (TranscriptionError)
```swift
public enum TranscriptionError: Error, Sendable, Equatable {
    case backendFailed(backend: String, reason: String, recoverable: Bool)
    case audioFormatUnsupported(format: String, supportedFormats: [String])
    case timeout(operation: String, duration: Duration)
    case modelUnavailable(model: String, reason: String)
    case networkFailure(reason: String)
    case rateLimited(provider: String, retryAfter: Date?)
}
```

### AudioBuffer (from AudioCaptureService)
```swift
public struct AudioBuffer: Sendable, Equatable, Identifiable {
    public let samples: [Float]
    public let sampleRate: Double
    public let channelCount: Int
    public let timestamp: Duration
    public let id: AudioSegmentID
}
```

### TranscriptionSegment (from protocol)
```swift
public struct TranscriptionSegment: Sendable, Identifiable, Equatable {
    public let id: UtteranceID
    public let text: String
    public let startTime: Duration
    public let endTime: Duration
    public let confidence: Double
    public let isPartial: Bool
    public let speakerID: SpeakerID?
    public let language: LanguageCode?
}
```

## MLX Audio Requirements
- Input: Float32 samples at 16kHz mono
- MLX models: GLMASRModel, ParakeetModel, GraniteSpeechModel
- MLXArray for input
- GPU acceleration via Metal

## Model Download Strategy
- 5MB chunks for optimal balance
- 6 concurrent downloads for efficiency
- Resume capability via HTTP Range headers
- Progress reporting via AsyncStream
