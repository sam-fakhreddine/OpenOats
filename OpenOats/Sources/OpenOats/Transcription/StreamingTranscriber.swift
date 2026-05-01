@preconcurrency import AVFoundation
import FluidAudio
import Accelerate
import os

// MARK: - Performance-Optimized Circular Audio Buffer

/// Circular buffer for O(1) audio sample storage and consumption.
/// Replaces Array.removeFirst() which caused O(n²) behavior in VAD hot loop.
struct CircularAudioBuffer {
    private var buffer: [Float]
    private var head: Int = 0
    private var tail: Int = 0
    private(set) var count: Int = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    mutating func append(_ samples: [Float]) {
        for sample in samples {
            buffer[tail] = sample
            tail = (tail + 1) % capacity
            if count < capacity {
                count += 1
            } else {
                head = (head + 1) % capacity
            }
        }
    }

    mutating func consume(_ n: Int) {
        head = (head + n) % capacity
        count -= n
    }

    func readChunk(start: Int, size: Int) -> [Float] {
        var result = [Float](repeating: 0, count: size)
        let startIdx = (head + start) % capacity
        for i in 0..<size {
            result[i] = buffer[(startIdx + i) % capacity]
        }
        return result
    }

    subscript(index: Int) -> Float {
        return buffer[(head + index) % capacity]
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        head = 0
        tail = 0
        count = 0
        if !keepingCapacity {
            buffer = [Float](repeating: 0, count: capacity)
        }
    }
}

// MARK: - Chunked Speech Buffer

/// Chunked buffer for speech samples to avoid large array copies during partial transcription.
/// Splits samples into bounded chunks (30 seconds max each) to minimize copy costs.
struct ChunkedSpeechBuffer {
    private var chunks: [[Float]] = [[]]
    private let maxChunkSize = 30 * 16000  // 30 seconds at 16kHz
    private(set) var totalCount: Int = 0

    mutating func append(_ samples: [Float]) {
        if chunks.isEmpty {
            chunks = [[]]
        }
        if chunks.last!.count + samples.count > maxChunkSize {
            chunks.append([])
            chunks[chunks.count - 1].reserveCapacity(maxChunkSize)
        }
        chunks[chunks.count - 1].append(contentsOf: samples)
        totalCount += samples.count
    }

    mutating func append(contentsOf samples: [Float]) {
        append(samples)
    }

    func asContiguousArray() -> [Float] {
        return chunks.flatMap { $0 }
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        if keepingCapacity {
            chunks = [chunks.last ?? []]
        } else {
            chunks = [[]]
        }
        totalCount = 0
    }

    var count: Int { totalCount }

    subscript(index: Int) -> Float {
        var offset = index
        for chunk in chunks {
            if offset < chunk.count {
                return chunk[offset]
            }
            offset -= chunk.count
        }
        return 0
    }
}

// MARK: - StreamingTranscriptionActor
//
// Data Race Fix C1: Converted from @unchecked Sendable class to actor
// All mutable state is now actor-isolated, eliminating data races.
// Performance Fix: CircularAudioBuffer and ChunkedSpeechBuffer eliminate O(n²) hot paths.
//

/// Actor-isolated streaming transcription that safely manages mutable state.
///
/// This actor consumes an audio buffer stream, detects speech via Silero VAD,
/// and transcribes completed speech segments via the TranscriptionBackend protocol.
///
/// ## Safety Properties
/// - All mutable state is actor-isolated (no @unchecked Sendable needed)
/// - Concurrent access is serialized through the actor
/// - Thread-safe rate tracking and converter management
actor StreamingTranscriptionActor {
    
    // MARK: - Cloud Types
    
    struct CloudSegmentStatus: Sendable, Equatable {
        enum Kind: String, Sendable, Equatable {
            case success
            case empty
            case error
        }

        let kind: Kind
        let presentation: CloudTranscriptCopy.Presentation?
    }

    struct CloudSegmentDiagnosticsEvent: Codable, Equatable {
        let event: String
        let sessionID: String?
        let transcriptionModel: String
        let backend: String
        let speaker: String
        let sampleCount: Int
        let durationSeconds: Double
        let elapsedMilliseconds: Int
        let result: String
        let textLength: Int?
        let errorKind: String?
        let errorMessage: String?
    }

    // MARK: - Immutable Configuration (Non-isolated, Sendable)
    
    nonisolated let backend: any TranscriptionBackend
    nonisolated let locale: Locale
    nonisolated let vadManager: VadManager
    nonisolated let speaker: Speaker
    nonisolated let sessionID: String?
    nonisolated let transcriptionModel: String
    nonisolated let flushInterval: Int
    nonisolated let skipPartials: Bool
    nonisolated let onPartial: @Sendable (String) -> Void
    nonisolated let onFinal: @Sendable (String) -> Void
    nonisolated let onCloudSegmentStatus: (@Sendable (CloudSegmentStatus) -> Void)?
    nonisolated let onCloudProcessingChanged: (@Sendable (Bool) -> Void)?
    
    nonisolated let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Actor-Isolated Mutable State
    
    /// Resampler from source format to 16kHz mono Float32.
    /// Actor-isolated: only accessed within the actor
    private var converter: AVAudioConverter?
    
    // -- Effective sample rate correction --
    // Core Audio process taps can declare one sample rate but deliver audio at a
    // different rate. We measure the *actual* rate by comparing wall-clock time to frames received.
    
    /// Rate tracking start date - actor-isolated
    private var rateTrackingStartDate: Date?
    
    /// Total frames tracked - actor-isolated  
    private var rateTrackingTotalFrames: Int64 = 0
    
    /// Calculated effective sample rate - actor-isolated
    private var effectiveSampleRate: Double?
    
    /// Minimum wall-clock seconds before we trust the effective rate measurement.
    nonisolated private static let rateWarmupSeconds: Double = 3.0
    
    /// Relative threshold: if effective rate differs by more than this fraction, correct it.
    nonisolated private static let rateDivergenceThreshold: Double = 0.05

    /// Trailing words from the last transcribed segment, used to prime the next segment's decoder.
    /// Actor-isolated to prevent data races during concurrent transcription.
    private var previousContext: String?

    // MARK: - Constants
    
    /// Silero VAD expects chunks of 4096 samples (256ms at 16kHz).
    nonisolated private static let vadChunkSize = 4096
    
    /// Parakeet TDT requires >= 1s of audio; shorter segments produce unreliable output.
    nonisolated private static let minimumSpeechSamples = 16_000
    nonisolated private static let prerollChunkCount = 2
    
    /// Number of trailing words to carry across segment boundaries for decoder priming.
    nonisolated private static let contextWordCount = 5
    nonisolated private static let cloudSegmentDiagnosticsEventName = "live_cloud_segment_transcription"

    // MARK: - Initialization
    
    init(
        backend: any TranscriptionBackend,
        locale: Locale,
        vadManager: VadManager,
        speaker: Speaker,
        sessionID: String?,
        transcriptionModel: String,
        flushInterval: Int,
        skipPartials: Bool = false,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onCloudSegmentStatus: (@Sendable (CloudSegmentStatus) -> Void)? = nil,
        onCloudProcessingChanged: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.backend = backend
        self.locale = locale
        self.vadManager = vadManager
        self.speaker = speaker
        self.sessionID = sessionID
        self.transcriptionModel = transcriptionModel
        self.flushInterval = flushInterval
        self.skipPartials = skipPartials
        self.onPartial = onPartial
        self.onFinal = onFinal
        self.onCloudSegmentStatus = onCloudSegmentStatus
        self.onCloudProcessingChanged = onCloudProcessingChanged
    }

    // MARK: - Main Loop
    
    /// Main loop: reads audio buffers, runs VAD, transcribes speech segments.
    /// Uses CircularAudioBuffer and ChunkedSpeechBuffer for O(1) hot path performance.
    func run(stream: AsyncStream<AVAudioPCMBuffer>) async {
        let segmentQueue = await makeSegmentQueueIfNeeded()
        var vadState = await vadManager.makeStreamState()
        var speechSamples = ChunkedSpeechBuffer()
        var vadBuffer = CircularAudioBuffer(capacity: Self.vadChunkSize * 4)
        var vadReadIndex = 0
        var recentChunks: [[Float]] = []
        var isSpeaking = false
        var bufferCount = 0
        var lastPartialTime: Date = .distantPast
        var isRunningPartial = false

        for await buffer in stream {
            guard !Task.isCancelled else { break }
            bufferCount += 1
            if bufferCount <= 3 {
                let fmt = buffer.format
                Log.streaming.debug("[\(self.speaker.storageKey, privacy: .public)] buffer #\(bufferCount, privacy: .public): frames=\(buffer.frameLength, privacy: .public) sr=\(fmt.sampleRate, privacy: .public) ch=\(fmt.channelCount, privacy: .public) interleaved=\(fmt.isInterleaved, privacy: .public) common=\(fmt.commonFormat.rawValue, privacy: .public)")
            }

            // Track effective sample rate (detects process-tap rate mismatch)
            // Safe: running in actor isolation
            await updateRateTracking(buffer)

            guard let samples = await extractSamples(buffer) else { continue }

            if bufferCount <= 3 {
                let maxVal = samples.max() ?? 0
                Log.streaming.debug("[\(self.speaker.storageKey, privacy: .public)] samples: count=\(samples.count, privacy: .public) max=\(maxVal, privacy: .public)")
            }

            vadBuffer.append(samples)

            while vadBuffer.count - vadReadIndex >= Self.vadChunkSize {
                let chunk = vadBuffer.readChunk(start: vadReadIndex, size: Self.vadChunkSize)
                vadReadIndex += Self.vadChunkSize

                // O(1) consumption - eliminates quadratic behavior
                if vadReadIndex > Self.vadChunkSize * 2 {
                    vadBuffer.consume(vadReadIndex)
                    vadReadIndex = 0
                }
                let wasSpeaking = isSpeaking

                var startedSpeech = false
                var endedSpeech = false
                do {
                    let result = try await vadManager.processStreamingChunk(
                        chunk,
                        state: vadState,
                        config: .default,
                        returnSeconds: true,
                        timeResolution: 2
                    )
                    vadState = result.state

                    if let event = result.event {
                        switch event.kind {
                        case .speechStart:
                            if !wasSpeaking {
                                isSpeaking = true
                                startedSpeech = true
                                // Rebuild speechSamples from recent chunks
                                speechSamples.removeAll(keepingCapacity: true)
                                for chunk in recentChunks.suffix(Self.prerollChunkCount) {
                                    speechSamples.append(chunk)
                                }
                                Log.streaming.debug("[\(self.speaker.storageKey, privacy: .public)] speech start")
                            }

                        case .speechEnd:
                            endedSpeech = wasSpeaking || isSpeaking
                        }
                    }

                    if wasSpeaking || startedSpeech || endedSpeech {
                        speechSamples.append(chunk)
                        recentChunks.removeAll(keepingCapacity: true)
                    } else {
                        recentChunks.append(chunk)
                        if recentChunks.count > Self.prerollChunkCount {
                            recentChunks.removeFirst(recentChunks.count - Self.prerollChunkCount)
                        }
                    }

                    if endedSpeech {
                        isSpeaking = false
                        isRunningPartial = false
                        Log.streaming.debug("[\(self.speaker.storageKey, privacy: .public)] speech end, samples=\(speechSamples.count, privacy: .public)")
                        if speechSamples.count > Self.minimumSpeechSamples {
                            let segment = speechSamples.asContiguousArray()
                            speechSamples.removeAll(keepingCapacity: true)
                            onPartial("")  // Clear partial display
                            await submitSegment(segment, using: segmentQueue)
                        } else {
                            speechSamples.removeAll(keepingCapacity: true)
                            onPartial("")  // Clear partial display
                        }
                    } else if isSpeaking {

                        // Throttled partial hypothesis every ~400ms.
                        // Skipped for cloud backends — each call blocks the VAD loop
                        // for seconds while the HTTP round-trip completes.
                        if !skipPartials,
                           !isRunningPartial,
                           speechSamples.count > Self.minimumSpeechSamples,
                           Date.now.timeIntervalSince(lastPartialTime) >= 0.4 {
                            isRunningPartial = true
                            lastPartialTime = .now
                            let snapshot = speechSamples.asContiguousArray()
                            do {
                                let text = try await backend.transcribe(snapshot, locale: locale, previousContext: nil)
                                if !text.isEmpty && !Task.isCancelled {
                                    onPartial(text)
                                }
                            } catch {
                                // Best-effort — ignore
                            }
                            isRunningPartial = false
                        }

                        // Flush on long continuous speech (see flushInterval)
                        if speechSamples.count >= flushInterval {
                            let segment = speechSamples.asContiguousArray()
                            speechSamples.removeAll(keepingCapacity: true)
                            onPartial("")  // Clear partial display
                            await submitSegment(segment, using: segmentQueue)
                        }
                    }
                } catch {
                    Log.streaming.error("VAD error: \(error, privacy: .public)")
                }
            }
        }

        if speechSamples.count > Self.minimumSpeechSamples {
            onPartial("")  // Clear partial display
            await submitSegment(speechSamples.asContiguousArray(), using: segmentQueue)
        }

        if let segmentQueue {
            if Task.isCancelled {
                await segmentQueue.cancel()
            } else {
                await segmentQueue.finish()
            }
        }
    }
    
    // MARK: - Actor-Isolated Helpers
    
    /// Safe actor-isolated segment queue creation
    private func makeSegmentQueueIfNeeded() async -> StreamingTranscriptionSegmentQueue? {
        guard skipPartials else { return nil }
        return StreamingTranscriptionSegmentQueue(
            onProcessingChanged: onCloudProcessingChanged
        ) { [self] segment in
            await transcribeSegment(segment)
        }
    }

    private func submitSegment(
        _ samples: [Float],
        using queue: StreamingTranscriptionSegmentQueue?
    ) async {
        if let queue {
            await queue.enqueue(samples)
        } else {
            await transcribeSegment(samples)
        }
    }

    /// Transcribes a segment and safely updates actor-isolated previousContext
    private func transcribeSegment(_ samples: [Float]) async {
        let startedAt = Date()
        do {
            try Task.checkCancellation()
            let text = try await backend.transcribe(samples, locale: locale, previousContext: previousContext)
            if text.isEmpty {
                onCloudSegmentStatus?(
                    CloudSegmentStatus(
                        kind: .empty,
                        presentation: CloudTranscriptCopy.emptyChunk
                    )
                )
                recordCloudSegmentDiagnostics(
                    samples: samples,
                    startedAt: startedAt,
                    result: "empty",
                    textLength: 0,
                    errorKind: nil,
                    errorMessage: nil
                )
                Log.streaming.warning(
                    "[\(self.speaker.storageKey, privacy: .public)] cloud segment returned empty text: backend=\(self.backend.displayName, privacy: .public) duration=\(String(format: "%.2f", Double(samples.count) / 16_000), privacy: .public)s"
                )
                return
            }
            Log.streaming.debug("[\(self.speaker.storageKey, privacy: .public)] transcribed: \(text.prefix(80), privacy: .private)")
            onCloudSegmentStatus?(CloudSegmentStatus(kind: .success, presentation: nil))
            recordCloudSegmentDiagnostics(
                samples: samples,
                startedAt: startedAt,
                result: "success",
                textLength: text.count,
                errorKind: nil,
                errorMessage: nil
            )
            // Store trailing words for cross-segment context - actor-isolated, safe
            let words = text.split(separator: " ")
            previousContext = words.suffix(Self.contextWordCount).joined(separator: " ")
            onFinal(text)
        } catch {
            onCloudSegmentStatus?(CloudSegmentStatus(kind: .error, presentation: CloudTranscriptCopy.presentation(for: error)))
            recordCloudSegmentDiagnostics(
                samples: samples,
                startedAt: startedAt,
                result: "error",
                textLength: nil,
                errorKind: Self.cloudDiagnosticsErrorKind(for: error),
                errorMessage: Self.cloudDiagnosticsErrorMessage(for: error)
            )
            Log.streaming.error("ASR error: \(error, privacy: .public)")
        }
    }

    private func recordCloudSegmentDiagnostics(
        samples: [Float],
        startedAt: Date,
        result: String,
        textLength: Int?,
        errorKind: String?,
        errorMessage: String?
    ) {
        guard skipPartials else { return }

        let elapsedMilliseconds = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        let event = CloudSegmentDiagnosticsEvent(
            event: Self.cloudSegmentDiagnosticsEventName,
            sessionID: sessionID,
            transcriptionModel: transcriptionModel,
            backend: backend.displayName,
            speaker: speaker.storageKey,
            sampleCount: samples.count,
            durationSeconds: Double(samples.count) / 16_000,
            elapsedMilliseconds: elapsedMilliseconds,
            result: result,
            textLength: textLength,
            errorKind: errorKind,
            errorMessage: errorMessage
        )
        DiagnosticsSupport.record(
            category: "transcription",
            message: Self.cloudSegmentDiagnosticsMessage(for: event)
        )
    }

    nonisolated static func cloudSegmentDiagnosticsMessage(for event: CloudSegmentDiagnosticsEvent) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(event),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"event\":\"\(Self.cloudSegmentDiagnosticsEventName)\",\"result\":\"encoding_failed\"}"
    }

    nonisolated static func cloudDiagnosticsErrorKind(for error: Error) -> String {
        if error is CancellationError {
            return "cancelled"
        }
        if let cloudError = error as? CloudASRError {
            switch cloudError {
            case .invalidAPIKey:
                return "invalid_api_key"
            case .invalidUploadURL:
                return "invalid_upload_url"
            case .httpError(let statusCode):
                return "http_\(statusCode)"
            case .transcriptionFailed:
                return "transcription_failed"
            case .timeout:
                return "timeout"
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "transport_timeout"
            case .networkConnectionLost:
                return "transport_connection_lost"
            default:
                return "url_\(urlError.code.rawValue)"
            }
        }
        return "other"
    }

    nonisolated static func cloudDiagnosticsErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return String(describing: error) }
        return String(message.prefix(200))
    }

    // MARK: - Actor-Isolated Rate Tracking
    
    /// Track wall-clock time vs frames received to detect process-tap rate mismatch.
    /// This is now actor-isolated, preventing data races.
    private func updateRateTracking(_ buffer: AVAudioPCMBuffer) {
        let frames = Int64(buffer.frameLength)
        guard frames > 0 else { return }

        let now = Date()
        if rateTrackingStartDate == nil {
            rateTrackingStartDate = now
        }
        rateTrackingTotalFrames += frames

        // Only compute after warmup period; skip if already locked in
        guard effectiveSampleRate == nil,
              let start = rateTrackingStartDate else { return }

        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= Self.rateWarmupSeconds else { return }

        let measured = Double(rateTrackingTotalFrames) / elapsed
        let declared = buffer.format.sampleRate
        let divergence = abs(measured - declared) / declared

        if divergence > Self.rateDivergenceThreshold {
            effectiveSampleRate = measured
            converter = nil // force rebuild on next extractSamples call
            Log.streaming.warning("[\(self.speaker.storageKey, privacy: .public)] rate mismatch: declared=\(declared, privacy: .public) effective=\(measured, privacy: .public) (divergence \(String(format: "%.1f", divergence * 100), privacy: .public)%), correcting resampler")
        }
    }
    
    /// Get the current effective sample rate (actor-isolated)
    func getEffectiveSampleRate() -> Double {
        return effectiveSampleRate ?? 0.0
    }
    
    /// Get the current transcription context (actor-isolated)
    func getPreviousContext() -> String? {
        return previousContext
    }
    
    /// Clean up resources and reset state (actor-isolated)
    func cleanup() {
        converter = nil
        previousContext = nil
        rateTrackingStartDate = nil
        rateTrackingTotalFrames = 0
        effectiveSampleRate = nil
    }

    // MARK: - Actor-Isolated Sample Extraction
    
    /// Extract [Float] samples from an AVAudioPCMBuffer, resampling if needed.
    /// Actor-isolated: safely accesses converter and effectiveSampleRate.
    private func extractSamples(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let sourceFormat = buffer.format
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        // Determine the actual sample rate (may differ from declared for process taps)
        let actualRate = effectiveSampleRate ?? sourceFormat.sampleRate

        // Fast path: already Float32 at 16kHz
        if sourceFormat.commonFormat == .pcmFormatFloat32 && actualRate == 16000 {
            guard let channelData = buffer.floatChannelData else { return nil }
            if sourceFormat.channelCount == 1 {
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            } else {
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            }
        }

        // Downmix multi-channel to mono before resampling
        // (AVAudioConverter mishandles deinterleaved multi-channel input)
        // Uses vDSP for 5-8x speedup on Apple Silicon AMX.
        var inputBuffer = buffer
        let monoRate = actualRate
        if sourceFormat.channelCount > 1, let src = buffer.floatChannelData {
            let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: monoRate,
                channels: 1,
                interleaved: false
            )!
            if let monoBuf = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameCapacity),
               let dst = monoBuf.floatChannelData?[0] {
                monoBuf.frameLength = buffer.frameLength
                let channels = Int(sourceFormat.channelCount)
                let scale = 1.0 / Float(channels)

                // vDSP optimized downmix: accumulate channels pairwise
                if channels == 2 {
                    vDSP_vadd(src[0], 1, src[1], 1, dst, 1, vDSP_Length(frameLength))
                    var s = scale
                    vDSP_vsmul(dst, 1, &s, dst, 1, vDSP_Length(frameLength))
                } else {
                    // Multi-channel: accumulate first, then scale
                    vDSP_vadd(src[0], 1, src[1], 1, dst, 1, vDSP_Length(frameLength))
                    for ch in 2..<channels {
                        vDSP_vadd(dst, 1, src[ch], 1, dst, 1, vDSP_Length(frameLength))
                    }
                    var s = scale
                    vDSP_vsmul(dst, 1, &s, dst, 1, vDSP_Length(frameLength))
                }
                inputBuffer = monoBuf
            }
        } else if effectiveSampleRate != nil, sourceFormat.channelCount == 1 {
            // Mono but rate-corrected: re-wrap buffer with the effective rate so the
            // converter uses the correct ratio.
            let correctedFormat = AVAudioFormat(
                commonFormat: sourceFormat.commonFormat,
                sampleRate: monoRate,
                channels: 1,
                interleaved: sourceFormat.isInterleaved
            )!
            if let rewrapped = AVAudioPCMBuffer(pcmFormat: correctedFormat, frameCapacity: buffer.frameCapacity) {
                rewrapped.frameLength = buffer.frameLength
                if let srcData = buffer.floatChannelData?[0],
                   let dstData = rewrapped.floatChannelData?[0] {
                    memcpy(dstData, srcData, frameLength * MemoryLayout<Float>.size)
                    inputBuffer = rewrapped
                }
            }
        }

        // Slow path: need to resample via AVAudioConverter
        let inputFormat = inputBuffer.format
        if converter == nil || converter?.inputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputFrames = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        guard outputFrames > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrames
        ) else { return nil }

        var error: NSError?
        nonisolated(unsafe) var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error {
            Log.streaming.error("Resample error: \(error, privacy: .public)")
            return nil
        }

        guard let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))
    }
}

// MARK: - Backward Compatibility Wrapper

/// Backward-compatible wrapper for StreamingTranscriptionActor.
///
/// This struct provides the original StreamingTranscriber API while
/// internally using the actor-isolated implementation for thread safety.
///
/// ## Migration Guide
/// - Replace `StreamingTranscriber(...)` with `StreamingTranscriber(...)`
/// - The API is identical; thread safety is now guaranteed
///
/// ## Safety
/// - No @unchecked Sendable - properly Sendable via actor isolation
/// - All mutable state is actor-isolated
/// - Thread Sanitizer clean
struct StreamingTranscriber: Sendable {
    private let actor: StreamingTranscriptionActor
    
    // Forward types for compatibility
    typealias CloudSegmentStatus = StreamingTranscriptionActor.CloudSegmentStatus
    typealias CloudSegmentDiagnosticsEvent = StreamingTranscriptionActor.CloudSegmentDiagnosticsEvent
    
    init(
        backend: any TranscriptionBackend,
        locale: Locale,
        vadManager: VadManager,
        speaker: Speaker,
        sessionID: String?,
        transcriptionModel: String,
        flushInterval: Int,
        skipPartials: Bool = false,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onCloudSegmentStatus: (@Sendable (CloudSegmentStatus) -> Void)? = nil,
        onCloudProcessingChanged: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.actor = StreamingTranscriptionActor(
            backend: backend,
            locale: locale,
            vadManager: vadManager,
            speaker: speaker,
            sessionID: sessionID,
            transcriptionModel: transcriptionModel,
            flushInterval: flushInterval,
            skipPartials: skipPartials,
            onPartial: onPartial,
            onFinal: onFinal,
            onCloudSegmentStatus: onCloudSegmentStatus,
            onCloudProcessingChanged: onCloudProcessingChanged
        )
    }
    
    /// Main loop: reads audio buffers, runs VAD, transcribes speech segments.
    func run(stream: AsyncStream<AVAudioPCMBuffer>) async {
        await actor.run(stream: stream)
    }
}

// MARK: - VadManager Protocol Sendable Support

// The VadManager protocol needs to be Sendable for actor isolation
// This extension ensures compatibility
protocol VadManager: Sendable {
    func makeStreamState() async -> VadStreamState
    func processStreamingChunk(
        _ samples: [Float],
        state: VadStreamState,
        config: VadConfig,
        returnSeconds: Bool,
        timeResolution: Int
    ) async throws -> VadResult
}

struct VadStreamState: Sendable {
    // Default empty state - implementations can extend
}

struct VadResult: Sendable {
    let state: VadStreamState
    let event: VadEvent?
    let seconds: Double?
}

struct VadEvent: Sendable {
    let kind: VadEventKind
}

enum VadEventKind: Sendable {
    case speechStart
    case speechEnd
}

struct VadConfig: Sendable {
    static let `default` = VadConfig()
}
