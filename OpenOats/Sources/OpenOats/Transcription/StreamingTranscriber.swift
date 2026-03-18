@preconcurrency import AVFoundation
import FluidAudio
import os

/// Consumes an audio buffer stream, detects speech via Silero VAD,
/// and transcribes completed speech segments via Parakeet-TDT.
final class StreamingTranscriber: @unchecked Sendable {
    private let asrProvider: any ASRProvider
    private let vadManager: VadManager
    private let speaker: Speaker
    private let diarizerManager: DiarizerManager?
    private let onPartial: @Sendable (String) -> Void
    private let onFinal: @Sendable (String, UUID) -> Void
    /// Callback fired when diarization re-labels an utterance. Arguments: (utteranceID, newSpeaker).
    var onSpeakerIdentified: (@Sendable (UUID, Speaker) -> Void)?
    /// Ring of (utteranceID, wallClockTime) for utterances that arrived during the current diarization window.
    private var pendingUtterances: [(id: UUID, time: Date)] = []
    private let log = Logger(subsystem: "com.openoats", category: "StreamingTranscriber")

    /// Resampler from source format to 16kHz mono Float32.
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    init(
        asrProvider: any ASRProvider,
        vadManager: VadManager,
        speaker: Speaker,
        diarizerManager: DiarizerManager? = nil,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String, UUID) -> Void
    ) {
        self.asrProvider = asrProvider
        self.vadManager = vadManager
        self.speaker = speaker
        self.diarizerManager = diarizerManager
        self.onPartial = onPartial
        self.onFinal = onFinal
    }

    /// Silero VAD expects chunks of 4096 samples (256ms at 16kHz).
    private static let vadChunkSize = 4096
    /// Flush speech for transcription every ~3 seconds (48,000 samples at 16kHz).
    private static let flushInterval = 48_000
    /// Diarization chunk: 10 seconds at 16kHz.
    private static let diarizationChunkSize = 160_000

    /// Main loop: reads audio buffers, runs VAD, transcribes speech segments.
    func run(stream: AsyncStream<AVAudioPCMBuffer>) async {
        var vadState = await vadManager.makeStreamState()
        var speechSamples: [Float] = []
        var vadBuffer: [Float] = []
        var vadHead: Int = 0
        var isSpeaking = false
        var bufferCount = 0
        // Diarization accumulator — only used when diarizerManager != nil
        var pcmAccumulator: [Float] = []
        var chunkStartTime: TimeInterval = Date().timeIntervalSinceReferenceDate
        var chunkStartDate: Date = Date()

        for await buffer in stream {
            bufferCount += 1
            if bufferCount <= 3 {
                let fmt = buffer.format
                diagLog("[\(speaker.displayLabel)] buffer #\(bufferCount): frames=\(buffer.frameLength) sr=\(fmt.sampleRate) ch=\(fmt.channelCount) interleaved=\(fmt.isInterleaved) common=\(fmt.commonFormat.rawValue)")
            }

            guard let samples = extractSamples(buffer) else { continue }

            if bufferCount <= 3 {
                let maxVal = samples.max() ?? 0
                diagLog("[\(speaker.displayLabel)] samples: count=\(samples.count) max=\(maxVal)")
            }

            // Feed diarization accumulator when diarizer is available
            if diarizerManager != nil {
                if pcmAccumulator.isEmpty {
                    chunkStartDate = Date()
                    chunkStartTime = chunkStartDate.timeIntervalSinceReferenceDate
                }
                pcmAccumulator.append(contentsOf: samples)
                if pcmAccumulator.count >= Self.diarizationChunkSize {
                    let chunk = Array(pcmAccumulator.prefix(Self.diarizationChunkSize))
                    pcmAccumulator.removeFirst(Self.diarizationChunkSize)
                    await flushDiarizationChunk(chunk, chunkStartDate: chunkStartDate)
                    chunkStartDate = Date()
                    chunkStartTime = chunkStartDate.timeIntervalSinceReferenceDate
                }
            }

            vadBuffer.append(contentsOf: samples)

            while vadBuffer.count - vadHead >= Self.vadChunkSize {
                let chunk = Array(vadBuffer[vadHead..<vadHead + Self.vadChunkSize])
                vadHead += Self.vadChunkSize
                // Compact when head has advanced past half the buffer to bound memory growth
                if vadHead > vadBuffer.count / 2 {
                    vadBuffer.removeFirst(vadHead)
                    vadHead = 0
                }

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
                            isSpeaking = true
                            speechSamples.removeAll(keepingCapacity: true)
                            diagLog("[\(self.speaker.displayLabel)] speech start")

                        case .speechEnd:
                            isSpeaking = false
                            diagLog("[\(self.speaker.displayLabel)] speech end, samples=\(speechSamples.count)")
                            if speechSamples.count > 8000 {
                                let segment = speechSamples
                                speechSamples.removeAll(keepingCapacity: true)
                                await transcribeSegment(segment)
                            } else {
                                speechSamples.removeAll(keepingCapacity: true)
                            }
                        }
                    }

                    if isSpeaking {
                        speechSamples.append(contentsOf: chunk)

                        // Flush every ~3s for near-real-time output during continuous speech
                        if speechSamples.count >= Self.flushInterval {
                            let segment = speechSamples
                            speechSamples.removeAll(keepingCapacity: true)
                            await transcribeSegment(segment)
                        }
                    }
                } catch {
                    log.error("VAD error: \(error.localizedDescription)")
                }
            }
        }

        if speechSamples.count > 8000 {
            await transcribeSegment(speechSamples)
        }

        // Flush any remaining PCM that did not reach a full 10s diarization chunk
        if diarizerManager != nil && !pcmAccumulator.isEmpty {
            await flushDiarizationChunk(pcmAccumulator, chunkStartDate: chunkStartDate)
            pcmAccumulator.removeAll()
        }
    }

    // MARK: - Diarization

    /// Runs diarization on a full 10-second PCM chunk and re-labels any buffered utterances
    /// whose timestamps fall within each speaker segment.
    private func flushDiarizationChunk(_ chunk: [Float], chunkStartDate: Date) async {
        guard let dm = diarizerManager else { return }
        let atTime = chunkStartDate.timeIntervalSinceReferenceDate
        do {
            let result = try dm.performCompleteDiarization(chunk, sampleRate: 16000, atTime: atTime)
            let segments = result.segments
            guard !segments.isEmpty else { return }

            let pending = pendingUtterances
            pendingUtterances.removeAll(keepingCapacity: true)

            for entry in pending {
                let offsetSeconds = Float(entry.time.timeIntervalSince(chunkStartDate))
                if let seg = segments.first(where: {
                    $0.startTimeSeconds <= offsetSeconds && offsetSeconds < $0.endTimeSeconds
                }) {
                    let rawID = seg.speakerId
                    let index: Int
                    if rawID.hasPrefix("speaker_"), let n = Int(rawID.dropFirst("speaker_".count)) {
                        index = n + 1
                    } else {
                        index = 1
                    }
                    onSpeakerIdentified?(entry.id, .namedSpeaker(id: index))
                }
            }
        } catch {
            diagLog("[DIARIZE-ERR] \(error.localizedDescription)")
        }
    }

    private func transcribeSegment(_ samples: [Float]) async {
        do {
            let text = try await asrProvider.transcribe(samples, sampleRate: 16000).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let utteranceID = UUID()
            pendingUtterances.append((id: utteranceID, time: Date()))
            log.info("[\(self.speaker.displayLabel)] transcribed: \(text.prefix(80))")
            onFinal(text, utteranceID)
        } catch {
            log.error("ASR error: \(error.localizedDescription)")
        }
    }

    /// Extract [Float] samples from an AVAudioPCMBuffer, resampling if needed.
    private func extractSamples(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let sourceFormat = buffer.format
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        // Fast path: already Float32 at 16kHz (common for system audio from ScreenCaptureKit)
        if sourceFormat.commonFormat == .pcmFormatFloat32 && sourceFormat.sampleRate == 16000 {
            guard let channelData = buffer.floatChannelData else { return nil }
            if sourceFormat.channelCount == 1 {
                // Mono — direct copy
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            } else {
                // Multi-channel — take first channel only
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            }
        }

        // Slow path: need to resample via AVAudioConverter
        if converter == nil || converter?.inputFormat != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrames > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrames
        ) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            log.error("Resample error: \(error.localizedDescription)")
            return nil
        }

        guard let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))
    }
}
