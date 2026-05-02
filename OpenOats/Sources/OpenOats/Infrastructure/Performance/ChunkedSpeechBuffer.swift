import Foundation
import Accelerate
import AVFoundation

// MARK: - VDSPChunkedSpeechBuffer
/// Bounded memory buffer for speech audio with 768KB maximum size.
/// Manages audio in fixed-size chunks to prevent memory bloat during
/// long transcription sessions.
///
/// ## Memory Management
/// - Maximum size: 768KB (configurable at initialization)
/// - Chunk size: 64KB (default, configurable)
/// - Automatic chunk recycling when full
/// - Watermark-based preemption for low-latency operation
///
/// ## Performance Characteristics
/// - Write: O(1) amortized (chunk allocation)
/// - Read: O(1) per chunk (vDSP-accelerated when possible)
/// - Memory: Bounded, never exceeds maxSize
/// - SIMD: Uses vDSP for chunk operations
///
/// ## Thread Safety
/// All operations are actor-isolated. The buffer uses a pool of reusable
/// chunks to minimize allocation overhead during streaming.
@available(macOS 15.0, *)
public actor VDSPChunkedSpeechBuffer {
    
    // MARK: - Types
    
    /// Configuration for buffer behavior
    public struct Configuration: Sendable {
        /// Maximum total buffer size in bytes (default: 768KB)
        let maxSizeBytes: Int
        
        /// Chunk size in samples (default: 16384 = 64KB of Float32)
        let chunkSizeSamples: Int
        
        /// Low watermark fraction for preemption (default: 0.75)
        let lowWatermarkFraction: Double
        
        /// High watermark fraction for forced flush (default: 0.90)
        let highWatermarkFraction: Double
        
        public init(
            maxSizeBytes: Int = 768 * 1024,
            chunkSizeSamples: Int = 16384,
            lowWatermarkFraction: Double = 0.75,
            highWatermarkFraction: Double = 0.90
        ) {
            self.maxSizeBytes = maxSizeBytes
            self.chunkSizeSamples = chunkSizeSamples
            self.lowWatermarkFraction = lowWatermarkFraction
            self.highWatermarkFraction = highWatermarkFraction
        }
        
        /// Default configuration (768KB max)
        public static let `default` = Configuration()
        
        /// Conservative configuration (384KB max, smaller chunks)
        public static let conservative = Configuration(
            maxSizeBytes: 384 * 1024,
            chunkSizeSamples: 8192,
            lowWatermarkFraction: 0.70,
            highWatermarkFraction: 0.85
        )
        
        /// Aggressive configuration (1.5MB max, larger chunks)
        public static let aggressive = Configuration(
            maxSizeBytes: 1536 * 1024,
            chunkSizeSamples: 32768,
            lowWatermarkFraction: 0.80,
            highWatermarkFraction: 0.95
        )
        
        /// Maximum number of chunks based on configuration
        var maxChunks: Int {
            let bytesPerChunk = chunkSizeSamples * MemoryLayout<Float>.size
            return max(1, maxSizeBytes / bytesPerChunk)
        }
        
        /// Low watermark sample count
        var lowWatermarkSamples: Int {
            Int(Double(maxChunks * chunkSizeSamples) * lowWatermarkFraction)
        }
        
        /// High watermark sample count
        var highWatermarkSamples: Int {
            Int(Double(maxChunks * chunkSizeSamples) * highWatermarkFraction)
        }
    }
    
    /// Audio chunk container
    private struct Chunk: Sendable {
        var id: UInt64
        var samples: [Float]
        var fillCount: Int
        var timestamp: Double
        var isSealed: Bool
        
        init(id: UInt64, capacity: Int, timestamp: Double = 0) {
            self.id = id
            self.samples = Array(repeating: 0.0, count: capacity)
            self.fillCount = 0
            self.timestamp = timestamp
            self.isSealed = false
        }
        
        mutating func write(_ newSamples: [Float]) -> Int {
            let spaceRemaining = samples.count - fillCount
            let toWrite = min(newSamples.count, spaceRemaining)
            
            guard toWrite > 0 else { return 0 }
            
            // vDSP copy for speed
            newSamples.withUnsafeBufferPointer { src in
                samples.withUnsafeMutableBufferPointer { dest in
                    vDSP_mmov(
                        src.baseAddress!,
                        dest.baseAddress! + fillCount,
                        vDSP_Length(toWrite),
                        1,
                        1,
                        1
                    )
                }
            }
            
            fillCount += toWrite
            
            if fillCount >= samples.count {
                isSealed = true
            }
            
            return toWrite
        }
        
        mutating func clear() {
            fillCount = 0
            isSealed = false
            timestamp = 0
            // Zero for security
            vDSP_vclr(&samples, 1, vDSP_Length(samples.count))
        }
    }
    
    /// Buffer state
    private enum State: Sendable {
        case normal
        case nearFull
        case full
    }
    
    // MARK: - Properties
    
    /// Buffer configuration
    public let configuration: Configuration
    
    /// Active chunks containing data
    private var activeChunks: [Chunk] = []
    
    /// Pool of reusable chunks
    private var chunkPool: [Chunk] = []
    
    /// Total samples currently buffered
    private var totalSampleCount: Int = 0
    
    /// Chunk ID counter
    private var nextChunkID: UInt64 = 1
    
    /// Current state
    private var state: State = .normal
    
    /// Timestamp offset for chunk timing
    private var baseTimestamp: Double = 0
    
    /// Total samples ever written
    private var lifetimeWriteCount: Int64 = 0
    
    /// Total samples ever read
    private var lifetimeReadCount: Int64 = 0
    
    /// Preemption callbacks
    private var preemptionHandlers: [@Sendable () async -> Void] = []
    
    /// Lock for nonisolated reads
    private let statsLock = NSLock()
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    public init() {
        self.init(configuration: .default)
    }
    
    // MARK: - Write Operations
    
    /// Write samples to buffer
    ///
    /// Writes samples into chunks, automatically creating new chunks as needed.
    /// When buffer reaches capacity, oldest chunks are recycled (FIFO).
    ///
    /// - Parameter samples: Float samples to write
    /// - Returns: Number of samples actually written
    @discardableResult
    public func write(_ samples: [Float]) async -> Int {
        var samplesRemaining = samples
        var totalWritten = 0
        
        // Fill current chunk if available
        if var currentChunk = activeChunks.last, !currentChunk.isSealed {
            let written = currentChunk.write(samplesRemaining)
            totalSampleCount += written
            totalWritten += written
            lifetimeWriteCount += Int64(written)
            
            if written > 0 {
                activeChunks[activeChunks.count - 1] = currentChunk
                samplesRemaining = samplesRemaining[written...]
            }
        }
        
        // Create new chunks as needed
        while !samplesRemaining.isEmpty {
            // Check if we need to recycle
            if activeChunks.count >= configuration.maxChunks {
                await recycleOldestChunk()
            }
            
            // Get or create chunk
            var newChunk = await acquireChunk()
            let timestamp = baseTimestamp + Double(totalSampleCount) / 16000.0  // Assume 16kHz
            newChunk.timestamp = timestamp
            
            let written = newChunk.write(samplesRemaining)
            totalSampleCount += written
            totalWritten += written
            lifetimeWriteCount += Int64(written)
            
            if written > 0 {
                activeChunks.append(newChunk)
                samplesRemaining = samplesRemaining[written...]
            } else {
                // Shouldn't happen, but break to avoid infinite loop
                break
            }
        }
        
        // Update state and check watermarks
        await updateState()
        
        return totalWritten
    }
    
    /// Write samples with automatic gain control
    ///
    /// Writes samples after normalizing to target RMS level.
    ///
    /// - Parameters:
    ///   - samples: Float samples to write
    ///   - targetRMS: Target RMS level (default: 0.3)
    /// - Returns: Number of samples actually written
    @discardableResult
    public func writeWithAGC(_ samples: [Float], targetRMS: Float = 0.3) async -> Int {
        guard !samples.isEmpty else { return 0 }
        
        // Calculate current RMS using vDSP
        var meanSquare: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            vDSP_measqv(ptr.baseAddress!, 1, &meanSquare, vDSP_Length(samples.count))
        }
        let currentRMS = sqrt(meanSquare)
        
        // Apply gain if needed
        if currentRMS > 0.001 {
            let gain = targetRMS / currentRMS
            var scaled = samples
            var g = gain
            scaled.withUnsafeMutableBufferPointer { ptr in
                vDSP_vsmul(ptr.baseAddress!, 1, &g, ptr.baseAddress!, 1, vDSP_Length(samples.count))
            }
            return await write(scaled)
        }
        
        return await write(samples)
    }
    
    // MARK: - Read Operations
    
    /// Read samples from buffer (FIFO order)
    ///
    /// Reads samples from oldest chunks first. Chunks are automatically
    /// returned to the pool when fully consumed.
    ///
    /// - Parameter count: Number of samples to read
    /// - Returns: Array of Float samples
    public func read(count: Int) -> [Float] {
        var result: [Float] = []
        var remaining = count
        
        while remaining > 0, !activeChunks.isEmpty {
            var chunk = activeChunks[0]
            let available = chunk.fillCount
            let toRead = min(remaining, available)
            
            guard toRead > 0 else { break }
            
            // Extract samples using vDSP
            let chunkSamples = Array(chunk.samples[0..<toRead])
            result.append(contentsOf: chunkSamples)
            
            // Remove consumed samples by shifting remaining
            if toRead < chunk.fillCount {
                let remainingInChunk = chunk.fillCount - toRead
                chunk.samples.withUnsafeMutableBufferPointer { buf in
                    vDSP_mmov(
                        buf.baseAddress! + toRead,
                        buf.baseAddress!,
                        vDSP_Length(remainingInChunk),
                        1,
                        1,
                        1
                    )
                }
                chunk.fillCount = remainingInChunk
                activeChunks[0] = chunk
            } else {
                // Chunk fully consumed - return to pool
                returnChunkToPool(chunk)
                activeChunks.removeFirst()
            }
            
            totalSampleCount -= toRead
            remaining -= toRead
            lifetimeReadCount += Int64(toRead)
        }
        
        // Update state
        Task {
            await updateState()
        }
        
        return result
    }
    
    /// Peek at samples without removing
    ///
    /// - Parameter count: Number of samples to peek at
    /// - Returns: Array of Float samples (copy)
    public func peek(count: Int) -> [Float] {
        var result: [Float] = []
        var remaining = count
        
        for chunk in activeChunks {
            let available = chunk.fillCount
            let toRead = min(remaining, available)
            
            guard toRead > 0 else { continue }
            
            let chunkSamples = Array(chunk.samples[0..<toRead])
            result.append(contentsOf: chunkSamples)
            
            remaining -= toRead
            if remaining <= 0 { break }
        }
        
        return result
    }
    
    /// Get all buffered samples as contiguous array
    public func allSamples() -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(totalSampleCount)
        
        for chunk in activeChunks {
            result.append(contentsOf: chunk.samples[0..<chunk.fillCount])
        }
        
        return result
    }
    
    // MARK: - vDSP Operations
    
    /// Calculate RMS energy of all buffered samples
    public func calculateEnergy() -> Float {
        guard totalSampleCount > 0 else { return 0 }
        
        var sumSquares: Float = 0
        var totalCount: vDSP_Length = 0
        
        for chunk in activeChunks {
            let count = chunk.fillCount
            guard count > 0 else { continue }
            
            var chunkMeanSquare: Float = 0
            chunk.samples.withUnsafeBufferPointer { ptr in
                vDSP_measqv(ptr.baseAddress!, 1, &chunkMeanSquare, vDSP_Length(count))
            }
            
            // Weighted sum (approximate for multi-chunk)
            sumSquares += chunkMeanSquare * Float(count)
            totalCount += vDSP_Length(count)
        }
        
        guard totalCount > 0 else { return 0 }
        let overallMeanSquare = sumSquares / Float(totalCount)
        return sqrt(overallMeanSquare)
    }
    
    /// Apply gain to all buffered samples
    public func applyGain(_ gain: Float) {
        var g = gain
        
        for i in activeChunks.indices {
            activeChunks[i].samples.withUnsafeMutableBufferPointer { ptr in
                vDSP_vsmul(
                    ptr.baseAddress!,
                    1,
                    &g,
                    ptr.baseAddress!,
                    1,
                    vDSP_Length(activeChunks[i].fillCount)
                )
            }
        }
    }
    
    /// Normalize all samples to target RMS
    public func normalize(targetRMS: Float = 0.3) {
        let currentRMS = calculateEnergy()
        guard currentRMS > 0.001 else { return }
        
        let gain = targetRMS / currentRMS
        applyGain(gain)
    }
    
    // MARK: - Chunk Management
    
    /// Acquire a chunk from pool or create new
    private func acquireChunk() -> Chunk {
        if let pooled = chunkPool.popLast() {
            var chunk = pooled
            chunk.clear()
            chunk.id = nextChunkID
            nextChunkID += 1
            return chunk
        }
        
        return Chunk(
            id: nextChunkID,
            capacity: configuration.chunkSizeSamples
        )
    }
    
    /// Return chunk to pool
    private func returnChunkToPool(_ chunk: Chunk) {
        var reusable = chunk
        reusable.clear()
        
        // Limit pool size to prevent memory growth
        if chunkPool.count < configuration.maxChunks {
            chunkPool.append(reusable)
        }
    }
    
    /// Recycle oldest chunk when buffer is full
    private func recycleOldestChunk() async {
        guard !activeChunks.isEmpty else { return }
        
        let oldest = activeChunks.removeFirst()
        totalSampleCount -= oldest.fillCount
        returnChunkToPool(oldest)
        
        // Notify preemption handlers
        for handler in preemptionHandlers {
            await handler()
        }
    }
    
    // MARK: - State Management
    
    /// Update buffer state based on fill level
    private func updateState() {
        let fillFraction = Double(totalSampleCount) / Double(configuration.highWatermarkSamples)
        
        if fillFraction >= 1.0 {
            state = .full
        } else if fillFraction >= configuration.lowWatermarkFraction {
            state = .nearFull
        } else {
            state = .normal
        }
    }
    
    /// Register a preemption handler
    public func onPreempt(_ handler: @escaping @Sendable () async -> Void) {
        preemptionHandlers.append(handler)
    }
    
    // MARK: - Utility Operations
    
    /// Clear all samples and return chunks to pool
    public func clear() {
        for chunk in activeChunks {
            returnChunkToPool(chunk)
        }
        activeChunks.removeAll()
        totalSampleCount = 0
        state = .normal
    }
    
    /// Get current fill fraction
    public func fillFraction() -> Double {
        let maxSamples = configuration.maxChunks * configuration.chunkSizeSamples
        return Double(totalSampleCount) / Double(maxSamples)
    }
    
    /// Check if buffer is empty
    public var isEmpty: Bool { totalSampleCount == 0 }
    
    /// Check if buffer is at or above high watermark
    public var isNearFull: Bool {
        state == .nearFull || state == .full
    }
    
    /// Estimated duration at given sample rate
    public func duration(sampleRate: Double = 16000.0) -> Double {
        Double(totalSampleCount) / sampleRate
    }
    
    // MARK: - Statistics
    
    /// Buffer statistics
    public struct Statistics: Sendable {
        public let totalSamples: Int
        public let activeChunks: Int
        public let pooledChunks: Int
        public let fillFraction: Double
        public let state: String
        public let lifetimeWrites: Int64
        public let lifetimeReads: Int64
        public let estimatedDuration: Double
    }
    
    /// Get current statistics
    public func getStatistics(sampleRate: Double = 16000.0) -> Statistics {
        Statistics(
            totalSamples: totalSampleCount,
            activeChunks: activeChunks.count,
            pooledChunks: chunkPool.count,
            fillFraction: fillFraction(),
            state: String(describing: state),
            lifetimeWrites: lifetimeWriteCount,
            lifetimeReads: lifetimeReadCount,
            estimatedDuration: duration(sampleRate: sampleRate)
        )
    }
    
    /// Memory usage in bytes
    public func memoryUsage() -> Int {
        let chunkBytes = configuration.chunkSizeSamples * MemoryLayout<Float>.size
        let activeMemory = activeChunks.count * chunkBytes
        let poolMemory = chunkPool.count * chunkBytes
        return activeMemory + poolMemory
    }
}

// MARK: - Convenience Extensions

@available(macOS 15.0, *)
extension VDSPChunkedSpeechBuffer {
    
    /// Write samples from AVAudioPCMBuffer
    public func write(pcmBuffer: AVAudioPCMBuffer) async {
        guard let channelData = pcmBuffer.floatChannelData,
              pcmBuffer.frameLength > 0 else { return }

        let frameLength = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)

        if channelCount == 1 {
            // Mono - direct copy
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            _ = await self.write(samples)
        } else {
            // Multi-channel - mix down using vDSP
            var mixed = Array(repeating: Float(0), count: frameLength)

            for ch in 0..<channelCount {
                let channelPtr = channelData[ch]
                if ch == 0 {
                    // First channel - copy
                    vDSP_mmov(channelPtr, &mixed, vDSP_Length(frameLength), 1, 1, 1)
                } else {
                    // Add to mix
                    mixed.withUnsafeMutableBufferPointer { dest in
                        vDSP_vadd(dest.baseAddress!, 1, channelPtr, 1, dest.baseAddress!, 1, vDSP_Length(frameLength))
                    }
                }
            }

            // Scale by 1/channelCount
            var scale = 1.0 / Float(channelCount)
            mixed.withUnsafeMutableBufferPointer { ptr in
                vDSP_vsmul(ptr.baseAddress!, 1, &scale, ptr.baseAddress!, 1, vDSP_Length(frameLength))
            }

            _ = await self.write(mixed)
        }
    }

    /// Append contents of another buffer
    public func appendContentsOf(_ other: VDSPChunkedSpeechBuffer) async {
        let otherSamples = await other.allSamples()
        _ = await self.write(otherSamples)
    }
}

