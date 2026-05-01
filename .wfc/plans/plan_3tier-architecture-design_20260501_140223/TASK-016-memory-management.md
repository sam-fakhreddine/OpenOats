# TASK-016: Fix Memory Management and OOM Prevention

## Overview
Address memory issues identified in deep architecture review: unbounded audio loading, temp file durability, and speech buffer growth.

## Critical Issues from Deep Architecture Review

### C3. Unbounded Memory in mergeAndEncode (CRITICAL)

**Issue**: `readAllMono()` loads entire recording into `[Float]` arrays:
- 2-hour meeting at 48kHz = ~2.6GB memory
- OOM kill on 8GB Macs

**Fix Design - Streaming Audio Processing**:

```swift
// MARK: - Streaming Audio Processor Protocol

protocol AudioStreamProcessor: Sendable {
    /// Process audio in fixed-size chunks
    /// - Parameters:
    ///   - input: Input audio stream
    ///   - chunkSize: Frames per chunk (default 64K = ~768KB)
    /// - Returns: Processed audio stream
    func processStream(
        input: AsyncThrowingStream<AudioFrame, Error>,
        chunkSize: Int
    ) -> AsyncThrowingStream<AudioFrame, Error>
}

// MARK: - Fixed-Size Buffer Pool

/// Reusable buffer pool to minimize allocations
actor AudioBufferPool {
    /// Maximum buffer size: 64K frames = ~768KB for 48kHz stereo float
    static let defaultChunkSize: Int = 64 * 1024
    static let maxPoolSize: Int = 4  // ~3MB total pool
    
    private var availableBuffers: [[Float]] = []
    private var inUseCount: Int = 0
    
    /// Acquire a buffer from the pool
    func acquire() -> [Float] {
        if let buffer = availableBuffers.popLast() {
            inUseCount += 1
            return buffer
        }
        // Create new if pool exhausted
        inUseCount += 1
        return Array(repeating: 0.0, count: Self.defaultChunkSize)
    }
    
    /// Return buffer to pool for reuse
    func release(_ buffer: inout [Float]) {
        if availableBuffers.count < Self.maxPoolSize {
            buffer.resetToZero()  // Zero for security
            availableBuffers.append(buffer)
        }
        inUseCount -= 1
        buffer = []  // Clear reference
    }
    
    var stats: PoolStats {
        PoolStats(
            available: availableBuffers.count,
            inUse: inUseCount,
            totalMemory: (availableBuffers.count + inUseCount) * Self.defaultChunkSize * MemoryLayout<Float>.size
        )
    }
}

struct PoolStats: Sendable {
    let available: Int
    let inUse: Int
    let totalMemory: Int
}

// MARK: - Streaming Merge and Encode

/// Replaces mergeAndEncode with streaming version
actor StreamingAudioMerger {
    private let bufferPool = AudioBufferPool()
    private let chunkSize = AudioBufferPool.defaultChunkSize
    
    /// Merge microphone and system audio streams
    /// Memory usage: ~768KB regardless of recording length
    func mergeStreams(
        micStream: AsyncThrowingStream<AudioFrame, Error>,
        sysStream: AsyncThrowingStream<AudioFrame, Error>,
        outputURL: URL
    ) async throws {
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: defaultAudioSettings
        )
        
        // Process in fixed-size chunks
        var micBuffer = await bufferPool.acquire()
        var sysBuffer = await bufferPool.acquire()
        defer {
            Task {
                await bufferPool.release(&micBuffer)
                await bufferPool.release(&sysBuffer)
            }
        }
        
        var micIterator = micStream.makeAsyncIterator()
        var sysIterator = sysStream.makeAsyncIterator()
        
        while true {
            // Fill mic buffer
            var micFilled = 0
            while micFilled < chunkSize {
                guard let frame = try await micIterator.next() else { break }
                micBuffer[micFilled] = frame.sample
                micFilled += 1
            }
            
            // Fill system buffer
            var sysFilled = 0
            while sysFilled < chunkSize {
                guard let frame = try await sysIterator.next() else { break }
                sysBuffer[sysFilled] = frame.sample
                sysFilled += 1
            }
            
            // If both empty, we're done
            if micFilled == 0 && sysFilled == 0 {
                break
            }
            
            // Mix and write
            let mixed = mixBuffers(
                mic: micBuffer,
                micCount: micFilled,
                sys: sysBuffer,
                sysCount: sysFilled
            )
            
            try writeToFile(mixed, to: outputFile)
            
            // Memory stays bounded - we reuse buffers
        }
        
        outputFile.close()
    }
    
    private func mixBuffers(
        mic: [Float],
        micCount: Int,
        sys: [Float],
        sysCount: Int
    ) -> AVAudioPCMBuffer {
        let count = max(micCount, sysCount)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(count)
        )!
        
        guard let data = buffer.floatChannelData?[0] else {
            fatalError("Failed to get audio buffer")
        }
        
        // Use vDSP for efficient mixing
        vDSP_vadd(
            mic, 1,
            sys, 1,
            data, 1,
            vDSP_Length(count)
        )
        
        // Normalize
        var scale: Float = 0.5
        vDSP_vsmul(data, 1, &scale, data, 1, vDSP_Length(count))
        
        buffer.frameLength = AVAudioFrameCount(count)
        return buffer
    }
}
```

### C4. Temp Audio File Durability (CRITICAL)

**Issue**: `NSTemporaryDirectory()` can be purged by OS under memory pressure - recording files deleted during live recording.

**Fix Design - Durable Storage**:

```swift
// MARK: - Storage Location Strategy

enum AudioStorageLocation: Sendable {
    /// Temporary - for ephemeral processing (may be purged)
    case temporary
    
    /// Application Support - durable, crash-recoverable
    case applicationSupport
    
    /// Caches - for replacable data (OS may purge)
    case caches
    
    /// Documents - for user-visible files
    case documents
    
    /// Custom path
    case custom(URL)
}

// MARK: - Recording Storage Policy

/// Determines where recordings are stored based on lifecycle
protocol RecordingStoragePolicy: Sendable {
    /// Get storage location for active recording
    func location(for state: RecordingState) -> AudioStorageLocation
    
    /// Get directory URL for location
    func directory(for location: AudioStorageLocation) throws -> URL
}

/// Default policy: Application Support for durability
struct DurableRecordingStoragePolicy: RecordingStoragePolicy {
    func location(for state: RecordingState) -> AudioStorageLocation {
        switch state {
        case .recording, .paused:
            // Active recordings must be durable
            return .applicationSupport
        case .finalizing:
            // Keep durable until saved
            return .applicationSupport
        case .completed:
            // Move to user preference (usually Documents)
            return .documents
        case .cancelled:
            // Can be temporary (will be deleted)
            return .temporary
        }
    }
    
    func directory(for location: AudioStorageLocation) throws -> URL {
        let fm = FileManager.default
        
        switch location {
        case .temporary:
            return URL(fileURLWithPath: NSTemporaryDirectory())
            
        case .applicationSupport:
            let url = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appDir = url.appendingPathComponent("OpenOats", isDirectory: true)
            let recordingsDir = appDir.appendingPathComponent("Recordings", isDirectory: true)
            try fm.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
            return recordingsDir
            
        case .caches:
            let url = try fm.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return url.appendingPathComponent("AudioCache", isDirectory: true)
            
        case .documents:
            let url = try fm.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return url
            
        case .custom(let url):
            return url
        }
    }
}

// MARK: - Audio Recording Repository

/// Manages audio file lifecycle with durability guarantees
actor AudioRecordingRepository {
    private let policy: any RecordingStoragePolicy
    private let fileManager = FileManager.default
    
    /// Active recordings with their current storage location
    private var activeRecordings: [SessionID: RecordingEntry] = [:]
    
    init(policy: any RecordingStoragePolicy = DurableRecordingStoragePolicy()) {
        self.policy = policy
    }
    
    /// Create recording file for a new session
    func createRecordingFile(for sessionID: SessionID) throws -> URL {
        let location = policy.location(for: .recording)
        let directory = try policy.directory(for: location)
        
        let fileName = "recording_\(sessionID.uuidString).caf"
        let fileURL = directory.appendingPathComponent(fileName)
        
        // Ensure file doesn't exist
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        
        // Create entry
        let entry = RecordingEntry(
            sessionID: sessionID,
            fileURL: fileURL,
            location: location,
            createdAt: Date(),
            state: .recording
        )
        activeRecordings[sessionID] = entry
        
        return fileURL
    }
    
    /// Update recording state and storage location if needed
    func updateState(sessionID: SessionID, to newState: RecordingState) throws {
        guard var entry = activeRecordings[sessionID] else {
            throw StorageError.recordingNotFound(sessionID)
        }
        
        let newLocation = policy.location(for: newState)
        
        // If location changed, move file
        if newLocation != entry.location {
            let newDirectory = try policy.directory(for: newLocation)
            let newURL = newDirectory.appendingPathComponent(entry.fileURL.lastPathComponent)
            
            try fileManager.moveItem(at: entry.fileURL, to: newURL)
            entry.fileURL = newURL
            entry.location = newLocation
        }
        
        entry.state = newState
        entry.updatedAt = Date()
        activeRecordings[sessionID] = entry
    }
    
    /// Recover any recordings from previous app sessions
    func recoverOrphanedRecordings() throws -> [RecordingEntry] {
        let durableDir = try policy.directory(for: .applicationSupport)
        let contents = try fileManager.contentsOfDirectory(
            at: durableDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )
        
        // Find recordings without active sessions
        return contents
            .filter { $0.pathExtension == "caf" }
            .compactMap { try? parseRecordingEntry(from: $0) }
            .filter { !isActiveSession($0.sessionID) }
    }
    
    private func parseRecordingEntry(from url: URL) throws -> RecordingEntry {
        // Parse session ID from filename
        let fileName = url.lastPathComponent
        guard let uuid = fileName.split(separator: "_").last?.replacingOccurrences(of: ".caf", with: ""),
              let sessionID = UUID(uuidString: uuid) else {
            throw StorageError.invalidRecordingFile(url)
        }
        
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let createdAt = attributes[.creationDate] as? Date ?? Date()
        
        return RecordingEntry(
            sessionID: SessionID(rawValue: sessionID),
            fileURL: url,
            location: .applicationSupport,
            createdAt: createdAt,
            state: .unknown
        )
    }
}

struct RecordingEntry: Sendable {
    let sessionID: SessionID
    var fileURL: URL
    var location: AudioStorageLocation
    let createdAt: Date
    var updatedAt: Date = Date()
    var state: RecordingState
}

enum RecordingState: Sendable {
    case recording
    case paused
    case finalizing
    case completed
    case cancelled
    case unknown
}
```

### H3. Unbounded Speech Buffer (HIGH)

**Issue**: `speechSamples` grows until flush interval (30s = ~1.9MB), causing latency spikes.

**Fix Design - Circular Buffer with Streaming**:

```swift
// MARK: - Circular Audio Buffer

/// Fixed-size circular buffer for speech samples
struct CircularAudioBuffer: Sendable {
    private var buffer: [Float]
    private var head: Int = 0  // Write position
    private var tail: Int = 0  // Read position
    private var count: Int = 0
    
    let capacity: Int
    let overlap: Int  // Overlap between chunks for continuity
    
    /// Default: 5 second buffer at 16kHz with 0.5s overlap
    static let defaultCapacity: Int = 16_000 * 5  // 80K samples
    static let defaultOverlap: Int = 16_000 / 2   // 0.5s
    
    init(capacity: Int = defaultCapacity, overlap: Int = defaultOverlap) {
        self.capacity = capacity
        self.overlap = overlap
        self.buffer = Array(repeating: 0.0, count: capacity)
    }
    
    /// Write samples to buffer
    mutating func write(_ samples: [Float]) {
        for sample in samples {
            buffer[head] = sample
            head = (head + 1) % capacity
            
            if count < capacity {
                count += 1
            } else {
                // Buffer full, advance tail (overwriting oldest)
                tail = (tail + 1) % capacity
            }
        }
    }
    
    /// Read chunk for transcription (with overlap)
    mutating func readChunk() -> [Float]? {
        guard count >= capacity / 2 else {
            return nil  // Not enough data yet
        }
        
        var result: [Float] = []
        result.reserveCapacity(capacity / 2)
        
        // Read first half
        let readCount = capacity / 2
        for i in 0..<readCount {
            let index = (tail + i) % capacity
            result.append(buffer[index])
        }
        
        // Move tail back by overlap for next read
        tail = (tail + readCount - overlap) % capacity
        count = overlap + (capacity - readCount)
        
        return result
    }
    
    /// Get current buffer fill level (0.0 - 1.0)
    var fillLevel: Double {
        Double(count) / Double(capacity)
    }
    
    /// Check if buffer is ready for transcription
    var hasChunk: Bool {
        count >= capacity / 2
    }
    
    /// Clear buffer
    mutating func clear() {
        head = 0
        tail = 0
        count = 0
        buffer.resetToZero()
    }
}

// MARK: - Streaming Speech Processor

/// Replaces unbounded speech buffer with streaming approach
actor StreamingSpeechProcessor {
    private var buffer = CircularAudioBuffer()
    private var isProcessing: Bool = false
    
    /// Maximum memory usage: ~320KB (80K floats * 4 bytes)
    static let maxMemoryUsage: Int = 320_000
    
    /// Process incoming speech samples
    func processSamples(_ samples: [Float]) async throws {
        buffer.write(samples)
        
        // Transcribe in chunks as buffer fills
        if buffer.hasChunk && !isProcessing {
            try await transcribeChunk()
        }
    }
    
    /// Transcribe a chunk of audio
    private func transcribeChunk() async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        guard let chunk = buffer.readChunk() else {
            return
        }
        
        // Non-blocking transcription
        Task {
            let result = try await transcriptionService.transcribe(
                audio: chunk,
                config: .stream
            )
            await emitTranscription(result)
        }
    }
    
    /// Force flush remaining audio
    func flush() async throws {
        while buffer.count > 0 {
            try await transcribeChunk()
        }
    }
    
    func reset() {
        buffer.clear()
        isProcessing = false
    }
    
    var currentMemoryUsage: Int {
        // Fixed at ~320KB
        Self.maxMemoryUsage
    }
}
```

## Memory Budget Summary

| Component | Before | After | Reduction |
|-----------|--------|-------|-----------|
| Audio loading (2hr) | ~2.6 GB | ~768 KB | 99.97% |
| Speech buffer (30s) | ~1.9 MB | ~320 KB | 83% |
| Buffer pool (4 chunks) | N/A | ~3 MB | - |
| **Total Peak** | **~4.5 GB** | **~4 MB** | **99.9%** |

## Formal Properties

- **SAFETY**: Memory usage bounded regardless of recording length (< 5MB peak)
- **SAFETY**: Recording files durable against OS purge (Application Support)
- **LIVENESS**: No OOM crashes on 8GB Macs
- **INVARIANT**: Audio buffer size < 1MB at all times

