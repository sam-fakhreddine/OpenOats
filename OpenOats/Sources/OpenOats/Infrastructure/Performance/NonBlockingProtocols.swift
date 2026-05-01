import Foundation
import Accelerate
@preconcurrency import AVFoundation

// MARK: - Non-Blocking Performance Protocols
//
// These protocols and implementations address the critical performance issues
// identified in the architecture review:
//
// H1: Non-blocking transcription - Use TranscriptionTaskManager actor
// H2: vDSP audio processing - Replace scalar loops with Accelerate framework
// H4: Structured concurrency - Use AudioCaptureTask with proper cancellation

// MARK: - H1: Non-Blocking Transcription Protocol

/// Protocol for non-blocking transcription task management
/// Ensures VAD loop never blocks on transcription operations
public protocol NonBlockingTranscriptionProtocol: Actor {
    /// Maximum time VAD loop can block (target: < 10ms)
    static var maxVADLatency: Duration { get }
    
    /// Enqueue transcription without blocking
    func enqueueTranscription(
        samples: [Float],
        locale: Locale,
        previousContext: String?
    ) async -> TranscriptionTaskID
    
    /// Cancel a specific transcription task
    func cancelTranscription(_ taskID: TranscriptionTaskID) async
    
    /// Get results for completed transcriptions
    func collectResults() async -> [TranscriptionResult]
    
    /// Current number of pending transcription tasks
    var pendingCount: Int { get }
    
    /// Cancel all pending transcription tasks
    func cancelAll() async
}

/// Unique identifier for transcription tasks
public struct TranscriptionTaskID: Sendable, Hashable, Equatable {
    let uuid: UUID
    public init() { self.uuid = UUID() }
}

/// Result of a transcription task
public struct TranscriptionResult: Sendable {
    public let taskID: TranscriptionTaskID
    public let text: String
    public let duration: Duration
    public let success: Bool
    public let error: Error?
    
    public init(
        taskID: TranscriptionTaskID,
        text: String,
        duration: Duration,
        success: Bool,
        error: Error? = nil
    ) {
        self.taskID = taskID
        self.text = text
        self.duration = duration
        self.success = success
        self.error = error
    }
}

// MARK: - H2: vDSP Audio Processing Protocol

/// Protocol for high-performance audio processing using vDSP
/// Replaces scalar loops with vectorized operations
public protocol VDSPAudioProcessingProtocol: Sendable {
    /// Maximum lock hold time (target: < 5ms)
    static var maxLockHoldTime: Duration { get }
    
    /// Process audio buffer using vDSP (outside locks)
    func processBuffer(_ buffer: AVAudioPCMBuffer) async -> ProcessedAudioBuffer
    
    /// Downmix multi-channel to mono using vDSP
    func downmixToMono(_ buffer: AVAudioPCMBuffer) -> [Float]
    
    /// Apply gain using vDSP
    func applyGain(_ samples: [Float], gain: Float) -> [Float]
    
    /// Mix multiple channels using vDSP
    func mixChannels(_ buffer: AVAudioPCMBuffer) -> [Float]
    
    /// Measure current DSP latency
    func measureDSPLatency() async -> Duration
}

/// Processed audio buffer result
public struct ProcessedAudioBuffer: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let channelCount: Int
    public let processingTime: Duration
    
    public init(
        samples: [Float],
        sampleRate: Double,
        channelCount: Int,
        processingTime: Duration
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.processingTime = processingTime
    }
}

// MARK: - H4: Structured Concurrency Protocol

/// Protocol for structured audio capture with proper cancellation
/// Ensures tasks can be cancelled within 100ms
public protocol StructuredAudioCaptureProtocol: Actor {
    /// Maximum cancellation latency (target: < 100ms)
    static var maxCancellationLatency: Duration { get }
    
    /// Start audio capture with proper structured concurrency
    func startCapture() async throws -> AsyncStream<PerformanceAudioFrame>
    
    /// Stop capture with guaranteed cleanup
    func stopCapture() async
    
    /// Check if capture is currently active
    var isCapturing: Bool { get }
    
    /// Current task scope for structured cancellation
    var captureTaskScope: AudioCaptureTaskScope? { get }
}

/// Task scope for structured audio capture
public actor AudioCaptureTaskScope: Sendable {
    private var tasks: [Task<Void, Never>] = []
    private(set) var isActive: Bool = false
    private var cancellationContinuation: CheckedContinuation<Void, Never>?
    
    /// Initialize and activate the scope
    public init() {
        self.isActive = true
    }
    
    /// Add a task to this scope
    public func addTask(_ task: Task<Void, Never>) {
        guard isActive else {
            task.cancel()
            return
        }
        tasks.append(task)
    }
    
    /// Cancel all tasks in this scope
    public func cancelAll() async {
        isActive = false
        
        // Cancel all child tasks
        for task in tasks {
            task.cancel()
        }
        
        // Wait for all tasks to complete (with timeout)
        for task in tasks {
            _ = await task.result
        }
        
        tasks.removeAll()
        cancellationContinuation?.resume()
        cancellationContinuation = nil
    }
    
    /// Wait for scope to be cancelled
    public func waitForCancellation() async {
        guard isActive else { return }
        await withCheckedContinuation { continuation in
            cancellationContinuation = continuation
        }
    }
    
    /// Check if any tasks are still running
    public var hasActiveTasks: Bool {
        tasks.contains { !$0.isCancelled }
    }
}

// MARK: - Performance Metrics

/// Performance metrics for monitoring
public struct PerformanceMetrics: Sendable {
    public var vadLatency: Duration
    public var dspLockTime: Duration
    public var cancellationTime: Duration
    public var transcriptionQueueDepth: Int
    public var activeTaskCount: Int
    
    public init(
        vadLatency: Duration = .zero,
        dspLockTime: Duration = .zero,
        cancellationTime: Duration = .zero,
        transcriptionQueueDepth: Int = 0,
        activeTaskCount: Int = 0
    ) {
        self.vadLatency = vadLatency
        self.dspLockTime = dspLockTime
        self.cancellationTime = cancellationTime
        self.transcriptionQueueDepth = transcriptionQueueDepth
        self.activeTaskCount = activeTaskCount
    }
    
    /// Check if all metrics meet their targets
    public var allTargetsMet: Bool {
        vadLatency < .milliseconds(10) &&
        dspLockTime < .milliseconds(5) &&
        cancellationTime < .milliseconds(100)
    }
}

// MARK: - Audio Frame Type (Performance-specific)

/// Audio frame for performance testing - compatible with test expectations
public struct PerformanceAudioFrame: Sendable {
    public let samples: [Float]
    public let timestamp: Date
    public let sampleRate: Double
    
    public init(
        samples: [Float],
        timestamp: Date,
        sampleRate: Double
    ) {
        self.samples = samples
        self.timestamp = timestamp
        self.sampleRate = sampleRate
    }
}

// MARK: - Audio Segment Type (Performance-specific)

/// Audio segment for transcription - compatible with test expectations
public struct PerformanceAudioSegment: Sendable {
    public let samples: [Float]
    public let timestamp: Date
    public let sampleRate: Double
    
    public init(
        samples: [Float],
        timestamp: Date,
        sampleRate: Double
    ) {
        self.samples = samples
        self.timestamp = timestamp
        self.sampleRate = sampleRate
    }
}

// MARK: - NSLock Extension

extension NSLock {
    /// Execute operation with lock, measuring hold time
    func withMeasuredLock<T>(_ operation: () -> T) -> (result: T, holdTime: Duration) {
        let start = ContinuousClock().now
        lock()
        let result = operation()
        unlock()
        let holdTime = start.duration(to: ContinuousClock().now)
        return (result, holdTime)
    }
}
