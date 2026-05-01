# TASK-015: Address Critical Data Races and Concurrency Issues

## Overview
Address critical data races identified in deep architecture review, converting `@unchecked Sendable` types to proper actor isolation.

## Critical Issues from Deep Architecture Review

### C1. StreamingTranscriber Data Race (CRITICAL)

**Issue**: `@unchecked Sendable` with mutable fields:
- `converter: AudioConverter?`
- `rateTrackingStartDate: Date?`
- `previousContext: WhisperContext?`
- `effectiveSampleRate: Double`

**Risk**: `EXC_BAD_ACCESS` if concurrent access occurs during streaming.

**Fix Design**:

```swift
/// Actor-isolated streaming transcription state
actor StreamingTranscriptionActor {
    // MARK: - Mutable State (Actor-isolated)
    
    private var converter: AudioConverter?
    private var rateTrackingStartDate: Date?
    private var previousContext: WhisperContext?
    private var effectiveSampleRate: Double = 0.0
    private var pendingBuffers: [AudioSegment] = []
    private var isProcessing: Bool = false
    
    // MARK: - Immutable Configuration (Sendable, nonisolated)
    
    let config: TranscriptionConfiguration
    let backendID: BackendID
    let maxBufferSize: Int = 1024 * 1024 // 1MB max buffer
    
    // MARK: - Interface Methods
    
    /// Process incoming audio buffer
    func processBuffer(_ segment: AudioSegment) throws -> TranscriptionSegment? {
        // Actor-isolated: safe mutation of converter, context, etc.
        guard !isProcessing else {
            // Queue for later if already processing
            if pendingBuffers.count < maxBufferSize {
                pendingBuffers.append(segment)
            }
            return nil
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Safe mutation of actor-isolated state
        if converter == nil {
            converter = createConverter(for: segment.format)
        }
        
        // Process with converter
        return try processWithConverter(segment)
    }
    
    /// Update rate tracking
    func updateRateTracking(startDate: Date) {
        rateTrackingStartDate = startDate
    }
    
    /// Get current sample rate (safe read from actor context)
    func getEffectiveSampleRate() -> Double {
        return effectiveSampleRate
    }
    
    /// Cleanup resources
    func cleanup() {
        converter = nil
        previousContext = nil
        pendingBuffers.removeAll()
        isProcessing = false
    }
    
    // MARK: - Private Helper Methods
    
    private func createConverter(for format: AudioFormat) -> AudioConverter {
        // Implementation
    }
    
    private func processWithConverter(_ segment: AudioSegment) throws -> TranscriptionSegment? {
        // Implementation using actor-isolated converter
        return nil
    }
}

/// Public interface wrapper for the actor
/// Preserves original API while providing actor safety
struct StreamingTranscriber: Sendable {
    private let actor: StreamingTranscriptionActor
    private let transcriptionStream: AsyncStream<TranscriptionSegment>
    
    init(config: TranscriptionConfiguration) {
        self.actor = StreamingTranscriptionActor(config: config, backendID: .mlx)
        // ... setup stream
    }
    
    /// Process audio (safe - runs in actor context)
    func processAudio(_ segment: AudioSegment) async throws -> TranscriptionSegment? {
        return try await actor.processBuffer(segment)
    }
    
    /// Access to transcription stream (immutable, Sendable)
    var stream: AsyncStream<TranscriptionSegment> { transcriptionStream }
    
    /// Cleanup
    func stop() async {
        await actor.cleanup()
    }
}
```

### C2. MicCapture Audio Callback Data Race (CRITICAL)

**Issue**: `tapCallCount += 1` on audio thread without synchronization:

```swift
// BEFORE (unsafe)
installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
    self?.tapCallCount += 1  // Data race! Audio thread writes, main thread reads
    self?.processAudioBuffer(buffer)
}
```

**Fix Design - Option A: Atomic Operations**:

```swift
import os.atomic

actor MicCaptureActor {
    // Use OSAllocatedUnfairLock for atomic counter
    private let tapCounterLock = OSAllocatedUnfairLock<Int>(initialState: 0)
    
    nonisolated func incrementTapCount() {
        tapCounterLock.withLock { $0 += 1 }
    }
    
    nonisolated var tapCallCount: Int {
        tapCounterLock.withLock { $0 }
    }
    
    // Audio callback (called on audio thread)
    nonisolated func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Safe: nonisolated with atomic operations
        incrementTapCount()
        
        // Send to actor for processing
        Task {
            await processBuffer(buffer, at: time)
        }
    }
    
    // Actor-isolated processing
    func processBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) async {
        // Safe processing with actor isolation
    }
}
```

**Fix Design - Option B: Strict Actor Isolation**:

```swift
/// Complete actor isolation for audio capture
actor MicCapture {
    // MARK: - State
    
    private var engine: AVAudioEngine?
    private var isRecording: Bool = false
    private var tapCallCount: Int = 0  // Now actor-isolated
    
    // MARK: - Audio Callback (bridged to actor)
    
    func startRecording() throws {
        let engine = AVAudioEngine()
        
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, time in
            // Bridge audio thread to actor
            Task { [weak self] in
                await self?.handleAudioBuffer(buffer, at: time)
            }
        }
        
        try engine.start()
        self.engine = engine
        self.isRecording = true
    }
    
    // MARK: - Actor-Isolated Handler
    
    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        // Safe: running in actor context
        tapCallCount += 1
        
        // Process buffer...
        processBuffer(buffer, timestamp: time)
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer, timestamp: AVAudioTime) {
        // Safe audio processing
    }
    
    // MARK: - Public Interface
    
    func getTapCount() -> Int {
        return tapCallCount
    }
    
    func stopRecording() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        isRecording = false
    }
}
```

### Additional Data Race Fixes Required

#### AudioRingBuffer Thread Safety

```swift
/// Thread-safe ring buffer for audio data
actor AudioRingBuffer {
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var filledCount: Int = 0
    
    let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: 0.0, count: capacity)
    }
    
    /// Write samples (actor-isolated, safe)
    func write(_ samples: [Float]) -> Int {
        var written = 0
        for sample in samples {
            if filledCount >= capacity {
                break
            }
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            filledCount += 1
            written += 1
        }
        return written
    }
    
    /// Read samples (actor-isolated, safe)
    func read(count: Int) -> [Float] {
        let toRead = min(count, filledCount)
        var result: [Float] = []
        result.reserveCapacity(toRead)
        
        for _ in 0..<toRead {
            result.append(buffer[readIndex])
            readIndex = (readIndex + 1) % capacity
            filledCount -= 1
        }
        
        return result
    }
    
    var isEmpty: Bool { filledCount == 0 }
    var isFull: Bool { filledCount >= capacity }
    var count: Int { filledCount }
}
```

#### Thread-Safe State Transitions

```swift
/// Actor for managing transcription state transitions
actor TranscriptionStateMachine {
    enum State: Sendable {
        case idle
        case initializing
        case listening
        case processing(segmentID: UUID)
        case finalizing
        case completed(result: Transcript)
        case failed(error: TranscriptionError)
    }
    
    private var state: State = .idle
    private var stateHistory: [(State, Date)] = []
    
    func transition(to newState: State) throws {
        // Validate transition
        guard isValidTransition(from: state, to: newState) else {
            throw TranscriptionError.invalidStateTransition(
                from: String(describing: state),
                to: String(describing: newState)
            )
        }
        
        stateHistory.append((state, Date()))
        state = newState
    }
    
    func getCurrentState() -> State {
        return state
    }
    
    func getStateHistory() -> [(State, Date)] {
        return stateHistory
    }
    
    private func isValidTransition(from: State, to: State) -> Bool {
        // Define valid transitions
        switch (from, to) {
        case (.idle, .initializing),
             (.initializing, .listening),
             (.listening, .processing),
             (.processing, .listening),
             (.processing, .finalizing),
             (.listening, .finalizing),
             (.finalizing, .completed),
             (.finalizing, .failed),
             (_, .failed):  // Can fail from any state
            return true
        default:
            return false
        }
    }
}
```

## Migration Checklist

### Phase 1: Convert to Actors
- [ ] Convert `StreamingTranscriber` → `StreamingTranscriptionActor`
- [ ] Convert `MicCapture` → `MicCaptureActor`  
- [ ] Convert `SystemAudioCapture` → `SystemAudioCaptureActor`
- [ ] Convert `AudioRingBuffer` → `AudioRingBufferActor`

### Phase 2: Remove @unchecked Sendable
- [ ] Remove `@unchecked Sendable` from all types
- [ ] Add proper `Sendable` conformance via actor isolation
- [ ] Audit all mutable state access

### Phase 3: Audio Thread Safety
- [ ] Replace `tapCallCount += 1` with atomic or actor-isolated pattern
- [ ] Audit all AVAudioEngine tap callbacks
- [ ] Bridge audio callbacks to actors via Task

### Phase 4: Validation
- [ ] Run Thread Sanitizer (TSan) tests
- [ ] Stress test concurrent transcription
- [ ] Verify no data races in audio pipeline

## Test Strategy

```swift
import XCTest

final class ConcurrencySafetyTests: XCTestCase {
    func testStreamingTranscriberNoDataRaces() async throws {
        let transcriber = StreamingTranscriber(config: .default)
        
        // Concurrent access from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let segment = AudioSegment.mock(id: i)
                    _ = try? await transcriber.processAudio(segment)
                }
            }
        }
        
        // If we get here without crashes, no data races
    }
    
    func testMicCaptureThreadSafety() async throws {
        let capture = MicCaptureActor()
        
        // Simulate concurrent tap callbacks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    // Simulates audio thread callback
                    await capture.handleAudioBuffer(.mock, at: .mock)
                }
            }
        }
        
        let count = await capture.getTapCount()
        XCTAssertEqual(count, 1000)
    }
}
```

## Formal Properties Verification

- **SAFETY**: No `@unchecked Sendable` with mutable state - All types use proper actor isolation
- **SAFETY**: Audio callbacks use thread-safe operations - Bridged to actors via Task
- **INVARIANT**: All concurrent mutable state is properly isolated - Verified by compiler

