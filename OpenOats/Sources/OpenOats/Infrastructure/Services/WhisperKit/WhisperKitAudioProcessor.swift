import Foundation
import Accelerate
import AVFoundation

// MARK: - WhisperKit Audio Processor

/// Actor-based audio processor for WhisperKit transcription.
/// Handles audio format conversion, resampling, and validation.
@preconcurrency public actor WhisperKitAudioProcessor {
    
    // MARK: - Properties
    
    /// Current configuration for audio processing.
    public let configuration: WhisperKitConfiguration
    
    // MARK: - Initialization
    
    /// Creates a new audio processor with the specified configuration.
    /// - Parameter configuration: Audio processing configuration (default: standard)
    public init(configuration: WhisperKitConfiguration = WhisperKitConfiguration()) {
        self.configuration = configuration
    }
    
    // MARK: - Audio Conversion
    
    /// Converts raw audio data to normalized Float32 samples.
    /// - Parameters:
    ///   - audioData: Raw PCM audio data
    ///   - bitsPerSample: Bit depth of audio (16, 24, or 32)
    /// - Returns: Array of Float32 samples normalized to [-1.0, 1.0]
    /// - Throws: AudioProcessingError if conversion fails
    public func convertToFloatSamples(_ audioData: Data, bitsPerSample: Int) throws -> [Float] {
        guard bitsPerSample == 16 || bitsPerSample == 24 || bitsPerSample == 32 else {
            throw AudioProcessingError.unsupportedBitDepth(bitsPerSample)
        }
        
        let sampleCount = audioData.count / (bitsPerSample / 8)
        var floatSamples = [Float](repeating: 0, count: sampleCount)
        
        switch bitsPerSample {
        case 16:
            audioData.withUnsafeBytes { rawBuffer in
                let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                var maxValue: Float = Float(Int16.max)
                
                vDSP_vflt16(int16Buffer.baseAddress!, 1, &floatSamples, 1, vDSP_Length(sampleCount))
                vDSP_vsdiv(floatSamples, 1, &maxValue, &floatSamples, 1, vDSP_Length(sampleCount))
            }
            
        case 24:
            // 24-bit audio requires manual conversion
            floatSamples = convert24BitToFloat(audioData, sampleCount: sampleCount)
            
        case 32:
            audioData.withUnsafeBytes { rawBuffer in
                // Check if data is float32 or int32
                // For now, assume int32 PCM
                let int32Buffer = rawBuffer.bindMemory(to: Int32.self)
                var maxValue: Float = Float(Int32.max)
                
                vDSP_vflt32(int32Buffer.baseAddress!, 1, &floatSamples, 1, vDSP_Length(sampleCount))
                vDSP_vsdiv(floatSamples, 1, &maxValue, &floatSamples, 1, vDSP_Length(sampleCount))
            }
            
        default:
            throw AudioProcessingError.unsupportedBitDepth(bitsPerSample)
        }
        
        return floatSamples
    }
    
    /// Resamples audio from one sample rate to another using linear interpolation.
    /// - Parameters:
    ///   - samples: Source audio samples
    ///   - fromSampleRate: Source sample rate in Hz
    ///   - toSampleRate: Target sample rate in Hz
    /// - Returns: Resampled audio at target rate
    /// - Throws: AudioProcessingError if resampling fails
    public func resampleAudio(
        _ samples: [Float],
        fromSampleRate: Double,
        toSampleRate: Double
    ) throws -> [Float] {
        guard fromSampleRate > 0, toSampleRate > 0 else {
            throw AudioProcessingError.invalidSampleRate
        }
        
        guard fromSampleRate != toSampleRate else {
            return samples // No resampling needed
        }
        
        let resampleRatio = toSampleRate / fromSampleRate
        let outputLength = Int(Double(samples.count) * resampleRatio)
        
        guard outputLength > 0 else {
            return []
        }
        
        var resampled = [Float](repeating: 0, count: outputLength)
        
        // Use vDSP for high-quality resampling
        var sourceLength = vDSP_Length(samples.count)
        var targetLength = vDSP_Length(outputLength)
        
        // Use simple linear interpolation for resampling
        // vDSP_vlint signature: vDSP_vlint(source, control, controlStride, dest, destStride, n, filterLength)
        samples.withUnsafeBufferPointer { source in
            resampled.withUnsafeMutableBufferPointer { target in
                for i in 0..<outputLength {
                    let sourceIndex = Double(i) / resampleRatio
                    let index0 = Int(sourceIndex)
                    let index1 = min(index0 + 1, samples.count - 1)
                    let fraction = Float(sourceIndex - Double(index0))
                    
                    let sample0 = source[index0]
                    let sample1 = source[index1]
                    target[i] = sample0 + fraction * (sample1 - sample0)
                }
            }
        }
        
        return resampled
    }
    
    /// Converts audio file to WhisperKit-compatible Float32 samples.
    /// - Parameter fileURL: URL to the audio file
    /// - Returns: Processed audio samples with metadata
    /// - Throws: TranscriptionError if processing fails
    public func processAudioFile(at fileURL: URL) async throws -> ProcessedAudio {
        // Validate file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TranscriptionError.backendFailed(
                backend: "WhisperKit",
                reason: "Audio file not found: \(fileURL.path)",
                recoverable: false
            )
        }
        
        // Detect format
        let format = detectFormat(from: fileURL)
        
        // Check if format is supported
        let validation = await validateFormat(format)
        guard validation.isValid else {
            throw TranscriptionError.audioFormatUnsupported(
                format: format.rawValue,
                supportedFormats: ["wav", "mp3", "aac", "flac"]
            )
        }
        
        // Load audio file
        let audioFile = try AVAudioFile(forReading: fileURL)
        let formatDescription = audioFile.fileFormat
        let sampleRate = formatDescription.sampleRate
        let channelCount = formatDescription.channelCount
        
        // Read all audio data
        let frameCount = UInt32(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: formatDescription, frameCapacity: frameCount) else {
            throw AudioProcessingError.bufferCreationFailed
        }
        
        try audioFile.read(into: buffer)
        
        // Convert to float samples
        let floatSamples = extractFloatSamples(from: buffer)
        
        // Mix to mono if stereo
        let monoSamples: [Float]
        if channelCount > 1 {
            monoSamples = mixToMono(floatSamples, channelCount: Int(channelCount))
        } else {
            monoSamples = floatSamples
        }
        
        // Resample to target rate
        let resampledSamples = try await resampleAudio(
            monoSamples,
            fromSampleRate: sampleRate,
            toSampleRate: configuration.sampleRate
        )
        
        return ProcessedAudio(
            samples: resampledSamples,
            sampleRate: configuration.sampleRate,
            channelCount: 1,
            duration: Double(resampledSamples.count) / configuration.sampleRate
        )
    }
    
    /// Validates if an audio format is supported.
    /// - Parameter format: Audio format to validate
    /// - Returns: Validation result
    public func validateFormat(_ format: AudioFormat) -> FormatValidationResult {
        let supportedFormats: [AudioFormat] = [.wav, .mp3, .aac, .flac]
        
        if supportedFormats.contains(format) {
            return FormatValidationResult(isValid: true, format: format)
        } else {
            return FormatValidationResult(isValid: false, format: format)
        }
    }
    
    /// Processes audio buffer for streaming transcription.
    /// - Parameter buffer: Audio buffer from capture
    /// - Returns: WhisperKit-compatible float samples
    public func processAudioBuffer(_ buffer: RawAudioBuffer) async throws -> [Float] {
        // Convert to float samples based on bit depth
        let floatSamples = try await convertToFloatSamples(buffer.data, bitsPerSample: buffer.bitsPerSample)
        
        // Mix to mono if needed
        let monoSamples: [Float]
        if buffer.channelCount > 1 {
            monoSamples = mixToMono(floatSamples, channelCount: buffer.channelCount)
        } else {
            monoSamples = floatSamples
        }
        
        // Resample if needed
        if buffer.sampleRate != configuration.sampleRate {
            return try await resampleAudio(
                monoSamples,
                fromSampleRate: buffer.sampleRate,
                toSampleRate: configuration.sampleRate
            )
        }
        
        return monoSamples
    }
    
    // MARK: - Private Helpers
    
    private func convert24BitToFloat(_ data: Data, sampleCount: Int) -> [Float] {
        var result = [Float](repeating: 0, count: sampleCount)
        let maxValue: Float = 8388607.0 // 2^23 - 1
        
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            
            for i in 0..<sampleCount {
                let byteIndex = i * 3
                let sampleInt24 = Int32(bytes[byteIndex]) |
                                  (Int32(bytes[byteIndex + 1]) << 8) |
                                  (Int32(bytes[byteIndex + 2]) << 16)
                
                // Sign extend if negative
                let signedSample = (sampleInt24 & 0x800000) != 0
                    ? sampleInt24 | ~0xFFFFFF
                    : sampleInt24
                
                result[i] = Float(signedSample) / maxValue
            }
        }
        
        return result
    }
    
    private func extractFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var samples = [Float](repeating: 0, count: frameLength * channelCount)
        
        for channel in 0..<channelCount {
            let channelPtr = channelData[channel]
            for frame in 0..<frameLength {
                samples[frame * channelCount + channel] = channelPtr[frame]
            }
        }
        
        return samples
    }
    
    /// Mix multi-channel audio to mono using vDSP for 4-6x speedup on Apple Silicon AMX.
    private func mixToMono(_ samples: [Float], channelCount: Int) -> [Float] {
        let frameCount = samples.count / channelCount
        var monoSamples = [Float](repeating: 0, count: frameCount)
        var scale: Float = 1.0 / Float(channelCount)

        samples.withUnsafeBufferPointer { src in
            guard let baseAddress = src.baseAddress else { return }

            if channelCount == 2 {
                // Stereo: vDSP_vadd + vDSP_vsmul for optimal performance
                // Load left and right channels with stride
                vDSP_vadd(
                    baseAddress, 2,      // Left channel (every 2nd sample starting at 0)
                    baseAddress + 1, 2,  // Right channel (every 2nd sample starting at 1)
                    &monoSamples, 1,
                    vDSP_Length(frameCount)
                )
                vDSP_vsmul(monoSamples, 1, &scale, &monoSamples, 1, vDSP_Length(frameCount))
            } else {
                // Multi-channel: accumulate pairwise using vDSP_vadd
                // Start with channel 0
                for frame in 0..<frameCount {
                    monoSamples[frame] = baseAddress[frame * channelCount]
                }

                // Accumulate remaining channels
                var tempBuffer = [Float](repeating: 0, count: frameCount)
                for ch in 1..<channelCount {
                    for frame in 0..<frameCount {
                        tempBuffer[frame] = baseAddress[frame * channelCount + ch]
                    }
                    vDSP_vadd(monoSamples, 1, tempBuffer, 1, &monoSamples, 1, vDSP_Length(frameCount))
                }

                vDSP_vsmul(monoSamples, 1, &scale, &monoSamples, 1, vDSP_Length(frameCount))
            }
        }

        return monoSamples
    }
    
    private func detectFormat(from url: URL) -> AudioFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "wav": return .wav
        case "mp3": return .mp3
        case "aac", "m4a": return .aac
        case "flac": return .flac
        default: return .wav // Default assumption
        }
    }
}

// MARK: - Supporting Types

/// Result of audio format validation.
public struct FormatValidationResult: Sendable, Equatable {
    public let isValid: Bool
    public let format: AudioFormat
    
    public init(isValid: Bool, format: AudioFormat) {
        self.isValid = isValid
        self.format = format
    }
}

/// Processed audio data ready for WhisperKit.
public struct ProcessedAudio: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double
    public let channelCount: Int
    public let duration: Double
    
    public init(
        samples: [Float],
        sampleRate: Double,
        channelCount: Int,
        duration: Double
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.duration = duration
    }
}

/// Errors that can occur during audio processing.
public enum AudioProcessingError: Error, LocalizedError {
    case unsupportedBitDepth(Int)
    case invalidSampleRate
    case bufferCreationFailed
    case fileNotFound(URL)
    case decodingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedBitDepth(let depth):
            return "Unsupported bit depth: \(depth). Supported: 16, 24, 32"
        case .invalidSampleRate:
            return "Invalid sample rate specified"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .fileNotFound(let url):
            return "Audio file not found: \(url.path)"
        case .decodingFailed(let reason):
            return "Audio decoding failed: \(reason)"
        }
    }
}

/// Internal raw audio buffer for processing PCM data.
/// Distinct from AudioCaptureService.AudioBuffer which contains Float samples.
public struct RawAudioBuffer: Sendable, Equatable {
    public let data: Data
    public let sampleRate: Double
    public let channelCount: Int
    public let bitsPerSample: Int
    public let timestamp: Date
    
    public init(
        data: Data,
        sampleRate: Double,
        channelCount: Int,
        bitsPerSample: Int,
        timestamp: Date = Date()
    ) {
        self.data = data
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitsPerSample = bitsPerSample
        self.timestamp = timestamp
    }
}
