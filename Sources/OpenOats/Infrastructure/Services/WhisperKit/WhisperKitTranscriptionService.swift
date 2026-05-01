import Foundation
import WhisperKit
import AVFoundation

// MARK: - WhisperKit Service Errors

/// Errors specific to WhisperKit transcription service.
public enum WhisperKitServiceError: Error, LocalizedError, Sendable {
    /// Model has not been loaded yet.
    case modelNotLoaded
    
    /// Audio format is not supported.
    case audioFormatNotSupported(format: String)
    
    /// Transcription operation timed out.
    case transcriptionTimeout
    
    /// Audio processing failed.
    case audioProcessingFailed(reason: String)
    
    /// CoreML execution error.
    case coreMLError(underlying: Error)
    
    /// Model download failed.
    case modelDownloadFailed(reason: String)
    
    /// Invalid configuration.
    case invalidConfiguration(String)
    
    /// Transcription in progress cannot be started.
    case transcriptionInProgress
    
    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "WhisperKit model has not been loaded. Call prepare() first."
        case .audioFormatNotSupported(let format):
            return "Audio format '\(format)' is not supported by WhisperKit"
        case .transcriptionTimeout:
            return "Transcription operation timed out"
        case .audioProcessingFailed(let reason):
            return "Audio processing failed: \(reason)"
        case .coreMLError(let error):
            return "CoreML execution error: \(error.localizedDescription)"
        case .modelDownloadFailed(let reason):
            return "Model download failed: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .transcriptionInProgress:
            return "Transcription is already in progress"
        }
    }
}

// MARK: - WhisperKit Transcription Service

/// Actor-based transcription service using WhisperKit.
/// Implements both StreamingTranscriptionService and BatchTranscriptionService protocols.
@preconcurrency public actor WhisperKitTranscriptionService: TranscriptionService, StreamingTranscriptionService, BatchTranscriptionService {
    
    // MARK: - TranscriptionService Protocol Properties
    
    public nonisolated let backendID: BackendID = .whisperKit
    public nonisolated let displayName: String = "WhisperKit"
    public nonisolated let supportedFormats: [AudioFormat] = [.wav, .mp3, .aac, .flac]
    public nonisolated let supportedLanguages: [LanguageCode] = [
        .english, .spanish, .french, .german, .italian,
        .portuguese, .chinese, .japanese, .korean,
        .arabic, .hindi, .russian, .autoDetect
    ]
    
    // MARK: - StreamingTranscriptionService Protocol Properties
    
    public var streamingConfiguration: StreamingConfiguration = StreamingConfiguration()
    
    // MARK: - BatchTranscriptionService Protocol Properties
    
    public nonisolated var supportsSpeakerDiarization: Bool { false }
    
    // MARK: - Private Properties
    
    /// WhisperKit pipeline instance.
    private var whisperKit: WhisperKit?
    
    /// Audio processor for format conversion.
    private let audioProcessor: WhisperKitAudioProcessor
    
    /// Service configuration.
    private let configuration: WhisperKitConfiguration
    
    /// Whether the service is currently available (model loaded).
    private var isModelLoaded: Bool = false
    
    /// Current transcription task for cancellation.
    private var currentTranscriptionTask: Task<Void, Never>?
    
    /// Download progress handler.
    private var downloadProgressHandler: (@Sendable (Double) -> Void)?
    
    /// Status update handler.
    private var statusHandler: (@Sendable (String) -> Void)?
    
    // MARK: - Initialization
    
    /// Creates a new WhisperKit transcription service.
    /// - Parameter configuration: Service configuration (default: standard)
    public init(configuration: WhisperKitConfiguration = WhisperKitConfiguration()) {
        self.configuration = configuration
        self.audioProcessor = WhisperKitAudioProcessor(configuration: configuration)
    }
    
    // MARK: - TranscriptionService Protocol Methods
    
    /// Checks if the service is available for transcription.
    /// - Returns: true if the model is loaded and ready
    public func isAvailable() async -> Bool {
        return isModelLoaded && whisperKit != nil
    }
    
    /// Validates an audio file without transcribing.
    /// - Parameter audioURL: URL to the audio file
    /// - Returns: Validation result
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        // Check file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            return .invalid(error: .fileNotFound(audioURL))
        }
        
        // Check format
        let ext = audioURL.pathExtension.lowercased()
        let format: AudioFormat
        switch ext {
        case "wav": format = .wav
        case "mp3": format = .mp3
        case "aac", "m4a": format = .aac
        case "flac": format = .flac
        default:
            return ValidationResult(
                isValid: false,
                format: nil,
                duration: nil,
                error: .formatNotSupported(ext)
            )
        }
        
        // Try to get duration
        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            
            return ValidationResult(
                isValid: true,
                format: format,
                duration: .seconds(duration),
                error: nil
            )
        } catch {
            return ValidationResult(
                isValid: false,
                format: format,
                duration: nil,
                error: .decodingFailed(error.localizedDescription)
            )
        }
    }
    
    // MARK: - StreamingTranscriptionService Protocol Methods
    
    /// Starts streaming transcription from an audio stream.
    /// - Parameters:
    ///   - audioStream: Async stream of audio buffers
    ///   - language: Target language code (nil = auto-detect)
    /// - Returns: Async stream of transcription segments
    public nonisolated func transcribeStream(
        _ audioStream: AsyncStream<AudioBuffer>,
        language: LanguageCode?
    ) -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError> {
        AsyncThrowingStream { continuation in
            Task {
                await self.performStreamingTranscription(
                    audioStream: audioStream,
                    language: language,
                    continuation: continuation
                )
            }
        }
    }
    
    /// Starts streaming transcription from microphone capture.
    /// - Parameters:
    ///   - audioCaptureService: Service providing microphone audio
    ///   - language: Target language code
    /// - Returns: Async stream of transcription segments
    public func transcribeFromMicrophone(
        using audioCaptureService: AudioCaptureService,
        language: LanguageCode?
    ) async throws -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError> {
        let audioStream = try await audioCaptureService.startCapture()
        return transcribeStream(audioStream, language: language)
    }
    
    // MARK: - BatchTranscriptionService Protocol Methods
    
    /// Transcribes an audio file.
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - language: Target language code (nil = auto-detect)
    ///   - speakerDiarization: Whether to identify speakers (not supported)
    ///   - progressHandler: Callback for progress updates
    /// - Returns: Full transcription result
    public func transcribeFile(
        at audioURL: URL,
        language: LanguageCode?,
        speakerDiarization: Bool,
        progressHandler: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> BatchTranscriptionResult {
        guard let whisperKit = whisperKit else {
            throw mapError(.modelNotLoaded)
        }
        
        let startTime = Date()
        
        // Process audio file
        statusHandler?("Processing audio...")
        let processedAudio = try await audioProcessor.processAudioFile(at: audioURL)
        
        progressHandler?(TranscriptionProgress(
            audioProcessed: .seconds(0),
            totalDuration: .seconds(processedAudio.duration),
            percentage: 0.0,
            estimatedTimeRemaining: nil
        ))
        
        // Perform transcription
        statusHandler?("Transcribing...")
        let languageCode = language?.rawValue
        
        let options = DecodingOptions(
            language: languageCode,
            wordTimestamps: configuration.enableTimestamps,
            promptTokens: nil
        )
        
        let results = try await whisperKit.transcribe(
            audioArray: processedAudio.samples,
            decodeOptions: options
        )
        
        // Build segments
        let segments = results.enumerated().map { index, result in
            TranscriptionSegment(
                id: UtteranceID(),
                text: result.text,
                startTime: .seconds(result.start),
                endTime: .seconds(result.end),
                confidence: result.confidence,
                isPartial: false,
                speakerID: nil,
                language: language
            )
        }
        
        let fullText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let processingTime = Date().timeIntervalSince(startTime)
        
        progressHandler?(TranscriptionProgress(
            audioProcessed: .seconds(processedAudio.duration),
            totalDuration: .seconds(processedAudio.duration),
            percentage: 1.0,
            estimatedTimeRemaining: .seconds(0)
        ))
        
        return BatchTranscriptionResult(
            transcriptID: TranscriptID(),
            segments: segments,
            fullText: fullText,
            language: language ?? .autoDetect,
            duration: .seconds(processedAudio.duration),
            processingTime: .seconds(processingTime)
        )
    }
    
    /// Estimates transcription time for an audio file.
    /// - Parameter audioURL: URL to the audio file
    /// - Returns: Estimated processing time
    public func estimateProcessingTime(for audioURL: URL) async -> Duration {
        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            
            // Rough estimate: real-time factor of 0.5x (2x faster than real-time)
            // This varies by model size and hardware
            let estimate = duration * 0.5
            
            return .seconds(estimate)
        } catch {
            return .seconds(30) // Default estimate
        }
    }
    
    // MARK: - Service Lifecycle
    
    /// Prepares the service for use by downloading and loading the model.
    /// - Parameters:
    ///   - onStatus: Status update callback
    ///   - onProgress: Progress update callback (0.0-1.0)
    public func prepare(
        onStatus: @Sendable (String) -> Void,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        self.statusHandler = onStatus
        self.downloadProgressHandler = onProgress
        
        guard !isModelLoaded else {
            onStatus("Model already loaded")
            onProgress(1.0)
            return
        }
        
        onStatus("Downloading \(configuration.model) model (\(configuration.modelSizeEstimate))...")
        
        do {
            // Download model
            let modelFolder = try await WhisperKit.download(
                variant: configuration.model,
                from: WhisperKitConfiguration.modelRepo
            ) { progress in
                onProgress(progress.fractionCompleted)
            }
            
            onStatus("Loading model...")
            
            // Configure and load WhisperKit
            let config = WhisperKitConfig(
                model: configuration.model,
                modelRepo: WhisperKitConfiguration.modelRepo,
                modelFolder: modelFolder.path,
                computeOptions: MLComputeOptions(
                    audioEncoderCompute: configuration.computeUnits.whisperKitComputeOptions,
                    textDecoderCompute: configuration.computeUnits.whisperKitComputeOptions
                ),
                verbose: false,
                prewarm: configuration.prewarmModel,
                download: false
            )
            
            let whisperKit = try await WhisperKit(config)
            self.whisperKit = whisperKit
            self.isModelLoaded = true
            
            onStatus("Model ready")
            onProgress(1.0)
            
        } catch {
            throw mapError(.modelDownloadFailed(reason: error.localizedDescription))
        }
    }
    
    /// Cleans up resources and unloads the model.
    public func cleanup() async {
        // Cancel any ongoing transcription
        currentTranscriptionTask?.cancel()
        currentTranscriptionTask = nil
        
        // Release model
        whisperKit = nil
        isModelLoaded = false
        
        // Clear handlers
        statusHandler = nil
        downloadProgressHandler = nil
    }
    
    /// Clears cached model files.
    public func clearModelCache() async {
        let fm = FileManager.default
        guard let documentsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let hfCacheDir = documentsDir
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
        
        guard let contents = try? fm.contentsOfDirectory(atPath: hfCacheDir.path) else { return }
        
        for entry in contents where entry.contains(configuration.modelIdentifier) {
            try? fm.removeItem(at: hfCacheDir.appendingPathComponent(entry))
        }
    }
    
    // MARK: - Error Mapping
    
    /// Maps WhisperKit-specific errors to common TranscriptionError.
    /// - Parameter error: WhisperKit service error
    /// - Returns: Common transcription error
    public func mapError(_ error: WhisperKitServiceError) -> TranscriptionError {
        switch error {
        case .modelNotLoaded:
            return .modelUnavailable(
                model: configuration.model,
                reason: "Model has not been loaded. Call prepare() first."
            )
        case .audioFormatNotSupported(let format):
            return .audioFormatUnsupported(
                format: format,
                supportedFormats: ["wav", "mp3", "aac", "flac"]
            )
        case .transcriptionTimeout:
            return .timeout(
                operation: "transcription",
                duration: .seconds(60)
            )
        case .audioProcessingFailed(let reason):
            return .backendFailed(
                backend: "WhisperKit",
                reason: "Audio processing failed: \(reason)",
                recoverable: true
            )
        case .coreMLError(let underlying):
            return .backendFailed(
                backend: "WhisperKit",
                reason: "CoreML error: \(underlying.localizedDescription)",
                recoverable: true
            )
        case .modelDownloadFailed(let reason):
            return .modelUnavailable(
                model: configuration.model,
                reason: "Download failed: \(reason)"
            )
        case .invalidConfiguration(let reason):
            return .backendFailed(
                backend: "WhisperKit",
                reason: "Invalid configuration: \(reason)",
                recoverable: false
            )
        case .transcriptionInProgress:
            return .backendFailed(
                backend: "WhisperKit",
                reason: "Transcription already in progress",
                recoverable: true
            )
        }
    }
    
    // MARK: - Test Helpers
    
    /// Sets the streaming configuration (for testing).
    /// - Parameter configuration: New streaming configuration
    public func setStreamingConfiguration(_ configuration: StreamingConfiguration) {
        self.streamingConfiguration = configuration
    }
    
    // MARK: - Private Methods
    
    private func performStreamingTranscription(
        audioStream: AsyncStream<AudioBuffer>,
        language: LanguageCode?,
        continuation: AsyncThrowingStream<TranscriptionSegment, TranscriptionError>.Continuation
    ) async {
        guard let whisperKit = whisperKit else {
            continuation.finish(throwing: mapError(.modelNotLoaded))
            return
        }
        
        var accumulatedSamples: [Float] = []
        let minSamplesNeeded = Int(streamingConfiguration.minAudioLength.seconds * 16000)
        var segmentID = 0
        
        do {
            for try await buffer in audioStream {
                // Process buffer
                let samples = try await audioProcessor.processAudioBuffer(buffer)
                accumulatedSamples.append(contentsOf: samples)
                
                // Check if we have enough for transcription
                guard accumulatedSamples.count >= minSamplesNeeded else {
                    continue
                }
                
                // Transcribe accumulated audio
                let languageCode = language?.rawValue
                let options = DecodingOptions(
                    language: languageCode,
                    wordTimestamps: false,
                    promptTokens: nil
                )
                
                let results = try await whisperKit.transcribe(
                    audioArray: accumulatedSamples,
                    decodeOptions: options
                )
                
                // Emit segments
                for result in results {
                    let segment = TranscriptionSegment(
                        id: UtteranceID(),
                        text: result.text,
                        startTime: .seconds(result.start),
                        endTime: .seconds(result.end),
                        confidence: result.confidence,
                        isPartial: false,
                        speakerID: nil,
                        language: language
                    )
                    
                    continuation.yield(segment)
                }
                
                // Clear accumulated (or keep overlap for context)
                accumulatedSamples.removeAll(keepingCapacity: true)
                segmentID += 1
            }
            
            continuation.finish()
        } catch {
            let transcriptionError = (error as? TranscriptionError) ?? mapError(
                .audioProcessingFailed(reason: error.localizedDescription)
            )
            continuation.finish(throwing: transcriptionError)
        }
    }
}

// MARK: - Audio Error Types

/// Audio-related errors for validation.
public enum AudioError: Error, Sendable, Equatable {
    case fileNotFound(URL)
    case formatNotSupported(String)
    case decodingFailed(String)
    case invalidDuration
}

extension AudioError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Audio file not found: \(url.path)"
        case .formatNotSupported(let format):
            return "Audio format '\(format)' is not supported"
        case .decodingFailed(let reason):
            return "Failed to decode audio: \(reason)"
        case .invalidDuration:
            return "Invalid audio duration"
        }
    }
}

// MARK: - ML Compute Options

/// Compute options for CoreML execution.
public struct MLComputeOptions: Sendable {
    public let audioEncoderCompute: MLComputeUnits
    public let textDecoderCompute: MLComputeUnits
    
    public init(
        audioEncoderCompute: MLComputeUnits,
        textDecoderCompute: MLComputeUnits
    ) {
        self.audioEncoderCompute = audioEncoderCompute
        self.textDecoderCompute = textDecoderCompute
    }
}
