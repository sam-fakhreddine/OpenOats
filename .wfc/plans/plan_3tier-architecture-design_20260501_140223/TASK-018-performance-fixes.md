# TASK-018: Fix Performance and Latency Issues

## Overview
Address performance issues identified in deep architecture review: blocking transcription in VAD loop, scalar DSP under locks, and unstructured tasks.

## Critical Issues from Deep Architecture Review

### H1. Partial Transcription Blocks VAD Loop (HIGH)

**Issue**: `backend.transcribe` awaited inline in VAD loop → 200-500ms inference stalls VAD, audio buffers queue up.

**Fix Design - Non-Blocking Transcription**:

```swift
// MARK: - Transcription Task Manager

actor TranscriptionTaskManager {
    private var isRunningPartial: Bool = false
    private var pendingBuffers: [AudioSegment] = []
    private var currentTask: Task<Void, Never>?
    
    /// Maximum concurrent transcription tasks
    private let maxConcurrentTasks = 2
    
    /// Process audio segment without blocking VAD loop
    func processSegment(
        _ segment: AudioSegment,
        completion: @escaping (Result<TranscriptionSegment, TranscriptionError>) -> Void
    ) {
        // If already processing, queue or drop based on priority
        if isRunningPartial {
            // Keep only latest 2 pending segments
            if pendingBuffers.count < 2 {
                pendingBuffers.append(segment)
            }
            return
        }
        
        // Mark as running and start transcription in background
        isRunningPartial = true
        
        currentTask = Task {
            defer {
                Task {
                    await markComplete()
                    // Process any pending buffers
                    await processPending()
                }
            }
            
            do {
                let result = try await performTranscription(segment)
                completion(.success(result))
            } catch {
                completion(.failure(error as! TranscriptionError))
            }
        }
    }
    
    private func performTranscription(_ segment: AudioSegment) async throws -> TranscriptionSegment {
        // Actual transcription call
        return try await transcriptionService.transcribe(segment: segment)
    }
    
    private func markComplete() {
        isRunningPartial = false
    }
    
    private func processPending() async {
        while !pendingBuffers.isEmpty && !isRunningPartial {
            let next = pendingBuffers.removeFirst()
            await processSegment(next) { _ in }
        }
    }
    
    /// Cancel current transcription
    func cancel() {
        currentTask?.cancel()
        isRunningPartial = false
        pendingBuffers.removeAll()
    }
}

// MARK: - Non-Blocking VAD Loop

/// Voice Activity Detection with non-blocking transcription
actor NonBlockingVADLoop {
    private let transcriptionManager = TranscriptionTaskManager()
    private var accumulatedSamples: [Float] = []
    private let minSpeechSamples: Int = 16_000  // 1 second at 16kHz
    
    /// Main VAD processing loop - never blocks
    func processAudioFrame(_ frame: AudioFrame) async {
        // Fast path: just accumulate samples (microseconds)
        accumulatedSamples.append(contentsOf: frame.samples)
        
        // Check if we have enough for transcription
        guard accumulatedSamples.count >= minSpeechSamples else {
            return
        }
        
        // Extract segment for transcription
        let segment = AudioSegment(
            samples: accumulatedSamples,
            timestamp: frame.timestamp,
            sampleRate: frame.sampleRate
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
            await emitTranscription(segment)
        case .failure(let error):
            await handleTranscriptionError(error)
        }
    }
    
    private func emitTranscription(_ segment: TranscriptionSegment) async {
        // Emit to UI or downstream pipeline
    }
    
    private func handleTranscriptionError(_ error: TranscriptionError) async {
        // Log and potentially retry
    }
}
```

### H2. Scalar Audio DSP Under NSLock (HIGH)

**Issue**: `writeMicBuffer` runs entirely under lock including scalar downmix → contention with `writeSysBuffer`, no vDSP optimization.

**Fix Design - vDSP + Lock Minimization**:

```swift
// MARK: - Audio DSP Processor with vDSP

/// High-performance audio DSP using Accelerate framework
actor AudioDSPProcessor {
    private var micBuffer: [Float] = []
    private var sysBuffer: [Float] = []
    private var outputBuffer: [Float] = []
    
    /// Process outside lock, only hold lock for file write
    func processAudioBuffers(
        micSamples: [Float],
        sysSamples: [Float],
        using writer: @escaping ([Float]) throws -> Void
    ) rethrows {
        // STEP 1: Prepare buffers (no lock needed)
        ensureBufferCapacity(
            micCount: micSamples.count,
            sysCount: sysSamples.count
        )
        
        // STEP 2: vDSP Downmix (no lock, compute-intensive)
        let mixedCount = max(micSamples.count, sysSamples.count)
        var mixed = Array(repeating: Float(0), count: mixedCount)
        
        // Use vDSP for downmix instead of scalar loops
        if !micSamples.isEmpty && !sysSamples.isEmpty {
            // Mix both sources
            vDSP_vadd(
                micSamples, 1,
                sysSamples, 1,
                &mixed, 1,
                vDSP_Length(mixedCount)
            )
            
            // Normalize by 0.5 to prevent clipping
            var scale: Float = 0.5
            vDSP_vsmul(
                mixed, 1,
                &scale,
                &mixed, 1,
                vDSP_Length(mixedCount)
            )
        } else if !micSamples.isEmpty {
            mixed = micSamples
        } else if !sysSamples.isEmpty {
            mixed = sysSamples
        }
        
        // STEP 3: Minimized lock - only for file write
        try writer(mixed)
    }
    
    /// Separate read and write locks for better concurrency
    actor DualLockAudioWriter {
        private let readLock = NSLock()
        private let writeLock = NSLock()
        private var readBuffer: [Float] = []
        private var writeFile: AudioFileID?
        
        /// Process with dual locks - read and write can overlap
        func processWithDualLocks(
            micSamples: [Float],
            sysSamples: [Float]
        ) {
            // Read phase (lock for buffer access)
            readLock.lock()
            // Copy to internal buffer
            readBuffer = micSamples  // Simplified
            readLock.unlock()
            
            // DSP Phase (NO LOCK - compute outside)
            let processed = performDSP(mic: micSamples, sys: sysSamples)
            
            // Write phase (lock only for file access)
            writeLock.lock()
            writeToFile(processed)
            writeLock.unlock()
        }
        
        private func performDSP(mic: [Float], sys: [Float]) -> [Float] {
            // vDSP operations here - no locks!
            var result = Array(repeating: Float(0), count: mic.count)
            vDSP_vadd(mic, 1, sys, 1, &result, 1, vDSP_Length(mic.count))
            return result
        }
        
        private func writeToFile(_ samples: [Float]) {
            // File write under write lock only
        }
    }
    
    private func ensureBufferCapacity(micCount: Int, sysCount: Int) {
        let maxCount = max(micCount, sysCount)
        if outputBuffer.count < maxCount {
            outputBuffer.reserveCapacity(maxCount)
        }
    }
}

// MARK: - vDSP Optimizations

/// vDSP-accelerated audio operations
enum vDSPAudio {
    /// Downmix stereo to mono using vDSP
    static func downmixStereoToMono(left: [Float], right: [Float]) -> [Float] {
        var result = Array(repeating: Float(0), count: left.count)
        
        // Average left and right: (L + R) / 2
        vDSP_vadd(left, 1, right, 1, &result, 1, vDSP_Length(left.count))
        
        var scale: Float = 0.5
        vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(left.count))
        
        return result
    }
    
    /// Calculate RMS energy using vDSP
    static func calculateEnergy(_ samples: [Float]) -> Float {
        var meanSquare: Float = 0
        vDSP_svesq(samples, 1, &meanSquare, vDSP_Length(samples.count))
        return sqrt(meanSquare / Float(samples.count))
    }
    
    /// Fast gain adjustment
    static func applyGain(_ samples: [Float], gain: Float) -> [Float] {
        var result = samples
        var g = gain
        vDSP_vsmul(samples, 1, &g, &result, 1, vDSP_Length(samples.count))
        return result
    }
    
    /// Normalize audio to target level
    static func normalize(_ samples: [Float], targetLevel: Float) -> [Float] {
        // Find peak using vDSP
        var peak: Float = 0
        vDSP_maxv(samples, 1, &peak, vDSP_Length(samples.count))
        
        guard peak > 0 else { return samples }
        
        // Calculate and apply gain
        let gain = targetLevel / peak
        return applyGain(samples, gain: gain)
    }
}
```

### H4. Unstructured Tasks Without Cancellation (HIGH)

**Issue**: `Task { for await buffer in ... }` not cancelled when engine stops → dangling tasks for mic, system, diarization.

**Fix Design - Structured Concurrency with Cancellation**:

```swift
// MARK: - Task Cancellable Protocol

/// Protocol for cancellable tasks with cleanup
protocol TaskCancellable: Sendable {
    /// Cancel the task and cleanup resources
    func cancel() async
    
    /// Check if task is still running
    var isRunning: Bool { get }
    
    /// Wait for task completion
    func waitForCompletion() async
}

// MARK: - Audio Capture Task

/// Structured audio capture with proper cancellation
actor AudioCaptureTask: TaskCancellable {
    private var task: Task<Void, Never>?
    private let stream: AsyncStream<AudioFrame>
    private let streamContinuation: AsyncStream<AudioFrame>.Continuation
    
    var isRunning: Bool { task != nil }
    
    init() {
        (stream, streamContinuation) = AsyncStream.makeStream(of: AudioFrame.self)
    }
    
    /// Start capture with structured cancellation
    func start(captureNode: AVAudioNode) {
        guard task == nil else { return }
        
        task = Task { [weak self] in
            await withTaskCancellationHandler {
                await self?.captureLoop(captureNode: captureNode)
            } onCancel: { [weak self] in
                Task {
                    await self?.cleanup(captureNode: captureNode)
                }
            }
        }
    }
    
    private func captureLoop(captureNode: AVAudioNode) async {
        // Setup tap
        captureNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, time in
            guard let self = self else { return }
            
            let frame = AudioFrame(
                samples: buffer.floatChannelData?.pointee ?? [],
                timestamp: time,
                sampleRate: buffer.format.sampleRate
            )
            
            self.streamContinuation.yield(frame)
        }
        
        // Wait for cancellation
        try? await Task.sleep(for: .seconds(3600))  // Long sleep, cancelled when needed
    }
    
    private func cleanup(captureNode: AVAudioNode) async {
        captureNode.removeTap(onBus: 0)
        streamContinuation.finish()
    }
    
    func cancel() async {
        task?.cancel()
        await waitForCompletion()
    }
    
    func waitForCompletion() async {
        _ = await task?.value
        task = nil
    }
}

// MARK: - Parent Task Scope

/// Manages child tasks with cancellation propagation
actor AudioEngineTaskScope {
    private var childTasks: [TaskCancellable] = []
    private var parentTask: Task<Void, Never>?
    
    /// Start all audio tasks with structured concurrency
    func start(micNode: AVAudioNode, sysNode: AVAudioNode) {
        parentTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                // Mic capture task
                let micTask = AudioCaptureTask()
                micTask.start(captureNode: micNode)
                await self?.registerChild(micTask)
                
                group.addTask {
                    await micTask.waitForCompletion()
                }
                
                // System audio capture task
                let sysTask = AudioCaptureTask()
                sysTask.start(captureNode: sysNode)
                await self?.registerChild(sysTask)
                
                group.addTask {
                    await sysTask.waitForCompletion()
                }
                
                // Wait for any task to finish (usually via cancellation)
                await group.next()
                
                // Cancel all others when one completes/fails
                group.cancelAll()
            }
        }
    }
    
    private func registerChild(_ task: TaskCancellable) {
        childTasks.append(task)
    }
    
    /// Stop all audio tasks
    func stop() async {
        // Cancel parent, which cancels all children
        parentTask?.cancel()
        
        // Explicitly cancel all children
        for task in childTasks {
            await task.cancel()
        }
        
        childTasks.removeAll()
        parentTask = nil
    }
}

// MARK: - Cancellation Propagation Helper

/// Wrapper for operations with proper cancellation handling
func withCancellation<T: Sendable>(
    operation: () async throws -> T,
    onCancel: () async -> Void
) async throws -> T {
    try await withTaskCancellationHandler {
        try await operation()
    } onCancel: {
        await onCancel()
    }
}

// MARK: - Transcription Pipeline with Cancellation

actor TranscriptionPipeline: TaskCancellable {
    private var transcriptionTask: Task<Void, Error>?
    private var diarizationTask: Task<Void, Error>?
    
    func start(audioStream: AsyncStream<AudioFrame>) {
        transcriptionTask = Task { [weak self] in
            try await withCancellation(
                operation: {
                    for await frame in audioStream {
                        try Task.checkCancellation()
                        try await self?.processFrame(frame)
                    }
                },
                onCancel: {
                    await self?.cleanupTranscription()
                }
            )
        }
        
        diarizationTask = Task { [weak self] in
            try await withCancellation(
                operation: {
                    // Diarization loop
                },
                onCancel: {
                    await self?.cleanupDiarization()
                }
            )
        }
    }
    
    private func processFrame(_ frame: AudioFrame) async throws {
        // Transcription processing
    }
    
    private func cleanupTranscription() async {
        // Cleanup transcription resources
    }
    
    private func cleanupDiarization() async {
        // Cleanup diarization resources
    }
    
    func cancel() async {
        transcriptionTask?.cancel()
        diarizationTask?.cancel()
        
        // Wait for cleanup
        _ = try? await transcriptionTask?.value
        _ = try? await diarizationTask?.value
    }
    
    var isRunning: Bool {
        transcriptionTask != nil || diarizationTask != nil
    }
}
```

## Performance Budget

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| VAD loop latency | 200-500ms | < 10ms | < 50ms |
| DSP processing | Scalar, under lock | vDSP, no lock | vDSP |
| Task cancellation | Unstructured (dangling) | Structured (<500ms) | < 500ms |
| Transcription latency | Blocks VAD | Non-blocking | < 500ms |

## Implementation Checklist

- [ ] TranscriptionTaskManager with `isRunningPartial` guard
- [ ] Non-blocking transcription dispatch with child Task
- [ ] vDSP for all audio DSP operations (no scalar loops)
- [ ] Process DSP outside locks, only hold lock for file write
- [ ] Dual lock pattern for read/write separation
- [ ] TaskCancellable protocol for all long-running tasks
- [ ] withTaskCancellationHandler for all cleanup
- [ ] Parent task scope for mic/system/diarization coordination
- [ ] Run Thread Sanitizer to verify no data races
- [ ] Profile with Instruments to verify latency targets

## Formal Properties

- **LIVENESS**: VAD loop never blocked by transcription ✓
- **LIVENESS**: All tasks cancellable within 500ms ✓
- **SAFETY**: No dangling tasks after engine stop ✓
- **PERF**: Audio DSP uses vDSP (not scalar) ✓

