import Foundation

// MARK: - Mock Transcription Service

/// Mock implementation of TranscriptionService for testing.
@available(macOS 15.0, *)
@preconcurrency public actor MockTranscriptionService: TranscriptionService, Sendable {
    public nonisolated let backendID: BackendID
    public nonisolated let displayName: String
    public nonisolated let supportedFormats: [AudioFormat]
    public nonisolated let supportedLanguages: [LanguageCode]
    
    private var availabilityState: Bool
    private var validationResult: ValidationResult
    
    public init(
        backendID: BackendID,
        displayName: String,
        isAvailable: Bool = true,
        supportedFormats: [AudioFormat] = [.wav, .mp3],
        supportedLanguages: [LanguageCode] = [.english, .spanish],
        validationResult: ValidationResult = .valid
    ) {
        self.backendID = backendID
        self.displayName = displayName
        self.availabilityState = isAvailable
        self.supportedFormats = supportedFormats
        self.supportedLanguages = supportedLanguages
        self.validationResult = validationResult
    }
    
    public func isAvailable() async -> Bool {
        return availabilityState
    }
    
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        return validationResult
    }
    
    // MARK: - Test Helpers
    
    public func setAvailability(_ available: Bool) {
        self.availabilityState = available
    }
    
    public func setValidationResult(_ result: ValidationResult) {
        self.validationResult = result
    }
}

// MARK: - Mock Streaming Transcription Service

/// Mock implementation of StreamingTranscriptionService for testing.
@available(macOS 15.0, *)
@preconcurrency public actor MockStreamingTranscriptionService: StreamingTranscriptionService, Sendable {
    public nonisolated let backendID: BackendID
    public nonisolated let displayName: String
    public nonisolated let supportedFormats: [AudioFormat]
    public nonisolated let supportedLanguages: [LanguageCode]
    public var streamingConfiguration: StreamingConfiguration
    
    private var availabilityState: Bool
    private var validationResult: ValidationResult
    private var transcribeStreamResult: [TranscriptionSegment]
    private var shouldThrowError: TranscriptionError?
    
    public init(
        backendID: BackendID,
        displayName: String,
        isAvailable: Bool = true,
        supportedFormats: [AudioFormat] = [.wav, .mp3],
        supportedLanguages: [LanguageCode] = [.english, .spanish],
        validationResult: ValidationResult = .valid,
        streamingConfiguration: StreamingConfiguration = StreamingConfiguration()
    ) {
        self.backendID = backendID
        self.displayName = displayName
        self.availabilityState = isAvailable
        self.supportedFormats = supportedFormats
        self.supportedLanguages = supportedLanguages
        self.validationResult = validationResult
        self.streamingConfiguration = streamingConfiguration
        self.transcribeStreamResult = []
    }
    
    public func isAvailable() async -> Bool {
        return availabilityState
    }
    
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        return validationResult
    }
    
    public nonisolated func transcribeStream(
        _ audioStream: AsyncStream<AudioBuffer>,
        language: LanguageCode?
    ) -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError> {
        return AsyncThrowingStream { continuation in
            Task {
                // Access actor state through MainActor or Task
                let segments = await self.transcribeStreamResult
                let error = await self.shouldThrowError
                
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                
                for segment in segments {
                    continuation.yield(segment)
                }
                continuation.finish()
            }
        }
    }
    
    public func transcribeFromMicrophone(
        using audioCaptureService: AudioCaptureService,
        language: LanguageCode?
    ) async throws -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError> {
        let audioStream = try await audioCaptureService.startCapture()
        return transcribeStream(audioStream, language: language)
    }
    
    // MARK: - Test Helpers
    
    public func setAvailability(_ available: Bool) {
        self.availabilityState = available
    }
    
    public func setStreamingConfiguration(_ config: StreamingConfiguration) {
        self.streamingConfiguration = config
    }
    
    public func setTranscribeStreamResult(_ segments: [TranscriptionSegment]) {
        self.transcribeStreamResult = segments
    }
    
    public func setShouldThrowError(_ error: TranscriptionError?) {
        self.shouldThrowError = error
    }
}

// MARK: - Mock Batch Transcription Service

/// Mock implementation of BatchTranscriptionService for testing.
@available(macOS 15.0, *)
@preconcurrency public actor MockBatchTranscriptionService: BatchTranscriptionService, Sendable {
    public nonisolated let backendID: BackendID
    public nonisolated let displayName: String
    public nonisolated let supportsSpeakerDiarization: Bool
    public nonisolated let supportedFormats: [AudioFormat]
    public nonisolated let supportedLanguages: [LanguageCode]
    
    private var availabilityState: Bool
    private var validationResult: ValidationResult
    private var transcribeFileResult: BatchTranscriptionResult?
    private var shouldThrowError: TranscriptionError?
    private var processingTimeEstimate: Duration
    private var progressHandlerCalls: [TranscriptionProgress]
    
    public init(
        backendID: BackendID,
        displayName: String,
        isAvailable: Bool = true,
        supportedFormats: [AudioFormat] = [.wav, .mp3],
        supportedLanguages: [LanguageCode] = [.english, .spanish],
        validationResult: ValidationResult = .valid,
        supportsSpeakerDiarization: Bool = true,
        processingTimeEstimate: Duration = .seconds(30)
    ) {
        self.backendID = backendID
        self.displayName = displayName
        self.availabilityState = isAvailable
        self.supportedFormats = supportedFormats
        self.supportedLanguages = supportedLanguages
        self.validationResult = validationResult
        self.supportsSpeakerDiarization = supportsSpeakerDiarization
        self.processingTimeEstimate = processingTimeEstimate
        self.transcribeFileResult = nil
        self.progressHandlerCalls = []
    }
    
    public func isAvailable() async -> Bool {
        return availabilityState
    }
    
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        return validationResult
    }
    
    public func transcribeFile(
        at audioURL: URL,
        language: LanguageCode?,
        speakerDiarization: Bool,
        progressHandler: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> BatchTranscriptionResult {
        // Simulate progress updates
        if let progressHandler = progressHandler {
            let totalDuration: Duration = .seconds(60)
            let steps = 5
            for i in 0...steps {
                let progress = TranscriptionProgress(
                    audioProcessed: .seconds(Double(i) * 12),
                    totalDuration: totalDuration,
                    percentage: Double(i) / Double(steps),
                    estimatedTimeRemaining: .seconds(Double(steps - i) * 2)
                )
                progressHandler(progress)
            }
        }
        
        if let error = shouldThrowError {
            throw error
        }
        
        guard let result = transcribeFileResult else {
            throw TranscriptionError.backendFailed(
                backend: backendID.rawValue,
                reason: "No mock result set",
                recoverable: false
            )
        }
        
        return result
    }
    
    public func estimateProcessingTime(for audioURL: URL) async -> Duration {
        return processingTimeEstimate
    }
    
    // MARK: - Test Helpers
    
    public func setAvailability(_ available: Bool) {
        self.availabilityState = available
    }
    
    public func setTranscribeFileResult(_ result: BatchTranscriptionResult?) {
        self.transcribeFileResult = result
    }
    
    public func setShouldThrowError(_ error: TranscriptionError?) {
        self.shouldThrowError = error
    }
    
    public func setProcessingTimeEstimate(_ duration: Duration) {
        self.processingTimeEstimate = duration
    }
}
