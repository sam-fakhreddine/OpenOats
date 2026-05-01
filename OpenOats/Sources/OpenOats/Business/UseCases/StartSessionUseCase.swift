import Foundation

// MARK: - StartSessionUseCase

/// Protocol definition for StartSessionUseCase
public protocol StartSessionUseCase: Sendable {
    func execute(input: StartSessionInput) async throws -> StartSessionOutput
}

/// Input for starting a recording session
public struct StartSessionInput: Sendable {
    public let name: String?
    public let backend: BackendID
    public let captureMicrophone: Bool
    public let captureSystemAudio: Bool
    public let enableTranscription: Bool
    public let language: String
    
    public init(
        name: String? = nil,
        backend: BackendID,
        captureMicrophone: Bool = true,
        captureSystemAudio: Bool = true,
        enableTranscription: Bool = true,
        language: String = "en"
    ) {
        self.name = name
        self.backend = backend
        self.captureMicrophone = captureMicrophone
        self.captureSystemAudio = captureSystemAudio
        self.enableTranscription = enableTranscription
        self.language = language
    }
}

/// Output from starting a session
public struct StartSessionOutput: Sendable {
    public let sessionID: SessionID
    public let session: Session
    
    public init(sessionID: SessionID, session: Session) {
        self.sessionID = sessionID
        self.session = session
    }
}

// MARK: - StartSessionUseCase Implementation

/// Implementation of StartSessionUseCase
public struct StartSessionUseCaseImpl: StartSessionUseCase {
    private let sessionRepository: any SessionRepositoryProtocol
    private let transcriptionService: (any StreamingTranscriptionService)?
    private let audioCaptureService: (any AudioCaptureService)?
    
    public init(
        sessionRepository: any SessionRepositoryProtocol,
        transcriptionService: (any StreamingTranscriptionService)? = nil,
        audioCaptureService: (any AudioCaptureService)? = nil
    ) {
        self.sessionRepository = sessionRepository
        self.transcriptionService = transcriptionService
        self.audioCaptureService = audioCaptureService
    }
    
    public func execute(input: StartSessionInput) async throws -> StartSessionOutput {
        // Validate input parameters
        try validateInput(input)
        
        // Check for cancellation before starting
        try Task.checkCancellation()
        
        // Create session with unique ID
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
        
        // Save session to repository
        let saveResult = await sessionRepository.save(session)
        switch saveResult {
        case .success:
            break
        case .failure(let error):
            throw error
        }
        
        // Check for cancellation after save
        try Task.checkCancellation()
        
        // Initialize transcription if enabled (optional - don't fail if service unavailable)
        if input.enableTranscription {
            _ = await transcriptionService?.isAvailable()
        }
        
        return StartSessionOutput(sessionID: sessionID, session: session)
    }
    
    private func validateInput(_ input: StartSessionInput) throws {
        // Validate backend ID is not empty
        if input.backend.rawValue.isEmpty {
            throw ValidationError.invalidInput(
                field: "backend",
                value: "",
                requirement: "Backend ID cannot be empty"
            )
        }
        
        // Validate language code format (ISO 639-1: 2 lowercase letters)
        let validLanguageCodes = ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "ar", "hi", "ru", "auto"]
        let language = input.language.lowercased()
        if !validLanguageCodes.contains(language) {
            // Check if it matches ISO 639-1 format (2 lowercase letters)
            let isoPattern = try? NSRegularExpression(pattern: "^[a-z]{2}$")
            let range = NSRange(language.startIndex..., in: language)
            if isoPattern?.firstMatch(in: language, options: [], range: range) == nil {
                throw ValidationError.invalidInput(
                    field: "language",
                    value: input.language,
                    requirement: "Language must be a valid ISO 639-1 code (2 lowercase letters)"
                )
            }
        }
    }
}
