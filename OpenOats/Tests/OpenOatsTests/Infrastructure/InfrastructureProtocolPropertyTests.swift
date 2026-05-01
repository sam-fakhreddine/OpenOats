import XCTest
@testable import OpenOatsKit

// MARK: - Property-Based Tests for Infrastructure Protocols
// Phase 1: RED - All tests intentionally fail to verify test infrastructure

// MARK: - TranscriptionService Property Tests

@available(macOS 15.0, *)
final class TranscriptionServicePropertyTests: XCTestCase {
    
    // MARK: - Sendable Safety Properties
    
    /// Property: TranscriptionService implementations must be Sendable-safe
    /// Verifies that the service can be safely shared across actors
    func test_transcriptionService_isSendableSafe() async {
        let service = await MockTranscriptionService(
            backendID: .whisperKit,
            displayName: "Test Backend"
        )
        
        // Test cross-actor safety by calling from multiple actors concurrently
        async let result1: Void = { await service.isAvailable() }()
        async let result2: Void = { await service.isAvailable() }()
        
        _ = await (result1, result2)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Sendable safety test not yet implemented")
    }
    
    /// Property: isAvailable() must return consistent result within session
    /// The availability state should not change without external configuration change
    func test_isAvailable_isConsistentWithinSession() async {
        let service = await MockTranscriptionService(
            backendID: .whisperKit,
            displayName: "Test"
        )
        
        let first = await service.isAvailable()
        let second = await service.isAvailable()
        let third = await service.isAvailable()
        
        // All results should be consistent
        XCTAssertEqual(first, second)
        XCTAssertEqual(second, third)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Consistency test not yet implemented")
    }
    
    /// Property: supportedFormats must not be empty when isAvailable returns true
    /// An available backend must support at least one audio format
    func test_availableServiceHasSupportedFormats() async {
        let service = await MockTranscriptionService(
            backendID: .whisperKit,
            displayName: "Test"
        )
        
        let isAvailable = await service.isAvailable()
        let formats = await service.supportedFormats
        
        if isAvailable {
            // If available, must support at least one format
            XCTAssertFalse(formats.isEmpty, "Available service must support at least one format")
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Format support test not yet implemented")
    }
    
    /// Property: validateAudioFile must return isValid=true for valid audio files
    func test_validateAudioFile_returnsValidForValidFiles() async throws {
        let service = await MockTranscriptionService(
            backendID: .whisperKit,
            displayName: "Test"
        )
        
        let validURL = URL(fileURLWithPath: "/tmp/test.wav")
        let result = await service.validateAudioFile(validURL)
        
        // For known valid formats, should return valid
        // Intentionally fail to verify RED phase
        XCTAssertTrue(result.isValid)
        XCTFail("RED PHASE: Validation test not yet implemented")
    }
    
    /// Property: backendID must be unique and non-empty
    func test_backendID_isValid() async {
        let service = await MockTranscriptionService(
            backendID: .whisperKit,
            displayName: "Test"
        )
        
        let backendID = await service.backendID
        
        XCTAssertFalse(backendID.rawValue.isEmpty, "Backend ID must not be empty")
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: BackendID validation not yet implemented")
    }
}

// MARK: - StreamingTranscriptionService Property Tests

@available(macOS 15.0, *)
final class StreamingTranscriptionServicePropertyTests: XCTestCase {
    
    /// Property: transcribeStream must yield segments in chronological order
    func test_transcribeStream_segmentsAreChronological() async throws {
        let service = await MockStreamingTranscriptionService(
            backendID: .mlxWhisper,
            displayName: "MLX Test"
        )
        
        let audioStream = AsyncStream<AudioBuffer> { continuation in
            continuation.finish()
        }
        
        var segments: [TranscriptionSegment] = []
        let stream = await service.transcribeStream(audioStream, language: .english)
        
        for try await segment in stream {
            segments.append(segment)
        }
        
        // Verify chronological order
        for i in 1..<segments.count {
            XCTAssertGreaterThan(
                segments[i].startTime,
                segments[i-1].startTime,
                "Segments must be in chronological order"
            )
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Chronological order test not yet implemented")
    }
    
    /// Property: Segment confidence must be within valid range [0.0, 1.0]
    func test_segmentConfidence_isWithinValidRange() async throws {
        let service = await MockStreamingTranscriptionService(
            backendID: .mlxWhisper,
            displayName: "MLX Test"
        )
        
        let segment = TranscriptionSegment(
            id: UtteranceID(),
            text: "Test",
            startTime: .seconds(0),
            endTime: .seconds(1),
            confidence: 0.95,
            isPartial: false
        )
        
        await service.setTranscribeStreamResult([segment])
        
        let audioStream = AsyncStream<AudioBuffer> { $0.finish() }
        let stream = await service.transcribeStream(audioStream, language: .english)
        
        for try await seg in stream {
            XCTAssertGreaterThanOrEqual(seg.confidence, 0.0)
            XCTAssertLessThanOrEqual(seg.confidence, 1.0)
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Confidence range test not yet implemented")
    }
    
    /// Property: Streaming must handle empty audio stream gracefully
    func test_transcribeStream_handlesEmptyStream() async throws {
        let service = await MockStreamingTranscriptionService(
            backendID: .mlxWhisper,
            displayName: "MLX Test"
        )
        
        let audioStream = AsyncStream<AudioBuffer> { $0.finish() }
        let stream = await service.transcribeStream(audioStream, language: .english)
        
        var segmentCount = 0
        for try await _ in stream {
            segmentCount += 1
        }
        
        // Empty stream should produce no segments or finish gracefully
        XCTAssertGreaterThanOrEqual(segmentCount, 0)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Empty stream test not yet implemented")
    }
    
    /// Property: Configuration changes must affect subsequent transcriptions
    func test_configurationChangesTakeEffect() async throws {
        let service = await MockStreamingTranscriptionService(
            backendID: .mlxWhisper,
            displayName: "MLX Test"
        )
        
        let initialConfig = await service.streamingConfiguration
        let newConfig = StreamingConfiguration(confidenceThreshold: 0.9)
        
        await service.setStreamingConfiguration(newConfig)
        let updatedConfig = await service.streamingConfiguration
        
        XCTAssertEqual(updatedConfig.confidenceThreshold, 0.9)
        XCTAssertNotEqual(initialConfig.confidenceThreshold, updatedConfig.confidenceThreshold)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Configuration change test not yet implemented")
    }
}

// MARK: - BatchTranscriptionService Property Tests

@available(macOS 15.0, *)
final class BatchTranscriptionServicePropertyTests: XCTestCase {
    
    /// Property: transcribeFile must produce consistent segments
    func test_transcribeFile_producesValidResult() async throws {
        let service = await MockBatchTranscriptionService(
            backendID: .assemblyAI,
            displayName: "AssemblyAI Test"
        )
        
        let mockResult = BatchTranscriptionResult(
            transcriptID: TranscriptID(),
            segments: [],
            fullText: "Test transcription",
            language: .english,
            duration: .seconds(60),
            processingTime: .seconds(5)
        )
        
        await service.setTranscribeFileResult(mockResult)
        
        let result = try await service.transcribeFile(
            at: URL(fileURLWithPath: "/tmp/test.wav"),
            language: .english,
            speakerDiarization: false,
            progressHandler: nil
        )
        
        XCTAssertEqual(result.fullText, "Test transcription")
        XCTAssertEqual(result.language, .english)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Batch transcription test not yet implemented")
    }
    
    /// Property: Processing time estimate must be positive
    func test_estimateProcessingTime_isPositive() async {
        let service = await MockBatchTranscriptionService(
            backendID: .assemblyAI,
            displayName: "AssemblyAI Test"
        )
        
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        let estimate = await service.estimateProcessingTime(for: audioURL)
        
        XCTAssertGreaterThan(estimate, .zero, "Processing time estimate must be positive")
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Processing time test not yet implemented")
    }
    
    /// Property: Progress handler must receive monotonically increasing progress
    func test_progressHandler_receivesMonotonicProgress() async throws {
        let service = await MockBatchTranscriptionService(
            backendID: .assemblyAI,
            displayName: "AssemblyAI Test"
        )
        
        var progressValues: [Double] = []
        
        let mockResult = BatchTranscriptionResult(
            transcriptID: TranscriptID(),
            segments: [],
            fullText: "Test",
            language: .english,
            duration: .seconds(60),
            processingTime: .seconds(5)
        )
        await service.setTranscribeFileResult(mockResult)
        
        let progressHandler: @Sendable (TranscriptionProgress) -> Void = { progress in
            progressValues.append(progress.percentage)
        }
        
        _ = try await service.transcribeFile(
            at: URL(fileURLWithPath: "/tmp/test.wav"),
            language: .english,
            speakerDiarization: false,
            progressHandler: progressHandler
        )
        
        // Verify monotonically increasing
        for i in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(
                progressValues[i],
                progressValues[i-1],
                "Progress must be monotonically increasing"
            )
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Progress handler test not yet implemented")
    }
}

// MARK: - AudioCaptureService Property Tests

@available(macOS 15.0, *)
final class AudioCaptureServicePropertyTests: XCTestCase {
    
    /// Property: AudioCaptureService must be Sendable-safe
    func test_audioCaptureService_isSendableSafe() async {
        let service = await MockAudioCaptureService(
            configuration: AudioCaptureConfiguration()
        )
        
        async let result1: Void = { await service.checkPermissions() }()
        async let result2: Void = { await service.checkPermissions() }()
        
        _ = await (result1, result2)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Sendable safety test not yet implemented")
    }
    
    /// Property: Permissions must be checked before capture
    func test_permissionsCheckedBeforeCapture() async {
        let service = await MockAudioCaptureService(
            configuration: AudioCaptureConfiguration()
        )
        
        let permissions = await service.checkPermissions()
        
        // If not authorized, isCapturing should be false
        if !permissions.allGranted {
            let isCapturing = await service.isCapturing
            XCTAssertFalse(isCapturing, "Should not be capturing without permissions")
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Permission check test not yet implemented")
    }
    
    /// Property: AudioBuffer duration calculation is consistent
    func test_audioBuffer_durationCalculation() {
        let samples = Array(repeating: Float(0.0), count: 48000) // 1 second at 48kHz
        let buffer = AudioBuffer(
            samples: samples,
            sampleRate: 48000,
            channelCount: 1,
            timestamp: .seconds(0),
            id: AudioSegmentID()
        )
        
        XCTAssertEqual(buffer.duration, .seconds(1), accuracy: 0.001)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Duration calculation test not yet implemented")
    }
    
    /// Property: toMono reduces channel count to 1
    func test_audioBuffer_toMono() {
        let samples = Array(repeating: Float(0.0), count: 96000) // Stereo, 1 second at 48kHz
        let stereoBuffer = AudioBuffer(
            samples: samples,
            sampleRate: 48000,
            channelCount: 2,
            timestamp: .seconds(0),
            id: AudioSegmentID()
        )
        
        let monoBuffer = stereoBuffer.toMono()
        
        XCTAssertEqual(monoBuffer.channelCount, 1)
        XCTAssertEqual(monoBuffer.samples.count, 48000)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Mono conversion test not yet implemented")
    }
    
    /// Property: isCapturing reflects actual capture state
    func test_isCapturing_reflectsState() async throws {
        let service = await MockAudioCaptureService(
            configuration: AudioCaptureConfiguration()
        )
        
        XCTAssertFalse(await service.isCapturing)
        
        _ = try await service.startCapture()
        // After starting, should be capturing
        // Note: Mock may need to update state
        
        await service.stopCapture()
        // After stopping, should not be capturing
        XCTAssertFalse(await service.isCapturing)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Capture state test not yet implemented")
    }
}

// MARK: - Repository Property Tests

@available(macOS 15.0, *)
final class RepositoryPropertyTests: XCTestCase {
    
    // MARK: - SessionRepository Properties
    
    /// Property: Save then get returns same session
    func test_sessionRepository_saveGetRoundTrip() async throws {
        let repository = await MockSessionRepository()
        let meetingID = MeetingID()
        let session = Session(
            id: SessionID(),
            meetingID: meetingID,
            startTime: Date()
        )
        
        let saveResult = await repository.save(session)
        XCTAssertTrue(saveResult.isSuccess)
        
        let getResult = await repository.get(by: session.id)
        
        switch getResult {
        case .success(let retrieved):
            XCTAssertEqual(retrieved.id, session.id)
            XCTAssertEqual(retrieved.meetingID, session.meetingID)
        case .failure:
            XCTFail("Should retrieve saved session")
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Save/Get roundtrip test not yet implemented")
    }
    
    /// Property: Exists returns true after save
    func test_sessionRepository_existsAfterSave() async throws {
        let repository = await MockSessionRepository()
        let session = Session(
            id: SessionID(),
            meetingID: MeetingID(),
            startTime: Date()
        )
        
        let existsBefore = await repository.exists(id: session.id)
        XCTAssertFalse(existsBefore)
        
        _ = await repository.save(session)
        
        let existsAfter = await repository.exists(id: session.id)
        XCTAssertTrue(existsAfter)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Exists test not yet implemented")
    }
    
    /// Property: Delete removes session
    func test_sessionRepository_deleteRemovesSession() async throws {
        let repository = await MockSessionRepository()
        let session = Session(
            id: SessionID(),
            meetingID: MeetingID(),
            startTime: Date()
        )
        
        _ = await repository.save(session)
        let existsBefore = await repository.exists(id: session.id)
        XCTAssertTrue(existsBefore)
        
        _ = await repository.delete(id: session.id)
        let existsAfter = await repository.exists(id: session.id)
        XCTAssertFalse(existsAfter)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Delete test not yet implemented")
    }
    
    /// Property: Query by meetingID returns matching sessions
    func test_sessionRepository_queryByMeetingID() async throws {
        let repository = await MockSessionRepository()
        let meetingID = MeetingID()
        
        let session1 = Session(id: SessionID(), meetingID: meetingID, startTime: Date())
        let session2 = Session(id: SessionID(), meetingID: MeetingID(), startTime: Date())
        let session3 = Session(id: SessionID(), meetingID: meetingID, startTime: Date())
        
        _ = await repository.save(session1)
        _ = await repository.save(session2)
        _ = await repository.save(session3)
        
        let result = await repository.getSessions(for: meetingID)
        
        switch result {
        case .success(let sessions):
            XCTAssertEqual(sessions.count, 2)
            XCTAssertTrue(sessions.allSatisfy { $0.meetingID == meetingID })
        case .failure:
            XCTFail("Query should succeed")
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Query test not yet implemented")
    }
    
    // MARK: - TranscriptRepository Properties
    
    /// Property: Save then get returns same transcript
    func test_transcriptRepository_saveGetRoundTrip() async throws {
        let repository = await MockTranscriptRepository()
        let transcript = Transcript(
            id: TranscriptID(),
            sessionID: SessionID(),
            language: "en"
        )
        
        let saveResult = await repository.save(transcript)
        XCTAssertTrue(saveResult.isSuccess)
        
        let getResult = await repository.get(by: transcript.id)
        
        switch getResult {
        case .success(let retrieved):
            XCTAssertEqual(retrieved.id, transcript.id)
            XCTAssertEqual(retrieved.language, transcript.language)
        case .failure:
            XCTFail("Should retrieve saved transcript")
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Transcript roundtrip test not yet implemented")
    }
    
    /// Property: Get for session returns transcript if exists
    func test_transcriptRepository_getForSession() async throws {
        let repository = await MockTranscriptRepository()
        let sessionID = SessionID()
        let transcript = Transcript(
            id: TranscriptID(),
            sessionID: sessionID,
            language: "en"
        )
        
        await repository.setGetForSessionResult(.success(transcript))
        
        let result = await repository.getTranscript(for: sessionID)
        
        switch result {
        case .success(let retrieved):
            XCTAssertNotNil(retrieved)
            XCTAssertEqual(retrieved?.sessionID, sessionID)
        case .failure:
            XCTFail("Should retrieve transcript for session")
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Get for session test not yet implemented")
    }
    
    // MARK: - SettingsRepository Properties
    
    /// Property: Set then get returns same value (String)
    func test_settingsRepository_stringRoundTrip() async {
        let repository = await MockSettingsRepository()
        
        await repository.set("test-value", for: .defaultTranscriptionBackend)
        let retrieved = await repository.string(for: .defaultTranscriptionBackend)
        
        XCTAssertEqual(retrieved, "test-value")
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: String roundtrip test not yet implemented")
    }
    
    /// Property: Set then get returns same value (Bool)
    func test_settingsRepository_boolRoundTrip() async {
        let repository = await MockSettingsRepository()
        
        await repository.set(true, for: .autoStartRecording)
        let retrieved = await repository.bool(for: .autoStartRecording)
        
        XCTAssertTrue(retrieved)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Bool roundtrip test not yet implemented")
    }
    
    /// Property: Set then get returns same value (Int)
    func test_settingsRepository_intRoundTrip() async {
        let repository = await MockSettingsRepository()
        
        await repository.set(42, for: .storageLimit)
        let retrieved = await repository.integer(for: .storageLimit)
        
        XCTAssertEqual(retrieved, 42)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Int roundtrip test not yet implemented")
    }
    
    /// Property: Remove clears value
    func test_settingsRepository_removeClearsValue() async {
        let repository = await MockSettingsRepository()
        
        await repository.set("test", for: .defaultTranscriptionBackend)
        XCTAssertNotNil(await repository.string(for: .defaultTranscriptionBackend))
        
        await repository.remove(key: .defaultTranscriptionBackend)
        XCTAssertNil(await repository.string(for: .defaultTranscriptionBackend))
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Remove test not yet implemented")
    }
    
    /// Property: Observer is called when value changes
    func test_settingsRepository_observerCalled() async {
        let repository = await MockSettingsRepository()
        var observerCalled = false
        
        let token = await repository.addObserver(for: .autoStartRecording) {
            observerCalled = true
        }
        
        await repository.set(true, for: .autoStartRecording)
        
        // Allow time for async observer
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertTrue(observerCalled, "Observer should be called when value changes")
        
        await repository.removeObserver(token)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Observer test not yet implemented")
    }
    
    /// Property: Reset to defaults clears all values
    func test_settingsRepository_resetToDefaults() async {
        let repository = await MockSettingsRepository()
        
        await repository.set("value1", for: .defaultTranscriptionBackend)
        await repository.set(true, for: .autoStartRecording)
        await repository.set(100, for: .storageLimit)
        
        await repository.resetToDefaults()
        
        XCTAssertNil(await repository.string(for: .defaultTranscriptionBackend))
        XCTAssertFalse(await repository.bool(for: .autoStartRecording))
        XCTAssertEqual(await repository.integer(for: .storageLimit), 0)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Reset test not yet implemented")
    }
}

// MARK: - LLMService Property Tests

@available(macOS 15.0, *)
final class LLMServicePropertyTests: XCTestCase {
    
    /// Property: complete returns valid response
    func test_llmService_completeReturnsValidResponse() async throws {
        let service = await MockLLMService()
        
        let response = await service.complete(
            prompt: "Hello",
            configuration: LLMConfiguration(model: "test-model")
        )
        
        switch response {
        case .success(let result):
            XCTAssertFalse(result.content.isEmpty, "Response should not be empty")
            XCTAssertFalse(result.model.isEmpty, "Model should not be empty")
            XCTAssertGreaterThanOrEqual(result.tokensUsed, 0)
        case .failure(let error):
            XCTFail("Should not fail: \(error)")
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Complete test not yet implemented")
    }
    
    /// Property: chat returns valid response
    func test_llmService_chatReturnsValidResponse() async throws {
        let service = await MockLLMService()
        
        let messages = [
            LLMMessage(role: .system, content: "You are a helpful assistant"),
            LLMMessage(role: .user, content: "Hello")
        ]
        
        let response = await service.chat(
            messages: messages,
            configuration: LLMConfiguration(model: "test-model")
        )
        
        switch response {
        case .success(let result):
            XCTAssertFalse(result.content.isEmpty)
        case .failure:
            XCTFail("Should not fail")
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Chat test not yet implemented")
    }
    
    /// Property: streamComplete yields content
    func test_llmService_streamCompleteYieldsContent() async throws {
        let service = await MockLLMService()
        
        let stream = await service.streamComplete(
            prompt: "Hello",
            configuration: LLMConfiguration(model: "test-model")
        )
        
        var chunks: [String] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }
        
        XCTAssertFalse(chunks.isEmpty, "Stream should yield content")
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Stream test not yet implemented")
    }
    
    /// Property: listAvailableModels returns non-empty list when available
    func test_llmService_listModelsWhenAvailable() async {
        let service = await MockLLMService()
        await service.setIsAvailableResult(true)
        
        let isAvailable = await service.isAvailable()
        let models = await service.listAvailableModels()
        
        XCTAssertTrue(isAvailable)
        
        switch models {
        case .success(let list):
            XCTAssertFalse(list.isEmpty, "Should return models when available")
        case .failure:
            XCTFail("Should not fail when available")
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: List models test not yet implemented")
    }
}

// MARK: - ServiceFactory Property Tests

@available(macOS 15.0, *)
final class ServiceFactoryPropertyTests: XCTestCase {
    
    /// Property: Factory creates non-nil services for configured backends
    func test_serviceFactory_createsServices() async {
        let factory = await MockServiceFactory()
        let backend = BackendID.whisperKit
        
        let transcriptionService = await factory.makeTranscriptionService(backend: backend)
        // Should return nil or a service depending on configuration
        // The test verifies the API contract
        
        let captureService = await factory.makeAudioCaptureService(
            configuration: AudioCaptureConfiguration()
        )
        XCTAssertNotNil(captureService)
        
        let sessionRepo = await factory.makeSessionRepository()
        XCTAssertNotNil(sessionRepo)
        
        let transcriptRepo = await factory.makeTranscriptRepository()
        XCTAssertNotNil(transcriptRepo)
        
        let settingsRepo = await factory.makeSettingsRepository()
        XCTAssertNotNil(settingsRepo)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Service creation test not yet implemented")
    }
    
    /// Property: Created services are Sendable-safe
    func test_serviceFactory_createdServicesAreSendable() async {
        let factory = await MockServiceFactory()
        
        let sessionRepo = await factory.makeSessionRepository()
        let transcriptRepo = await factory.makeTranscriptRepository()
        
        // Test concurrent access
        async let result1 = sessionRepo.count()
        async let result2 = transcriptRepo.search(query: "test", meetingID: nil)
        
        _ = await (result1, result2)
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Sendable safety test not yet implemented")
    }
}

// MARK: - Error Handling Property Tests

@available(macOS 15.0, *)
final class ErrorHandlingPropertyTests: XCTestCase {
    
    /// Property: StorageError descriptions are non-empty
    func test_storageError_descriptionsAreValid() {
        let errors: [StorageError] = [
            .writeFailed(path: "/tmp/test", underlying: nil),
            .readFailed(path: "/tmp/test", underlying: nil),
            .corruptionDetected(entity: "Session", id: "123"),
            .notFound(entity: "Session", id: "123"),
            .migrationFailed(fromVersion: 1, toVersion: 2, reason: "Incompatible"),
            .quotaExceeded(available: nil),
            .invalidPath(path: "/invalid")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Error descriptions test not yet implemented")
    }
    
    /// Property: TranscriptionError descriptions are non-empty
    func test_transcriptionError_descriptionsAreValid() {
        let errors: [TranscriptionError] = [
            .backendFailed(backend: "test", reason: "Failed", recoverable: false),
            .audioFormatUnsupported(format: "ogg", supportedFormats: ["wav", "mp3"]),
            .timeout(operation: "transcribe", duration: .seconds(30)),
            .modelUnavailable(model: "whisper-large", reason: "Not downloaded"),
            .networkFailure(reason: "Connection lost"),
            .rateLimited(provider: "AssemblyAI", retryAfter: nil)
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Transcription error descriptions test not yet implemented")
    }
    
    /// Property: AudioError descriptions are non-empty
    func test_audioError_descriptionsAreValid() {
        let errors: [AudioError] = [
            .captureFailed(device: "mic", reason: "Disconnected"),
            .formatUnsupported(format: "aac", sampleRate: nil),
            .permissionDenied,
            .deviceNotFound(device: "USB Mic"),
            .hardwareError(code: 42),
            .configurationFailed(reason: "Invalid sample rate"),
            .bufferOverflow(maxSize: 1024),
            .codecError(codec: "opus")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Audio error descriptions test not yet implemented")
    }
    
    /// Property: NetworkError descriptions are non-empty
    func test_networkError_descriptionsAreValid() {
        let errors: [NetworkError] = [
            .noConnectivity,
            .apiFailure(endpoint: "/api/v1/transcribe", statusCode: 500, message: "Server error"),
            .requestTimeout(endpoint: "/api", timeout: .seconds(30)),
            .dnsResolutionFailed(host: "api.example.com"),
            .sslError(reason: "Certificate expired"),
            .invalidURL(url: "not-a-url"),
            .responseParsingFailed(endpoint: "/api", reason: "Invalid JSON"),
            .authenticationFailed(reason: "Invalid API key")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
        
        // Intentionally fail to verify RED phase
        XCTFail("RED PHASE: Network error descriptions test not yet implemented")
    }
}

// MARK: - Extension Helpers

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    var isFailure: Bool {
        !isSuccess
    }
}
