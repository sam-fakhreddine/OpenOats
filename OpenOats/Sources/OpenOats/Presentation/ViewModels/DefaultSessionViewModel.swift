import Foundation
import SwiftUI

// MARK: - Test Factory Functions

// These factory functions are used by the test suite to create ViewModel instances.
// They are called by the test helpers to provide real implementations.

public func createSessionViewModel() async throws -> any SessionViewModel {
    return DefaultSessionViewModel()
}

public func createFailingSessionViewModel(expectedError: PresentationError? = nil) async throws -> any SessionViewModel {
    return DefaultSessionViewModel(shouldFailStart: true, expectedError: expectedError)
}

public func createFailingOnStopSessionViewModel() async throws -> any SessionViewModel {
    return DefaultSessionViewModel(shouldFailStop: true)
}

public func createTranscriptViewModel() async throws -> any TranscriptViewModel {
    return DefaultTranscriptViewModel()
}

public func createTranscriptViewModelWithTranscript() async throws -> any TranscriptViewModel {
    let viewModel = DefaultTranscriptViewModel()
    // Pre-load a transcript with sample data
    let transcriptID = TranscriptID()
    try await viewModel.loadTranscript(id: transcriptID)
    return viewModel
}

public func createFailingTranscriptViewModel() async throws -> any TranscriptViewModel {
    return DefaultTranscriptViewModel(shouldFailLoad: true)
}

public func createSettingsViewModel() async throws -> any SettingsViewModel {
    return DefaultSettingsViewModel()
}

public func createFailingSettingsViewModel() async throws -> any SettingsViewModel {
    return DefaultSettingsViewModel(shouldFailSave: true)
}

public func createOfflineSettingsViewModel() async throws -> any SettingsViewModel {
    return DefaultSettingsViewModel(isOffline: true)
}

public func createIdleDashboardViewModel(calendarEnabled: Bool = true) async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(calendarEnabled: calendarEnabled)
}

public func createIdleDashboardViewModelWithHistory() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withHistory: true)
}

public func createIdleDashboardViewModelWithEvents() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withEvents: true)
}

public func createIdleDashboardViewModelWithDeniedAccess() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(calendarAccessState: .denied)
}

public func createIdleDashboardViewModelWithActiveSession() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withActiveSession: true)
}

public func createIdleDashboardViewModelWithEventsAndHistory() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withEvents: true, withHistory: true)
}

public func createIdleDashboardViewModelWithFutureEvent() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withFutureEvent: true)
}

public func createIdleDashboardViewModelWithMeetingURLEvent() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withMeetingURL: true)
}

public func createIdleDashboardViewModelWithEarlierTodayEvents() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(withEarlierTodayEvents: true)
}

public func createFailingIdleDashboardViewModel() async throws -> any IdleDashboardViewModel {
    return DefaultIdleDashboardViewModel(shouldFail: true)
}

// MARK: - DefaultSessionViewModel

/// Default implementation of SessionViewModel for recording UI state
@MainActor
@Observable
final class DefaultSessionViewModel: SessionViewModel {
    let id: UUID
    
    var isLoading: Bool = false
    var error: PresentationError? = nil
    var sessionState: SessionState = .idle
    var isRecording: Bool = false
    var recordingDuration: Duration = .seconds(0)
    var audioLevel: Double = 0.0
    var selectedBackend: BackendID
    var availableBackends: [BackendConfiguration] = []
    
    // Private state
    private var currentSession: Session?
    private var recordingStartTime: Date?
    private var pausedDuration: Duration = .seconds(0)
    private var audioLevelTimer: Timer?
    
    // Test configuration
    private var shouldFailStart: Bool
    private var shouldFailStop: Bool
    private var expectedError: PresentationError?
    
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
        audioLevelTimer?.invalidate()
    }
    
    func clearError() {
        error = nil
    }
    
    func startRecording() async throws -> SessionID {
        guard !isLoading else {
            throw PresentationError.sessionStartFailed(reason: "Operation in progress")
        }
        
        guard sessionState == .idle else {
            throw PresentationError.sessionStartFailed(reason: "Already recording")
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Simulate failure if configured
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
        
        // Update state
        sessionState = .recording(startTime: now)
        isRecording = true
        
        // Start audio level simulation
        startAudioLevelSimulation()
        
        return sessionID
    }
    
    func stopRecording() async throws -> Session {
        guard !isLoading else {
            throw PresentationError.sessionStopFailed(reason: "Operation in progress")
        }
        
        guard sessionState != .idle else {
            throw PresentationError.sessionStopFailed(reason: "Not recording")
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Simulate failure if configured
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
        
        // Reset state
        sessionState = .idle
        isRecording = false
        recordingDuration = .seconds(0)
        audioLevel = 0.0
        recordingStartTime = nil
        
        return session
    }
    
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
    
    private func startAudioLevelSimulation() {
        audioLevelTimer?.invalidate()
        // Simulate audio levels between 0.1 and 0.8
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRecording else { return }
                self.audioLevel = Double.random(in: 0.1...0.8)
                
                // Update recording duration
                if case .recording(let startTime) = self.sessionState {
                    let elapsed = Date().timeIntervalSince(startTime)
                    self.recordingDuration = .seconds(Int(elapsed))
                }
            }
        }
    }
    
    private func stopAudioLevelSimulation() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = 0.0
    }
}
