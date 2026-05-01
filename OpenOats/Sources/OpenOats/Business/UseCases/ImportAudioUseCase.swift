import Foundation

// MARK: - ImportAudioUseCase

/// Protocol definition for ImportAudioUseCase
public protocol ImportAudioUseCase: Sendable, ProgressReportingUseCase {
    func execute(input: ImportAudioInput) async throws -> ImportAudioOutput
}

/// Audio format enum for import
public enum ImportAudioFormat: Sendable, Equatable, Hashable {
    case wav, mp3, m4a, flac, aac, ogg
}

/// Input for importing audio
public struct ImportAudioInput: Sendable {
    public let sourceURL: URL
    public let targetSessionName: String?
    public let autoTranscribe: Bool
    public let backend: BackendID?
    
    public init(
        sourceURL: URL,
        targetSessionName: String? = nil,
        autoTranscribe: Bool = true,
        backend: BackendID? = nil
    ) {
        self.sourceURL = sourceURL
        self.targetSessionName = targetSessionName
        self.autoTranscribe = autoTranscribe
        self.backend = backend
    }
}

/// Output from importing audio
public struct ImportAudioOutput: Sendable {
    public let session: Session
    public let transcript: Transcript?
    public let importedAt: Date
    
    public init(
        session: Session,
        transcript: Transcript? = nil,
        importedAt: Date
    ) {
        self.session = session
        self.transcript = transcript
        self.importedAt = importedAt
    }
}

/// Audio validation result
public struct ImportAudioValidationResult: Sendable {
    public let isValid: Bool
    public let format: ImportAudioFormat?
    public let duration: Duration?
    public let sampleRate: Int?
    public let error: AudioError?
    
    public init(
        isValid: Bool,
        format: ImportAudioFormat? = nil,
        duration: Duration? = nil,
        sampleRate: Int? = nil,
        error: AudioError? = nil
    ) {
        self.isValid = isValid
        self.format = format
        self.duration = duration
        self.sampleRate = sampleRate
        self.error = error
    }
}

// MARK: - ImportAudioUseCase Implementation

/// Implementation of ImportAudioUseCase
public actor ImportAudioUseCaseImpl: ImportAudioUseCase {
    private let sessionRepository: any SessionRepositoryProtocol
    private let transcriptRepository: any TranscriptRepository
    private let audioValidationService: any AudioValidationService
    private let batchTranscriptionService: (any BatchTranscriptionService)?
    private let audioStorage: (any AudioImportStorage)?
    
    private var progressContinuation: AsyncStream<Double>.Continuation?
    
    nonisolated public var progressStream: AsyncStream<Double> {
        AsyncStream { continuation in
            Task {
                await self.setProgressContinuation(continuation)
            }
        }
    }
    
    public init(
        sessionRepository: any SessionRepositoryProtocol,
        transcriptRepository: any TranscriptRepository,
        audioValidationService: any AudioValidationService,
        batchTranscriptionService: (any BatchTranscriptionService)? = nil,
        audioStorage: (any AudioImportStorage)? = nil
    ) {
        self.sessionRepository = sessionRepository
        self.transcriptRepository = transcriptRepository
        self.audioValidationService = audioValidationService
        self.batchTranscriptionService = batchTranscriptionService
        self.audioStorage = audioStorage
    }
    
    private func setProgressContinuation(_ continuation: AsyncStream<Double>.Continuation?) {
        self.progressContinuation = continuation
    }
    
    public func execute(input: ImportAudioInput) async throws -> ImportAudioOutput {
        reportProgress(0.0)
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Validate the audio file
        let validationResult = await validateAudioFile(url: input.sourceURL)
        guard validationResult.isValid else {
            throw validationResult.error ?? AudioError.formatUnsupported(
                format: input.sourceURL.pathExtension,
                sampleRate: nil
            )
        }
        
        reportProgress(0.2)
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Create new session for imported audio
        let sessionID = SessionID()
        let meetingID = MeetingID()
        let session = Session(
            id: sessionID,
            meetingID: meetingID,
            startTime: Date(),
            endTime: nil,
            status: .active,
            backendID: input.backend
        )
        
        // Save session
        let saveResult = await sessionRepository.save(session)
        switch saveResult {
        case .success:
            break
        case .failure(let error):
            throw error
        }
        
        reportProgress(0.4)
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Copy audio file to storage if storage service available
        if let storage = audioStorage {
            let copyResult = await storage.importAudio(from: input.sourceURL, for: sessionID)
            if case .failure(let error) = copyResult {
                throw error
            }
        }
        
        reportProgress(0.6)
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Generate transcript if auto-transcribe is enabled
        var transcript: Transcript?
        if input.autoTranscribe, let transcriptionService = batchTranscriptionService {
            do {
                let language = LanguageCode(rawValue: "en")
                let transcriptionResult = try await transcriptionService.transcribeFile(
                    at: input.sourceURL,
                    language: language,
                    speakerDiarization: false,
                    progressHandler: { progress in
                        let adjustedProgress = 0.6 + (progress.percentage * 0.3)
                        self.reportProgress(adjustedProgress)
                    }
                )
                
                // Check for cancellation
                try Task.checkCancellation()
                
                // Create transcript entity
                transcript = Transcript(
                    id: TranscriptID(),
                    sessionID: sessionID,
                    language: transcriptionResult.language.rawValue,
                    utteranceIDs: transcriptionResult.segments.map { _ in UtteranceID() },
                    isComplete: true
                )
                
                // Save transcript
                if let transcriptToSave = transcript {
                    _ = await transcriptRepository.save(transcriptToSave)
                }
            } catch is TranscriptionError {
                // Transcription failed, but session was created
                // Don't throw - transcript will be nil
            }
        }
        
        reportProgress(1.0)
        
        return ImportAudioOutput(
            session: session,
            transcript: transcript,
            importedAt: Date()
        )
    }
    
    public func validateAudioFile(url: URL) async -> ImportAudioValidationResult {
        let result = await audioValidationService.validate(url: url)
        
        return ImportAudioValidationResult(
            isValid: result.isValid,
            format: detectFormat(from: url),
            duration: result.duration,
            sampleRate: result.sampleRate,
            error: result.error
        )
    }
    
    private func detectFormat(from url: URL) -> ImportAudioFormat? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "wav": return .wav
        case "mp3": return .mp3
        case "m4a", "mp4", "aac": return .m4a
        case "flac": return .flac
        case "ogg": return .ogg
        default: return nil
        }
    }
    
    private func reportProgress(_ value: Double) {
        progressContinuation?.yield(value)
        if value >= 1.0 {
            progressContinuation?.finish()
        }
    }
}

// MARK: - Audio Validation Service Protocol

/// Protocol for audio file validation
public protocol AudioValidationService: Sendable {
    func validate(url: URL) async -> ImportAudioValidationServiceResult
}

/// Result of audio validation
public struct ImportAudioValidationServiceResult: Sendable {
    public let isValid: Bool
    public let duration: Duration?
    public let sampleRate: Int?
    public let error: AudioError?
    
    public init(
        isValid: Bool,
        duration: Duration? = nil,
        sampleRate: Int? = nil,
        error: AudioError? = nil
    ) {
        self.isValid = isValid
        self.duration = duration
        self.sampleRate = sampleRate
        self.error = error
    }
}

// MARK: - Audio Import Storage Protocol

/// Protocol for audio import storage
public protocol AudioImportStorage: Sendable {
    func importAudio(from sourceURL: URL, for sessionID: SessionID) async -> Result<URL, StorageError>
}
