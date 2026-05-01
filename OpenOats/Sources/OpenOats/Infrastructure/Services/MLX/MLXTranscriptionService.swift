import Foundation
import MLX
import MLXAudioSTT
import Accelerate

// MARK: - MLX Configuration

/// Extended configuration for MLX transcription service.
public struct MLXServiceConfiguration: Sendable, Equatable {
    /// Base MLX configuration
    public let mlxConfiguration: MLXConfiguration
    
    /// Model repository to use
    public let modelRepository: String
    
    /// Custom model storage URL (nil = use default cache)
    public let customStorageURL: URL?
    
    /// Whether to use streaming mode
    public let enableStreaming: Bool
    
    /// Audio preprocessing configuration
    public let audioConfiguration: AudioProcessingConfiguration
    
    /// Download configuration
    public let downloadConfiguration: DownloadConfiguration
    
    public init(
        mlxConfiguration: MLXConfiguration = MLXConfiguration(
            modelPath: "mlx-community/GLM-ASR-Nano-2512-4bit",
            quantization: .q4,
            useGPU: true,
            memoryLimitMB: nil
        ),
        modelRepository: String = "mlx-community/GLM-ASR-Nano-2512-4bit",
        customStorageURL: URL? = nil,
        enableStreaming: Bool = true,
        audioConfiguration: AudioProcessingConfiguration = AudioProcessingConfiguration(),
        downloadConfiguration: DownloadConfiguration = DownloadConfiguration()
    ) {
        self.mlxConfiguration = mlxConfiguration
        self.modelRepository = modelRepository
        self.customStorageURL = customStorageURL
        self.enableStreaming = enableStreaming
        self.audioConfiguration = audioConfiguration
        self.downloadConfiguration = downloadConfiguration
    }
}

/// Audio processing configuration.
public struct AudioProcessingConfiguration: Sendable, Equatable {
    public let targetSampleRate: Double
    public let normalizeAudio: Bool
    public let minConfidenceThreshold: Double
    
    public init(
        targetSampleRate: Double = 16000,
        normalizeAudio: Bool = true,
        minConfidenceThreshold: Double = 0.7
    ) {
        self.targetSampleRate = targetSampleRate
        self.normalizeAudio = normalizeAudio
        self.minConfidenceThreshold = minConfidenceThreshold
    }
}

/// Download configuration.
public struct DownloadConfiguration: Sendable, Equatable {
    public let chunkSize: Int
    public let maxConcurrentDownloads: Int
    public let enableResume: Bool
    public let timeout: Duration
    
    public init(
        chunkSize: Int = 5 * 1024 * 1024, // 5MB
        maxConcurrentDownloads: Int = 6,
        enableResume: Bool = true,
        timeout: Duration = .seconds(300)
    ) {
        self.chunkSize = chunkSize
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.enableResume = enableResume
        self.timeout = timeout
    }
}

// MARK: - MLX Transcription Service

/// Actor-based MLX transcription service implementing TranscriptionService protocols.
/// Provides streaming and batch transcription using MLX models.
public actor MLXTranscriptionService: TranscriptionService, StreamingTranscriptionService, BatchTranscriptionService {
    
    // MARK: - Properties
    
    public nonisolated let backendID: BackendID = .mlxWhisper
    public nonisolated let displayName: String = "MLX Whisper"
    
    public nonisolated var supportedFormats: [AudioFormat] {
        [.wav, .mp3, .flac, .aac]
    }
    
    public nonisolated var supportedLanguages: [LanguageCode] {
        [.english, .spanish, .french, .german, .italian, .portuguese, 
         .chinese, .japanese, .korean, .arabic, .hindi, .russian, .autoDetect]
    }
    
    public nonisolated var supportsSpeakerDiarization: Bool {
        false // MLX models don't support speaker diarization
    }
    
    public var streamingConfiguration: StreamingConfiguration {
        get { _streamingConfiguration }
        set { _streamingConfiguration = newValue }
    }
    private var _streamingConfiguration: StreamingConfiguration = StreamingConfiguration()
    
    // MARK: - Private Properties
    
    /// Service configuration
    private let configuration: MLXServiceConfiguration
    
    /// Audio processor for preprocessing
    private let audioProcessor: MLXAudioProcessor
    
    /// Model downloader
    private var modelDownloader: MLXModelDownloader?
    
    /// Loaded MLX model (optional until loaded)
    private var mlxModel: AnySendableMLXModel?
    
    /// Model state
    private var modelState: ModelState = .notLoaded
    
    /// Active transcription tasks for cancellation
    private var transcriptionTasks: [UUID: Task<Void, Error>] = [:]
    
    /// Streaming buffer for audio accumulation
    private var streamingBuffer: [Float] = []
    
    /// Last transcription context for continuity
    private var lastContext: String?
    
    // MARK: - Types
    
    private enum ModelState: Sendable {
        case notLoaded
        case loading
        case loaded(model: AnySendableMLXModel)
        case failed(error: TranscriptionError)
    }
    
    /// Wrapper to make MLX model Sendable-safe
    private struct AnySendableMLXModel: @unchecked Sendable {
        let model: Any
        let generate: (MLXArray) -> String
    }
    
    // MARK: - Initialization
    
    /// Creates a new MLX transcription service.
    /// - Parameter configuration: Service configuration
    public init(configuration: MLXServiceConfiguration = MLXServiceConfiguration()) {
        self.configuration = configuration
        self.audioProcessor = MLXAudioProcessor(
            targetSampleRate: configuration.audioConfiguration.targetSampleRate,
            shouldNormalize: configuration.audioConfiguration.normalizeAudio
        )
    }
    
    // MARK: - TranscriptionService Protocol
    
    public func isAvailable() async -> Bool {
        switch modelState {
        case .loaded:
            return true
        case .notLoaded:
            // Check if model is already downloaded
            let modelURL = getModelURL()
            return await checkModelExists(at: modelURL)
        case .loading:
            return false
        case .failed:
            return false
        }
    }
    
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        let fileManager = FileManager.default
        
        // Check file exists
        guard fileManager.fileExists(atPath: audioURL.path) else {
            return .invalid(error: .fileNotFound)
        }
        
        // Check file size
        do {
            let attributes = try fileManager.attributesOfItem(atPath: audioURL.path)
            guard let fileSize = attributes[.size] as? Int64 else {
                return .invalid(error: .invalidFile)
            }
            
            // Check if file is too large (> 2GB)
            if fileSize > 2_000_000_000 {
                return .invalid(error: .fileTooLarge)
            }
            
            // Check file extension
            let ext = audioURL.pathExtension.lowercased()
            let validExtensions = ["wav", "mp3", "flac", "aac", "m4a"]
            guard validExtensions.contains(ext) else {
                return ValidationResult(
                    isValid: false,
                    format: nil,
                    duration: nil,
                    error: .unsupportedFormat(ext)
                )
            }
            
            // Try to get audio info
            // This would use AVFoundation in real implementation
            return .valid
            
        } catch {
            return .invalid(error: .invalidFile)
        }
    }
    
    // MARK: - StreamingTranscriptionService Protocol
    
    public func transcribeStream(
        _ audioStream: AsyncStream<AudioBuffer>,
        language: LanguageCode?
    ) -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performStreamingTranscription(
                        audioStream: audioStream,
                        language: language,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: mapError(error))
                }
            }
            
            // Store task for cancellation
            let taskID = UUID()
            transcriptionTasks[taskID] = task
            
            continuation.onTermination = { _ in
                Task {
                    await self.cancelTranscription(id: taskID)
                }
            }
        }
    }
    
    public func transcribeFromMicrophone(
        using audioCaptureService: AudioCaptureService,
        language: LanguageCode?
    ) async throws -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError> {
        // Start audio capture
        let audioStream = try await audioCaptureService.startCapture()
        
        // Return transcription stream
        return transcribeStream(audioStream, language: language)
    }
    
    // MARK: - BatchTranscriptionService Protocol
    
    public func transcribeFile(
        at audioURL: URL,
        language: LanguageCode?,
        speakerDiarization: Bool,
        progressHandler: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> BatchTranscriptionResult {
        // Validate file
        let validation = await validateAudioFile(audioURL)
        guard validation.isValid else {
            throw TranscriptionError.audioFormatUnsupported(
                format: audioURL.pathExtension,
                supportedFormats: supportedFormats.map { $0.rawValue }
            )
        }
        
        // Load audio file
        let audioData = try await loadAudioFile(audioURL)
        
        // Create audio buffer
        let buffer = AudioBuffer(
            samples: audioData.samples,
            sampleRate: audioData.sampleRate,
            channelCount: audioData.channelCount,
            timestamp: .zero,
            id: AudioSegmentID()
        )
        
        // Process audio
        let processedBuffer = try await audioProcessor.prepareForMLX(buffer)
        
        // Perform transcription
        let startTime = Date()
        let text = try await transcribeBuffer(processedBuffer, language: language)
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Create single segment result
        let segment = TranscriptionSegment(
            id: UtteranceID(),
            text: text,
            startTime: .zero,
            endTime: processedBuffer.duration,
            confidence: 0.9,
            isPartial: false,
            speakerID: nil,
            language: language
        )
        
        // Report progress
        progressHandler?(TranscriptionProgress(
            audioProcessed: processedBuffer.duration,
            totalDuration: processedBuffer.duration,
            percentage: 1.0,
            estimatedTimeRemaining: nil
        ))
        
        return BatchTranscriptionResult(
            transcriptID: TranscriptID(),
            segments: [segment],
            fullText: text,
            language: language ?? .english,
            duration: processedBuffer.duration,
            processingTime: .seconds(processingTime)
        )
    }
    
    public func estimateProcessingTime(for audioURL: URL) async -> Duration {
        // Estimate based on file size and typical RTF (Real-Time Factor)
        // MLX Whisper has RTF ~0.1-0.3 on Apple Silicon
        let estimatedRTF = 0.2
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                // Rough estimate: 1MB per 10 seconds of audio at good quality
                let estimatedDuration = Double(fileSize) / (1024 * 1024 * 10)
                let estimatedProcessingTime = estimatedDuration * estimatedRTF
                return .seconds(estimatedProcessingTime)
            }
        } catch {
            // Fallback estimate
        }
        
        return .seconds(30) // Default 30 second estimate
    }
    
    // MARK: - Model Management
    
    /// Prepares the service by loading/downloading the model.
    /// - Parameters:
    ///   - onStatus: Status callback
    ///   - onProgress: Progress callback
    public func prepare(
        onStatus: @Sendable (String) -> Void,
        onProgress: @Sendable (Double) -> Void
    ) async throws {
        guard modelState != .loaded else {
            onStatus("Model already loaded")
            return
        }
        
        modelState = .loading
        onStatus("Checking model availability...")
        
        let modelURL = getModelURL()
        let modelExists = await checkModelExists(at: modelURL)
        
        if !modelExists {
            onStatus("Downloading model...")
            try await downloadModel(progress: onProgress)
        }
        
        onStatus("Loading MLX model...")
        try await loadMLXModel()
        
        onStatus("MLX Whisper ready")
    }
    
    /// Clears the loaded model and cached files.
    public func clearModelCache() async throws {
        // Cancel any active transcriptions
        for (id, _) in transcriptionTasks {
            await cancelTranscription(id: id)
        }
        transcriptionTasks.removeAll()
        
        // Clear model
        mlxModel = nil
        modelState = .notLoaded
        
        // Clear downloaded files
        let modelURL = getModelURL()
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
    }
    
    // MARK: - Private Methods
    
    private func getModelURL() -> URL {
        if let customURL = configuration.customStorageURL {
            return customURL
                .appendingPathComponent(configuration.modelRepository.replacingOccurrences(of: "/", with: "_"))
        }
        
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenOats")
            .appendingPathComponent("MLXModels")
            .appendingPathComponent(configuration.modelRepository.replacingOccurrences(of: "/", with: "_"))
    }
    
    private func checkModelExists(at url: URL) async -> Bool {
        let essentialFiles = ["config.json", "model.safetensors"]
        let fileManager = FileManager.default
        
        for file in essentialFiles {
            let fileURL = url.appendingPathComponent(file)
            if !fileManager.fileExists(atPath: fileURL.path) {
                return false
            }
        }
        
        return true
    }
    
    private func downloadModel(progress: @Sendable (Double) -> Void) async throws {
        let modelURL = getModelURL()
        
        modelDownloader = MLXModelDownloader(
            modelRepository: configuration.modelRepository,
            destinationURL: modelURL,
            supportsResume: configuration.downloadConfiguration.enableResume
        )
        
        let progressStream = modelDownloader!.download()
        
        for await downloadProgress in progressStream {
            progress(downloadProgress.percentage)
        }
        
        // Verify download succeeded
        let downloaded = await modelDownloader!.isModelDownloaded()
        if !downloaded {
            throw TranscriptionError.modelUnavailable(
                model: configuration.modelRepository,
                reason: "Download failed or incomplete"
            )
        }
    }
    
    private func loadMLXModel() async throws {
        do {
            // Load GLMASR model from downloaded location
            let model = try await GLMASRModel.fromPretrained(configuration.modelRepository)
            
            // Wrap in Sendable container
            mlxModel = AnySendableMLXModel(
                model: model,
                generate: { audioArray in
                    let output = model.generate(audio: audioArray)
                    return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            )
            
            modelState = .loaded(model: mlxModel!)
        } catch {
            let transcriptionError = TranscriptionError.modelUnavailable(
                model: configuration.modelRepository,
                reason: error.localizedDescription
            )
            modelState = .failed(error: transcriptionError)
            throw transcriptionError
        }
    }
    
    private func transcribeBuffer(
        _ buffer: AudioBuffer,
        language: LanguageCode?
    ) async throws -> String {
        guard case .loaded = modelState else {
            throw TranscriptionError.modelUnavailable(
                model: configuration.modelRepository,
                reason: "Model not loaded. Call prepare() first."
            )
        }
        
        guard let model = mlxModel else {
            throw TranscriptionError.backendFailed(
                backend: displayName,
                reason: "Internal error: model not available",
                recoverable: true
            )
        }
        
        // Convert to MLXArray
        let mlxArray = audioProcessor.toMLXArray(buffer)
        
        // Perform transcription
        let text = model.generate(mlxArray)
        
        return text
    }
    
    private func performStreamingTranscription(
        audioStream: AsyncStream<AudioBuffer>,
        language: LanguageCode?,
        continuation: AsyncThrowingStream<TranscriptionSegment, TranscriptionError>.Continuation
    ) async throws {
        // Ensure model is loaded
        guard case .loaded = modelState else {
            throw TranscriptionError.modelUnavailable(
                model: configuration.modelRepository,
                reason: "Model not loaded"
            )
        }
        
        let minSamples = Int(streamingConfiguration.minAudioLength.seconds * 16000)
        var accumulatedSamples: [Float] = []
        var segmentStartTime: Duration = .zero
        
        for await buffer in audioStream {
            // Check for cancellation
            try Task.checkCancellation()
            
            // Process buffer
            let processed = try await audioProcessor.prepareForMLX(buffer)
            accumulatedSamples.append(contentsOf: processed.samples)
            
            // Check if we have enough audio for transcription
            guard accumulatedSamples.count >= minSamples else {
                continue
            }
            
            // Create audio buffer for transcription
            let transcriptionBuffer = AudioBuffer(
                samples: accumulatedSamples,
                sampleRate: 16000,
                channelCount: 1,
                timestamp: segmentStartTime,
                id: AudioSegmentID()
            )
            
            // Perform transcription
            let text = try await transcribeBuffer(transcriptionBuffer, language: language)
            
            if !text.isEmpty {
                let segment = TranscriptionSegment(
                    id: UtteranceID(),
                    text: text,
                    startTime: segmentStartTime,
                    endTime: segmentStartTime + transcriptionBuffer.duration,
                    confidence: 0.85,
                    isPartial: streamingConfiguration.enablePartialResults,
                    speakerID: nil,
                    language: language
                )
                
                continuation.yield(segment)
                
                // Update context for continuity
                lastContext = text
            }
            
            // Reset accumulator (or keep overlap for continuity)
            segmentStartTime = segmentStartTime + transcriptionBuffer.duration
            accumulatedSamples.removeAll(keepingCapacity: true)
        }
        
        continuation.finish()
    }
    
    private func cancelTranscription(id: UUID) async {
        transcriptionTasks[id]?.cancel()
        transcriptionTasks.removeValue(forKey: id)
    }
    
    private func loadAudioFile(_ url: URL) async throws -> (samples: [Float], sampleRate: Double, channelCount: Int) {
        // This would use AVFoundation to load and decode audio
        // For now, return placeholder that would trigger an error
        throw TranscriptionError.audioFormatUnsupported(
            format: url.pathExtension,
            supportedFormats: ["wav", "mp3", "flac"]
        )
    }
    
    private func mapError(_ error: Error) -> TranscriptionError {
        if let transcriptionError = error as? TranscriptionError {
            return transcriptionError
        }
        
        if let audioError = error as? MLXAudioError {
            return TranscriptionError.backendFailed(
                backend: displayName,
                reason: audioError.localizedDescription,
                recoverable: true
            )
        }
        
        if let modelError = error as? ModelDownloadError {
            switch modelError {
            case .downloadCancelled:
                return TranscriptionError.backendFailed(
                    backend: displayName,
                    reason: "Download cancelled",
                    recoverable: true
                )
            case .networkFailure(let reason):
                return TranscriptionError.networkFailure(reason: reason)
            case .insufficientStorage:
                return TranscriptionError.backendFailed(
                    backend: displayName,
                    reason: "Insufficient storage for model",
                    recoverable: false
                )
            default:
                return TranscriptionError.backendFailed(
                    backend: displayName,
                    reason: modelError.localizedDescription,
                    recoverable: true
                )
            }
        }
        
        return TranscriptionError.backendFailed(
            backend: displayName,
            reason: error.localizedDescription,
            recoverable: true
        )
    }
}

// MARK: - Audio Validation Error

private enum AudioValidationError: Error {
    case fileNotFound
    case invalidFile
    case fileTooLarge
    case unsupportedFormat(String)
}
