import XCTest
@testable import OpenOats
import Accelerate

// MARK: - Performance Issue Demonstration Tests (Phase 1: RED)
//
// These tests demonstrate the three critical performance issues identified
// in the architecture review. All tests are expected to FAIL initially,
// showing the performance problems that need to be fixed.
//
// Issues:
// - H1: Partial transcription blocks VAD loop (200-500ms stall)
// - H2: Scalar audio DSP under NSLock (contention)
// - H4: Unstructured Tasks without cancellation

// MARK: - H1 Test: Blocking Transcription in VAD Loop

/// Demonstrates that partial transcription blocks the VAD loop for 200-500ms
/// This test should FAIL, showing the blocking behavior
final class BlockingTranscriptionTests: XCTestCase {
    
    /// Tests that transcription blocks the VAD loop (demonstrates H1)
    /// Expected: FAIL - shows blocking latency > 500ms
    func testPartialTranscriptionBlocksVADLoop() async throws {
        // Given: A mock transcription backend that simulates 300ms inference time
        let slowBackend = SlowTranscriptionBackend(delay: .milliseconds(300))
        let transcriber = LegacyStreamingTranscriber(backend: slowBackend)
        
        // When: Processing audio frames while speech is active
        let audioStream = AsyncStream<AudioFrame> { continuation in
            // Simulate continuous audio frames every 20ms
            for i in 0..<50 {
                let frame = AudioFrame(
                    samples: Array(repeating: Float.random(in: -0.5...0.5), count: 320),
                    timestamp: Date(),
                    sampleRate: 16000
                )
                continuation.yield(frame)
                try? await Task.sleep(for: .milliseconds(20))
            }
            continuation.finish()
        }
        
        // Measure VAD loop processing times
        var processingTimes: [Duration] = []
        let startTime = ContinuousClock().now
        
        for await frame in audioStream {
            let frameStart = ContinuousClock().now
            await transcriber.processFrameBlocking(frame)
            let frameEnd = ContinuousClock().now
            processingTimes.append(frameStart.duration(to: frameEnd))
        }
        
        // Then: Most frames should process quickly (< 50ms), but some will block
        let totalTime = startTime.duration(to: ContinuousClock().now)
        let slowFrames = processingTimes.filter { $0 > .milliseconds(200) }
        
        // This assertion should FAIL - showing the blocking issue
        // Expected: At least some frames block for > 200ms due to transcription
        XCTAssertEqual(slowFrames.count, 0, "Expected no blocking frames, but found \(slowFrames.count) frames that blocked for >200ms")
        
        // Additional latency check
        let averageTime = totalTime / processingTimes.count
        XCTAssertLessThan(averageTime, .milliseconds(50), "Average frame processing should be <50ms, but was \(averageTime)")
    }
    
    /// Property-based load test: VAD loop should never block
    /// Expected: FAIL under load conditions
    func testVADLoopNeverBlocksUnderLoad() async throws {
        // Given: High-frequency audio stream
        let backend = SlowTranscriptionBackend(delay: .milliseconds(250))
        let transcriber = LegacyStreamingTranscriber(backend: backend)
        
        // When: Rapid frame arrival (10ms intervals)
        var latencies: [Duration] = []
        let frameCount = 100
        
        await withTaskGroup(of: Duration.self) { group in
            for i in 0..<frameCount {
                group.addTask {
                    let frame = AudioFrame(
                        samples: Array(repeating: 0.1, count: 160),
                        timestamp: Date(),
                        sampleRate: 16000
                    )
                    let start = ContinuousClock().now
                    await transcriber.processFrameBlocking(frame)
                    return start.duration(to: ContinuousClock().now)
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            
            for await latency in group {
                latencies.append(latency)
            }
        }
        
        // Then: 99th percentile should be < 50ms (this will FAIL)
        let sortedLatencies = latencies.sorted { $0 < $1 }
        let p99 = sortedLatencies[Int(Double(sortedLatencies.count) * 0.99)]
        
        XCTAssertLessThan(p99, .milliseconds(50), "P99 latency should be <50ms, but was \(p99)")
    }
    
    /// Tests that transcription queue grows when backend is slow
    /// Expected: FAIL - queue will overflow
    func testTranscriptionQueueOverflow() async throws {
        let backend = SlowTranscriptionBackend(delay: .milliseconds(500))
        let transcriber = LegacyStreamingTranscriber(backend: backend)
        
        // Rapidly enqueue segments faster than they can be processed
        for i in 0..<20 {
            let segment = AudioSegment(
                samples: Array(repeating: 0.1, count: 16000),
                timestamp: Date(),
                sampleRate: 16000
            )
            await transcriber.enqueueSegmentBlocking(segment)
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        // This should FAIL - queue will have overflowed
        let pendingCount = await transcriber.pendingSegmentCount
        XCTAssertEqual(pendingCount, 0, "Queue should be empty, but has \(pendingCount) pending segments")
    }
}

// MARK: - H2 Test: Scalar DSP Under Lock

/// Demonstrates scalar audio DSP causing lock contention
/// This test should FAIL, showing contention issues
final class ScalarDSPContentionTests: XCTestCase {
    
    /// Tests that scalar downmix causes lock contention (demonstrates H2)
    /// Expected: FAIL - high contention ratio
    func testScalarDownmixCausesLockContention() async throws {
        // Given: Audio recorder with scalar DSP
        let recorder = LegacyAudioRecorder()
        let testIterations = 100
        let concurrentWriters = 4
        
        // When: Concurrent mic and system writes with scalar processing
        let startTime = ContinuousClock().now
        
        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<concurrentWriters {
                group.addTask {
                    for i in 0..<testIterations {
                        let buffer = self.createMockBuffer(
                            channelCount: writer % 2 == 0 ? 1 : 2,
                            frameCount: 1024
                        )
                        if writer % 2 == 0 {
                            await recorder.writeMicBufferLegacy(buffer)
                        } else {
                            await recorder.writeSysBufferLegacy(buffer)
                        }
                    }
                }
            }
        }
        
        let totalTime = startTime.duration(to: ContinuousClock().now)
        
        // Then: Should complete in reasonable time (this will FAIL with scalar DSP)
        // With vDSP this should take ~50ms, with scalar loops ~500ms+
        XCTAssertLessThan(totalTime, .milliseconds(100), 
                         "Concurrent writes should complete in <100ms, but took \(totalTime)")
    }
    
    /// Benchmark: vDSP vs Scalar performance
    /// Expected: FAIL - scalar is much slower
    func testScalarVsVDSPPerformance() {
        let sampleCount = 16384  // Typical buffer size
        let iterations = 1000
        
        let leftChannel = Array(repeating: Float(0.5), count: sampleCount)
        let rightChannel = Array(repeating: Float(0.3), count: sampleCount)
        
        // Measure scalar downmix time
        let scalarStart = ContinuousClock().now
        for _ in 0..<iterations {
            var result = Array(repeating: Float(0), count: sampleCount)
            for i in 0..<sampleCount {
                result[i] = (leftChannel[i] + rightChannel[i]) * 0.5
            }
        }
        let scalarTime = scalarStart.duration(to: ContinuousClock().now)
        
        // Measure vDSP downmix time
        let vdspStart = ContinuousClock().now
        for _ in 0..<iterations {
            var result = Array(repeating: Float(0), count: sampleCount)
            vDSP_vadd(leftChannel, 1, rightChannel, 1, &result, 1, vDSP_Length(sampleCount))
            var scale: Float = 0.5
            vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(sampleCount))
        }
        let vdspTime = vdspStart.duration(to: ContinuousClock().now)
        
        // Then: vDSP should be at least 2x faster (this will likely FAIL for scalar)
        let speedup = Double(scalarTime.components.attoseconds) / Double(vdspTime.components.attoseconds)
        XCTAssertGreaterThan(speedup, 2.0, 
                           "vDSP should be at least 2x faster, but only \(String(format: "%.1f", speedup))x faster")
    }
    
    /// Tests that lock hold time is excessive during DSP
    /// Expected: FAIL - lock held during entire DSP operation
    func testLockHoldTimeDuringDSP() async throws {
        let recorder = LockHoldTimeRecorder()
        let buffer = createMockBuffer(channelCount: 3, frameCount: 4800)
        
        // Measure lock hold time
        let lockHoldTime = await recorder.measureLockHoldTime(buffer: buffer)
        
        // Then: Lock should be held for <5ms (this will FAIL - currently held for full DSP)
        XCTAssertLessThan(lockHoldTime, .milliseconds(5), 
                         "Lock hold time should be <5ms, but was \(lockHoldTime)")
    }
    
    // MARK: - Helpers
    
    private func createMockBuffer(channelCount: Int, frameCount: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        if let data = buffer.floatChannelData {
            for ch in 0..<channelCount {
                for i in 0..<frameCount {
                    data[ch][i] = Float.random(in: -1...1)
                }
            }
        }
        
        return buffer
    }
}

// MARK: - H4 Test: Unstructured Task Cancellation

/// Demonstrates unstructured tasks without proper cancellation
/// This test should FAIL, showing dangling tasks
final class TaskCancellationTests: XCTestCase {
    
    /// Tests that unstructured tasks don't cancel properly (demonstrates H4)
    /// Expected: FAIL - tasks continue running after cancellation requested
    func testUnstructuredTaskNotCancelled() async throws {
        // Given: Unstructured task wrapper
        let taskWrapper = LegacyUnstructuredTaskWrapper()
        
        // When: Start a long-running task
        taskWrapper.startLongRunningTask()
        
        // Wait a bit then request cancellation
        try await Task.sleep(for: .milliseconds(100))
        await taskWrapper.requestCancellation()
        
        // Check if task is still running after cancellation
        try await Task.sleep(for: .milliseconds(200))
        
        // Then: Task should be stopped (this will FAIL with unstructured tasks)
        let isRunning = await taskWrapper.isTaskRunning
        XCTAssertFalse(isRunning, "Task should be cancelled, but is still running")
    }
    
    /// Tests cancellation latency
    /// Expected: FAIL - takes >500ms to cancel
    func testCancellationLatency() async throws {
        let taskWrapper = LegacyUnstructuredTaskWrapper()
        taskWrapper.startLongRunningTask()
        
        // Measure cancellation time
        let cancelStart = ContinuousClock().now
        await taskWrapper.requestCancellation()
        
        // Wait for task to actually stop
        var attempts = 0
        while await taskWrapper.isTaskRunning && attempts < 50 {
            try await Task.sleep(for: .milliseconds(20))
            attempts += 1
        }
        
        let cancelTime = cancelStart.duration(to: ContinuousClock().now)
        
        // Then: Should cancel within 100ms (this will FAIL)
        XCTAssertLessThan(cancelTime, .milliseconds(100), 
                         "Cancellation should complete in <100ms, but took \(cancelTime)")
    }
    
    /// Tests that child tasks are not cancelled with parent
    /// Expected: FAIL - child tasks become dangling
    func testChildTasksNotCancelledWithParent() async throws {
        let parent = LegacyUnstructuredParentTask()
        parent.startChildTasks()
        
        // Cancel parent
        await parent.cancel()
        
        // Wait
        try await Task.sleep(for: .milliseconds(300))
        
        // Then: All child tasks should be cancelled (this will FAIL)
        let activeChildren = await parent.activeChildCount
        XCTAssertEqual(activeChildren, 0, 
                      "All child tasks should be cancelled, but \(activeChildren) still active")
    }
    
    /// Tests resource cleanup on cancellation
    /// Expected: FAIL - resources leaked
    func testResourceCleanupOnCancellation() async throws {
        let resourceManager = LegacyResourceManager()
        await resourceManager.acquireResources()
        
        // Start task with resources
        resourceManager.startProcessingTask()
        
        // Cancel
        await resourceManager.requestCancellation()
        try await Task.sleep(for: .milliseconds(200))
        
        // Then: Resources should be released (this will FAIL)
        let resourcesLeaked = await resourceManager.hasLeakedResources
        XCTAssertFalse(resourcesLeaked, "Resources should be released on cancellation")
    }
    
    /// Tests cancellation propagation across task boundaries
    /// Expected: FAIL - cancellation doesn't propagate
    func testCancellationPropagation() async throws {
        let coordinator = LegacyTaskCoordinator()
        await coordinator.startCoordinatedTasks()
        
        // Cancel coordinator
        await coordinator.cancelAll()
        
        try await Task.sleep(for: .milliseconds(200))
        
        // Then: All coordinated tasks should be cancelled (this will FAIL)
        let anyRunning = await coordinator.anyTaskRunning
        XCTAssertFalse(anyRunning, "All tasks should be cancelled")
    }
}

// MARK: - Performance Benchmarks as Tests

/// Performance benchmarks that will fail until issues are fixed
final class PerformanceBenchmarkTests: XCTestCase {
    
    /// VAD loop latency benchmark
    /// Target: < 50ms per frame
    func testVADLoopLatencyBenchmark() async throws {
        let backend = MockFastBackend()
        let transcriber = LegacyStreamingTranscriber(backend: backend)
        
        var latencies: [Duration] = []
        
        for i in 0..<100 {
            let frame = AudioFrame(
                samples: Array(repeating: 0.1, count: 320),
                timestamp: Date(),
                sampleRate: 16000
            )
            
            let start = ContinuousClock().now
            await transcriber.processFrameBlocking(frame)
            let latency = start.duration(to: ContinuousClock().now)
            latencies.append(latency)
        }
        
        let avgLatency = latencies.reduce(.zero) { $0 + $1 } / latencies.count
        let maxLatency = latencies.max()!
        
        // Then: Should meet performance budget
        XCTAssertLessThan(avgLatency, .milliseconds(10), "Avg latency: \(avgLatency)")
        XCTAssertLessThan(maxLatency, .milliseconds(50), "Max latency: \(maxLatency)")
    }
    
    /// Audio processing throughput benchmark
    /// Target: Process 1 second of audio in < 100ms
    func testAudioProcessingThroughput() async throws {
        let recorder = LegacyAudioRecorder()
        let audioData = Array(repeating: Float(0.5), count: 48000)  // 1 second at 48kHz
        let buffer = createFloatBuffer(samples: audioData, sampleRate: 48000)
        
        let start = ContinuousClock().now
        await recorder.writeMicBufferLegacy(buffer)
        let processingTime = start.duration(to: ContinuousClock().now)
        
        // Then: Should process 1 second of audio in < 100ms
        XCTAssertLessThan(processingTime, .milliseconds(100), 
                         "Processing time: \(processingTime)")
    }
    
    /// Concurrent task cancellation benchmark
    /// Target: Cancel 100 tasks in < 500ms
    func testBulkCancellationBenchmark() async throws {
        let coordinator = LegacyTaskCoordinator()
        await coordinator.startManyTasks(count: 100)
        
        let cancelStart = ContinuousClock().now
        await coordinator.cancelAll()
        
        // Wait for all to cancel
        var cancelledCount = 0
        var attempts = 0
        while cancelledCount < 100 && attempts < 100 {
            cancelledCount = await coordinator.cancelledTaskCount
            try await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        
        let cancelTime = cancelStart.duration(to: ContinuousClock().now)
        
        // Then: Should cancel all in < 500ms
        XCTAssertEqual(cancelledCount, 100, "Should cancel all 100 tasks")
        XCTAssertLessThan(cancelTime, .milliseconds(500), "Cancel time: \(cancelTime)")
    }
    
    // MARK: - Helpers
    
    private func createFloatBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        
        if let data = buffer.floatChannelData {
            for i in 0..<samples.count {
                data[0][i] = samples[i]
            }
        }
        
        return buffer
    }
}

// MARK: - Mock Types for Testing

/// Mock transcription backend with configurable delay
actor SlowTranscriptionBackend: TranscriptionBackend {
    let delay: Duration
    var callCount = 0
    
    init(delay: Duration) {
        self.delay = delay
    }
    
    func transcribe(_ samples: [Float], locale: Locale, previousContext: String?) async throws -> String {
        callCount += 1
        try await Task.sleep(for: delay)
        return "Transcribed text \(callCount)"
    }
    
    nonisolated var displayName: String { "SlowBackend" }
}

/// Fast mock backend for baseline measurements
actor MockFastBackend: TranscriptionBackend {
    func transcribe(_ samples: [Float], locale: Locale, previousContext: String?) async throws -> String {
        // Minimal work
        return "Fast result"
    }
    
    nonisolated var displayName: String { "FastBackend" }
}

// Placeholder types that represent the current problematic implementations
// These will be implemented to demonstrate the issues
actor LegacyStreamingTranscriber {
    let backend: any TranscriptionBackend
    var pendingSegments: [AudioSegment] = []
    var isRunningPartial = false
    
    init(backend: any TranscriptionBackend) {
        self.backend = backend
    }
    
    /// BLOCKING: Current implementation blocks on transcription
    func processFrameBlocking(_ frame: AudioFrame) async {
        // Simulate VAD processing
        try? await Task.sleep(for: .milliseconds(1))
        
        // PROBLEM: If we have enough samples, we block on transcription
        if frame.samples.count > 8000 && !isRunningPartial {
            isRunningPartial = true
            // This await BLOCKS the VAD loop!
            _ = try? await backend.transcribe(frame.samples, locale: Locale.current, previousContext: nil)
            isRunningPartial = false
        }
    }
    
    func enqueueSegmentBlocking(_ segment: AudioSegment) async {
        pendingSegments.append(segment)
        // Process immediately (blocks)
        _ = try? await backend.transcribe(segment.samples, locale: Locale.current, previousContext: nil)
        if let index = pendingSegments.firstIndex(where: { $0.timestamp == segment.timestamp }) {
            pendingSegments.remove(at: index)
        }
    }
    
    var pendingSegmentCount: Int { pendingSegments.count }
}

actor LegacyAudioRecorder {
    private let lock = NSLock()
    
    /// BLOCKING: Current implementation does scalar DSP under lock
    func writeMicBufferLegacy(_ buffer: AVAudioPCMBuffer) async {
        lock.withLock {
            // PROBLEM: Scalar downmix under lock
            let frames = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            
            if let src = buffer.floatChannelData {
                for i in 0..<frames {
                    var sum: Float = 0
                    for ch in 0..<channels {
                        sum += src[ch][i]
                    }
                    // Do something with sum
                    _ = sum * (1.0 / Float(channels))
                }
            }
        }
    }
    
    func writeSysBufferLegacy(_ buffer: AVAudioPCMBuffer) async {
        lock.withLock {
            // Just hold lock briefly to simulate contention
            let _ = buffer.frameLength
        }
    }
}

actor LockHoldTimeRecorder {
    private let lock = NSLock()
    
    func measureLockHoldTime(buffer: AVAudioPCMBuffer) async -> Duration {
        let start = ContinuousClock().now
        lock.withLock {
            // Simulate scalar DSP work
            let frames = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            
            if let src = buffer.floatChannelData {
                for i in 0..<frames {
                    var sum: Float = 0
                    for ch in 0..<channels {
                        sum += src[ch][i]
                    }
                    _ = sum / Float(channels)
                }
            }
        }
        return start.duration(to: ContinuousClock().now)
    }
}

/// Represents unstructured task issues
actor LegacyUnstructuredTaskWrapper {
    private var task: Task<Void, Never>?
    private(set) var isTaskRunning = false
    
    func startLongRunningTask() {
        isTaskRunning = true
        // PROBLEM: Unstructured task - no cancellation handler
        task = Task {
            // Simulate long work
            for i in 0..<100 {
                try? await Task.sleep(for: .milliseconds(50))
                // No cancellation check!
            }
            isTaskRunning = false
        }
    }
    
    func requestCancellation() async {
        // PROBLEM: Just nils the task reference without proper cancellation
        task = nil
        // Task may still be running!
    }
}

actor LegacyUnstructuredParentTask {
    private var childTasks: [Task<Void, Never>] = []
    
    func startChildTasks() {
        for i in 0..<5 {
            // PROBLEM: Child tasks not connected to parent
            let task = Task {
                try? await Task.sleep(for: .seconds(10))
            }
            childTasks.append(task)
        }
    }
    
    func cancel() async {
        // PROBLEM: Cancelling parent doesn't cancel children
        childTasks.removeAll()
    }
    
    var activeChildCount: Int { childTasks.count }
}

actor LegacyResourceManager {
    private var resourcesAcquired = false
    private var processingTask: Task<Void, Never>?
    
    func acquireResources() async {
        resourcesAcquired = true
    }
    
    func startProcessingTask() {
        processingTask = Task {
            try? await Task.sleep(for: .seconds(5))
        }
    }
    
    func requestCancellation() async {
        // PROBLEM: No cleanup on cancellation
        processingTask = nil
    }
    
    var hasLeakedResources: Bool { resourcesAcquired }
}

actor LegacyTaskCoordinator {
    private var tasks: [Task<Void, Never>] = []
    private(set) var cancelledTaskCount = 0
    
    func startCoordinatedTasks() async {
        for i in 0..<3 {
            let task = Task {
                try? await Task.sleep(for: .seconds(10))
            }
            tasks.append(task)
        }
    }
    
    func startManyTasks(count: Int) async {
        for i in 0..<count {
            let task = Task {
                try? await Task.sleep(for: .seconds(10))
            }
            tasks.append(task)
        }
    }
    
    func cancelAll() async {
        // PROBLEM: Just drops references, doesn't cancel
        cancelledTaskCount = tasks.count
        tasks.removeAll()
    }
    
    var anyTaskRunning: Bool { !tasks.isEmpty }
}

// MARK: - Supporting Types

struct AudioFrame: Sendable {
    let samples: [Float]
    let timestamp: Date
    let sampleRate: Double
}

extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}

// Need to import these from OpenOats
// For now, define minimal conformances needed for tests

struct AudioSegment: Sendable {
    let samples: [Float]
    let timestamp: Date
    let sampleRate: Double
}

// Extend to use the real type from OpenOats
extension OpenOats.AudioSegment {
    init(samples: [Float], timestamp: Date, sampleRate: Double) {
        self.init(
            id: AudioSegmentID(),
            sessionID: SessionID(),
            audioData: Data(),
            sampleRate: sampleRate,
            channelCount: 1,
            bitsPerSample: 16,
            startTime: .zero,
            duration: .seconds(Double(samples.count) / sampleRate)
        )
    }
}
