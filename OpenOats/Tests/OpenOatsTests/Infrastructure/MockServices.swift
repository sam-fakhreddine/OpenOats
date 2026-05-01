import Foundation
@testable import OpenOatsKit

// MARK: - Mock Transcription Services

/// Mock implementation of TranscriptionService for testing.
public actor MockTranscriptionService: TranscriptionService {
    public let backendID: BackendID
    public let displayName: String
    
    public var isAvailableResult: Bool = true
    public var supportedFormatsResult: [AudioFormat] = [.wav, .mp3, .m4a]
    public var supportedLanguagesResult: [LanguageCode] = [.english, .spanish, .french]
    public var validateAudioFileResult: ValidationResult = .valid
    
    public init(backendID: BackendID, displayName: String) {
        self.backendID = backendID
        self.displayName = displayName
    }
    
    public func isAvailable() async -> Bool {
        isAvailableResult
    }
    
    public var supportedFormats: [AudioFormat] {
        supportedFormatsResult
    }
    
    public var supportedLanguages: [LanguageCode] {
        supportedLanguagesResult
    }
    
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        validateAudioFileResult
    }
}

/// Mock implementation of StreamingTranscriptionService for testing.
public actor MockStreamingTranscriptionService: StreamingTranscriptionService {
    public let backendID: BackendID
    public let displayName: String
    
    public var isAvailableResult: Bool = true
    public var supportedFormatsResult: [AudioFormat] = [.wav, .mp3]
    public var supportedLanguagesResult: [LanguageCode] = [.english]
    public var validateAudioFileResult: ValidationResult = .valid
    public var streamingConfiguration: StreamingConfiguration = StreamingConfiguration()
    
    public var transcribeStreamResult: [TranscriptionSegment] = []
    public var transcribeStreamError: TranscriptionError?
    
    public init(backendID: BackendID, displayName: String) {
        self.backendID = backendID
        self.displayName = displayName
    }
    
    public func isAvailable() async -> Bool {
        isAvailableResult
    }
    
    public var supportedFormats: [AudioFormat] {
        supportedFormatsResult
    }
    
    public var supportedLanguages: [LanguageCode] {
        supportedLanguagesResult
    }
    
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        validateAudioFileResult
    }
    
    public func transcribeStream(
        _ audioStream: AsyncStream<AudioBuffer>,
        language: LanguageCode?
    ) -> AsyncThrowingStream<TranscriptionSegment, TranscriptionError> {
        AsyncThrowingStream { continuation in
            if let error = transcribeStreamError {
                continuation.finish(throwing: error)
            } else {
                for segment in transcribeStreamResult {
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
        return transcribeStream(AsyncStream { _ in }, language: language)
    }
    
    public func setTranscribeStreamResult(_ segments: [TranscriptionSegment]) {
        self.transcribeStreamResult = segments
    }
    
    public func setStreamingConfiguration(_ config: StreamingConfiguration) {
        self.streamingConfiguration = config
    }
}

/// Mock implementation of BatchTranscriptionService for testing.
public actor MockBatchTranscriptionService: BatchTranscriptionService {
    public let backendID: BackendID
    public let displayName: String
    
    public var isAvailableResult: Bool = true
    public var supportedFormatsResult: [AudioFormat] = [.wav, .mp3, .m4a]
    public var supportedLanguagesResult: [LanguageCode] = [.english]
    public var validateAudioFileResult: ValidationResult = .valid
    public var supportsSpeakerDiarizationResult: Bool = false
    
    public var transcribeFileResult: BatchTranscriptionResult?
    public var transcribeFileError: TranscriptionError?
    public var estimateProcessingTimeResult: Duration = .seconds(30)
    
    public init(backendID: BackendID, displayName: String) {
        self.backendID = backendID
        self.displayName = displayName
    }
    
    public func isAvailable() async -> Bool {
        isAvailableResult
    }
    
    public var supportedFormats: [AudioFormat] {
        supportedFormatsResult
    }
    
    public var supportedLanguages: [LanguageCode] {
        supportedLanguagesResult
    }
    
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        validateAudioFileResult
    }
    
    public func transcribeFile(
        at audioURL: URL,
        language: LanguageCode?,
        speakerDiarization: Bool,
        progressHandler: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> BatchTranscriptionResult {
        if let error = transcribeFileError {
            throw error
        }
        guard let result = transcribeFileResult else {
            throw TranscriptionError.backendFailed(
                backend: backendID.rawValue,
                reason: "No result configured",
                recoverable: false
            )
        }
        return result
    }
    
    public func estimateProcessingTime(for audioURL: URL) async -> Duration {
        estimateProcessingTimeResult
    }
    
    public var supportsSpeakerDiarization: Bool {
        supportsSpeakerDiarizationResult
    }
    
    public func setTranscribeFileResult(_ result: BatchTranscriptionResult?) {
        self.transcribeFileResult = result
    }
    
    public func setTranscribeFileError(_ error: TranscriptionError?) {
        self.transcribeFileError = error
    }
}

// MARK: - Mock Audio Services

/// Mock implementation of AudioCaptureService for testing.
public actor MockAudioCaptureService: AudioCaptureService {
    public let configuration: AudioCaptureConfiguration
    
    public var checkPermissionsResult: PermissionStatus = PermissionStatus(
        microphone: .authorized,
        systemAudio: .authorized
    )
    public var requestPermissionsResult: PermissionStatus = PermissionStatus(
        microphone: .authorized,
        systemAudio: .authorized
    )
    public var currentLevelResult: Float = 0.5
    public var isCapturingResult: Bool = false
    
    public var startCaptureResult: AsyncStream<AudioBuffer>?
    public var startCaptureError: AudioError?
    
    public init(configuration: AudioCaptureConfiguration) {
        self.configuration = configuration
    }
    
    public func checkPermissions() async -> PermissionStatus {
        checkPermissionsResult
    }
    
    public func requestPermissions() async -> PermissionStatus {
        requestPermissionsResult
    }
    
    public func startCapture() async throws -> AsyncStream<AudioBuffer> {
        if let error = startCaptureError {
            throw error
        }
        return startCaptureResult ?? AsyncStream { _ in }
    }
    
    public func stopCapture() async {
        isCapturingResult = false
    }
    
    public var currentLevel: Float {
        currentLevelResult
    }
    
    public var isCapturing: Bool {
        isCapturingResult
    }
}

/// Mock implementation of AudioFormatService for testing.
public actor MockAudioFormatService: AudioFormatService {
    public var getAudioInfoResult: Result<AudioInfo, AudioError> = .success(
        AudioInfo(
            format: .wav,
            sampleRate: 48000,
            channelCount: 1,
            duration: .seconds(60),
            fileSize: 1024,
            bitRate: nil
        )
    )
    public var convertAudioResult: Result<URL, AudioError> = .success(URL(fileURLWithPath: "/tmp/output.wav"))
    public var validateAudioFileResult: ValidationResult = .valid
    public var splitAudioResult: Result<[URL], AudioError> = .success([])
    public var mergeAudioFilesResult: Result<URL, AudioError> = .success(URL(fileURLWithPath: "/tmp/merged.wav"))
    
    public func getAudioInfo(for audioURL: URL) async -> Result<AudioInfo, AudioError> {
        getAudioInfoResult
    }
    
    public func convertAudio(
        from sourceURL: URL,
        to destinationURL: URL,
        targetFormat: AudioFormat,
        sampleRate: Double?
    ) async -> Result<URL, AudioError> {
        convertAudioResult
    }
    
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        validateAudioFileResult
    }
    
    public func splitAudio(
        at audioURL: URL,
        chunkDuration: Duration,
        outputDirectory: URL
    ) async -> Result<[URL], AudioError> {
        splitAudioResult
    }
    
    public func mergeAudioFiles(
        _ audioURLs: [URL],
        to destinationURL: URL
    ) async -> Result<URL, AudioError> {
        mergeAudioFilesResult
    }
}

// MARK: - Mock Repository Services

/// Mock implementation of SessionRepository for testing.
public actor MockSessionRepository: SessionRepositoryProtocol {
    public var sessions: [SessionID: Session] = [:]
    public var saveResult: Result<Void, StorageError> = .success(())
    public var getResult: Result<Session, StorageError>?
    public var deleteResult: Result<Void, StorageError> = .success(())
    public var existsResult: Bool = false
    public var countResult: Int = 0
    public var statisticsResult: SessionStorageStats = SessionStorageStats(
        totalSessions: 0,
        totalAudioDuration: .zero,
        totalStorageSize: 0,
        oldestSession: nil,
        newestSession: nil
    )
    
    public init() {}
    
    public func save(_ session: Session) async -> Result<Void, StorageError> {
        sessions[session.id] = session
        return saveResult
    }
    
    public func get(by id: SessionID) async -> Result<Session, StorageError> {
        if let result = getResult {
            return result
        }
        guard let session = sessions[id] else {
            return .failure(.notFound(entity: "Session", id: id.rawValue.uuidString))
        }
        return .success(session)
    }
    
    public func getSessions(for meetingID: MeetingID) async -> Result<[Session], StorageError> {
        let sessions = sessions.values.filter { $0.meetingID == meetingID }
        return .success(Array(sessions))
    }
    
    public func list(query: SessionQuery) async -> Result<[Session], StorageError> {
        var result = Array(sessions.values)
        
        if let meetingID = query.meetingID {
            result = result.filter { $0.meetingID == meetingID }
        }
        
        if let dateRange = query.dateRange {
            result = result.filter { dateRange.contains($0.startTime) }
        }
        
        switch query.sortBy {
        case .startTime:
            result.sort { $0.startTime < $1.startTime }
        default:
            break
        }
        
        if query.sortOrder == .descending {
            result.reverse()
        }
        
        if let limit = query.limit {
            result = Array(result.prefix(limit))
        }
        
        return .success(result)
    }
    
    public func delete(id: SessionID) async -> Result<Void, StorageError> {
        sessions.removeValue(forKey: id)
        return deleteResult
    }
    
    public func exists(id: SessionID) async -> Bool {
        existsResult || sessions[id] != nil
    }
    
    public func count() async -> Int {
        countResult
    }
    
    public func getStatistics() async -> SessionStorageStats {
        statisticsResult
    }
}

/// Mock implementation of TranscriptRepository for testing.
public actor MockTranscriptRepository: TranscriptRepository {
    public var transcripts: [TranscriptID: Transcript] = [:]
    public var saveResult: Result<Void, StorageError> = .success(())
    public var getResult: Result<Transcript, StorageError>?
    public var getForSessionResult: Result<Transcript?, StorageError> = .success(nil)
    public var searchResult: Result<[Transcript], StorageError> = .success([])
    public var deleteResult: Result<Void, StorageError> = .success(())
    public var exportResult: Result<URL, StorageError> = .success(URL(fileURLWithPath: "/tmp/export.txt"))
    
    public init() {}
    
    public func save(_ transcript: Transcript) async -> Result<Void, StorageError> {
        transcripts[transcript.id] = transcript
        return saveResult
    }
    
    public func get(by id: TranscriptID) async -> Result<Transcript, StorageError> {
        if let result = getResult {
            return result
        }
        guard let transcript = transcripts[id] else {
            return .failure(.notFound(entity: "Transcript", id: id.rawValue.uuidString))
        }
        return .success(transcript)
    }
    
    public func getTranscript(for sessionID: SessionID) async -> Result<Transcript?, StorageError> {
        getForSessionResult
    }
    
    public func search(query: String, meetingID: MeetingID?) async -> Result<[Transcript], StorageError> {
        searchResult
    }
    
    public func delete(id: TranscriptID) async -> Result<Void, StorageError> {
        transcripts.removeValue(forKey: id)
        return deleteResult
    }
    
    public func export(
        transcriptID: TranscriptID,
        format: TranscriptExportFormat
    ) async -> Result<URL, StorageError> {
        exportResult
    }
    
    public func setGetForSessionResult(_ result: Result<Transcript?, StorageError>) {
        self.getForSessionResult = result
    }
}

/// Mock implementation of SettingsRepository for testing.
public actor MockSettingsRepository: SettingsRepository {
    public var storage: [SettingsKey: Any] = [:]
    public var observers: [SettingsKey: [SettingsObserverToken: @Sendable () -> Void]] = [:]
    
    public init() {}
    
    public func string(for key: SettingsKey) -> String? {
        storage[key] as? String
    }
    
    public func bool(for key: SettingsKey) -> Bool {
        storage[key] as? Bool ?? false
    }
    
    public func integer(for key: SettingsKey) -> Int {
        storage[key] as? Int ?? 0
    }
    
    public func double(for key: SettingsKey) -> Double {
        storage[key] as? Double ?? 0.0
    }
    
    public func data(for key: SettingsKey) -> Data? {
        storage[key] as? Data
    }
    
    public func codable<T: Codable & Sendable>(for key: SettingsKey) -> T? {
        guard let data = storage[key] as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    public func set(_ value: String?, for key: SettingsKey) {
        storage[key] = value
        notifyObservers(for: key)
    }
    
    public func set(_ value: Bool, for key: SettingsKey) {
        storage[key] = value
        notifyObservers(for: key)
    }
    
    public func set(_ value: Int, for key: SettingsKey) {
        storage[key] = value
        notifyObservers(for: key)
    }
    
    public func set(_ value: Double, for key: SettingsKey) {
        storage[key] = value
        notifyObservers(for: key)
    }
    
    public func set(_ value: Data?, for key: SettingsKey) {
        storage[key] = value
        notifyObservers(for: key)
    }
    
    public func set<T: Codable & Sendable>(_ value: T?, for key: SettingsKey) {
        guard let value = value else {
            storage[key] = nil
            notifyObservers(for: key)
            return
        }
        storage[key] = try? JSONEncoder().encode(value)
        notifyObservers(for: key)
    }
    
    public func remove(key: SettingsKey) {
        storage.removeValue(forKey: key)
        notifyObservers(for: key)
    }
    
    public func resetToDefaults() {
        storage.removeAll()
        for key in SettingsKey.allCases {
            notifyObservers(for: key)
        }
    }
    
    public func addObserver(
        for key: SettingsKey,
        callback: @Sendable @escaping () -> Void
    ) -> SettingsObserverToken {
        let token = SettingsObserverToken()
        observers[key, default: [:]][token] = callback
        return token
    }
    
    public func removeObserver(_ token: SettingsObserverToken) {
        for key in observers.keys {
            observers[key]?.removeValue(forKey: token)
        }
    }
    
    private func notifyObservers(for key: SettingsKey) {
        observers[key]?.values.forEach { $0() }
    }
}

// MARK: - Mock LLM Services

/// Mock implementation of LLMService for testing.
public actor MockLLMService: LLMService {
    public var completeResult: Result<LLMResponse, NetworkError> = .success(
        LLMResponse(content: "Mock response", model: "mock", tokensUsed: 10, finishReason: nil)
    )
    public var chatResult: Result<LLMResponse, NetworkError> = .success(
        LLMResponse(content: "Mock chat response", model: "mock", tokensUsed: 20, finishReason: nil)
    )
    public var listAvailableModelsResult: Result<[String], NetworkError> = .success(["model1", "model2"])
    public var isAvailableResult: Bool = true
    
    public init() {}
    
    public func complete(
        prompt: String,
        configuration: LLMConfiguration
    ) async -> Result<LLMResponse, NetworkError> {
        completeResult
    }
    
    public func chat(
        messages: [LLMMessage],
        configuration: LLMConfiguration
    ) async -> Result<LLMResponse, NetworkError> {
        chatResult
    }
    
    public func streamComplete(
        prompt: String,
        configuration: LLMConfiguration
    ) -> AsyncThrowingStream<String, NetworkError> {
        AsyncThrowingStream { continuation in
            continuation.yield("Mock stream response")
            continuation.finish()
        }
    }
    
    public func listAvailableModels() async -> Result<[String], NetworkError> {
        listAvailableModelsResult
    }
    
    public func isAvailable() async -> Bool {
        isAvailableResult
    }
    
    public func setCompleteResult(_ result: Result<LLMResponse, NetworkError>) {
        self.completeResult = result
    }
    
    public func setChatResult(_ result: Result<LLMResponse, NetworkError>) {
        self.chatResult = result
    }
    
    public func setIsAvailableResult(_ value: Bool) {
        self.isAvailableResult = value
    }
}

/// Mock implementation of EmbeddingService for testing.
public actor MockEmbeddingService: EmbeddingService {
    public var embedTextsResult: Result<[[Float]], NetworkError> = .success([[0.1, 0.2, 0.3]])
    public var embedTextResult: Result<[Float], NetworkError> = .success([0.1, 0.2, 0.3])
    public var similarityResult: Double = 0.95
    
    public init() {}
    
    public func embed(
        texts: [String],
        configuration: EmbeddingConfiguration
    ) async -> Result<[[Float]], NetworkError> {
        embedTextsResult
    }
    
    public func embed(
        text: String,
        configuration: EmbeddingConfiguration
    ) async -> Result<[Float], NetworkError> {
        embedTextResult
    }
    
    public func similarity(between embedding1: [Float], and embedding2: [Float]) -> Double {
        similarityResult
    }
}

/// Mock implementation of ServiceFactory for testing.
public actor MockServiceFactory: ServiceFactory {
    public var transcriptionServices: [BackendID: TranscriptionService] = [:]
    public var streamingTranscriptionServices: [BackendID: StreamingTranscriptionService] = [:]
    public var batchTranscriptionServices: [BackendID: BatchTranscriptionService] = [:]
    public var audioCaptureService: AudioCaptureService?
    public var audioFormatService: AudioFormatService?
    public var sessionRepository: SessionRepositoryProtocol?
    public var transcriptRepository: TranscriptRepository?
    public var settingsRepository: SettingsRepository?
    public var meetingRepository: MeetingRepositoryProtocol?
    public var llmServices: [LLMProviderID: LLMService] = [:]
    public var embeddingServices: [EmbeddingProviderID: EmbeddingService] = [:]
    public var suggestionService: AISuggestionService?
    
    public init() {}
    
    public func makeTranscriptionService(backend: BackendID) -> TranscriptionService? {
        transcriptionServices[backend]
    }
    
    public func makeStreamingTranscriptionService(backend: BackendID) -> StreamingTranscriptionService? {
        streamingTranscriptionServices[backend]
    }
    
    public func makeBatchTranscriptionService(backend: BackendID) -> BatchTranscriptionService? {
        batchTranscriptionServices[backend]
    }
    
    public func makeAudioCaptureService(configuration: AudioCaptureConfiguration) -> AudioCaptureService {
        audioCaptureService ?? MockAudioCaptureService(configuration: configuration)
    }
    
    public func makeAudioFormatService() -> AudioFormatService {
        audioFormatService ?? MockAudioFormatService()
    }
    
    public func makeSessionRepository() -> SessionRepositoryProtocol {
        sessionRepository ?? MockSessionRepository()
    }
    
    public func makeTranscriptRepository() -> TranscriptRepository {
        transcriptRepository ?? MockTranscriptRepository()
    }
    
    public func makeSettingsRepository() -> SettingsRepository {
        settingsRepository ?? MockSettingsRepository()
    }
    
    public func makeMeetingRepository() -> MeetingRepositoryProtocol {
        fatalError("MockMeetingRepository not implemented")
    }
    
    public func makeLLMService(provider: LLMProviderID) -> LLMService? {
        llmServices[provider]
    }
    
    public func makeEmbeddingService(provider: EmbeddingProviderID) -> EmbeddingService? {
        embeddingServices[provider]
    }
    
    public func makeAISuggestionService() -> AISuggestionService {
        suggestionService ?? MockAISuggestionService()
    }
}

/// Mock implementation of AISuggestionService for testing.
public actor MockAISuggestionService: AISuggestionService {
    public var generateSuggestionsResult: Result<[AISuggestion], NetworkError> = .success([])
    public var generateNotesResult: Result<AINote, NetworkError> = .success(
        AINote(title: "Mock Notes", content: "Mock content")
    )
    public var answerQuestionResult: Result<String, NetworkError> = .success("Mock answer")

    public init() {}

    public func generateSuggestions(
        from transcript: Transcript,
        context: AIMeetingContext?
    ) async -> Result<[AISuggestion], NetworkError> {
        generateSuggestionsResult
    }

    public func generateNotes(
        from transcript: Transcript,
        style: AINoteStyle
    ) async -> Result<AINote, NetworkError> {
        generateNotesResult
    }

    public func answerQuestion(
        _ question: String,
        basedOn transcript: Transcript
    ) async -> Result<String, NetworkError> {
        answerQuestionResult
    }
}
