import Foundation
import SwiftUI

// MARK: - Test Factory Functions

// These factory functions are used by the test suite to create ViewModel instances.
// They are called by the test helpers to provide real implementations.
// All factory functions are @MainActor to ensure proper isolation when creating ViewModels.

@MainActor
public func createSessionViewModel() async throws -> any SessionViewModel {
    return DefaultSessionViewModel()
}

@MainActor
public func createFailingSessionViewModel(expectedError: PresentationError? = nil) async throws -> any SessionViewModel {
    return DefaultSessionViewModel(shouldFailStart: true, expectedError: expectedError)
}

@MainActor
public func createFailingOnStopSessionViewModel() async throws -> any SessionViewModel {
    return DefaultSessionViewModel(shouldFailStop: true)
}

@MainActor
public func createTranscriptViewModel() async throws -> any TranscriptViewModel {
    return DefaultTranscriptViewModel()
}

@MainActor
public func createTranscriptViewModelWithTranscript() async throws -> any TranscriptViewModel {
    let viewModel = DefaultTranscriptViewModel()
    // Pre-load a transcript with sample data
    let transcriptID = TranscriptID()
    try await viewModel.loadTranscript(id: transcriptID)
    return viewModel
}

@MainActor
public func createFailingTranscriptViewModel() async throws -> any TranscriptViewModel {
    return DefaultTranscriptViewModel(shouldFailLoad: true)
}

@MainActor
public func createSettingsViewModel() async throws -> any SettingsViewModel {
    return DefaultSettingsViewModel()
}

@MainActor
public func createFailingSettingsViewModel() async throws -> any SettingsViewModel {
    return DefaultSettingsViewModel(shouldFailSave: true)
}

@MainActor
public func createOfflineSettingsViewModel() async throws -> any SettingsViewModel {
    return DefaultSettingsViewModel(isOffline: true)
}

@MainActor
public func createIdleDashboardViewModel(calendarEnabled: Bool = true) async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(calendarEnabled: calendarEnabled)
}

@MainActor
public func createIdleDashboardViewModelWithHistory() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withHistory: true)
}

@MainActor
public func createIdleDashboardViewModelWithEvents() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withEvents: true)
}

@MainActor
public func createIdleDashboardViewModelWithDeniedAccess() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(calendarAccessState: .denied)
}

@MainActor
public func createIdleDashboardViewModelWithActiveSession() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withActiveSession: true)
}

@MainActor
public func createIdleDashboardViewModelWithEventsAndHistory() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withEvents: true, withHistory: true)
}

@MainActor
public func createIdleDashboardViewModelWithFutureEvent() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withFutureEvent: true)
}

@MainActor
public func createIdleDashboardViewModelWithMeetingURLEvent() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withMeetingURL: true)
}

@MainActor
public func createIdleDashboardViewModelWithEarlierTodayEvents() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withEarlierTodayEvents: true)
}

@MainActor
public func createFailingIdleDashboardViewModel() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(shouldFail: true)
}

// MARK: - DefaultSessionViewModel

/// Default implementation of SessionViewModel for recording UI state.
/// 
/// This ViewModel manages the lifecycle of a recording session, including:
/// - Starting, pausing, resuming, and stopping recordings
/// - Tracking recording duration and audio levels
/// - Managing transcription backend selection
/// - Handling errors and loading states
///
/// ## Concurrency Safety
/// - Marked with `@MainActor` to ensure all UI updates happen on the main thread
/// - Uses `@Observable` macro for SwiftUI integration (iOS 17+/macOS 14+)
/// - Timer-based audio level simulation is properly isolated to main actor
@MainActor
@Observable
final class DefaultSessionViewModel: SessionViewModel {
    // MARK: - Published State (Observable properties)
    
    let id: UUID
    
    var isLoading: Bool = false
    var error: PresentationError? = nil
    var sessionState: SessionState = .idle
    var isRecording: Bool = false
    var recordingDuration: Duration = .seconds(0)
    var audioLevel: Double = 0.0
    var selectedBackend: BackendID
    var availableBackends: [BackendConfiguration] = []
    
    // MARK: - Private State
    
    private var currentSession: Session?
    private var recordingStartTime: Date?
    private var pausedDuration: Duration = .seconds(0)
    
    /// Timer for audio level simulation. Must be accessed only on MainActor.
    /// - Important: Always invalidate existing timer before creating new one.
    private var audioLevelTimer: Timer?
    
    // MARK: - Test Configuration
    
    private let shouldFailStart: Bool
    private let shouldFailStop: Bool
    private let expectedError: PresentationError?
    
    // MARK: - Initialization
    
    /// Creates a new SessionViewModel instance.
    ///
    /// - Parameters:
    ///   - shouldFailStart: If true, `startRecording()` will always fail (for testing)
    ///   - shouldFailStop: If true, `stopRecording()` will always fail (for testing)
    ///   - expectedError: The error to throw when failing (if nil, a default error is used)
    init(
        shouldFailStart: Bool = false,
        shouldFailStop: Bool = false,
        expectedError: PresentationError? = nil
    ) {
        self.id = UUID()
        self.shouldFailStart = shouldFailStart
        self.shouldFailStop = shouldFailStop
        self.expectedError = expectedError
        
        // Initialize with default backends
        self.selectedBackend = .mlxWhisper
        self.availableBackends = [
            BackendConfiguration(
                id: .mlxWhisper,
                name: "MLX Whisper",
                description: "Fast local transcription using MLX",
                isLocal: true,
                requiresAPIKey: false,
                supportedLanguages: ["en", "es", "fr", "de", "it"],
                capabilities: [.streaming, .batch, .speakerDiarization]
            ),
            BackendConfiguration(
                id: .whisperKit,
                name: "WhisperKit",
                description: "Apple Silicon optimized Whisper",
                isLocal: true,
                requiresAPIKey: false,
                supportedLanguages: ["en", "es", "fr", "de", "it", "ja", "zh"],
                capabilities: [.streaming, .batch, .realTimeProcessing]
            ),
            BackendConfiguration(
                id: .assemblyAI,
                name: "AssemblyAI",
                description: "Cloud transcription with high accuracy",
                isLocal: false,
                requiresAPIKey: true,
                supportedLanguages: ["en"],
                capabilities: [.streaming, .batch, .speakerDiarization, .realTimeProcessing]
            )
        ]
    }
    
    deinit {
        // Timer must be invalidated to prevent memory leaks and crashes
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        error = nil
    }
    
    // MARK: - Session Lifecycle
    
    /// Starts a new recording session.
    ///
    /// - Returns: The ID of the created session
    /// - Throws: `PresentationError.sessionStartFailed` if session cannot be started
    func startRecording() async throws -> SessionID {
        // Validate preconditions
        guard !isLoading else {
            throw PresentationError.sessionStartFailed(reason: "Operation in progress")
        }
        
        guard sessionState == .idle else {
            throw PresentationError.sessionStartFailed(reason: "Already recording")
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Simulate failure if configured (for testing)
        if shouldFailStart {
            let failError = expectedError ?? PresentationError.sessionStartFailed(reason: "Microphone denied")
            error = failError
            throw failError
        }
        
        // Create new session
        let sessionID = SessionID()
        let now = Date()
        recordingStartTime = now
        pausedDuration = .seconds(0)
        
        // Create domain session
        currentSession = Session(
            id: sessionID,
            meetingID: MeetingID(),
            startTime: now,
            endTime: nil,
            status: .active,
            backendID: selectedBackend
        )
        
        // Update UI state
        sessionState = .recording(startTime: now)
        isRecording = true
        
        // Start audio level simulation
        startAudioLevelSimulation()
        
        return sessionID
    }
    
    /// Stops the current recording session.
    ///
    /// - Returns: The finalized session with end time and completed status
    /// - Throws: `PresentationError.sessionStopFailed` if stop fails
    func stopRecording() async throws -> Session {
        // Validate preconditions
        guard !isLoading else {
            throw PresentationError.sessionStopFailed(reason: "Operation in progress")
        }
        
        guard sessionState != .idle else {
            throw PresentationError.sessionStopFailed(reason: "Not recording")
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Simulate failure if configured (for testing)
        if shouldFailStop {
            let failError = PresentationError.sessionStopFailed(reason: "Stop failed")
            error = failError
            throw failError
        }
        
        // Stop audio level simulation
        stopAudioLevelSimulation()
        
        let now = Date()
        
        // Update session
        guard var session = currentSession else {
            throw PresentationError.sessionStopFailed(reason: "No active session")
        }
        
        session = session
            .withEndedAt(now)
            .withStatus(.completed)
        
        currentSession = session
        
        // Reset UI state
        sessionState = .idle
        isRecording = false
        recordingDuration = .seconds(0)
        audioLevel = 0.0
        recordingStartTime = nil
        
        return session
    }
    
    /// Pauses the current recording while keeping the session alive.
    ///
    /// - Throws: `PresentationError.sessionStopFailed` if not currently recording
    func pauseRecording() async throws {
        guard case .recording(let startTime) = sessionState else {
            throw PresentationError.sessionStopFailed(reason: "Cannot pause when not recording")
        }
        
        // Calculate duration so far
        let now = Date()
        let elapsed = now.timeIntervalSince(startTime)
        pausedDuration = .seconds(Int(elapsed))
        
        // Update state
        sessionState = .paused(duration: pausedDuration, startTime: startTime)
        isRecording = false
        
        // Stop audio level simulation
        stopAudioLevelSimulation()
        audioLevel = 0.0
    }
    
    /// Resumes a paused recording.
    ///
    /// - Throws: `PresentationError.sessionStartFailed` if not currently paused
    func resumeRecording() async throws {
        guard case .paused(let duration, let startTime) = sessionState else {
            throw PresentationError.sessionStartFailed(reason: "Cannot resume when not paused")
        }
        
        // Update state
        pausedDuration = duration
        sessionState = .recording(startTime: startTime)
        isRecording = true
        
        // Restart audio level simulation
        startAudioLevelSimulation()
    }
    
    /// Switches to a different transcription backend.
    ///
    /// - Parameter backend: The backend to switch to
    /// - Throws: `PresentationError.backendSwitchFailed` if backend is unavailable
    func switchBackend(to backend: BackendID) async throws {
        guard availableBackends.contains(where: { $0.id == backend }) else {
            let failError = PresentationError.backendSwitchFailed(
                from: selectedBackend,
                to: backend,
                reason: "Backend not available"
            )
            error = failError
            throw failError
        }
        
        selectedBackend = backend
    }
    
    /// Cancels the current session without saving.
    /// This resets all state to idle.
    func cancelSession() async {
        // Stop audio level simulation
        stopAudioLevelSimulation()
        
        // Reset all state
        sessionState = .idle
        isRecording = false
        recordingDuration = .seconds(0)
        audioLevel = 0.0
        recordingStartTime = nil
        pausedDuration = .seconds(0)
        currentSession = nil
    }
    
    // MARK: - Private Methods
    
    /// Starts the audio level simulation timer.
    ///
    /// Creates a timer that fires every 100ms to update:
    /// - `audioLevel`: Random value between 0.1 and 0.8 for visualization
    /// - `recordingDuration`: Calculated from start time
    ///
    /// - Important: Must be called on MainActor. Invalidates any existing timer first.
    private func startAudioLevelSimulation() {
        // Invalidate any existing timer to prevent duplicates
        audioLevelTimer?.invalidate()
        
        // Create new timer on the main run loop
        // Since this class is @MainActor, the timer fires on the main thread
        // No need for Task { @MainActor } wrapper
        let newTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Direct access is safe because timer fires on main run loop
            // and this class is isolated to MainActor
            guard self.isRecording else { return }
            
            self.audioLevel = Double.random(in: 0.1...0.8)
            
            // Update recording duration
            if case .recording(let startTime) = self.sessionState {
                let elapsed = Date().timeIntervalSince(startTime)
                self.recordingDuration = .seconds(Int(elapsed))
            }
        }
        
        // Store the timer reference for later invalidation
        audioLevelTimer = newTimer
    }
    
    /// Stops the audio level simulation timer.
    ///
    /// - Important: Must be called on MainActor.
    private func stopAudioLevelSimulation() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = 0.0
    }
}
