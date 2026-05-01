import AVFoundation
import FluidAudio

// MARK: - Actor Protocol Definitions for Data Race Fixes
//
// This file defines the actor protocols and actor-isolated types
// that will replace the @unchecked Sendable implementations.
//
// These protocols define the contract for safe concurrent access.
//

// MARK: - Streaming Transcription Actor Protocol

/// Actor protocol for streaming transcription with safe mutable state access
///
/// This protocol defines the interface for an actor-isolated transcription
/// system that safely manages mutable state like converters, rate tracking,
/// and transcription context.
///
/// ## Migration from StreamingTranscriber
/// Replace `StreamingTranscriber` (class with @unchecked Sendable) with
/// an actor conforming to this protocol.
///
/// ## Safety Properties
/// - All mutable state is actor-isolated
/// - Concurrent access is serialized through the actor
/// - No @unchecked Sendable needed
///
protocol StreamingTranscriptionActorProtocol: Actor {
    
    // MARK: - Associated Types
    
    /// The type of transcription segment produced
    associatedtype TranscriptionSegment: Sendable
    
    /// The type of audio segment consumed
    associatedtype AudioSegment: Sendable
    
    // MARK: - Audio Processing
    
    /// Process an incoming audio buffer and return any transcription results
    ///
    /// - Parameter segment: The audio segment to process
    /// - Returns: A transcription segment if speech was detected and transcribed
    /// - Throws: Transcription errors
    ///
    /// This method is actor-isolated, meaning all mutable state access
    /// (converter, context, rate tracking) happens safely.
    func processBuffer(_ segment: AudioSegment) async throws -> TranscriptionSegment?
    
    /// Update rate tracking for sample rate correction
    ///
    /// - Parameter startDate: The date to use as the tracking start
    ///
    /// Safe mutation of:
    /// - rateTrackingStartDate
    /// - rateTrackingTotalFrames
    /// - effectiveSampleRate
    func updateRateTracking(startDate: Date) async
    
    /// Get the current effective sample rate
    ///
    /// - Returns: The measured sample rate, or 0 if not yet determined
    ///
    /// Safe read of actor-isolated state.
    func getEffectiveSampleRate() async -> Double
    
    /// Clean up resources and reset state
    ///
    /// Safe cleanup of:
    /// - converter
    /// - previousContext
    /// - pending buffers
    /// - processing flags
    func cleanup() async
    
    // MARK: - State Access
    
    /// Get the current transcription context for continuity
    ///
    /// - Returns: The context string from the previous transcription
    func getPreviousContext() async -> String?
    
    /// Set the transcription context for the next segment
    ///
    /// - Parameter context: The context string to use
    func setPreviousContext(_ context: String?) async
}

// MARK: - Default Implementation

extension StreamingTranscriptionActorProtocol {
    /// Default implementation for getting sample rate
    func getEffectiveSampleRate() async -> Double {
        // Default: return 0.0
        return 0.0
    }
    
    /// Default implementation for cleanup
    func cleanup() async {
        // Default: no-op
    }
}

// MARK: - Mic Capture Actor Protocol

/// Actor protocol for microphone capture with safe audio thread bridging
///
/// This protocol defines the interface for an actor-isolated audio capture
/// system that safely handles audio thread callbacks.
///
/// ## Migration from MicCapture
/// Replace `MicCapture` (class with @unchecked Sendable) with
/// an actor conforming to this protocol.
///
/// ## Safety Properties
/// - Audio thread callbacks use atomic operations or bridge to actor
/// - All mutable state is actor-isolated
/// - No @unchecked Sendable needed
///
protocol MicCaptureActorProtocol: Actor {
    
    // MARK: - Recording Control
    
    /// Start recording from the microphone
    ///
    /// - Throws: Audio hardware errors
    ///
    /// Sets up the audio tap and bridges callbacks to actor isolation.
    func startRecording() async throws
    
    /// Stop recording and clean up resources
    ///
    /// Stops the engine, removes the tap, and resets state.
    func stopRecording() async
    
    /// Get the current tap call count
    ///
    /// - Returns: The number of times the audio tap has been called
    ///
    /// Uses atomic operations for thread-safe access from the audio thread.
    func getTapCount() async -> Int
    
    // MARK: - State Access
    
    /// Check if currently recording
    ///
    /// - Returns: true if the audio engine is running
    func isRecording() async -> Bool
    
    /// Get the current audio level
    ///
    /// - Returns: The RMS audio level (0.0 - 1.0)
    func getAudioLevel() async -> Float
    
    /// Check if muted
    ///
    /// - Returns: true if audio capture is muted
    func isMuted() async -> Bool
    
    /// Set the muted state
    ///
    /// - Parameter muted: Whether to mute the capture
    func setMuted(_ muted: Bool) async
    
    /// Check if paused
    ///
    /// - Returns: true if audio capture is paused
    func isPaused() async -> Bool
    
    /// Set the paused state
    ///
    /// - Parameter paused: Whether to pause the capture
    func setPaused(_ paused: Bool) async
    
    // MARK: - Audio Callback (Bridged)
    
    /// Handle an audio buffer from the tap callback
    ///
    /// - Parameters:
    ///   - buffer: The audio buffer from the tap
    ///   - time: The audio time information
    ///
    /// This method is called from the actor context (after bridging from
    /// the audio thread via Task { await ... }).
    func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) async
    
    // MARK: - Stream Access
    
    /// Get the async stream of audio buffers
    ///
    /// - Returns: An AsyncStream of audio PCM buffers
    ///
    /// The stream is safe to consume from any context.
    func bufferStream() -> AsyncStream<AVAudioPCMBuffer>
}

// MARK: - Audio Ring Buffer Actor Protocol

/// Actor protocol for a thread-safe ring buffer for audio data
///
/// Provides safe concurrent access to a circular audio buffer through
/// actor isolation.
///
protocol AudioRingBufferActorProtocol: Actor {
    
    /// The capacity of the buffer in samples
    nonisolated var capacity: Int { get }
    
    /// Write samples to the buffer
    ///
    /// - Parameter samples: The samples to write
    /// - Returns: The number of samples actually written
    func write(_ samples: [Float]) async -> Int
    
    /// Read samples from the buffer
    ///
    /// - Parameter count: The number of samples to read
    /// - Returns: The samples read (may be fewer than requested)
    func read(count: Int) async -> [Float]
    
    /// Check if the buffer is empty
    ///
    /// - Returns: true if no samples are available
    func isEmpty() async -> Bool
    
    /// Check if the buffer is full
    ///
    /// - Returns: true if no more samples can be written
    func isFull() async -> Bool
    
    /// Get the number of samples available to read
    ///
    /// - Returns: The current fill level
    func availableSamples() async -> Int
    
    /// Clear all samples from the buffer
    func clear() async
}

// MARK: - Transcription State Machine Protocol

/// Actor protocol for managing transcription state transitions
///
/// Provides safe state machine behavior with validated transitions.
///
protocol TranscriptionStateMachineProtocol: Actor {
    
    /// The type of state managed by this state machine
    associatedtype State: Sendable
    
    /// The type of errors that can occur during transitions
    associatedtype TransitionError: Error
    
    /// Attempt to transition to a new state
    ///
    /// - Parameter newState: The state to transition to
    /// - Throws: TransitionError if the transition is invalid
    ///
    /// Validates the transition before applying it and records
    /// the state change in history.
    func transition(to newState: State) async throws
    
    /// Get the current state
    ///
    /// - Returns: The current state
    func getCurrentState() async -> State
    
    /// Get the state transition history
    ///
    /// - Returns: An array of (state, timestamp) pairs
    func getStateHistory() async -> [(State, Date)]
    
    /// Check if a transition is valid without performing it
    ///
    /// - Parameter state: The target state
    /// - Returns: true if the transition is allowed
    func canTransition(to state: State) async -> Bool
}

// MARK: - Concrete Actor Types (To Be Implemented)

/// Actor-isolated streaming transcription implementation
///
/// This actor will replace `StreamingTranscriber` and provide
/// safe concurrent access to transcription state.
///
/// ## Implementation Checklist
/// - [ ] Convert mutable fields to actor-isolated
/// - [ ] Implement StreamingTranscriptionActorProtocol
/// - [ ] Remove @unchecked Sendable
/// - [ ] Add proper Sendable conformance
///
actor StreamingTranscriptionActor: StreamingTranscriptionActorProtocol {
    
    // MARK: - Types
    
    typealias TranscriptionSegment = String
    typealias AudioSegment = [Float]
    
    // MARK: - Mutable State (Actor-Isolated)
    
    private var converter: AVAudioConverter?
    private var rateTrackingStartDate: Date?
    private var rateTrackingTotalFrames: Int64 = 0
    private var effectiveSampleRate: Double?
    private var previousContext: String?
    private var isProcessing: Bool = false
    private var pendingBuffers: [[Float]] = []
    
    // MARK: - Immutable Configuration
    
    nonisolated let config: TranscriptionConfiguration
    nonisolated let backend: any TranscriptionBackend
    nonisolated let speaker: Speaker  // Uses Speaker from Domain/Utterance.swift
    nonisolated let maxBufferSize: Int = 1024 * 1024 // 1MB
    
    // MARK: - Initialization
    
    init(
        config: TranscriptionConfiguration,
        backend: any TranscriptionBackend,
        speaker: Speaker
    ) {
        self.config = config
        self.backend = backend
        self.speaker = speaker
    }
    
    // MARK: - StreamingTranscriptionActorProtocol
    
    func processBuffer(_ segment: AudioSegment) async throws -> TranscriptionSegment? {
        // Prevent concurrent processing of the same stream
        guard !isProcessing else {
            // Queue for later if already processing
            if pendingBuffers.count < maxBufferSize {
                pendingBuffers.append(segment)
            }
            return nil
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Safe mutation: create converter if needed
        // Implementation placeholder
        
        return try await transcribeSegment(segment)
    }
    
    func updateRateTracking(startDate: Date) async {
        rateTrackingStartDate = startDate
    }
    
    func getEffectiveSampleRate() async -> Double {
        return effectiveSampleRate ?? 0.0
    }
    
    func cleanup() async {
        converter = nil
        previousContext = nil
        pendingBuffers.removeAll()
        isProcessing = false
    }
    
    func getPreviousContext() async -> String? {
        return previousContext
    }
    
    func setPreviousContext(_ context: String?) async {
        previousContext = context
    }
    
    // MARK: - Private Helpers
    
    private func transcribeSegment(_ samples: [Float]) async throws -> String? {
        // Implementation placeholder
        return nil
    }
}

/// Actor-isolated microphone capture implementation
///
/// This actor will replace `MicCapture` and provide
/// safe audio thread bridging.
///
/// ## Implementation Checklist
/// - [ ] Convert to actor with OSAllocatedUnfairLock for tap counter
/// - [ ] Bridge audio thread callbacks to actor
/// - [ ] Implement MicCaptureActorProtocol
/// - [ ] Remove @unchecked Sendable
/// - [ ] Add proper Sendable conformance
///
actor MicCaptureActor: MicCaptureActorProtocol {
    
    // MARK: - State
    
    private var engine: AVAudioEngine?
    private var isRecording: Bool = false
    private var streamContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    
    /// Atomic counter for tap calls - thread-safe access from audio thread
    private let tapCounterLock = OSAllocatedUnfairLock<Int>(initialState: 0)
    
    /// Audio level - thread-safe
    private let audioLevelLock = OSAllocatedUnfairLock<Float>(initialState: 0)
    
    /// Muted state - thread-safe
    private let mutedLock = OSAllocatedUnfairLock<Bool>(initialState: false)
    
    /// Paused state - thread-safe
    private let pausedLock = OSAllocatedUnfairLock<Bool>(initialState: false)
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - MicCaptureActorProtocol
    
    func startRecording() async throws {
        let engine = AVAudioEngine()
        
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        
        // Install tap with callback that bridges to actor
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            // Bridge audio thread to actor
            Task { [weak self] in
                await self?.handleAudioBuffer(buffer, at: time)
            }
            
            // Thread-safe counter increment
            self?.tapCounterLock.withLock { $0 += 1 }
        }
        
        try engine.start()
        self.engine = engine
        self.isRecording = true
    }
    
    func stopRecording() async {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        isRecording = false
        streamContinuation?.finish()
        streamContinuation = nil
    }
    
    func getTapCount() async -> Int {
        return tapCounterLock.withLock { $0 }
    }
    
    func isRecording() async -> Bool {
        return isRecording
    }
    
    func getAudioLevel() async -> Float {
        return audioLevelLock.withLock { $0 }
    }
    
    func isMuted() async -> Bool {
        return mutedLock.withLock { $0 }
    }
    
    func setMuted(_ muted: Bool) async {
        mutedLock.withLock { $0 = muted }
    }
    
    func isPaused() async -> Bool {
        return pausedLock.withLock { $0 }
    }
    
    func setPaused(_ paused: Bool) async {
        pausedLock.withLock { $0 = paused }
    }
    
    func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) async {
        // Safe: running in actor context
        // Process buffer and yield to stream if not muted/paused
        
        let isMuted = mutedLock.withLock { $0 }
        let isPaused = pausedLock.withLock { $0 }
        
        guard !isMuted && !isPaused else { return }
        
        streamContinuation?.yield(buffer)
    }
    
    func bufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        return AsyncStream { continuation in
            self.streamContinuation = continuation
            
            continuation.onTermination = { _ in
                Task {
                    await self.stopRecording()
                }
            }
        }
    }
}

// MARK: - Public Interface Wrappers

/// Public wrapper for StreamingTranscriptionActor
///
/// Preserves the original API while providing actor safety.
/// This is the type that clients will use.
///
struct StreamingTranscriberSafe: Sendable {
    private let actor: StreamingTranscriptionActor
    
    init(config: TranscriptionConfiguration, backend: any TranscriptionBackend, speaker: Speaker) {
        self.actor = StreamingTranscriptionActor(
            config: config,
            backend: backend,
            speaker: speaker
        )
    }
    
    /// Process audio safely through actor isolation
    func processAudio(_ segment: [Float]) async throws -> String? {
        return try await actor.processBuffer(segment)
    }
    
    /// Clean up resources
    func stop() async {
        await actor.cleanup()
    }
    
    /// Get current sample rate
    func effectiveSampleRate() async -> Double {
        return await actor.getEffectiveSampleRate()
    }
}

/// Public wrapper for MicCaptureActor
///
/// Preserves the original API while providing actor safety.
/// This is the type that clients will use.
///
struct MicCaptureSafe: Sendable {
    private let actor: MicCaptureActor
    
    init() {
        self.actor = MicCaptureActor()
    }
    
    /// Start recording
    func start() async throws {
        try await actor.startRecording()
    }
    
    /// Stop recording
    func stop() async {
        await actor.stopRecording()
    }
    
    /// Get the tap call count
    func tapCount() async -> Int {
        return await actor.getTapCount()
    }
    
    /// Get the buffer stream
    func stream() -> AsyncStream<AVAudioPCMBuffer> {
        // The stream is safe to return - it's just the configuration
        // Actual yields happen through the actor
        return actor.bufferStream()
    }
}

// MARK: - Supporting Types

/// Configuration for transcription
/// Note: Uses domain types from the existing codebase:
/// - Speaker: Defined in Domain/Utterance.swift (you, them, remote)
/// - AudioFormat: Defined in Domain/Entities/AudioSegment.swift (wav, mp3, aac, flac)
struct TranscriptionConfiguration: Sendable {
    let sampleRate: Double
    let channels: Int
    
    static let `default` = TranscriptionConfiguration(
        sampleRate: 16000,
        channels: 1
    )
}
