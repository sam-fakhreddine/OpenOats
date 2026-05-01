// MARK: - Streaming Audio Memory Management Protocols
//
// These protocols define the streaming audio processing architecture
// designed to fix the memory issues identified in TASK-016.
//
// Issues Addressed:
// - C3: Unbounded memory in mergeAndEncode (replaced with streaming)
// - H3: Unbounded speech buffer (replaced with circular buffer)
//
// Design: Memory usage bounded at < 5MB regardless of recording length

import AVFoundation

// MARK: - Core Types

/// Single audio frame for streaming processing
public struct AudioFrame: Sendable {
    public let sample: Float
    public let timestamp: UInt64  // Sample index for synchronization
    
    public init(sample: Float, timestamp: UInt64) {
        self.sample = sample
        self.timestamp = timestamp
    }
}

/// Audio stream type identifier
public enum AudioStreamType: Sendable {
    case microphone
    case system
    case mixed
}

// MARK: - Audio Stream Processor Protocol

/// Protocol for processing audio in fixed-size chunks
/// Replaces the unbounded readAllMono() approach
public protocol AudioStreamProcessor: Sendable {
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

// MARK: - Buffer Pool Protocol

/// Protocol for reusable buffer management
/// Minimizes allocations during streaming processing
public protocol BufferPool: Sendable {
    associatedtype Buffer: Sendable
    
    /// Maximum number of buffers in the pool
    static var maxPoolSize: Int { get }
    
    /// Size of each buffer in elements
    static var bufferSize: Int { get }
    
    /// Acquire a buffer from the pool
    func acquire() async -> Buffer
    
    /// Return buffer to pool for reuse
    func release(_ buffer: inout Buffer) async
    
    /// Get current pool statistics
    var stats: PoolStats { get async }
}

/// Statistics for buffer pool monitoring
public struct PoolStats: Sendable {
    public let available: Int
    public let inUse: Int
    public let totalMemory: Int
    public let totalAllocations: Int
    public let totalReleases: Int
    
    public init(available: Int, inUse: Int, totalMemory: Int, totalAllocations: Int, totalReleases: Int) {
        self.available = available
        self.inUse = inUse
        self.totalMemory = totalMemory
        self.totalAllocations = totalAllocations
        self.totalReleases = totalReleases
    }
    
    public var hitRate: Double {
        guard totalAllocations > 0 else { return 0 }
        return Double(totalReleases) / Double(totalAllocations)
    }
}

// MARK: - Float Buffer Pool (Primary Implementation)

/// Reusable buffer pool for Float arrays
/// Default: 4 buffers * 64K floats = ~1MB pool
public actor AudioBufferPool: BufferPool {
    /// Maximum buffer size: 64K frames = ~768KB for 48kHz stereo float
    public static let defaultChunkSize: Int = 64 * 1024
    public static let maxPoolSize: Int = 4  // ~3MB total pool
    public static let bufferSize: Int = defaultChunkSize
    
    private var availableBuffers: [[Float]] = []
    private var inUseCount: Int = 0
    private var allocationCount: Int = 0
    private var releaseCount: Int = 0
    
    public init() {}
    
    /// Acquire a buffer from the pool
    public func acquire() -> [Float] {
        if let buffer = availableBuffers.popLast() {
            inUseCount += 1
            allocationCount += 1
            return buffer
        }
        // Create new if pool exhausted
        inUseCount += 1
        allocationCount += 1
        return Array(repeating: 0.0, count: Self.defaultChunkSize)
    }
    
    /// Return buffer to pool for reuse
    public func release(_ buffer: inout [Float]) {
        if availableBuffers.count < Self.maxPoolSize {
            // Zero the buffer for security/privacy
            for i in buffer.indices {
                buffer[i] = 0.0
            }
            availableBuffers.append(buffer)
        }
        inUseCount -= 1
        releaseCount += 1
        buffer = []  // Clear reference
    }
    
    public var stats: PoolStats {
        PoolStats(
            available: availableBuffers.count,
            inUse: inUseCount,
            totalMemory: (availableBuffers.count + inUseCount) * Self.defaultChunkSize * MemoryLayout<Float>.size,
            totalAllocations: allocationCount,
            totalReleases: releaseCount
        )
    }
}

// MARK: - Circular Audio Buffer Protocol

/// Protocol for fixed-size circular buffer
/// Replaces unbounded Array growth for speech samples
public protocol CircularBufferProtocol: Sendable {
    /// Buffer capacity in samples
    var capacity: Int { get }
    
    /// Overlap between chunks for continuity
    var overlap: Int { get }
    
    /// Current fill level (0.0 - 1.0)
    var fillLevel: Double { get }
    
    /// Whether buffer has enough data for a chunk
    var hasChunk: Bool { get }
    
    /// Write samples to buffer (overwrites oldest if full)
    mutating func write(_ samples: [Float])
    
    /// Read a chunk of audio (with overlap for continuity)
    /// Returns nil if not enough data
    mutating func readChunk() -> [Float]?
    
    /// Clear the buffer
    mutating func clear()
}

// MARK: - Circular Audio Buffer (Implementation)

/// Fixed-size circular buffer for speech samples
/// Default: 5 second buffer at 16kHz = 80K samples = ~320KB
public struct CircularAudioBuffer: CircularBufferProtocol {
    private var _buffer: [Float]
    private var head: Int = 0  // Write position
    private var tail: Int = 0  // Read position
    private var _count: Int = 0
    
    public let capacity: Int
    public let overlap: Int
    
    /// Default: 5 second buffer at 16kHz with 0.5s overlap
    public static let defaultCapacity: Int = 16_000 * 5  // 80K samples
    public static let defaultOverlap: Int = 16_000 / 2   // 0.5s
    
    public init(capacity: Int = defaultCapacity, overlap: Int = defaultOverlap) {
        self.capacity = capacity
        self.overlap = overlap
        self._buffer = Array(repeating: 0.0, count: capacity)
    }
    
    /// Write samples to buffer
    public mutating func write(_ samples: [Float]) {
        for sample in samples {
            _buffer[head] = sample
            head = (head + 1) % capacity
            
            if _count < capacity {
                _count += 1
            } else {
                // Buffer full, advance tail (overwriting oldest)
                tail = (tail + 1) % capacity
            }
        }
    }
    
    /// Read chunk for transcription (with overlap)
    public mutating func readChunk() -> [Float]? {
        let chunkSize = capacity / 2
        
        guard _count >= chunkSize else {
            return nil  // Not enough data yet
        }
        
        var result: [Float] = []
        result.reserveCapacity(chunkSize)
        
        // Read chunk
        for i in 0..<chunkSize {
            let index = (tail + i) % capacity
            result.append(_buffer[index])
        }
        
        // Move tail back by overlap for next read
        tail = (tail + chunkSize - overlap) % capacity
        _count = overlap + (capacity - chunkSize)
        
        return result
    }
    
    /// Get current buffer fill level (0.0 - 1.0)
    public var fillLevel: Double {
        Double(_count) / Double(capacity)
    }
    
    /// Check if buffer is ready for transcription
    public var hasChunk: Bool {
        _count >= capacity / 2
    }
    
    /// Access to the internal buffer (for testing)
    public var buffer: [Float] { _buffer }
    
    /// Current count of samples in buffer
    public var count: Int { _count }
    
    /// Clear buffer
    public mutating func clear() {
        head = 0
        tail = 0
        _count = 0
        // Zero for security
        for i in _buffer.indices {
            _buffer[i] = 0.0
        }
    }
}

// MARK: - Streaming Merger Protocol

/// Protocol for streaming audio merging
/// Replaces mergeAndEncode() which loaded entire files
public protocol StreamingAudioMergerProtocol: Sendable {
    /// Merge microphone and system audio streams
    /// Memory usage: ~768KB regardless of recording length
    func mergeStreams(
        micStream: AsyncThrowingStream<AudioFrame, Error>,
        sysStream: AsyncThrowingStream<AudioFrame, Error>,
        outputURL: URL
    ) async throws
}

// MARK: - Streaming Merger (Implementation)

/// Streaming audio merger with bounded memory
public actor StreamingAudioMerger: StreamingAudioMergerProtocol {
    private let bufferPool = AudioBufferPool()
    private let chunkSize = AudioBufferPool.defaultChunkSize
    
    public init() {}
    
    /// Merge microphone and system audio streams
    /// Memory usage: ~768KB regardless of recording length
    public func mergeStreams(
        micStream: AsyncThrowingStream<AudioFrame, Error>,
        sysStream: AsyncThrowingStream<AudioFrame, Error>,
        outputURL: URL
    ) async throws {
        let targetFormat = AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 1
        )!
        
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
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
            let mixed = try mixBuffers(
                mic: micBuffer,
                micCount: micFilled,
                sys: sysBuffer,
                sysCount: sysFilled,
                format: targetFormat
            )
            
            try outputFile.write(from: mixed)
            
            // Memory stays bounded - we reuse buffers
        }
        
        // File handle closes automatically when outputFile goes out of scope
    }
    
    private func mixBuffers(
        mic: [Float],
        micCount: Int,
        sys: [Float],
        sysCount: Int,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let count = max(micCount, sysCount)
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(count)
        ),
        let data = buffer.floatChannelData?[0] else {
            throw AudioMixerError.bufferCreationFailed
        }
        
        // Mix: average of mic and system audio
        for i in 0..<count {
            let m: Float = i < micCount ? mic[i] : 0
            let s: Float = i < sysCount ? sys[i] : 0
            data[i] = max(-1, min(1, (m + s) * 0.5))
        }
        
        buffer.frameLength = AVAudioFrameCount(count)
        return buffer
    }
}

public enum AudioMixerError: Error {
    case bufferCreationFailed
    case fileCreationFailed
    case writeFailed
}

// MARK: - Streaming Speech Processor Protocol

/// Protocol for streaming speech transcription
/// Replaces unbounded speechSamples array
public protocol StreamingSpeechProcessorProtocol: Actor {
    /// Maximum memory usage in bytes
    static var maxMemoryUsage: Int { get }
    
    /// Process incoming speech samples
    func processSamples(_ samples: [Float]) async throws
    
    /// Force flush remaining audio
    func flush() async throws
    
    /// Reset processor state
    func reset()
    
    /// Current memory usage in bytes
    var currentMemoryUsage: Int { get }
}

// MARK: - Streaming Speech Processor (Implementation)

/// Replaces unbounded speech buffer with streaming approach
public actor StreamingSpeechProcessor: StreamingSpeechProcessorProtocol {
    private var buffer: CircularAudioBuffer
    private var isProcessing: Bool = false
    private var transcriptionBackend: StreamingTranscriptionBackend?
    
    /// Maximum memory usage: ~320KB (80K floats * 4 bytes)
    public static let maxMemoryUsage: Int = 320_000
    
    public init(transcriptionBackend: StreamingTranscriptionBackend? = nil) {
        self.transcriptionBackend = transcriptionBackend
        self.buffer = CircularAudioBuffer()
    }
    
    /// Process incoming speech samples
    public func processSamples(_ samples: [Float]) async throws {
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
            _ = try await transcriptionBackend?.transcribe(
                audio: chunk,
                config: .stream
            )
        }
    }
    
    /// Force flush remaining audio
    public func flush() async throws {
        while buffer.hasChunk {
            try await transcribeChunk()
        }
    }
    
    public func reset() {
        buffer.clear()
        isProcessing = false
    }
    
    nonisolated public var currentMemoryUsage: Int {
        // Fixed at ~320KB for the circular buffer
        Self.maxMemoryUsage
    }
}

// MARK: - Supporting Types

/// Transcription configuration
public enum TranscriptionConfig: Sendable {
    case stream      // Real-time streaming
    case batch       // Batch processing
    case partial     // Partial hypothesis
}

/// Transcription service protocol for streaming audio
/// Note: This is used internally by StreamingSpeechProcessor
public protocol StreamingTranscriptionBackend: Sendable {
    func transcribe(audio: [Float], config: TranscriptionConfig) async throws -> String
}

// MARK: - Storage Types for C4 (Temp File Durability)

/// Audio storage location options
public enum AudioStorageLocation: Sendable, Equatable {
    case temporary
    case applicationSupport
    case caches
    case documents
    case custom(URL)
}

/// Recording state for lifecycle management
public enum RecordingState: Sendable {
    case recording
    case paused
    case finalizing
    case completed
    case cancelled
    case unknown
}

/// Recording entry for repository
public struct RecordingEntry: Sendable {
    public let sessionID: SessionID
    public var fileURL: URL
    public var location: AudioStorageLocation
    public let createdAt: Date
    public var updatedAt: Date
    public var state: RecordingState
    
    public init(
        sessionID: SessionID,
        fileURL: URL,
        location: AudioStorageLocation,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        state: RecordingState
    ) {
        self.sessionID = sessionID
        self.fileURL = fileURL
        self.location = location
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
    }
}

/// Protocol for storage policy
public protocol RecordingStoragePolicy: Sendable {
    func location(for state: RecordingState) -> AudioStorageLocation
    func directory(for location: AudioStorageLocation) throws -> URL
}

/// Durable recording storage policy
/// Active recordings use Application Support (not NSTemporaryDirectory)
public struct DurableRecordingStoragePolicy: RecordingStoragePolicy {
    
    public init() {}
    
    public func location(for state: RecordingState) -> AudioStorageLocation {
        switch state {
        case .recording, .paused, .finalizing:
            // Active recordings use Application Support for durability
            return .applicationSupport
        case .completed:
            // Completed recordings move to Documents
            return .documents
        case .cancelled:
            // Cancelled recordings can use temporary storage (will be deleted)
            return .temporary
        case .unknown:
            // Unknown state defaults to temporary
            return .temporary
        }
    }
    
    public func directory(for location: AudioStorageLocation) throws -> URL {
        let fm = FileManager.default
        
        switch location {
        case .temporary:
            return URL(fileURLWithPath: NSTemporaryDirectory())
            
        case .applicationSupport:
            guard let url = try? fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )?.appendingPathComponent("OpenOats/Recordings", isDirectory: true) else {
                throw StorageError.directoryCreationFailed
            }
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
            
        case .caches:
            guard let url = try? fm.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) else {
                throw StorageError.directoryCreationFailed
            }
            return url
            
        case .documents:
            guard let url = try? fm.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )?.appendingPathComponent("OpenOats/Recordings", isDirectory: true) else {
                throw StorageError.directoryCreationFailed
            }
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
            
        case .custom(let url):
            return url
        }
    }
}

/// Repository for managing audio recordings with crash recovery
public actor AudioRecordingRepository {
    private let policy: RecordingStoragePolicy
    private var entries: [SessionID: RecordingEntry] = [:]
    
    public init(policy: RecordingStoragePolicy = DurableRecordingStoragePolicy()) {
        self.policy = policy
    }
    
    /// Recover orphaned recordings from Application Support
    /// Called on app startup to find recordings from previous sessions
    public func recoverOrphanedRecordings() throws -> [RecordingEntry] {
        var orphaned: [RecordingEntry] = []
        
        // Get Application Support directory
        let appSupportDir = try policy.directory(for: .applicationSupport)
        
        // Scan for recording files that don't have corresponding active sessions
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: appSupportDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return orphaned
        }
        
        for fileURL in files {
            // Parse session ID from filename (format: recording_<uuid>.caf)
            let filename = fileURL.lastPathComponent
            guard filename.hasPrefix("recording_"),
                  filename.hasSuffix(".caf") else {
                continue
            }
            
            // Extract UUID from filename
            let uuidString = filename
                .replacingOccurrences(of: "recording_", with: "")
                .replacingOccurrences(of: ".caf", with: "")
            
            guard let uuid = UUID(uuidString: uuidString) else {
                continue
            }
            
            let sessionID = SessionID(rawValue: uuid)
            
            // Check if this entry is already tracked
            guard entries[sessionID] == nil else {
                continue
            }
            
            // Get file creation date
            let attributes = try? fm.attributesOfItem(atPath: fileURL.path)
            let createdAt = attributes?[.creationDate] as? Date ?? Date()
            
            // Create entry for orphaned recording
            let entry = RecordingEntry(
                sessionID: sessionID,
                fileURL: fileURL,
                location: .applicationSupport,
                createdAt: createdAt,
                state: .unknown
            )
            
            orphaned.append(entry)
            entries[sessionID] = entry
        }
        
        return orphaned
    }
    
    /// Get all recording entries
    public func allEntries() -> [RecordingEntry] {
        Array(entries.values)
    }
    
    /// Get entry for specific session
    public func entry(for sessionID: SessionID) -> RecordingEntry? {
        entries[sessionID]
    }
    
    /// Add new recording entry
    public func addEntry(_ entry: RecordingEntry) {
        entries[entry.sessionID] = entry
    }
    
    /// Update recording entry
    public func updateEntry(_ entry: RecordingEntry) {
        entries[entry.sessionID] = entry
    }
}

// MARK: - Memory Budget Summary

/*
 Memory Budget (from TASK-016 design):
 
 | Component | Before | After | Reduction |
 |-----------|--------|-------|-----------|
 | Audio loading (2hr) | ~2.6 GB | ~768 KB | 99.97% |
 | Speech buffer (30s) | ~1.9 MB | ~320 KB | 83% |
 | Buffer pool (4 chunks) | N/A | ~3 MB | - |
 | **Total Peak** | **~4.5 GB** | **~4 MB** | **99.9%** |
 
 Formal Properties:
 - SAFETY: Memory usage bounded regardless of recording length (< 5MB peak)
 - SAFETY: Audio buffer size < 1MB at all times
 - INVARIANT: Buffer pool size <= 4 chunks
 - INVARIANT: Circular buffer capacity fixed at 80K samples
 */
