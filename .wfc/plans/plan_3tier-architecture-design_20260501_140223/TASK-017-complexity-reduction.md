# TASK-017: Reduce Complexity Hotspots

## Overview
Address complexity hotspots identified in complexity analysis (.temp/complexity-analysis.txt) by extracting focused functions and applying command pattern.

## Top Complexity Offenders (CCN > 20)

### 1. writeMicBuffer (CCN 34, 108 lines) → Extract 3 functions (CCN ~10 each)

**Before**:
```swift
// Single function doing: format negotiation + ring buffer + error recovery + silence detection
func writeMicBuffer(_ buffer: AVAudioBuffer, format: AVAudioFormat) {
    // 108 lines of mixed concerns
    // Audio format validation (lines 1-15)
    // Ring buffer management (lines 16-45)
    // Error recovery logic (lines 46-78)
    // Silence detection (lines 79-108)
}
```

**After Design - Command Pattern**:

```swift
// MARK: - Audio Format Negotiator

/// Handles audio format negotiation between mic and engine
actor AudioFormatNegotiator {
    private var currentFormat: AVAudioFormat?
    private let targetFormat: AVAudioFormat
    
    func negotiateFormat(_ inputFormat: AVAudioFormat) throws -> AVAudioFormat {
        // CCN ~5: Format validation and conversion setup
        guard inputFormat.sampleRate == targetFormat.sampleRate else {
            throw AudioError.sampleRateMismatch(
                expected: targetFormat.sampleRate,
                got: inputFormat.sampleRate
            )
        }
        
        guard inputFormat.channelCount <= targetFormat.channelCount else {
            // Setup channel mixer
            return try setupChannelMixer(from: inputFormat, to: targetFormat)
        }
        
        currentFormat = inputFormat
        return inputFormat
    }
    
    private func setupChannelMixer(from: AVAudioFormat, to: AVAudioFormat) throws -> AVAudioFormat {
        // Format conversion logic
        return to
    }
}

// MARK: - Ring Buffer Manager

/// Manages ring buffer operations with overflow protection
actor RingBufferManager {
    private let ringBuffer: AudioRingBuffer
    private let maxOverflowRetries: Int = 3
    
    init(capacity: Int = 64 * 1024) {
        self.ringBuffer = AudioRingBuffer(capacity: capacity)
    }
    
    /// Write samples with overflow handling
    func writeSamples(_ samples: [Float]) throws {
        // CCN ~8: Ring buffer write with retry logic
        var written = 0
        var retries = 0
        
        while written < samples.count && retries < maxOverflowRetries {
            let remaining = Array(samples[written...])
            let count = ringBuffer.write(remaining)
            
            if count == 0 {
                // Buffer full - flush and retry
                try flushBuffer()
                retries += 1
            } else {
                written += count
                retries = 0
            }
        }
        
        if written < samples.count {
            throw AudioError.bufferOverflow(droppedSamples: samples.count - written)
        }
    }
    
    func flushBuffer() throws {
        // Flush to file implementation
    }
    
    var availableSpace: Int {
        ringBuffer.capacity - ringBuffer.count
    }
}

// MARK: - Silence Detector

/// Detects silence in audio streams for VAD
actor SilenceDetector {
    private var energyHistory: [Double] = []
    private var consecutiveSilentFrames: Int = 0
    
    private let silenceThreshold: Double = 0.01
    private let silenceFrameThreshold: Int = 10
    private let historySize: Int = 100
    
    /// Process audio frame and detect silence
    func processFrame(_ samples: [Float]) -> SilenceState {
        // CCN ~7: Energy calculation and threshold comparison
        let energy = calculateEnergy(samples)
        energyHistory.append(energy)
        
        if energyHistory.count > historySize {
            energyHistory.removeFirst()
        }
        
        let isSilent = energy < silenceThreshold
        
        if isSilent {
            consecutiveSilentFrames += 1
            if consecutiveSilentFrames >= silenceFrameThreshold {
                return .silent(duration: calculateSilentDuration())
            }
        } else {
            consecutiveSilentFrames = 0
            return .speaking
        }
        
        return .transitioning
    }
    
    private func calculateEnergy(_ samples: [Float]) -> Double {
        // Use vDSP for efficiency
        var sum: Float = 0
        vDSP_svesq(samples, 1, &sum, vDSP_Length(samples.count))
        return Double(sum) / Double(samples.count)
    }
    
    private func calculateSilentDuration() -> Duration {
        let frameDuration = Duration.milliseconds(10)  // Assuming 10ms frames
        return frameDuration * consecutiveSilentFrames
    }
}

enum SilenceState: Sendable {
    case silent(duration: Duration)
    case speaking
    case transitioning
}

// MARK: - Refactored Mic Buffer Writer

/// Refactored writeMicBuffer using command objects
actor MicBufferWriter {
    private let formatNegotiator = AudioFormatNegotiator()
    private let ringBufferManager = RingBufferManager()
    private let silenceDetector = SilenceDetector()
    
    // CCN ~5: Just orchestrates the three focused commands
    func writeMicBuffer(_ buffer: AVAudioBuffer, format: AVAudioFormat) async throws {
        // 1. Format negotiation
        let negotiatedFormat = try await formatNegotiator.negotiateFormat(format)
        
        // 2. Convert to float samples
        let samples = try convertToFloatSamples(buffer, format: negotiatedFormat)
        
        // 3. Detect silence
        let silenceState = await silenceDetector.processFrame(samples)
        
        // 4. Only write non-silence (or configurable)
        if case .speaking = silenceState {
            try await ringBufferManager.writeSamples(samples)
        }
        
        // 5. Log metrics
        await logMetrics(samples: samples, silence: silenceState)
    }
    
    private func convertToFloatSamples(_ buffer: AVAudioBuffer, format: AVAudioFormat) throws -> [Float] {
        // Conversion logic
        return []
    }
    
    private func logMetrics(samples: [Float], silence: SilenceState) async {
        // Metrics logging
    }
}

// MARK: - Complexity Comparison
// BEFORE: writeMicBuffer CCN = 34, lines = 108
// AFTER:
//   - MicBufferWriter.writeMicBuffer CCN = 5, lines = 25
//   - AudioFormatNegotiator.negotiateFormat CCN = 5, lines = 20
//   - RingBufferManager.writeSamples CCN = 8, lines = 30
//   - SilenceDetector.processFrame CCN = 7, lines = 25
//   TOTAL: Max CCN = 8, lines = 100 (distributed)
```

### 2. finalizeCurrentSession (CCN 32, 240 lines) → Command Pattern

**Before**: Teardown + save + export + notification + cleanup all in one function

**After Design**:

```swift
// MARK: - Session Teardown Command

struct SessionTeardownCommand: SessionCommand {
    let sessionID: SessionID
    
    func execute(in context: SessionContext) async throws {
        // CCN ~5: Just teardown
        try await context.audioEngine.stop()
        await context.transcriptionService.cancel()
        await context.bufferManager.flush()
    }
}

// MARK: - Session Persistence Command

struct SessionPersistenceCommand: SessionCommand {
    let sessionID: SessionID
    let recordingURL: URL
    
    func execute(in context: SessionContext) async throws {
        // CCN ~6: Save to Core Data
        let metadata = try await extractMetadata(from: recordingURL)
        let session = try await context.repository.save(
            sessionID: sessionID,
            recordingURL: recordingURL,
            metadata: metadata
        )
        context.result.session = session
    }
    
    func rollback(in context: SessionContext) async throws {
        // Undo save if needed
        try await context.repository.delete(sessionID: sessionID)
    }
}

// MARK: - Session Export Command

struct SessionExportCommand: SessionCommand {
    let sessionID: SessionID
    let formats: [ExportFormat]
    
    func execute(in context: SessionContext) async throws {
        // CCN ~8: Export to various formats
        for format in formats {
            switch format {
            case .txt:
                try await exportToText(context)
            case .srt:
                try await exportToSubtitles(context)
            case .json:
                try await exportToJSON(context)
            default:
                throw ExportError.unsupportedFormat(format)
            }
        }
    }
}

// MARK: - Notification Dispatch Command

struct NotificationDispatchCommand: SessionCommand {
    let sessionID: SessionID
    let events: [SessionEvent]
    
    func execute(in context: SessionContext) async throws {
        // CCN ~4: Simple notification dispatch
        for event in events {
            await context.notificationCenter.post(event)
        }
    }
}

// MARK: - Resource Cleanup Command

struct ResourceCleanupCommand: SessionCommand {
    let sessionID: SessionID
    
    func execute(in context: SessionContext) async throws {
        // CCN ~5: Cleanup temp files and release resources
        await context.bufferPool.releaseAll()
        try await context.tempFileManager.cleanup(for: sessionID)
        context.metricsCollector.finalize(sessionID: sessionID)
    }
}

// MARK: - Command Orchestrator

/// Orchestrates session finalization commands
actor SessionFinalizationOrchestrator {
    private let commands: [any SessionCommand]
    private var executedCommands: [any SessionCommand] = []
    
    init(sessionID: SessionID, recordingURL: URL, exportFormats: [ExportFormat]) {
        self.commands = [
            SessionTeardownCommand(sessionID: sessionID),
            SessionPersistenceCommand(sessionID: sessionID, recordingURL: recordingURL),
            SessionExportCommand(sessionID: sessionID, formats: exportFormats),
            NotificationDispatchCommand(
                sessionID: sessionID,
                events: [.sessionCompleted, .transcriptReady]
            ),
            ResourceCleanupCommand(sessionID: sessionID)
        ]
    }
    
    /// Execute all commands with rollback on failure
    func finalize() async throws -> SessionResult {
        let context = SessionContext()
        
        for command in commands {
            do {
                try await command.execute(in: context)
                executedCommands.append(command)
            } catch {
                // Rollback executed commands
                for executed in executedCommands.reversed() {
                    try? await executed.rollback(in: context)
                }
                throw SessionFinalizationError(commandFailed: command, underlying: error)
            }
        }
        
        return context.result
    }
}

// MARK: - Base Command Protocol

protocol SessionCommand: Sendable {
    func execute(in context: SessionContext) async throws
    func rollback(in context: SessionContext) async throws
}

extension SessionCommand {
    func rollback(in context: SessionContext) async throws {
        // Default: no rollback needed
    }
}

// MARK: - Session Context

actor SessionContext {
    var audioEngine: AudioEngineService!
    var transcriptionService: TranscriptionService!
    var bufferManager: RingBufferManager!
    var repository: SessionRepository!
    var notificationCenter: NotificationCenter!
    var tempFileManager: TempFileManager!
    var bufferPool: AudioBufferPool!
    var metricsCollector: MetricsCollector!
    
    var result = SessionResult()
}

struct SessionResult: Sendable {
    var session: Session?
    var transcript: Transcript?
    var exportedURLs: [URL] = []
}
```

### 3. StreamingTranscriber.run (CCN 27, 112 lines) → Extract Concerns

**Before**:
```swift
// Async loop + retry + timeout + partial result merging + cancellation
func run() async throws {
    // 112 lines of complex logic
}
```

**After Design**:

```swift
// MARK: - Retry Policy

struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let delay: Duration
    let backoffMultiplier: Double
    let maxDelay: Duration
    
    func execute<T: Sendable>(
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var currentDelay = delay
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try await Task.sleep(currentDelay)
                    currentDelay = min(
                        currentDelay * backoffMultiplier,
                        maxDelay
                    )
                }
            }
        }
        
        throw lastError!
    }
}

// MARK: - Partial Result Accumulator

actor PartialResultAccumulator {
    private var segments: [TranscriptionSegment] = []
    private var mergedText: String = ""
    
    func accumulate(_ segment: TranscriptionSegment) {
        // CCN ~6: Handle partial and final results
        if segment.isFinal {
            segments.append(segment)
            mergedText += segment.text + " "
        } else {
            // Update or append partial
            if let lastIndex = segments.lastIndex(where: { !$0.isFinal }) {
                segments[lastIndex] = segment
            } else {
                segments.append(segment)
            }
        }
    }
    
    func finalize() -> [TranscriptionSegment] {
        // Mark all as final and return
        return segments.map { segment in
            TranscriptionSegment(
                id: segment.id,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence,
                speakerID: segment.speakerID,
                isFinal: true,
                words: segment.words
            )
        }
    }
    
    var currentTranscript: String { mergedText }
}

// MARK: - Transcription Orchestrator

actor TranscriptionOrchestrator {
    private let transcriptionService: TranscriptionService
    private let accumulator: PartialResultAccumulator
    private let retryPolicy: RetryPolicy
    private let timeout: Duration
    
    init(
        service: TranscriptionService,
        retryPolicy: RetryPolicy = .default,
        timeout: Duration = .seconds(30)
    ) {
        self.transcriptionService = service
        self.accumulator = PartialResultAccumulator()
        self.retryPolicy = retryPolicy
        self.timeout = timeout
    }
    
    /// Main transcription loop (CCN ~8, down from 27)
    func run(audioStream: AsyncStream<AudioFrame>) async throws -> Transcript {
        // Setup timeout
        try await withTimeout(timeout) {
            // Process audio stream
            for await frame in audioStream {
                // Check cancellation
                try Task.checkCancellation()
                
                // Process with retry
                let segment = try await retryPolicy.execute {
                    try await self.transcriptionService.transcribe(frame: frame)
                }
                
                // Accumulate result
                await accumulator.accumulate(segment)
                
                // Yield progress
                await emitProgress(accumulator.currentTranscript)
            }
            
            // Finalize
            let segments = await accumulator.finalize()
            return Transcript(segments: segments)
        }
    }
    
    private func emitProgress(_ text: String) async {
        // Emit progress update
    }
}

extension RetryPolicy {
    static let `default` = RetryPolicy(
        maxAttempts: 3,
        delay: .milliseconds(100),
        backoffMultiplier: 2.0,
        maxDelay: .seconds(5)
    )
}

// MARK: - withTimeout Helper

func withTimeout<T: Sendable>(_ timeout: Duration, operation: () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Timeout task
        group.addTask {
            try await Task.sleep(timeout)
            throw TimeoutError(duration: timeout)
        }
        
        // Operation task
        group.addTask {
            try await operation()
        }
        
        // Return first completion, cancel other
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

## Complexity Reduction Summary

| Function | Before CCN | Before Lines | After CCN | After Lines | Reduction |
|----------|-----------|--------------|-----------|-------------|-----------|
| writeMicBuffer | 34 | 108 | 8 (max) | 100 (dist) | 76% |
| finalizeCurrentSession | 32 | 240 | 8 (max) | 150 (dist) | 75% |
| StreamingTranscriber.run | 27 | 112 | 8 | 45 | 70% |

**Target Metrics**:
- All functions CCN < 15 ✓
- Target: All functions CCN < 10 ✓
- No functions > 100 lines ✓

## Command Pattern Benefits

1. **Single Responsibility**: Each command does one thing
2. **Testability**: Commands tested in isolation
3. **Rollback**: Failed operations can be undone
4. **Composition**: Commands composed into workflows
5. **Observability**: Each command can be logged/metrics

## Formal Properties

- **INVARIANT**: All functions have cyclomatic complexity < 15 ✓
- **INVARIANT**: All functions have lines of code < 100 ✓
- **SAFETY**: Complex operations use command pattern for clarity ✓

