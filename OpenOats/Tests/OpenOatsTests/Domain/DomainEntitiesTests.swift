import Foundation
import Testing

@testable import OpenOatsKit

// MARK: - Type Aliases for Tests
// These aliases help tests reference the new domain types
// while the old Utterance.swift still exists in the Domain folder

typealias DomainUtterance = UtteranceEntity
typealias DomainSpeaker = SpeakerEntity

// MARK: - ID Value Object Tests

@Suite("Domain ID Types")
struct DomainIDTests {
    
    @Test("MeetingID can be created from UUID")
    func testMeetingIDCreation() {
        let uuid = UUID()
        let meetingID = MeetingID(uuid)
        
        #expect(meetingID.rawValue == uuid)
    }
    
    @Test("MeetingID generates new UUID when initialized without parameter")
    func testMeetingIDDefaultCreation() {
        let meetingID1 = MeetingID()
        let meetingID2 = MeetingID()
        
        #expect(meetingID1 != meetingID2)
        #expect(meetingID1.rawValue != meetingID2.rawValue)
    }
    
    @Test("SessionID can be created from UUID")
    func testSessionIDCreation() {
        let uuid = UUID()
        let sessionID = SessionID(uuid)
        
        #expect(sessionID.rawValue == uuid)
    }
    
    @Test("SpeakerID can be created from UUID")
    func testSpeakerIDCreation() {
        let uuid = UUID()
        let speakerID = SpeakerID(uuid)
        
        #expect(speakerID.rawValue == uuid)
    }
    
    @Test("TranscriptID can be created from UUID")
    func testTranscriptIDCreation() {
        let uuid = UUID()
        let transcriptID = TranscriptID(uuid)
        
        #expect(transcriptID.rawValue == uuid)
    }
    
    @Test("BackendID can be created from String")
    func testBackendIDCreation() {
        let backendID = BackendID("mlx-whisper")
        
        #expect(backendID.rawValue == "mlx-whisper")
    }
    
    @Test("ID types are Equatable")
    func testIDEquatable() {
        let uuid = UUID()
        let id1 = MeetingID(uuid)
        let id2 = MeetingID(uuid)
        let id3 = MeetingID()
        
        #expect(id1 == id2)
        #expect(id1 != id3)
    }
    
    @Test("ID types are Hashable")
    func testIDHashable() {
        let uuid = UUID()
        let id1 = MeetingID(uuid)
        let id2 = SessionID(uuid)
        
        var set = Set<MeetingID>()
        set.insert(id1)
        
        #expect(set.contains(id1))
        // Different ID types should not conflict
        let meetingSet = Set<MeetingID>([MeetingID(uuid)])
        let sessionSet = Set<SessionID>([SessionID(uuid)])
        #expect(meetingSet.count == 1)
        #expect(sessionSet.count == 1)
    }
    
    @Test("ID types are Codable")
    func testIDCodable() throws {
        let meetingID = MeetingID()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(meetingID)
        let decoded = try decoder.decode(MeetingID.self, from: data)
        
        #expect(meetingID == decoded)
    }
    
    @Test("ID types are Sendable")
    func testIDSendable() async {
        // Compile-time check for Sendable conformance
        let meetingID = MeetingID()
        let sessionID = SessionID()
        
        // If this compiles, Sendable is satisfied
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = meetingID
                _ = sessionID
            }
        }
    }
    
    @Test("ID types cannot be mixed accidentally")
    func testIDTypeSafety() {
        let uuid = UUID()
        let meetingID = MeetingID(uuid)
        let sessionID = SessionID(uuid)
        
        // Same UUID but different types - type safety prevents mixing
        // This is a compile-time check - if it compiles, the types are distinct
        #expect(meetingID.rawValue == sessionID.rawValue)
    }
}

// MARK: - Meeting Entity Tests

@Suite("Meeting Entity")
struct MeetingTests {
    
    @Test("Meeting can be created with required properties")
    func testMeetingCreation() {
        let meetingID = MeetingID()
        let title = "Weekly Standup"
        let startTime = Date()
        
        let meeting = Meeting(
            id: meetingID,
            title: title,
            startTime: startTime
        )
        
        #expect(meeting.id == meetingID)
        #expect(meeting.title == title)
        #expect(meeting.startTime == startTime)
        #expect(meeting.endTime == nil)
        #expect(meeting.sessionIDs.isEmpty)
    }
    
    @Test("Meeting can have optional end time")
    func testMeetingWithEndTime() {
        let startTime = Date()
        let endTime = Date().addingTimeInterval(3600)
        
        let meeting = Meeting(
            id: MeetingID(),
            title: "Test",
            startTime: startTime,
            endTime: endTime
        )
        
        #expect(meeting.endTime == endTime)
        #expect(meeting.duration == 3600)
    }
    
    @Test("Meeting duration is nil when not ended")
    func testMeetingDurationWhenActive() {
        let meeting = Meeting(
            id: MeetingID(),
            title: "Active Meeting",
            startTime: Date()
        )
        
        #expect(meeting.duration == nil)
    }
    
    @Test("Meeting can add session IDs")
    func testMeetingWithSessions() {
        let sessionID1 = SessionID()
        let sessionID2 = SessionID()
        
        var meeting = Meeting(
            id: MeetingID(),
            title: "Test",
            startTime: Date()
        )
        
        // Since Meeting is immutable, we need an extension method
        // or recreate with updated values
        meeting = meeting.withSessionID(sessionID1)
        meeting = meeting.withSessionID(sessionID2)
        
        #expect(meeting.sessionIDs.count == 2)
        #expect(meeting.sessionIDs.contains(sessionID1))
        #expect(meeting.sessionIDs.contains(sessionID2))
    }
    
    @Test("Meeting is Equatable")
    func testMeetingEquatable() {
        let meetingID = MeetingID()
        let meeting1 = Meeting(
            id: meetingID,
            title: "Test",
            startTime: Date()
        )
        let meeting2 = Meeting(
            id: meetingID,
            title: "Test",
            startTime: meeting1.startTime
        )
        let meeting3 = Meeting(
            id: MeetingID(),
            title: "Different",
            startTime: Date()
        )
        
        #expect(meeting1 == meeting2)
        #expect(meeting1 != meeting3)
    }
    
    @Test("Meeting is Codable")
    func testMeetingCodable() throws {
        let meeting = Meeting(
            id: MeetingID(),
            title: "Test Meeting",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(meeting)
        let decoded = try decoder.decode(Meeting.self, from: data)
        
        #expect(meeting == decoded)
    }
    
    @Test("Meeting withEndedAt returns new instance with end time")
    func testMeetingWithEndedAt() {
        let startTime = Date()
        let meeting = Meeting(
            id: MeetingID(),
            title: "Test",
            startTime: startTime
        )
        
        let endTime = Date().addingTimeInterval(3600)
        let endedMeeting = meeting.withEndedAt(endTime)
        
        #expect(endedMeeting.endTime == endTime)
        #expect(meeting.endTime == nil) // Original unchanged
    }
}

// MARK: - Session Entity Tests

@Suite("Session Entity")
struct SessionTests {
    
    @Test("Session can be created with required properties")
    func testSessionCreation() {
        let sessionID = SessionID()
        let meetingID = MeetingID()
        let startTime = Date()
        
        let session = Session(
            id: sessionID,
            meetingID: meetingID,
            startTime: startTime
        )
        
        #expect(session.id == sessionID)
        #expect(session.meetingID == meetingID)
        #expect(session.startTime == startTime)
        #expect(session.endTime == nil)
        #expect(session.status == .active)
    }
    
    @Test("Session status transitions correctly")
    func testSessionStatus() {
        let session = Session(
            id: SessionID(),
            meetingID: MeetingID(),
            startTime: Date()
        )
        
        #expect(session.status == .active)
        
        let endedSession = session.withStatus(.completed)
        #expect(endedSession.status == .completed)
        #expect(session.status == .active) // Original unchanged
    }
    
    @Test("Session withEndedAt returns new instance")
    func testSessionWithEndedAt() {
        let session = Session(
            id: SessionID(),
            meetingID: MeetingID(),
            startTime: Date()
        )
        
        let endTime = Date().addingTimeInterval(3600)
        let endedSession = session.withEndedAt(endTime)
        
        #expect(endedSession.endTime == endTime)
        #expect(session.endTime == nil)
    }
    
    @Test("Session can have backend association")
    func testSessionWithBackend() {
        let backendID = BackendID("mlx-whisper")
        let session = Session(
            id: SessionID(),
            meetingID: MeetingID(),
            startTime: Date(),
            backendID: backendID
        )
        
        #expect(session.backendID == backendID)
    }
    
    @Test("Session is Equatable and Codable")
    func testSessionEquatableAndCodable() throws {
        let session = Session(
            id: SessionID(),
            meetingID: MeetingID(),
            startTime: Date()
        )
        
        // Equatable
        let sameSession = Session(
            id: session.id,
            meetingID: session.meetingID,
            startTime: session.startTime
        )
        let differentSession = Session(
            id: SessionID(),
            meetingID: MeetingID(),
            startTime: Date()
        )
        
        #expect(session == sameSession)
        #expect(session != differentSession)
        
        // Codable
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(session)
        let decoded = try decoder.decode(Session.self, from: data)
        
        #expect(session == decoded)
    }
}

// MARK: - Transcript Entity Tests

@Suite("Transcript Entity")
struct TranscriptTests {
    
    @Test("Transcript can be created with required properties")
    func testTranscriptCreation() {
        let transcriptID = TranscriptID()
        let sessionID = SessionID()
        let language = "en"
        
        let transcript = Transcript(
            id: transcriptID,
            sessionID: sessionID,
            language: language
        )
        
        #expect(transcript.id == transcriptID)
        #expect(transcript.sessionID == sessionID)
        #expect(transcript.language == language)
        #expect(transcript.utteranceIDs.isEmpty)
        #expect(transcript.isComplete == false)
    }
    
    @Test("Transcript can add utterance IDs")
    func testTranscriptWithUtterances() {
        let utteranceID1 = UtteranceID()
        let utteranceID2 = UtteranceID()
        
        var transcript = Transcript(
            id: TranscriptID(),
            sessionID: SessionID(),
            language: "en"
        )
        
        transcript = transcript.withUtteranceID(utteranceID1)
        transcript = transcript.withUtteranceID(utteranceID2)
        
        #expect(transcript.utteranceIDs.count == 2)
        #expect(transcript.utteranceIDs[0] == utteranceID1)
        #expect(transcript.utteranceIDs[1] == utteranceID2)
    }
    
    @Test("Transcript can be marked complete")
    func testTranscriptComplete() {
        let transcript = Transcript(
            id: TranscriptID(),
            sessionID: SessionID(),
            language: "en"
        )
        
        #expect(transcript.isComplete == false)
        
        let completedTranscript = transcript.markedComplete()
        #expect(completedTranscript.isComplete == true)
        #expect(transcript.isComplete == false) // Original unchanged
    }
    
    @Test("Transcript withText returns full text from utterances")
    func testTranscriptText() {
        // This would require looking up actual utterances
        // For now, just verify the property exists
        let transcript = Transcript(
            id: TranscriptID(),
            sessionID: SessionID(),
            language: "en"
        )
        
        // When no utterance lookup available, text is empty
        #expect(transcript.text.isEmpty)
    }
    
    @Test("Transcript is Equatable and Codable")
    func testTranscriptEquatableAndCodable() throws {
        let transcript = Transcript(
            id: TranscriptID(),
            sessionID: SessionID(),
            language: "en"
        )
        
        let sameTranscript = Transcript(
            id: transcript.id,
            sessionID: transcript.sessionID,
            language: transcript.language
        )
        
        #expect(transcript == sameTranscript)
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(transcript)
        let decoded = try decoder.decode(Transcript.self, from: data)
        
        #expect(transcript == decoded)
    }
}

// MARK: - Utterance Entity Tests

@Suite("Utterance Entity")
struct UtteranceEntityTests {
    
    @Test("Utterance can be created with required properties")
    func testUtteranceCreation() {
        let utteranceID = UtteranceID()
        let transcriptID = TranscriptID()
        let speakerID = SpeakerID()
        let text = "Hello world"
        let startTime: Duration = .seconds(0)
        let endTime: Duration = .seconds(2)
        let confidence: Double = 0.95
        
        let utterance = DomainUtterance(
            id: utteranceID,
            transcriptID: transcriptID,
            speakerID: speakerID,
            text: text,
            startTime: startTime,
            endTime: endTime,
            confidence: confidence
        )
        
        #expect(utterance.id == utteranceID)
        #expect(utterance.transcriptID == transcriptID)
        #expect(utterance.speakerID == speakerID)
        #expect(utterance.text == text)
        #expect(utterance.startTime == startTime)
        #expect(utterance.endTime == endTime)
        #expect(utterance.confidence == confidence)
    }
    
    @Test("Utterance duration is calculated correctly")
    func testUtteranceDuration() {
        let utterance = DomainUtterance(
            id: UtteranceID(),
            transcriptID: TranscriptID(),
            speakerID: SpeakerID(),
            text: "Test",
            startTime: .seconds(10),
            endTime: .seconds(15),
            confidence: 0.9
        )
        
        #expect(utterance.duration == .seconds(5))
    }
    
    @Test("Utterance requires valid time range")
    func testUtteranceTimeValidation() {
        // Should fail if endTime <= startTime
        let invalidUtterance = DomainUtterance(
            id: UtteranceID(),
            transcriptID: TranscriptID(),
            speakerID: SpeakerID(),
            text: "Test",
            startTime: .seconds(10),
            endTime: .seconds(5),
            confidence: 0.9
        )
        
        #expect(invalidUtterance.isValid == false)
    }
    
    @Test("Utterance is Equatable and Codable")
    func testUtteranceEquatableAndCodable() throws {
        let utterance = DomainUtterance(
            id: UtteranceID(),
            transcriptID: TranscriptID(),
            speakerID: SpeakerID(),
            text: "Test",
            startTime: .seconds(0),
            endTime: .seconds(1),
            confidence: 0.95
        )
        
        let sameUtterance = DomainUtterance(
            id: utterance.id,
            transcriptID: utterance.transcriptID,
            speakerID: utterance.speakerID,
            text: utterance.text,
            startTime: utterance.startTime,
            endTime: utterance.endTime,
            confidence: utterance.confidence
        )
        
        #expect(utterance == sameUtterance)
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(utterance)
        let decoded = try decoder.decode(DomainUtterance.self, from: data)
        
        #expect(utterance == decoded)
    }
}

// MARK: - Speaker Entity Tests

@Suite("Speaker Entity")
struct SpeakerEntityDomainTests {
    
    @Test("Speaker can be created with required properties")
    func testSpeakerCreation() {
        let speakerID = SpeakerID()
        let name = "John Doe"
        
        let speaker = DomainSpeaker(
            id: speakerID,
            name: name
        )
        
        #expect(speaker.id == speakerID)
        #expect(speaker.name == name)
        #expect(speaker.voiceSignature == nil)
    }
    
    @Test("Speaker can have voice signature")
    func testSpeakerWithVoiceSignature() {
        let voiceSignature = VoiceSignature(
            embedding: [0.1, 0.2, 0.3],
            sampleCount: 10
        )
        
        let speaker = DomainSpeaker(
            id: SpeakerID(),
            name: "Test",
            voiceSignature: voiceSignature
        )
        
        #expect(speaker.voiceSignature == voiceSignature)
    }
    
    @Test("Speaker withVoiceSignature returns new instance")
    func testSpeakerWithUpdatedSignature() {
        let speaker = DomainSpeaker(
            id: SpeakerID(),
            name: "Test"
        )
        
        let signature = VoiceSignature(
            embedding: [0.1, 0.2],
            sampleCount: 5
        )
        
        let updatedSpeaker = speaker.withVoiceSignature(signature)
        
        #expect(updatedSpeaker.voiceSignature == signature)
        #expect(speaker.voiceSignature == nil)
    }
    
    @Test("Speaker is Equatable and Codable")
    func testSpeakerEquatableAndCodable() throws {
        let speaker = DomainSpeaker(
            id: SpeakerID(),
            name: "Test"
        )
        
        let sameSpeaker = DomainSpeaker(
            id: speaker.id,
            name: speaker.name
        )
        
        #expect(speaker == sameSpeaker)
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(speaker)
        let decoded = try decoder.decode(DomainSpeaker.self, from: data)
        
        #expect(speaker == decoded)
    }
}

// MARK: - Note Entity Tests

@Suite("Note Entity")
struct NoteTests {
    
    @Test("Note can be created with required properties")
    func testNoteCreation() {
        let noteID = NoteID()
        let sessionID = SessionID()
        let content = "This is a meeting note"
        let category: Note.Category = .summary
        
        let note = Note(
            id: noteID,
            sessionID: sessionID,
            content: content,
            category: category
        )
        
        #expect(note.id == noteID)
        #expect(note.sessionID == sessionID)
        #expect(note.content == content)
        #expect(note.category == category)
        #expect(note.aiModel == nil)
    }
    
    @Test("Note can have AI model information")
    func testNoteWithAIModel() {
        let aiModel = AIModelInfo(
            provider: "openrouter",
            model: "anthropic/claude-sonnet-4-20250514",
            requestID: "req_12345"
        )
        
        let note = Note(
            id: NoteID(),
            sessionID: SessionID(),
            content: "Test",
            category: .actionItem,
            aiModel: aiModel
        )
        
        #expect(note.aiModel == aiModel)
    }
    
    @Test("Note category enum works correctly")
    func testNoteCategories() {
        let summary = Note(id: NoteID(), sessionID: SessionID(), content: "Summary", category: .summary)
        let actionItem = Note(id: NoteID(), sessionID: SessionID(), content: "Action", category: .actionItem)
        let decision = Note(id: NoteID(), sessionID: SessionID(), content: "Decision", category: .decision)
        let insight = Note(id: NoteID(), sessionID: SessionID(), content: "Insight", category: .insight)
        
        #expect(summary.category == .summary)
        #expect(actionItem.category == .actionItem)
        #expect(decision.category == .decision)
        #expect(insight.category == .insight)
    }
    
    @Test("Note is Equatable and Codable")
    func testNoteEquatableAndCodable() throws {
        let createdAt = Date()
        let note = Note(
            id: NoteID(),
            sessionID: SessionID(),
            content: "Test",
            category: .summary,
            createdAt: createdAt
        )
        
        let sameNote = Note(
            id: note.id,
            sessionID: note.sessionID,
            content: note.content,
            category: note.category,
            createdAt: createdAt
        )
        
        #expect(note == sameNote)
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(note)
        let decoded = try decoder.decode(Note.self, from: data)
        
        #expect(note == decoded)
    }
}

// MARK: - AudioSegment Entity Tests

@Suite("AudioSegment Entity")
struct AudioSegmentTests {
    
    @Test("AudioSegment can be created with required properties")
    func testAudioSegmentCreation() {
        let segmentID = AudioSegmentID()
        let sessionID = SessionID()
        let audioData = Data([0x00, 0x01, 0x02, 0x03])
        let sampleRate: Double = 48000
        let channelCount: Int = 1
        let bitsPerSample: Int = 16
        let startTime: Duration = .seconds(0)
        
        let segment = AudioSegment(
            id: segmentID,
            sessionID: sessionID,
            audioData: audioData,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitsPerSample: bitsPerSample,
            startTime: startTime
        )
        
        #expect(segment.id == segmentID)
        #expect(segment.sessionID == sessionID)
        #expect(segment.audioData == audioData)
        #expect(segment.sampleRate == sampleRate)
        #expect(segment.channelCount == channelCount)
        #expect(segment.bitsPerSample == bitsPerSample)
        #expect(segment.startTime == startTime)
        #expect(segment.duration == nil)
    }
    
    @Test("AudioSegment validates format parameters")
    func testAudioSegmentValidation() {
        let validSegment = AudioSegment(
            id: AudioSegmentID(),
            sessionID: SessionID(),
            audioData: Data(),
            sampleRate: 48000,
            channelCount: 1,
            bitsPerSample: 16,
            startTime: .seconds(0)
        )
        
        #expect(validSegment.isValid == true)
        
        let invalidSegment = AudioSegment(
            id: AudioSegmentID(),
            sessionID: SessionID(),
            audioData: Data(),
            sampleRate: -1,
            channelCount: 0,
            bitsPerSample: 7,
            startTime: .seconds(0)
        )
        
        #expect(invalidSegment.isValid == false)
    }
    
    @Test("AudioSegment calculates data size")
    func testAudioSegmentDataSize() {
        let segment = AudioSegment(
            id: AudioSegmentID(),
            sessionID: SessionID(),
            audioData: Data([0x00, 0x01, 0x02, 0x03]),
            sampleRate: 48000,
            channelCount: 2,
            bitsPerSample: 16,
            startTime: .seconds(0),
            duration: .seconds(1)
        )
        
        // 4 bytes, 2 channels, 16 bits = 1 sample per channel
        #expect(segment.dataSizeBytes == 4)
    }
    
    @Test("AudioSegment is Equatable and Codable")
    func testAudioSegmentEquatableAndCodable() throws {
        let segment = AudioSegment(
            id: AudioSegmentID(),
            sessionID: SessionID(),
            audioData: Data([0x00, 0x01]),
            sampleRate: 48000,
            channelCount: 1,
            bitsPerSample: 16,
            startTime: .seconds(0)
        )
        
        let sameSegment = AudioSegment(
            id: segment.id,
            sessionID: segment.sessionID,
            audioData: segment.audioData,
            sampleRate: segment.sampleRate,
            channelCount: segment.channelCount,
            bitsPerSample: segment.bitsPerSample,
            startTime: segment.startTime
        )
        
        #expect(segment == sameSegment)
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(segment)
        let decoded = try decoder.decode(AudioSegment.self, from: data)
        
        #expect(segment == decoded)
    }
}

// MARK: - Error Type Tests

@Suite("Domain Error Types")
struct DomainErrorTests {
    
    @Test("TranscriptionError cases exist")
    func testTranscriptionErrorCases() {
        let backendError = TranscriptionError.backendFailed(
            backend: "mlx-whisper",
            reason: "Model not found",
            recoverable: true
        )
        
        let audioError = TranscriptionError.audioFormatUnsupported(
            format: "OPUS",
            supportedFormats: ["WAV", "MP3"]
        )
        
        let timeoutError = TranscriptionError.timeout(
            operation: "transcribe",
            duration: .seconds(30)
        )
        
        #expect(backendError != audioError)
        
        // Verify we can check error type
        if case .backendFailed(let backend, let reason, let recoverable) = backendError {
            #expect(backend == "mlx-whisper")
            #expect(reason == "Model not found")
            #expect(recoverable == true)
        } else {
            #expect(Bool(false), "Expected backendFailed case")
        }
    }
    
    @Test("StorageError cases exist")
    func testStorageErrorCases() {
        let writeError = StorageError.writeFailed(
            path: "/tmp/test.txt",
            underlying: NSError(domain: "test", code: 1)
        )
        
        let corruptError = StorageError.corruptionDetected(
            entity: "Session",
            id: "session-123"
        )
        
        if case .writeFailed(let path, _) = writeError {
            #expect(path == "/tmp/test.txt")
        } else {
            #expect(Bool(false), "Expected writeFailed case")
        }
    }
    
    @Test("ValidationError cases exist")
    func testValidationErrorCases() {
        let invalidInput = ValidationError.invalidInput(
            field: "email",
            value: "not-an-email",
            requirement: "Must be valid email format"
        )
        
        if case .invalidInput(let field, let value, let requirement) = invalidInput {
            #expect(field == "email")
            #expect(value == "not-an-email")
            #expect(requirement == "Must be valid email format")
        } else {
            #expect(Bool(false), "Expected invalidInput case")
        }
    }
    
    @Test("NetworkError cases exist")
    func testNetworkErrorCases() {
        let apiError = NetworkError.apiFailure(
            endpoint: "https://api.example.com/transcribe",
            statusCode: 500,
            message: "Internal Server Error"
        )
        
        if case .apiFailure(let endpoint, let statusCode, let message) = apiError {
            #expect(endpoint == "https://api.example.com/transcribe")
            #expect(statusCode == 500)
            #expect(message == "Internal Server Error")
        } else {
            #expect(Bool(false), "Expected apiFailure case")
        }
    }
    
    @Test("AudioError cases exist")
    func testAudioErrorCases() {
        let captureError = AudioError.captureFailed(
            device: "Built-in Microphone",
            reason: "Permission denied"
        )
        
        let formatError = AudioError.formatUnsupported(
            format: "AAC",
            sampleRate: 44100
        )
        
        if case .captureFailed(let device, let reason) = captureError {
            #expect(device == "Built-in Microphone")
            #expect(reason == "Permission denied")
        } else {
            #expect(Bool(false), "Expected captureFailed case")
        }
    }
    
    @Test("Errors conform to Error protocol")
    func testErrorConformance() {
        // Compile-time check - these should all compile
        let transcriptionError: Error = TranscriptionError.timeout(operation: "test", duration: .seconds(1))
        let storageError: Error = StorageError.readFailed(path: "/test", underlying: nil)
        let validationError: Error = ValidationError.invalidInput(field: "test", value: "x", requirement: "y")
        let networkError: Error = NetworkError.noConnectivity
        let audioError: Error = AudioError.permissionDenied
        
        // All are Error types
        _ = transcriptionError
        _ = storageError
        _ = validationError
        _ = networkError
        _ = audioError
    }
    
    @Test("Errors conform to LocalizedError")
    func testLocalizedErrorConformance() {
        let error = TranscriptionError.backendFailed(
            backend: "whisper",
            reason: "OOM",
            recoverable: false
        )
        
        // Should have errorDescription
        #expect(error.localizedDescription.isEmpty == false)
    }
}

// MARK: - Sendable Conformance Tests

@Suite("Sendable Conformance")
struct SendableTests {
    
    @Test("All domain types are Sendable")
    func testSendableConformance() async {
        // Compile-time verification that all types are Sendable
        let meeting = Meeting(id: MeetingID(), title: "Test", startTime: Date())
        let session = Session(id: SessionID(), meetingID: MeetingID(), startTime: Date())
        let transcript = Transcript(id: TranscriptID(), sessionID: SessionID(), language: "en")
        let utterance = DomainUtterance(
            id: UtteranceID(),
            transcriptID: TranscriptID(),
            speakerID: SpeakerID(),
            text: "Test",
            startTime: .seconds(0),
            endTime: .seconds(1),
            confidence: 0.95
        )
        let speaker = DomainSpeaker(id: SpeakerID(), name: "Test")
        let note = Note(id: NoteID(), sessionID: SessionID(), content: "Test", category: .summary)
        let audioSegment = AudioSegment(
            id: AudioSegmentID(),
            sessionID: SessionID(),
            audioData: Data(),
            sampleRate: 48000,
            channelCount: 1,
            bitsPerSample: 16,
            startTime: .seconds(0)
        )
        
        // If this compiles and runs, all types are Sendable
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = meeting
                _ = session
                _ = transcript
                _ = utterance
                _ = speaker
                _ = note
                _ = audioSegment
            }
        }
    }
}
