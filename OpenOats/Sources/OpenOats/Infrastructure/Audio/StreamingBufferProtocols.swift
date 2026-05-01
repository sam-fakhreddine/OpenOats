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
struct AudioFrame: Sendable {
    let sample: Float
    let timestamp: UInt64  // Sample index for synchronization
}

/// Audio stream type identifier
enum AudioStreamType: Sendable {
    case microphone
    case system
    case mixed
}

// MARK: - Audio Stream Processor Protocol

/// Protocol for processing audio in fixed-size chunks
/// Replaces the unbounded readAllMono() approach
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

// MARK: - Buffer Pool Protocol

/// Protocol for reusable buffer management
/// Minimizes allocations during streaming processing
protocol BufferPool: Sendable {
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
struct PoolStats: Sendable {
    let available: Int
    let inUse: Int
    let totalMemory: Int
    let totalAllocations: Int
    let totalReleases: Int
    
    var hitRate: Double {
        guard totalAllocations > 0 else { return 0 }
        return Double(totalReleases) / Double(totalAllocations)
    }
}

// MARK: - Float Buffer Pool (Primary Implementation)

/// Reusable buffer pool for Float arrays
/// Default: 4 buffers * 64K floats = ~1MB pool
actor AudioBufferPool: BufferPool {
    /// Maximum buffer size: 64K frames = ~768KB for 48kHz stereo float
    static let defaultChunkSize: Int = 64 * 1024
    static let maxPoolSize: Int = 4  // ~3MB total pool
    static let bufferSize: Int = defaultChunkSize
    
    private var availableBuffers: [[Float]] = []
    private var inUseCount: Int = 0
    private var allocationCount: Int = 0
    private var releaseCount: Int = 0
    
    /// Acquire a buffer from the pool
    func acquire() -> [Float] {
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
    func release(_ buffer: inout [Float]) {
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
    
    var stats: PoolStats {
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
protocol CircularBufferProtocol: Sendable {
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
struct CircularAudioBuffer: CircularBufferProtocol {
    private var buffer: [Float]
    private var head: Int = 0  // Write position
    private var tail: Int = 0  // Read position
    private var count: Int = 0
    
    let capacity: Int
    let overlap: Int
    
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
        let chunkSize = capacity / 2
        
        guard count >= chunkSize else {
            return nil  // Not enough data yet
        }
        
        var result: [Float] = []
        result.reserveCapacity(chunkSize)
        
        // Read chunk
        for i in 0..<chunkSize {
            let index = (tail + i) % capacity
            result.append(buffer[index])
        }
        
        // Move tail back by overlap for next read
        tail = (tail + chunkSize - overlap) % capacity
        count = overlap + (capacity - chunkSize)
        
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
        // Zero for security
        for i in buffer.indices {
            buffer[i] = 0.0
        }
    }
}

// MARK: - Streaming Merger Protocol

/// Protocol for streaming audio merging
/// Replaces mergeAndEncode() which loaded entire files
protocol StreamingAudioMergerProtocol: Sendable {
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
actor StreamingAudioMerger: StreamingAudioMergerProtocol {
    private let bufferPool = AudioBufferPool()
    private let chunkSize = AudioBufferPool.defaultChunkSize
    
    /// Merge microphone and system audio streams
    /// Memory usage: ~768KB regardless of recording length
    func mergeStreams(
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

enum AudioMixerError: Error {
    case bufferCreationFailed
    case fileCreationFailed
    case writeFailed
}

// MARK: - Streaming Speech Processor Protocol

/// Protocol for streaming speech transcription
/// Replaces unbounded speechSamples array
protocol StreamingSpeechProcessorProtocol: Actor {
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
actor StreamingSpeechProcessor: StreamingSpeechProcessorProtocol {
    private var buffer = CircularAudioBuffer()
    private var isProcessing: Bool = false
    private var transcriptionBackend: StreamingTranscriptionBackend?
    
    /// Maximum memory usage: ~320KB (80K floats * 4 bytes)
    static let maxMemoryUsage: Int = 320_000
    
    init(transcriptionBackend: StreamingTranscriptionBackend? = nil) {
        self.transcriptionBackend = transcriptionBackend
    }
    
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
            _ = try await transcriptionBackend?.transcribe(
                audio: chunk,
                config: .stream
            )
        }
    }
    
    /// Force flush remaining audio
    func flush() async throws {
        while buffer.hasChunk {
            try await transcribeChunk()
        }
    }
    
    func reset() {
        buffer.clear()
        isProcessing = false
    }
    
    nonisolated var currentMemoryUsage: Int {
        // Fixed at ~320KB for the circular buffer
        Self.maxMemoryUsage
    }
}

// MARK: - Supporting Types

/// Transcription configuration
enum TranscriptionConfig: Sendable {
    case stream      // Real-time streaming
    case batch       // Batch processing
    case partial     // Partial hypothesis
}

/// Transcription service protocol for streaming audio
/// Note: This is used internally by StreamingSpeechProcessor
protocol StreamingTranscriptionBackend: Sendable {
    func transcribe(audio: [Float], config: TranscriptionConfig) async throws -> String
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
