import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - StartSessionUseCase Property-Based Tests

/// Protocol definition for StartSessionUseCase (from TASK-005 design)
/// This will be implemented in Phase 2 (GREEN)
protocol StartSessionUseCase: Sendable {
    func execute(input: StartSessionInput) async throws -> StartSessionOutput
}

/// Input for starting a recording session
struct StartSessionInput: Sendable {
    let name: String?
    let backend: BackendID
    let captureMicrophone: Bool
    let captureSystemAudio: Bool
    let enableTranscription: Bool
    let language: String
    
    init(
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
struct StartSessionOutput: Sendable {
    let sessionID: SessionID
    let session: Session
}

/// Mock implementation for testing (will be replaced by real implementation)
struct MockStartSessionUseCase: StartSessionUseCase {
    var shouldFail = false
    var failureError: Error = TestFailure("Mock failure")
    var delay: Duration = .zero
    
    func execute(input: StartSessionInput) async throws -> StartSessionOutput {
        // Simulate work
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        
        if shouldFail {
            throw failureError
        }
        
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
        
        return StartSessionOutput(sessionID: sessionID, session: session)
    }
}

// MARK: - Test Suite

@Suite("StartSessionUseCase Property-Based Tests")
struct StartSessionUseCaseTests {
    
    // MARK: - Property: Session ID Uniqueness
    
    /// Property: Every new session gets a unique ID
    /// INVARIANT: No two sessions should have the same ID
    @Test("Generated session IDs are unique")
    func sessionIDsAreUnique() async throws {
        let useCase = MockStartSessionUseCase()
        let gen = Generator<BackendID>.backendID
        let testRunner = try await forAll(gen, iterations: 50)
        
        var generatedIDs: Set<SessionID> = []
        var collisionCount = 0
        
        try await testRunner { backend in
            let input = StartSessionInput(backend: backend)
            let output = try await useCase.execute(input: input)
            
            if generatedIDs.contains(output.sessionID) {
                collisionCount += 1
                return false
            }
            generatedIDs.insert(output.sessionID)
            return true
        }
        
        // Verify we generated the expected number of unique IDs
        #expect(generatedIDs.count == 50, "Should have 50 unique session IDs")
        #expect(collisionCount == 0, "Should have zero ID collisions")
    }
    
    // MARK: - Property: Idempotency
    
    /// Property: Same input should produce equivalent sessions
    /// (Note: IDs will differ, but other properties should be consistent)
    @Test("Session creation is deterministic given same parameters")
    func sessionCreationIsDeterministic() async throws {
        let useCase = MockStartSessionUseCase()
        let backendGen = Generator<BackendID>.backendID
        let boolGen = Generator<Bool> { Bool.random() }
        let stringGen = Generator<String> { ["en", "es", "fr", "de", "zh"].randomElement()! }
        
        let testRunner = try await forAll3(backendGen, boolGen, stringGen, iterations: 30)
        
        try await testRunner { backend, enableTranscription, language in
            let input1 = StartSessionInput(
                backend: backend,
                captureMicrophone: true,
                captureSystemAudio: true,
                enableTranscription: enableTranscription,
                language: language
            )
            let input2 = StartSessionInput(
                backend: backend,
                captureMicrophone: true,
                captureSystemAudio: true,
                enableTranscription: enableTranscription,
                language: language
            )
            
            let output1 = try await useCase.execute(input: input1)
            let output2 = try await useCase.execute(input: input2)
            
            // Sessions should have equivalent properties (except IDs)
            return output1.session.status == output2.session.status &&
                   output1.session.backendID == output2.session.backendID &&
                   output1.session.endTime == output2.session.endTime
        }
    }
    
    // MARK: - Property: Error Propagation
    
    /// Property: Errors from dependencies are properly propagated
    @Test("Errors are propagated to caller")
    func errorsArePropagated() async throws {
        let expectedError = TranscriptionError.backendFailed(
            backend: "test",
            reason: "Test error",
            recoverable: false
        )
        let useCase = MockStartSessionUseCase(shouldFail: true, failureError: expectedError)
        
        let gen = Generator<BackendID>.backendID
        let testRunner = try await forAll(gen, iterations: 20)
        
        try await testRunner { backend in
            let input = StartSessionInput(backend: backend)
            
            do {
                _ = try await useCase.execute(input: input)
                return false // Should have thrown
            } catch let error as TranscriptionError {
                if case .backendFailed(let b, let r, let rec) = error {
                    return b == "test" && r == "Test error" && rec == false
                }
                return false
            } catch {
                return false
            }
        }
    }
    
    // MARK: - Property: Session State Validity
    
    /// Property: Newly created sessions are always in active state
    @Test("New sessions have active status")
    func newSessionsHaveActiveStatus() async throws {
        let useCase = MockStartSessionUseCase()
        let backendGen = Generator<BackendID>.backendID
        let testRunner = try await forAll(backendGen, iterations: 50)
        
        try await testRunner { backend in
            let input = StartSessionInput(backend: backend)
            let output = try await useCase.execute(input: input)
            
            return output.session.status == .active
        }
    }
    
    /// Property: Newly created sessions have no end time
    @Test("New sessions have no end time")
    func newSessionsHaveNoEndTime() async throws {
        let useCase = MockStartSessionUseCase()
        let backendGen = Generator<BackendID>.backendID
        let testRunner = try await forAll(backendGen, iterations: 50)
        
        try await testRunner { backend in
            let input = StartSessionInput(backend: backend)
            let output = try await useCase.execute(input: input)
            
            return output.session.endTime == nil
        }
    }
    
    /// Property: Session IDs are consistent between output and session
    @Test("Session ID consistency")
    func sessionIDConsistency() async throws {
        let useCase = MockStartSessionUseCase()
        let backendGen = Generator<BackendID>.backendID
        let testRunner = try await forAll(backendGen, iterations: 50)
        
        try await testRunner { backend in
            let input = StartSessionInput(backend: backend)
            let output = try await useCase.execute(input: input)
            
            return output.sessionID == output.session.id
        }
    }
    
    // MARK: - Property: Backend Assignment
    
    /// Property: Backend ID is properly assigned from input
    @Test("Backend ID is assigned from input")
    func backendIDAssignedFromInput() async throws {
        let useCase = MockStartSessionUseCase()
        let backendGen = Generator<BackendID>.backendID
        let testRunner = try await forAll(backendGen, iterations: 50)
        
        try await testRunner { backend in
            let input = StartSessionInput(backend: backend)
            let output = try await useCase.execute(input: input)
            
            return output.session.backendID == backend
        }
    }
    
    // MARK: - Property: Cancellation
    
    /// Property: Long-running operations can be cancelled
    @Test("Session creation is cancellable")
    func sessionCreationIsCancellable() async throws {
        let delay: Duration = .seconds(5)
        let useCase = MockStartSessionUseCase(delay: delay)
        let input = StartSessionInput(backend: BackendID.mlxWhisper)
        
        let task = Task {
            try await useCase.execute(input: input)
        }
        
        // Cancel after short delay
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        
        // Verify task was cancelled
        do {
            _ = try await task.value
            #expect(false, "Task should have been cancelled")
        } catch is CancellationError {
            // Expected
            #expect(true)
        } catch {
            #expect(false, "Unexpected error: \(error)")
        }
    }
    
    // MARK: - Property: Input Validation
    
    /// Property: Invalid language codes should fail gracefully
    @Test("Invalid language codes are rejected")
    func invalidLanguageCodesAreRejected() async throws {
        // This test will fail until proper validation is implemented
        let useCase = MockStartSessionUseCase()
        
        // Generate invalid language codes
        let invalidLangGen = Generator<String> {
            let invalid = ["", "xyz", "123", "TOOLONG", "a"]
            return invalid.randomElement()!
        }
        
        let testRunner = try await forAll(invalidLangGen, iterations: 20)
        
        // Note: This will fail until validation is implemented
        // For RED phase, we expect this to fail
        try await testRunner { language in
            let input = StartSessionInput(
                backend: BackendID.mlxWhisper,
                language: language
            )
            
            do {
                _ = try await useCase.execute(input: input)
                // If we get here without error, validation is missing
                return false
            } catch {
                // Expected: invalid language should throw
                return true
            }
        }
    }
    
    /// Property: Empty backend ID should fail
    @Test("Empty backend ID is rejected")
    func emptyBackendIDIsRejected() async throws {
        let useCase = MockStartSessionUseCase()
        let input = StartSessionInput(backend: BackendID(""))
        
        do {
            _ = try await useCase.execute(input: input)
            // Expected to fail in RED phase
            #expect(false, "Should reject empty backend ID")
        } catch {
            // Expected
            #expect(true)
        }
    }
    
    // MARK: - Property: Sendable Safety
    
    /// Property: Use case operations work correctly across actor boundaries
    @Test("Use case is Sendable-safe")
    func useCaseIsSendableSafe() async throws {
        let useCase = MockStartSessionUseCase()
        let input = StartSessionInput(backend: BackendID.mlxWhisper)
        
        // Execute from different actors concurrently
        await withTaskGroup(of: SessionID.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let output = try! await useCase.execute(input: input)
                    return output.sessionID
                }
            }
            
            var ids: [SessionID] = []
            for await id in group {
                ids.append(id)
            }
            
            // All IDs should be unique
            let uniqueIDs = Set(ids)
            #expect(uniqueIDs.count == ids.count, "All concurrent sessions should have unique IDs")
        }
    }
}

// MARK: - Use Case Placeholder (Will be implemented in GREEN phase)

/// Placeholder for the actual StartSessionUseCase implementation
/// This will be implemented by the Implementation Agent in Phase 2
struct StartSessionUseCaseImpl: StartSessionUseCase {
    func execute(input: StartSessionInput) async throws -> StartSessionOutput {
        // TODO: Implement in Phase 2 (GREEN)
        // Requirements:
        // - Validate input parameters
        // - Create session with unique ID
        // - Start audio capture if requested
        // - Initialize transcription if enabled
        // - Return session output
        throw NotImplementedError()
    }
}

struct NotImplementedError: Error {}
