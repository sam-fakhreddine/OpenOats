import Foundation

// MARK: - StopSessionUseCase

/// Protocol definition for StopSessionUseCase
public protocol StopSessionUseCase: Sendable {
    func execute(input: StopSessionInput) async throws -> StopSessionOutput
}

/// Input for stopping a session
public struct StopSessionInput: Sendable {
    public let sessionID: SessionID
    public let saveRecording: Bool
    
    public init(sessionID: SessionID, saveRecording: Bool = true) {
        self.sessionID = sessionID
        self.saveRecording = saveRecording
    }
}

/// Output from stopping a session
public struct StopSessionOutput: Sendable {
    public let session: Session
    public let transcript: Transcript?
    public let recordingURL: URL?
    
    public init(
        session: Session,
        transcript: Transcript? = nil,
        recordingURL: URL? = nil
    ) {
        self.session = session
        self.transcript = transcript
        self.recordingURL = recordingURL
    }
}

// MARK: - StopSessionUseCase Implementation

/// Implementation of StopSessionUseCase
public struct StopSessionUseCaseImpl: StopSessionUseCase {
    private let sessionRepository: any SessionRepositoryProtocol
    private let transcriptRepository: (any TranscriptRepository)?
    private let audioStorage: (any AudioStorageService)?
    
    public init(
        sessionRepository: any SessionRepositoryProtocol,
        transcriptRepository: (any TranscriptRepository)? = nil,
        audioStorage: (any AudioStorageService)? = nil
    ) {
        self.sessionRepository = sessionRepository
        self.transcriptRepository = transcriptRepository
        self.audioStorage = audioStorage
    }
    
    public func execute(input: StopSessionInput) async throws -> StopSessionOutput {
        // Check for cancellation
        try Task.checkCancellation()
        
        // Retrieve the session
        let sessionResult = await sessionRepository.get(by: input.sessionID)
        let session: Session
        switch sessionResult {
        case .success(let foundSession):
            session = foundSession
        case .failure:
            throw ValidationError.invalidInput(
                field: "sessionID",
                value: input.sessionID.rawValue.uuidString,
                requirement: "Session not found"
            )
        }
        
        // Check for cancellation after retrieval
        try Task.checkCancellation()
        
        // Update session with end time and completed status
        let endTime = Date()
        let stoppedSession = session
            .withEndedAt(endTime)
            .withStatus(.completed)
        
        // Save updated session
        let saveResult = await sessionRepository.save(stoppedSession)
        switch saveResult {
        case .success:
            break
        case .failure(let error):
            throw error
        }
        
        // Check for cancellation after save
        try Task.checkCancellation()
        
        // Get transcript if available (optional, don't fail if not found)
        var transcript: Transcript?
        if let transcriptRepo = transcriptRepository {
            let transcriptResult = await transcriptRepo.getTranscript(for: input.sessionID)
            if case .success(let foundTranscript) = transcriptResult {
                transcript = foundTranscript
            }
        }
        
        // Determine recording URL based on saveRecording flag
        var recordingURL: URL?
        if input.saveRecording {
            recordingURL = await audioStorage?.getRecordingURL(for: input.sessionID)
        } else {
            // Delete recording if not saving
            await audioStorage?.deleteRecording(for: input.sessionID)
        }
        
        return StopSessionOutput(
            session: stoppedSession,
            transcript: transcript,
            recordingURL: recordingURL
        )
    }
}

// MARK: - Audio Storage Service Protocol

/// Protocol for audio recording storage
public protocol AudioStorageService: Sendable {
    func getRecordingURL(for sessionID: SessionID) async -> URL?
    func deleteRecording(for sessionID: SessionID) async
}
