import Foundation
import Testing
@testable import OpenOats

// MARK: - SessionViewModel Property-Based Tests
// PHASE 1: RED - These tests will fail until implementations are created

@Suite("SessionViewModel State Transitions")
struct SessionViewModelStateTransitionTests {
    
    // MARK: - Initial State Invariants
    
    @Test("Initial state is idle with no recording")
    func testInitialStateIsIdle() async throws {
        // Given: A newly created SessionViewModel
        let viewModel = try await createSessionViewModel()
        
        // Then: Initial state invariants must hold
        #expect(viewModel.sessionState == .idle)
        #expect(viewModel.isRecording == false)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == nil)
        #expect(viewModel.recordingDuration == .seconds(0))
        #expect(viewModel.audioLevel == 0.0)
    }
    
    @Test("Initial backend is available in backends list")
    func testInitialBackendInAvailableList() async throws {
        // Given: A newly created SessionViewModel
        let viewModel = try await createSessionViewModel()
        
        // Then: Selected backend must exist in available backends
        let availableBackendIDs = viewModel.availableBackends.map { $0.id }
        #expect(availableBackendIDs.contains(viewModel.selectedBackend))
    }
    
    // MARK: - State Transition: Idle -> Recording
    
    @Test("Start recording transitions from idle to recording")
    func testStartRecordingFromIdle() async throws {
        // Given: SessionViewModel in idle state
        let viewModel = try await createSessionViewModel()
        #expect(viewModel.sessionState == .idle)
        
        // When: Starting recording
        let sessionID = try await viewModel.startRecording()
        
        // Then: State must transition to recording
        #expect(viewModel.sessionState == .recording(startTime: Date()))
        #expect(viewModel.isRecording == true)
        #expect(viewModel.recordingDuration >= .seconds(0))
    }
    
    @Test("Start recording returns valid session ID")
    func testStartRecordingReturnsValidID() async throws {
        // Given: SessionViewModel in idle state
        let viewModel = try await createSessionViewModel()
        
        // When: Starting recording
        let sessionID = try await viewModel.startRecording()
        
        // Then: Must return valid session ID
        #expect(sessionID.rawValue != UUID())
    }
    
    @Test("Cannot start recording when already recording")
    func testCannotStartWhenAlreadyRecording() async throws {
        // Given: SessionViewModel already recording
        let viewModel = try await createSessionViewModel()
        _ = try await viewModel.startRecording()
        #expect(viewModel.isRecording == true)
        
        // When: Attempting to start again
        // Then: Must throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.startRecording()
        }
    }
    
    // MARK: - State Transition: Recording -> Paused
    
    @Test("Pause recording transitions to paused state")
    func testPauseRecording() async throws {
        // Given: SessionViewModel recording
        let viewModel = try await createSessionViewModel()
        _ = try await viewModel.startRecording()
        let durationBeforePause = viewModel.recordingDuration
        
        // When: Pausing recording
        try await viewModel.pauseRecording()
        
        // Then: State must transition to paused
        if case .paused(let duration, _) = viewModel.sessionState {
            #expect(duration >= durationBeforePause)
        } else {
            Issue.record("Expected paused state but got \(viewModel.sessionState)")
        }
        #expect(viewModel.isRecording == false)
    }
    
    @Test("Cannot pause when not recording")
    func testCannotPauseWhenNotRecording() async throws {
        // Given: SessionViewModel in idle state
        let viewModel = try await createSessionViewModel()
        
        // When: Attempting to pause
        // Then: Must throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.pauseRecording()
        }
    }
    
    // MARK: - State Transition: Paused -> Recording
    
    @Test("Resume recording transitions back to recording")
    func testResumeRecording() async throws {
        // Given: SessionViewModel in paused state
        let viewModel = try await createSessionViewModel()
        _ = try await viewModel.startRecording()
        try await viewModel.pauseRecording()
        #expect(viewModel.isRecording == false)
        
        // When: Resuming recording
        try await viewModel.resumeRecording()
        
        // Then: State must transition back to recording
        if case .recording = viewModel.sessionState {
            // Expected state
        } else {
            Issue.record("Expected recording state but got \(viewModel.sessionState)")
        }
        #expect(viewModel.isRecording == true)
    }
    
    @Test("Cannot resume when not paused")
    func testCannotResumeWhenNotPaused() async throws {
        // Given: SessionViewModel in idle state
        let viewModel = try await createSessionViewModel()
        
        // When: Attempting to resume
        // Then: Must throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.resumeRecording()
        }
    }
    
    // MARK: - State Transition: Recording -> Idle (Stop)
    
    @Test("Stop recording returns finalized session")
    func testStopRecording() async throws {
        // Given: SessionViewModel recording
        let viewModel = try await createSessionViewModel()
        let sessionID = try await viewModel.startRecording()
        
        // When: Stopping recording
        let session = try await viewModel.stopRecording()
        
        // Then: State must transition to idle
        #expect(viewModel.sessionState == .idle)
        #expect(viewModel.isRecording == false)
        #expect(session.id == sessionID)
        #expect(session.status == .completed)
        #expect(session.endTime != nil)
    }
    
    @Test("Cannot stop when not recording")
    func testCannotStopWhenNotRecording() async throws {
        // Given: SessionViewModel in idle state
        let viewModel = try await createSessionViewModel()
        
        // When: Attempting to stop
        // Then: Must throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.stopRecording()
        }
    }
    
    // MARK: - Cancel Operation
    
    @Test("Cancel session transitions to idle without saving")
    func testCancelSession() async throws {
        // Given: SessionViewModel recording
        let viewModel = try await createSessionViewModel()
        _ = try await viewModel.startRecording()
        
        // When: Cancelling session
        await viewModel.cancelSession()
        
        // Then: State must transition to idle
        #expect(viewModel.sessionState == .idle)
        #expect(viewModel.isRecording == false)
        #expect(viewModel.recordingDuration == .seconds(0))
        #expect(viewModel.audioLevel == 0.0)
    }
    
    @Test("Cancel from idle remains idle")
    func testCancelFromIdle() async throws {
        // Given: SessionViewModel in idle state
        let viewModel = try await createSessionViewModel()
        #expect(viewModel.sessionState == .idle)
        
        // When: Cancelling from idle
        await viewModel.cancelSession()
        
        // Then: Must remain idle
        #expect(viewModel.sessionState == .idle)
    }
    
    // MARK: - Backend Switching
    
    @Test("Switch backend updates selected backend")
    func testSwitchBackend() async throws {
        // Given: SessionViewModel with available backends
        let viewModel = try await createSessionViewModel()
        let availableBackends = viewModel.availableBackends
        #expect(availableBackends.count >= 2, "Need at least 2 backends for this test")
        
        let initialBackend = viewModel.selectedBackend
        let newBackend = availableBackends.first { $0.id != initialBackend }!.id
        
        // When: Switching backend
        try await viewModel.switchBackend(to: newBackend)
        
        // Then: Selected backend must change
        #expect(viewModel.selectedBackend == newBackend)
    }
    
    @Test("Cannot switch to unavailable backend")
    func testCannotSwitchToUnavailableBackend() async throws {
        // Given: SessionViewModel
        let viewModel = try await createSessionViewModel()
        let unavailableBackend = BackendID("unavailable-backend")
        
        // When: Attempting to switch to unavailable backend
        // Then: Must throw error
        await #expect(throws: PresentationError.self) {
            try await viewModel.switchBackend(to: unavailableBackend)
        }
    }
    
    // MARK: - Audio Level Invariants
    
    @Test("Audio level is between 0 and 1 during recording")
    func testAudioLevelBounds() async throws {
        // Given: SessionViewModel recording
        let viewModel = try await createSessionViewModel()
        _ = try await viewModel.startRecording()
        
        // Simulate some recording time
        try await Task.sleep(for: .milliseconds(100))
        
        // Then: Audio level must be within bounds
        #expect(viewModel.audioLevel >= 0.0)
        #expect(viewModel.audioLevel <= 1.0)
    }
    
    @Test("Audio level is 0 when not recording")
    func testAudioLevelZeroWhenNotRecording() async throws {
        // Given: SessionViewModel not recording
        let viewModel = try await createSessionViewModel()
        #expect(viewModel.isRecording == false)
        
        // Then: Audio level must be 0
        #expect(viewModel.audioLevel == 0.0)
    }
    
    // MARK: - Loading State Invariants
    
    @Test("Loading state during async operations")
    func testLoadingStateDuringOperations() async throws {
        // Given: SessionViewModel
        let viewModel = try await createSessionViewModel()
        
        // When: Performing async operation
        let startTask = Task {
            try await viewModel.startRecording()
        }
        
        // Then: Should be loading during operation
        try await Task.sleep(for: .milliseconds(10))
        #expect(viewModel.isLoading == true)
        
        _ = try await startTask.value
        
        // After operation: Should not be loading
        #expect(viewModel.isLoading == false)
    }
    
    // MARK: - Error Handling
    
    @Test("Error is set on operation failure")
    func testErrorSetOnFailure() async throws {
        // Given: SessionViewModel in a state that will fail
        let viewModel = try await createFailingSessionViewModel()
        
        // When: Performing operation that fails
        do {
            _ = try await viewModel.startRecording()
            Issue.record("Expected operation to fail")
        } catch {
            // Then: Error should be set
            #expect(viewModel.error != nil)
        }
    }
    
    @Test("Clear error removes error state")
    func testClearError() async throws {
        // Given: SessionViewModel with an error
        let viewModel = try await createFailingSessionViewModel()
        do {
            _ = try await viewModel.startRecording()
        } catch {
            #expect(viewModel.error != nil)
        }
        
        // When: Clearing error
        viewModel.clearError()
        
        // Then: Error should be nil
        #expect(viewModel.error == nil)
    }
    
    // MARK: - Helper Functions
    
    private func createSessionViewModel() async throws -> any SessionViewModel {
        // This will fail until implementation is provided
        throw TestError.notImplemented("SessionViewModel implementation not available")
    }
    
    private func createFailingSessionViewModel() async throws -> any SessionViewModel {
        // This will fail until implementation is provided
        throw TestError.notImplemented("Failing SessionViewModel implementation not available")
    }
}

// MARK: - SessionViewModel Property Tests (Invariants)

@Suite("SessionViewModel UI State Invariants")
struct SessionViewModelInvariantTests {
    
    @Test("isRecording matches sessionState")
    func testRecordingFlagMatchesState() async throws {
        // Property: isRecording should be true iff sessionState is .recording
        let viewModel = try await createSessionViewModel()
        
        // Test various states
        #expect(viewModel.isRecording == false)
        #expect(matchesRecordingState(viewModel.sessionState, viewModel.isRecording))
        
        _ = try await viewModel.startRecording()
        #expect(matchesRecordingState(viewModel.sessionState, viewModel.isRecording))
        
        try await viewModel.pauseRecording()
        #expect(matchesRecordingState(viewModel.sessionState, viewModel.isRecording))
        
        try await viewModel.resumeRecording()
        #expect(matchesRecordingState(viewModel.sessionState, viewModel.isRecording))
        
        _ = try await viewModel.stopRecording()
        #expect(matchesRecordingState(viewModel.sessionState, viewModel.isRecording))
    }
    
    @Test("Duration increases monotonically during recording")
    func testDurationMonotonicity() async throws {
        // Property: Duration should only increase or stay same during recording
        let viewModel = try await createSessionViewModel()
        _ = try await viewModel.startRecording()
        
        var lastDuration = viewModel.recordingDuration
        
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(100))
            let currentDuration = viewModel.recordingDuration
            #expect(currentDuration >= lastDuration)
            lastDuration = currentDuration
        }
    }
    
    @Test("Duration is preserved when pausing")
    func testDurationPreservedOnPause() async throws {
        // Property: Duration should be preserved when pausing
        let viewModel = try await createSessionViewModel()
        _ = try await viewModel.startRecording()
        
        try await Task.sleep(for: .milliseconds(200))
        let durationBeforePause = viewModel.recordingDuration
        
        try await viewModel.pauseRecording()
        
        try await Task.sleep(for: .milliseconds(100))
        let durationAfterPause = viewModel.recordingDuration
        
        #expect(durationAfterPause == durationBeforePause)
    }
    
    @Test("Error and loading are mutually exclusive")
    func testErrorAndLoadingMutualExclusion() async throws {
        // Property: Cannot have both error and loading simultaneously
        let viewModel = try await createSessionViewModel()
        
        // During operation
        let task = Task {
            _ = try await viewModel.startRecording()
        }
        
        try await Task.sleep(for: .milliseconds(10))
        
        // Loading and error are mutually exclusive
        #expect(!(viewModel.isLoading && viewModel.error != nil))
        
        _ = try await task.value
        
        // After completion, neither should be true in normal state
        #expect(!(viewModel.isLoading && viewModel.error != nil))
    }
    
    @Test("Session ID is unique per startRecording call")
    func testSessionIDUniqueness() async throws {
        // Property: Each startRecording call produces unique session ID
        let viewModel = try await createSessionViewModel()
        
        let id1 = try await viewModel.startRecording()
        _ = try await viewModel.stopRecording()
        
        let id2 = try await viewModel.startRecording()
        
        #expect(id1 != id2)
    }
    
    // MARK: - Helper Functions
    
    private func matchesRecordingState(_ state: SessionState, _ isRecording: Bool) -> Bool {
        switch state {
        case .recording:
            return isRecording == true
        default:
            return isRecording == false
        }
    }
    
    private func createSessionViewModel() async throws -> any SessionViewModel {
        throw TestError.notImplemented("SessionViewModel implementation not available")
    }
}

// MARK: - Error Presentation Tests

@Suite("SessionViewModel Error Presentation")
struct SessionViewModelErrorPresentationTests {
    
    @Test("Session start failure presents correct error")
    func testSessionStartFailureError() async throws {
        let viewModel = try await createFailingSessionViewModel(expectedError: .sessionStartFailed(reason: "Microphone denied"))
        
        do {
            _ = try await viewModel.startRecording()
            Issue.record("Expected operation to fail")
        } catch {
            guard let presentationError = viewModel.error else {
                Issue.record("Expected error to be set")
                return
            }
            
            if case .sessionStartFailed(let reason) = presentationError {
                #expect(reason == "Microphone denied")
            } else {
                Issue.record("Expected sessionStartFailed error but got \(presentationError)")
            }
        }
    }
    
    @Test("Session stop failure presents correct error")
    func testSessionStopFailureError() async throws {
        let viewModel = try await createFailingOnStopSessionViewModel()
        _ = try await viewModel.startRecording()
        
        do {
            _ = try await viewModel.stopRecording()
            Issue.record("Expected operation to fail")
        } catch {
            guard let presentationError = viewModel.error else {
                Issue.record("Expected error to be set")
                return
            }
            
            if case .sessionStopFailed = presentationError {
                // Expected
            } else {
                Issue.record("Expected sessionStopFailed error but got \(presentationError)")
            }
        }
    }
    
    @Test("Backend switch failure presents correct error")
    func testBackendSwitchFailureError() async throws {
        let viewModel = try await createSessionViewModel()
        let fromBackend = viewModel.selectedBackend
        
        do {
            try await viewModel.switchBackend(to: BackendID("unavailable"))
            Issue.record("Expected operation to fail")
        } catch {
            guard let presentationError = viewModel.error else {
                Issue.record("Expected error to be set")
                return
            }
            
            if case .backendSwitchFailed(let from, let to, _) = presentationError {
                #expect(from == fromBackend)
                #expect(to == BackendID("unavailable"))
            } else {
                Issue.record("Expected backendSwitchFailed error but got \(presentationError)")
            }
        }
    }
    
    @Test("Error provides localized description")
    func testErrorLocalizedDescription() async throws {
        let error = PresentationError.sessionStartFailed(reason: "Test reason")
        
        #expect(error.errorDescription?.contains("Failed to start recording") == true)
        #expect(error.errorDescription?.contains("Test reason") == true)
    }
    
    @Test("Error provides recovery suggestion")
    func testErrorRecoverySuggestion() async throws {
        let error = PresentationError.sessionStartFailed(reason: "Test")
        
        #expect(error.recoverySuggestion?.contains("microphone") == true)
    }
    
    @Test("Multiple errors preserve latest")
    func testMultipleErrorsPreserveLatest() async throws {
        let viewModel = try await createFailingSessionViewModel()
        
        // First error
        do {
            _ = try await viewModel.startRecording()
        } catch {
            // Expected
        }
        
        viewModel.clearError()
        
        // Second error (should be the one preserved)
        do {
            try await viewModel.switchBackend(to: BackendID("invalid"))
        } catch {
            // Expected
        }
        
        // Then: Latest error should be preserved
        if case .backendSwitchFailed = viewModel.error {
            // Expected latest error
        } else if viewModel.error != nil {
            Issue.record("Expected backendSwitchFailed as latest error")
        }
    }
    
    // MARK: - Helper Functions
    
    private func createSessionViewModel() async throws -> any SessionViewModel {
        throw TestError.notImplemented("SessionViewModel implementation not available")
    }
    
    private func createFailingSessionViewModel(expectedError: PresentationError? = nil) async throws -> any SessionViewModel {
        throw TestError.notImplemented("Failing SessionViewModel implementation not available")
    }
    
    private func createFailingOnStopSessionViewModel() async throws -> any SessionViewModel {
        throw TestError.notImplemented("FailingOnStop SessionViewModel implementation not available")
    }
}

// MARK: - Test Error Types

enum TestError: Error {
    case notImplemented(String)
}
