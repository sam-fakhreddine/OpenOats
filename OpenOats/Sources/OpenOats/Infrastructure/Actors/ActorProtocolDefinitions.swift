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

// MARK: - Implementation Status

/// ## Actor Implementation Status: ✅ COMPLETE
///
/// Full implementations are in their respective source files:
/// - `StreamingTranscriptionActor`: `Transcription/StreamingTranscriber.swift`
/// - `MicCaptureActor`: `Audio/MicCapture.swift`
///
/// ## Data Race Fixes Summary
///
/// ### C1: StreamingTranscriber
/// - `converter`: AVAudioConverter? - now actor-isolated
/// - `rateTrackingStartDate`: Date? - now actor-isolated
/// - `rateTrackingTotalFrames`: Int64 - now actor-isolated
/// - `effectiveSampleRate`: Double? - now actor-isolated
/// - `previousContext`: String? - now actor-isolated
///
/// ### C2: MicCapture
/// - `tapCallCount`: Now uses OSAllocatedUnfairLock<Int> for atomic access
/// - Audio thread safely increments counter without data race
/// - All state uses proper synchronization
///
/// Note: Protocol stub implementations removed - full implementations exist in:
/// - `StreamingTranscriber.swift` - actor-based implementation with backward-compatible wrapper
/// - `MicCapture.swift` - actor-based implementation with backward-compatible wrapper

// MARK: - Public Interface Wrappers

/// Public wrapper for StreamingTranscriptionActor
///
/// Preserves the original API while providing actor safety.
/// This is the type that clients will use.
///
struct StreamingTranscriberSafe: Sendable {
    private let actor: StreamingTranscriptionActor
    
    init(
        backend: any TranscriptionBackend,
        locale: Locale,
        vadManager: VadManager,
        speaker: Speaker,
        sessionID: String?,
        transcriptionModel: String,
        flushInterval: Int,
        skipPartials: Bool = false,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onCloudSegmentStatus: (@Sendable (StreamingTranscriptionActor.CloudSegmentStatus) -> Void)? = nil,
        onCloudProcessingChanged: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.actor = StreamingTranscriptionActor(
            backend: backend,
            locale: locale,
            vadManager: vadManager,
            speaker: speaker,
            sessionID: sessionID,
            transcriptionModel: transcriptionModel,
            flushInterval: flushInterval,
            skipPartials: skipPartials,
            onPartial: onPartial,
            onFinal: onFinal,
            onCloudSegmentStatus: onCloudSegmentStatus,
            onCloudProcessingChanged: onCloudProcessingChanged
        )
    }
    
    /// Process audio stream safely through actor isolation
    func run(stream: AsyncStream<AVAudioPCMBuffer>) async {
        await actor.run(stream: stream)
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
    /// Note: Must be called from an async context to properly bridge to actor isolation
    func stream() async -> AsyncStream<AVAudioPCMBuffer> {
        // Access the stream from within actor isolation
        return await actor.bufferStream()
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
