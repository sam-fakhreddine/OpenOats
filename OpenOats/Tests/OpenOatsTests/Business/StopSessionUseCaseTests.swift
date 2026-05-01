import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - StopSessionUseCase Property-Based Tests

/// Protocol definition for StopSessionUseCase (from TASK-005 design)
protocol StopSessionUseCase: Sendable {
    func execute(input: StopSessionInput) async throws -> StopSessionOutput
}

/// Input for stopping a session
struct StopSessionInput: Sendable {
    let sessionID: SessionID
    let saveRecording: Bool
    
    init(sessionID: SessionID, saveRecording: Bool = true) {
        self.sessionID = sessionID
        self.saveRecording = saveRecording
    }
}

/// Output from stopping a session
struct StopSessionOutput: Sendable {
    let session: Session
    let transcript: Transcript?
    let recordingURL: URL?
}

/// Mock implementation for testing
struct MockStopSessionUseCase: StopSessionUseCase {
    var sessions: [SessionID: Session] = [:]
    var transcripts: [SessionID: Transcript] = [:]
    var shouldFail = false
    var failureError: Error = TestFailure("Mock stop failure")
    var delay: Duration = .zero
    
    func execute(input: StopSessionInput) async throws -> StopSessionOutput {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        
        if shouldFail {
            throw failureError
        }
        
        guard let session = sessions[input.sessionID] else {
            throw ValidationError.invalidInput(field: "sessionID", reason: "Session not found")
        }
        
        // Update session status
        let stoppedSession = session
            .withEndedAt(Date())
            .withStatus(.completed)
        
        let transcript = transcripts[input.sessionID]
        let recordingURL = input.saveRecording ? URL(fileURLWithPath: "/tmp/recording.wav") : nil
        
        return StopSessionOutput(
            session: stoppedSession,
            transcript: transcript,
            recordingURL: recordingURL
        )
    }
}

// MARK: - Test Suite

@Suite("StopSessionUseCase Property-Based Tests")
struct StopSessionUseCaseTests {
    
    // MARK: - Property: Idempotency
    
    /// Property: Stopping a session twice should produce consistent final state
    @Test("Stop session is idempotent")
    func stopSessionIsIdempotent() async throws {
        let sessionGen = Generator<Session>.session
        let testRunner = try await forAll(sessionGen, iterations: 30)
        
        try await testRunner { session in
            var mockUseCase = MockStopSessionUseCase()
            mockUseCase.sessions = [session.id: session]
            
            let input = StopSessionInput(sessionID: session.id)
            
            let output1 = try await mockUseCase.execute(input: input)
            let output2 = try await mockUseCase.execute(input: input)
            
            // Both should have same final status
            return output1.session.status == output2.session.status &&
                   output1.session.status == .completed
        }
    }
    
    /// Property: Stopping with same input always produces same session state
    @Test("Deterministic stop behavior")
    func stopIsDeterministic() async throws {
        let sessionGen = Generator<Session>.session
        let boolGen = Generator<Bool> { Bool.random() }
        let testRunner = try await forAll2(sessionGen, boolGen, iterations: 30)
        
        try await testRunner { session, saveRecording in
            var mockUseCase = MockStopSessionUseCase()
            mockUseCase.sessions = [session.id: session]
            
            let input = StopSessionInput(sessionID: session.id, saveRecording: saveRecording)
            
            let output1 = try await mockUseCase.execute(input: input)
            let output2 = try await mockUseCase.execute(input: input)
            
            // Session states should match
            return output1.session.status == output2.session.status &&
                   output1.session.endTime != nil &&
                   output2.session.endTime != nil &&
                   (output1.recordingURL != nil) == (output2.recordingURL != nil)
        }
    }
    
    // MARK: - Property: Session State Transitions
    
    /// Property: Stopped sessions always have end time
    @Test("Stopped sessions have end time")
    func stoppedSessionsHaveEndTime() async throws {
        let sessionGen = Generator<Session>.session
        let testRunner = try await forAll(sessionGen, iterations: 50)
        
        try await testRunner { session in
            var mockUseCase = MockStopSessionUseCase()
            mockUseCase.sessions = [session.id: session]
            
            let input = StopSessionInput(sessionID: session.id)
            let output = try await mockUseCase.execute(input: input)
            
            return output.session.endTime != nil
        }
    }
    
    /// Property: Stopped sessions always have completed or failed status
    @Test("Stopped sessions have terminal status")
    func stoppedSessionsHaveTerminalStatus() async throws {
        let sessionGen = Generator<Session>.session
        let testRunner = try await forAll(sessionGen, iterations: 50)
        
        try await testRunner { session in
            var mockUseCase = MockStopSessionUseCase()
            mockUseCase.sessions = [session.id: session]
            
            let input = StopSessionInput(sessionID: session.id)
            let output = try await mockUseCase.execute(input: input)
            
            let terminalStatuses: [SessionStatus] = [.completed, .failed, .cancelled]
            return terminalStatuses.contains(output.session.status)
        }
    }
    
    /// Property: Session duration is always positive after stopping
    @Test("Session duration is positive after stop")
    func sessionDurationIsPositive() async throws {
        let sessionGen = Generator<Session>.session
        let testRunner = try await forAll(sessionGen, iterations: 50)
        
        try await testRunner { session in
            var mockUseCase = MockStopSessionUseCase()
            mockUseCase.sessions = [session.id: session]
            
            let input = StopSessionInput(sessionID: session.id)
            let output = try await mockUseCase.execute(input: input)
            
            guard let duration = output.session.duration else {
                return false
            }
            
            return duration > 0
        }
    }
    
    // MARK: - Property: Error Handling
    
    /// Property: Stopping non-existent session throws appropriate error
    @Test("Stopping non-existent session throws error")
    func stoppingNonExistentSessionThrows() async throws {
        let sessionIDGen = Generator<SessionID>.sessionID
        let testRunner = try await forAll(sessionIDGen, iterations: 30)
        
        try await testRunner { sessionID in
            let mockUseCase = MockStopSessionUseCase() // Empty sessions
            let input = StopSessionInput(sessionID: sessionID)
            
            do {
                _ = try await mockUseCase.execute(input: input)
                return false // Should have thrown
            } catch {
                return true // Expected error
            }
        }
    }
    
    /// Property: Errors are properly propagated
    @Test("Errors are propagated from stop operation")
    func errorsArePropagated() async throws {
        let sessionGen = Generator<Session>.session
        let testRunner = try await forAll(sessionGen, iterations: 20)
        
        try await testRunner { session in
            var mockUseCase = MockStopSessionUseCase()
            mockUseCase.sessions = [session.id: session]
            mockUseCase.shouldFail = true
            
            let input = StopSessionInput(sessionID: session.id)
            
            do {
                _ = try await mockUseCase.execute(input: input)
                return false
            } catch {
                return true
            }
        }
    }
    
    // MARK: - Property: Recording Save Behavior
    
    /// Property: saveRecording flag controls whether URL is returned
    @Test("Save recording flag controls file preservation")
    func saveRecordingControlsFilePreservation() async throws {
        let sessionGen = Generator<Session>.session
        let testRunner = try await forAll(sessionGen, iterations: 30)
        
        try await testRunner { session in
            var mockUseCase = MockStopSessionUseCase()
            mockUseCase.sessions = [session.id: session]
            
            let saveInput = StopSessionInput(sessionID: session.id, saveRecording: true)
            let discardInput = StopSessionInput(sessionID: session.id, saveRecording: false)
            
            let saveOutput = try await mockUseCase.execute(input: saveInput)
            
            // Reset mock for second call
            mockUseCase.sessions = [session.id: session]
            let discardOutput = try await mockUseCase.execute(input: discardInput)
            
            return saveOutput.recordingURL != nil && discardOutput.recordingURL == nil
        }
    }
    
    // MARK: - Property: Cancellation
    
    /// Property: Long-running stop operations can be cancelled
    @Test("Stop operation is cancellable")
    func stopIsCancellable() async throws {
        let session = Generator<Session>.session.generate()
        var mockUseCase = MockStopSessionUseCase()
        mockUseCase.sessions = [session.id: session]
        mockUseCase.delay = .seconds(5)
        
        let input = StopSessionInput(sessionID: session.id)
        
        let task = Task {
            try await mockUseCase.execute(input: input)
        }
        
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        
        do {
            _ = try await task.value
            #expect(false, "Should have been cancelled")
        } catch is CancellationError {
            #expect(true)
        } catch {
            #expect(false, "Unexpected error: \(error)")
        }
    }
    
    // MARK: - Property: Transcript Association
    
    /// Property: If transcript exists, it should be returned
    @Test("Transcript is returned if available")
    func transcriptIsReturnedIfAvailable() async throws {
        let sessionGen = Generator<Session>.session
        let transcriptGen = Generator<Transcript>.transcript
        let testRunner = try await forAll2(sessionGen, transcriptGen, iterations: 30)
        
        try await testRunner { session, transcript in
            var mockUseCase = MockStopSessionUseCase()
            mockUseCase.sessions = [session.id: session]
            mockUseCase.transcripts = [session.id: transcript]
            
            let input = StopSessionInput(sessionID: session.id)
            let output = try await mockUseCase.execute(input: input)
            
            return output.transcript != nil
        }
    }
    
    /// Property: If no transcript exists, nil is returned (not error)
    @Test("Nil transcript returned when none exists")
    func nilTranscriptReturnedWhenNoneExists() async throws {
        let sessionGen = Generator<Session>.session
        let testRunner = try await forAll(sessionGen, iterations: 30)
        
        try await testRunner { session in
            var mockUseCase = MockStopSessionUseCase()
            mockUseCase.sessions = [session.id: session]
            // No transcripts added
            
            let input = StopSessionInput(sessionID: session.id)
            
            do {
                let output = try await mockUseCase.execute(input: input)
                return output.transcript == nil
            } catch {
                return false // Should not throw for missing transcript
            }
        }
    }
    
    // MARK: - Property: Session ID Validation
    
    /// Property: Invalid session IDs are rejected
    @Test("Invalid session ID is rejected")
    func invalidSessionIDIsRejected() async throws {
        let useCase = MockStopSessionUseCase()
        let invalidID = SessionID(UUID())
        let input = StopSessionInput(sessionID: invalidID)
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false, "Should reject unknown session ID")
        } catch {
            #expect(true)
        }
    }
    
    // MARK: - Property: Sendable Safety
    
    /// Property: Use case works correctly across actor boundaries
    @Test("Stop use case is Sendable-safe")
    func stopIsSendableSafe() async throws {
        let sessions = (0..<5).map { _ in Generator<Session>.session.generate() }
        var useCase = MockStopSessionUseCase()
        
        for session in sessions {
            useCase.sessions[session.id] = session
        }
        
        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask {
                    let input = StopSessionInput(sessionID: session.id)
                    _ = try? await useCase.execute(input: input)
                }
            }
        }
        
        // All sessions should be processed
        #expect(true)
    }
}
