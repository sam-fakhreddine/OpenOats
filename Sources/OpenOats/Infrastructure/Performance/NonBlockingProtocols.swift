import Foundation
import Accelerate
import AVFoundation

// MARK: - Non-Blocking Operation Protocols
//
// These protocols define the interfaces for fixing the performance issues
// identified in the architecture review. They support:
// - H1: Non-blocking transcription (async dispatch without awaiting)
// - H2: vDSP-based audio processing (no scalar loops under locks)
// - H4: Structured concurrency with proper cancellation

// MARK: - H1: Non-Blocking Transcription Protocols

/// Protocol for managing transcription tasks without blocking the calling loop
public protocol TranscriptionTaskManaging: Sendable {
    /// Process a segment asynchronously without blocking
    /// - Parameters:
    ///   - segment: The audio segment to transcribe
    ///   - completion: Callback with result (called on background queue)
    func processSegment(
        _ segment: AudioSegment,
        completion: @escaping @Sendable (Result<TranscriptionSegment, TranscriptionError>) -> Void
    ) async
    
    /// Cancel current transcription and clear pending queue
    func cancel() async
    
    /// Whether a transcription is currently in progress
    var isRunningPartial: Bool { get }
    
    /// Number of segments waiting to be processed
    var pendingCount: Int { get }
}

/// Represents a segment of transcribed text
public struct TranscriptionSegment: Sendable, Equatable {
    public let text: String
    public let confidence: Double
    public let startTime: Duration
    public let endTime: Duration
    public let contextWords: String?
    
    public init(
        text: String,
        confidence: Double,
        startTime: Duration,
        endTime: Duration,
        contextWords: String? = nil
    ) {
        self.text = text
        self.confidence = confidence
        self.startTime = startTime
        self.endTime = endTime
        self.contextWords = contextWords
    }
}

/// Protocol for VAD loop implementations that never block on transcription
public protocol NonBlockingVADLoopProtocol: Sendable {
    /// Process a single audio frame (non-blocking)
    /// - Parameter frame: The audio frame to process
    func processAudioFrame(_ frame: AudioFrame) async
    
    /// Start the VAD loop
    func start() async
    
    /// Stop the VAD loop and cancel any pending transcription
    func stop() async
    
    /// Current VAD state
    var isSpeaking: Bool { get }
    
    /// Callback for transcription results
    var onTranscriptionResult: (@Sendable (TranscriptionSegment) -> Void)? { get set }
}

/// Audio frame for VAD processing
public struct AudioFrame: Sendable {
    public let samples: [Float]
    public let timestamp: Date
    public let sampleRate: Double
    
    public init(samples: [Float], timestamp: Date, sampleRate: Double) {
        self.samples = samples
        self.timestamp = timestamp
        self.sampleRate = sampleRate
    }
}

// MARK: - H2: vDSP Audio Processing Protocols

/// Protocol for high-performance audio DSP using Accelerate framework
public protocol AudioDSPProcessing: Sendable {
    /// Process audio buffers using vDSP (no scalar loops)
    /// - Parameters:
    ///   - micSamples: Microphone audio samples
    ///   - sysSamples: System audio samples
    /// - Returns: Mixed and processed samples
    func processBuffers(micSamples: [Float], sysSamples: [Float]) -> [Float]
    
    /// Downmix stereo to mono using vDSP
    /// - Parameters:
    ///   - left: Left channel samples
    ///   - right: Right channel samples
    /// - Returns: Mono samples
    func downmixStereoToMono(left: [Float], right: [Float]) -> [Float]
    
    /// Calculate RMS energy using vDSP
    /// - Parameter samples: Audio samples
    /// - Returns: RMS energy value
    func calculateEnergy(_ samples: [Float]) -> Float
    
    /// Apply gain using vDSP
    /// - Parameters:
    ///   - samples: Audio samples
    ///   - gain: Gain multiplier
    /// - Returns: Scaled samples
    func applyGain(_ samples: [Float], gain: Float) -> [Float]
    
    /// Normalize audio to target level using vDSP
    /// - Parameters:
    ///   - samples: Audio samples
    ///   - targetLevel: Target peak level (0.0-1.0)
    /// - Returns: Normalized samples
    func normalize(_ samples: [Float], targetLevel: Float) -> [Float]
}

/// Protocol for audio writing with minimized lock contention
public protocol DualLockAudioWriting: Sendable {
    /// Process audio with separate read and write locks
    /// - Parameters:
    ///   - micSamples: Microphone samples
    ///   - sysSamples: System samples
    ///   - writer: File write closure (called under write lock only)
    func processWithDualLocks(
        micSamples: [Float],
        sysSamples: [Float],
        using writer: @escaping @Sendable ([Float]) throws -> Void
    ) rethrows
    
    /// Process DSP outside of any locks
    /// - Parameters:
    ///   - micSamples: Microphone samples
    ///   - sysSamples: System samples
    /// - Returns: Processed samples ready for writing
    func prepareBuffers(micSamples: [Float], sysSamples: [Float]) -> [Float]
}

/// Actor-based audio DSP processor using vDSP
public actor VDSPAaudioDSPProcessor: AudioDSPProcessing {
    private var outputBuffer: [Float] = []
    
    public init() {}
    
    public func processBuffers(micSamples: [Float], sysSamples: [Float]) -> [Float] {
        let mixedCount = max(micSamples.count, sysSamples.count)
        ensureBufferCapacity(mixedCount)
        
        var mixed = Array(repeating: Float(0), count: mixedCount)
        
        // Use vDSP for mixing (no scalar loops)
        if !micSamples.isEmpty && !sysSamples.isEmpty {
            let count = vDSP_Length(min(micSamples.count, sysSamples.count))
            
            // Mix: mic + sys
            vDSP_vadd(
                micSamples, 1,
                sysSamples, 1,
                &mixed, 1,
                count
            )
            
            // Normalize by 0.5 to prevent clipping
            var scale: Float = 0.5
            vDSP_vsmul(
                mixed, 1,
                &scale,
                &mixed, 1,
                count
            )
        } else if !micSamples.isEmpty {
            let count = vDSP_Length(micSamples.count)
            micSamples.withUnsafeBufferPointer { src in
                memcpy(&mixed, src.baseAddress!, Int(count) * MemoryLayout<Float>.size)
            }
        } else if !sysSamples.isEmpty {
            let count = vDSP_Length(sysSamples.count)
            sysSamples.withUnsafeBufferPointer { src in
                memcpy(&mixed, src.baseAddress!, Int(count) * MemoryLayout<Float>.size)
            }
        }
        
        return mixed
    }
    
    public func downmixStereoToMono(left: [Float], right: [Float]) -> [Float] {
        var result = Array(repeating: Float(0), count: left.count)
        
        // Average left and right: (L + R) / 2
        vDSP_vadd(left, 1, right, 1, &result, 1, vDSP_Length(left.count))
        
        var scale: Float = 0.5
        vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(left.count))
        
        return result
    }
    
    public func calculateEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        
        var meanSquare: Float = 0
        vDSP_svesq(samples, 1, &meanSquare, vDSP_Length(samples.count))
        return sqrt(meanSquare / Float(samples.count))
    }
    
    public func applyGain(_ samples: [Float], gain: Float) -> [Float] {
        var result = samples
        var g = gain
        vDSP_vsmul(samples, 1, &g, &result, 1, vDSP_Length(samples.count))
        return result
    }
    
    public func normalize(_ samples: [Float], targetLevel: Float) -> [Float] {
        guard !samples.isEmpty else { return samples }
        
        // Find peak using vDSP
        var peak: Float = 0
        vDSP_maxv(samples, 1, &peak, vDSP_Length(samples.count))
        
        guard peak > 0 else { return samples }
        
        // Calculate and apply gain
        let gain = targetLevel / peak
        return applyGain(samples, gain: gain)
    }
    
    private func ensureBufferCapacity(_ size: Int) {
        if outputBuffer.count < size {
            outputBuffer.reserveCapacity(size)
        }
    }
}

// MARK: - H4: Structured Concurrency Protocols

/// Protocol for cancellable tasks with cleanup
public protocol TaskCancellable: Sendable {
    /// Cancel the task and cleanup resources
    func cancel() async
    
    /// Check if task is still running
    var isRunning: Bool { get }
    
    /// Wait for task completion
    func waitForCompletion() async
}

/// Protocol for audio capture with structured cancellation
public protocol AudioCaptureTaskProtocol: TaskCancellable {
    /// Start capture with structured cancellation support
    /// - Parameter audioStream: Stream to capture from
    func start(audioStream: AsyncStream<AudioFrame>) async
    
    /// The stream of captured audio frames
    var frameStream: AsyncStream<AudioFrame> { get }
}

/// Protocol for managing a scope of related tasks with cancellation propagation
public protocol TaskScopeManaging: Sendable {
    /// Start all tasks in the scope with structured concurrency
    func start() async
    
    /// Stop all tasks (cancels parent and propagates to children)
    func stop() async
    
    /// Register a child task
    /// - Parameter task: Child task to register
    func registerChild<T: TaskCancellable>(_ task: T) async
    
    /// Whether any tasks in the scope are still running
    var hasRunningTasks: Bool { get }
    
    /// Number of child tasks
    var childTaskCount: Int { get }
}

/// Actor-based audio capture task with proper cancellation
public actor AudioCaptureTask: AudioCaptureTaskProtocol {
    private var task: Task<Void, Never>?
    private let _frameStream: AsyncStream<AudioFrame>
    private let streamContinuation: AsyncStream<AudioFrame>.Continuation
    
    public var isRunning: Bool { task != nil }
    
    public var frameStream: AsyncStream<AudioFrame> { _frameStream }
    
    public init() {
        (_frameStream, streamContinuation) = AsyncStream.makeStream(of: AudioFrame.self)
    }
    
    public func start(audioStream: AsyncStream<AudioFrame>) async {
        guard task == nil else { return }
        
        task = Task { [weak self] in
            await withTaskCancellationHandler {
                await self?.captureLoop(audioStream: audioStream)
            } onCancel: { [weak self] in
                Task {
                    await self?.cleanup()
                }
            }
        }
    }
    
    private func captureLoop(audioStream: AsyncStream<AudioFrame>) async {
        for await frame in audioStream {
            guard !Task.isCancelled else { break }
            streamContinuation.yield(frame)
        }
        streamContinuation.finish()
    }
    
    private func cleanup() async {
        streamContinuation.finish()
    }
    
    public func cancel() async {
        task?.cancel()
        await waitForCompletion()
    }
    
    public func waitForCompletion() async {
        _ = await task?.value
        task = nil
    }
}

/// Actor-based task scope for managing related tasks
public actor AudioEngineTaskScope: TaskScopeManaging {
    private var childTasks: [any TaskCancellable] = []
    private var parentTask: Task<Void, Never>?
    
    public var hasRunningTasks: Bool {
        parentTask != nil || childTasks.contains(where: { $0.isRunning })
    }
    
    public var childTaskCount: Int { childTasks.count }
    
    public init() {}
    
    public func registerChild<T: TaskCancellable>(_ task: T) async {
        childTasks.append(task)
    }
    
    public func start() async {
        parentTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                // Add child task completion watchers
                for child in await self?.childTasks ?? [] {
                    group.addTask {
                        await child.waitForCompletion()
                    }
                }
                
                // Wait for any task to finish (usually via cancellation)
                await group.next()
                
                // Cancel all others when one completes/fails
                group.cancelAll()
            }
        }
    }
    
    public func stop() async {
        // Cancel parent, which propagates to task group
        parentTask?.cancel()
        
        // Explicitly cancel all children
        for task in childTasks {
            await task.cancel()
        }
        
        // Wait for parent to complete
        _ = await parentTask?.value
        
        childTasks.removeAll()
        parentTask = nil
    }
}

// MARK: - Transcription Pipeline with Cancellation

/// Protocol for transcription pipeline with structured cancellation
public protocol TranscriptionPipelineProtocol: TaskCancellable {
    /// Start the transcription pipeline
    /// - Parameter audioStream: Stream of audio frames to transcribe
    func start(audioStream: AsyncStream<AudioFrame>) async
    
    /// Pause transcription (preserves state)
    func pause() async
    
    /// Resume transcription
    func resume() async
}

/// Actor-based transcription pipeline with proper cancellation
public actor TranscriptionPipeline: TranscriptionPipelineProtocol {
    private var transcriptionTask: Task<Void, Error>?
    private var diarizationTask: Task<Void, Error>?
    
    public var isRunning: Bool {
        transcriptionTask != nil || diarizationTask != nil
    }
    
    public func start(audioStream: AsyncStream<AudioFrame>) async {
        transcriptionTask = Task { [weak self] in
            try await withTaskCancellationHandler {
                for await frame in audioStream {
                    try Task.checkCancellation()
                    try await self?.processFrame(frame)
                }
            } onCancel: { [weak self] in
                Task {
                    await self?.cleanupTranscription()
                }
            }
        }
    }
    
    private func processFrame(_ frame: AudioFrame) async throws {
        // Transcription processing
        try Task.checkCancellation()
    }
    
    private func cleanupTranscription() async {
        // Cleanup resources
    }
    
    public func pause() async {
        // Pause without cancelling
    }
    
    public func resume() async {
        // Resume from pause
    }
    
    public func cancel() async {
        transcriptionTask?.cancel()
        diarizationTask?.cancel()
        
        // Wait for cleanup
        _ = try? await transcriptionTask?.value
        _ = try? await diarizationTask?.value
        
        transcriptionTask = nil
        diarizationTask = nil
    }
    
    public func waitForCompletion() async {
        _ = try? await transcriptionTask?.value
        _ = try? await diarizationTask?.value
    }
}

// MARK: - Transcription Task Manager Implementation

/// Actor-based transcription task manager for non-blocking processing
public actor TranscriptionTaskManager: TranscriptionTaskManaging {
    private var _isRunningPartial: Bool = false
    private var pendingBuffers: [AudioSegment] = []
    private var currentTask: Task<Void, Never>?
    
    /// Maximum concurrent transcription tasks
    private let maxConcurrentTasks = 2
    
    private let transcriptionService: any TranscriptionBackend
    
    public init(transcriptionService: any TranscriptionBackend) {
        self.transcriptionService = transcriptionService
    }
    
    public var isRunningPartial: Bool { _isRunningPartial }
    public var pendingCount: Int { pendingBuffers.count }
    
    public func processSegment(
        _ segment: AudioSegment,
        completion: @escaping @Sendable (Result<TranscriptionSegment, TranscriptionError>) -> Void
    ) async {
        // If already processing, queue or drop based on priority
        if _isRunningPartial {
            // Keep only latest 2 pending segments
            if pendingBuffers.count < 2 {
                pendingBuffers.append(segment)
            }
            return
        }
        
        // Mark as running and start transcription in background
        _isRunningPartial = true
        
        currentTask = Task { [weak self] in
            defer {
                Task {
                    await self?.markComplete()
                    // Process any pending buffers
                    await self?.processPending()
                }
            }
            
            do {
                let result = try await self?.performTranscription(segment)
                if let result = result {
                    completion(.success(result))
                }
            } catch {
                completion(.failure(error as? TranscriptionError ?? .backendFailed(
                    backend: "Unknown",
                    reason: String(describing: error),
                    recoverable: true
                )))
            }
        }
    }
    
    private func performTranscription(_ segment: AudioSegment) async throws -> TranscriptionSegment {
        // Convert AudioSegment to [Float] for transcription
        // This is a simplified version - real implementation would decode audioData
        let samples = segment.audioData.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
        
        let text = try await transcriptionService.transcribe(
            samples,
            locale: Locale.current,
            previousContext: nil
        )
        
        return TranscriptionSegment(
            text: text,
            confidence: 0.9,
            startTime: segment.startTime,
            endTime: segment.startTime + (segment.duration ?? .zero)
        )
    }
    
    private func markComplete() {
        _isRunningPartial = false
    }
    
    private func processPending() async {
        while !pendingBuffers.isEmpty && !_isRunningPartial {
            let next = pendingBuffers.removeFirst()
            await processSegment(next) { _ in }
        }
    }
    
    public func cancel() async {
        currentTask?.cancel()
        _isRunningPartial = false
        pendingBuffers.removeAll()
        
        // Wait for task to complete cleanup
        _ = await currentTask?.value
        currentTask = nil
    }
}

// MARK: - Non-Blocking VAD Loop Implementation

/// Voice Activity Detection with non-blocking transcription
public actor NonBlockingVADLoop: NonBlockingVADLoopProtocol {
    private let transcriptionManager: any TranscriptionTaskManaging
    private var accumulatedSamples: [Float] = []
    private let minSpeechSamples: Int = 16_000  // 1 second at 16kHz
    
    private var _isSpeaking: Bool = false
    private var vadState: VadStreamState?
    
    public var isSpeaking: Bool { _isSpeaking }
    public var onTranscriptionResult: (@Sendable (TranscriptionSegment) -> Void)?
    
    public init(transcriptionManager: some TranscriptionTaskManaging) {
        self.transcriptionManager = transcriptionManager
    }
    
    public func start() async {
        // Initialize VAD state
        vadState = await makeVADStreamState()
    }
    
    public func stop() async {
        await transcriptionManager.cancel()
        accumulatedSamples.removeAll()
        _isSpeaking = false
    }
    
    /// Main VAD processing loop - never blocks
    public func processAudioFrame(_ frame: AudioFrame) async {
        // Fast path: just accumulate samples (microseconds)
        accumulatedSamples.append(contentsOf: frame.samples)
        
        // Check if we have enough for transcription
        guard accumulatedSamples.count >= minSpeechSamples else {
            return
        }
        
        // Create segment for transcription
        let segment = AudioSegment(
            id: AudioSegmentID(),
            sessionID: SessionID(),
            audioData: Data(), // Would encode samples to Data
            sampleRate: frame.sampleRate,
            channelCount: 1,
            bitsPerSample: 16,
            startTime: .seconds(0),
            duration: .seconds(Double(accumulatedSamples.count) / frame.sampleRate)
        )
        
        // Clear accumulated (or keep overlap)
        accumulatedSamples.removeAll(keepingCapacity: true)
        
        // NON-BLOCKING: Start transcription without awaiting
        await transcriptionManager.processSegment(segment) { [weak self] result in
            Task {
                await self?.handleTranscriptionResult(result)
            }
        }
        
        // VAD loop continues immediately - no transcription latency
    }
    
    private func handleTranscriptionResult(
        _ result: Result<TranscriptionSegment, TranscriptionError>
    ) async {
        switch result {
        case .success(let segment):
            onTranscriptionResult?(segment)
        case .failure(let error):
            // Log error, could trigger retry
            print("Transcription error: \(error)")
        }
    }
    
    private func makeVADStreamState() async -> VadStreamState? {
        // Would create actual VAD state from VadManager
        return nil
    }
}

// MARK: - VAD State Placeholder

/// Placeholder for VAD stream state - would come from actual VAD implementation
public struct VadStreamState: Sendable {
    // VAD state implementation
}

// MARK: - Cancellation Helper

/// Wrapper for operations with proper cancellation handling
public func withCancellation<T: Sendable>(
    operation: () async throws -> T,
    onCancel: () async -> Void
) async rethrows -> T {
    try await withTaskCancellationHandler {
        try await operation()
    } onCancel: {
        await onCancel()
    }
}
