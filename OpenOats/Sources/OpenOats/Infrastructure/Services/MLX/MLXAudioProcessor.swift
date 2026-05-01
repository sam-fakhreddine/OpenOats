import Foundation
import MLX
import MLXAudioSTT
import Accelerate

// MARK: - MLX Audio Errors

/// Errors that can occur during MLX audio processing.
public enum MLXAudioError: Error, Sendable, Equatable {
    case invalidBuffer
    case invalidSampleRate
    case invalidChannelCount
    case resamplingFailed
    case normalizationFailed
    case unsupportedFormat(String)
    
    public var localizedDescription: String {
        switch self {
        case .invalidBuffer:
            return "Audio buffer is empty or invalid"
        case .invalidSampleRate:
            return "Invalid sample rate (must be > 0)"
        case .invalidChannelCount:
            return "Invalid channel count (must be >= 1)"
        case .resamplingFailed:
            return "Failed to resample audio"
        case .normalizationFailed:
            return "Failed to normalize audio levels"
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format)"
        }
    }
}

// MARK: - MLX Audio Processor

/// Actor-based audio processor for MLX transcription.
/// Handles audio preprocessing including resampling, format conversion,
/// stereo-to-mono conversion, and normalization using Accelerate framework.
public actor MLXAudioProcessor {
    
    // MARK: - Properties
    
    /// Target sample rate for MLX models (16kHz is standard)
    public let targetSampleRate: Double
    
    /// Whether to apply normalization
    public let shouldNormalize: Bool
    
    /// Preallocated buffer for resampling operations
    private var resampleBuffer: [Float] = []
    
    // MARK: - Initialization
    
    /// Creates a new MLX audio processor.
    /// - Parameters:
    ///   - targetSampleRate: Target sample rate (default 16000 Hz)
    ///   - shouldNormalize: Whether to normalize audio levels
    public init(
        targetSampleRate: Double = 16000,
        shouldNormalize: Bool = true
    ) {
        self.targetSampleRate = targetSampleRate
        self.shouldNormalize = shouldNormalize
    }
    
    // MARK: - Audio Processing
    
    /// Prepares an audio buffer for MLX transcription.
    /// Performs the following operations:
    /// 1. Validates input
    /// 2. Converts stereo to mono if needed
    /// 3. Resamples to target rate
    /// 4. Normalizes audio levels (optional)
    ///
    /// - Parameters:
    ///   - buffer: Input audio buffer
    ///   - targetSampleRate: Override target sample rate
    ///   - normalize: Override normalization setting
    /// - Returns: Processed audio buffer ready for MLX
    /// - Throws: MLXAudioError if processing fails
    public func prepareForMLX(
        _ buffer: AudioBuffer,
        targetSampleRate: Double? = nil,
        normalize: Bool? = nil
    ) async throws -> AudioBuffer {
        let targetRate = targetSampleRate ?? self.targetSampleRate
        let shouldNorm = normalize ?? self.shouldNormalize
        
        // Validate input
        try validateBuffer(buffer)
        
        var processedBuffer = buffer
        
        // Step 1: Convert to mono if stereo
        if buffer.channelCount > 1 {
            processedBuffer = await convertToMono(processedBuffer)
        }
        
        // Step 2: Resample to target rate if needed
        if abs(processedBuffer.sampleRate - targetRate) > 1.0 {
            processedBuffer = try await resample(processedBuffer, to: targetRate)
        }
        
        // Step 3: Normalize audio levels if enabled
        if shouldNorm {
            processedBuffer = await normalize(processedBuffer)
        }
        
        return processedBuffer
    }
    
    /// Converts audio samples to MLXArray format.
    /// - Parameter buffer: Processed audio buffer
    /// - Returns: MLXArray for model input
    public func toMLXArray(_ buffer: AudioBuffer) -> MLXArray {
        return MLXArray(buffer.samples)
    }
    
    /// Processes multiple buffers for batch transcription.
    /// - Parameter buffers: Array of audio buffers
    /// - Returns: Array of processed buffers
    /// - Throws: MLXAudioError if any buffer fails processing
    public func prepareBatchForMLX(
        _ buffers: [AudioBuffer]
    ) async throws -> [AudioBuffer] {
        var results: [AudioBuffer] = []
        results.reserveCapacity(buffers.count)
        
        for buffer in buffers {
            let processed = try await prepareForMLX(buffer)
            results.append(processed)
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    private func validateBuffer(_ buffer: AudioBuffer) throws {
        guard !buffer.samples.isEmpty else {
            throw MLXAudioError.invalidBuffer
        }
        
        guard buffer.sampleRate > 0 else {
            throw MLXAudioError.invalidSampleRate
        }
        
        guard buffer.channelCount >= 1 else {
            throw MLXAudioError.invalidChannelCount
        }
    }
    
    /// Converts stereo audio to mono using vDSP for performance.
    private func convertToMono(_ buffer: AudioBuffer) -> AudioBuffer {
        let channelCount = buffer.channelCount
        let frameCount = buffer.samples.count / channelCount
        
        var monoSamples = [Float](repeating: 0, count: frameCount)
        
        // Use vDSP for efficient channel mixing
        if channelCount == 2 {
            // Optimized path for stereo
            buffer.samples.withUnsafeBufferPointer { src in
                guard let baseAddress = src.baseAddress else { return }
                
                var leftChannel = [Float](repeating: 0, count: frameCount)
                var rightChannel = [Float](repeating: 0, count: frameCount)
                
                // Deinterleave left and right channels
                for i in 0..<frameCount {
                    leftChannel[i] = baseAddress[i * 2]
                    rightChannel[i] = baseAddress[i * 2 + 1]
                }
                
                // Average using vDSP: (L + R) / 2
                vDSP_vadd(leftChannel, 1, rightChannel, 1, &monoSamples, 1, vDSP_Length(frameCount))
                
                var scale: Float = 0.5
                vDSP_vsmul(monoSamples, 1, &scale, &monoSamples, 1, vDSP_Length(frameCount))
            }
        } else {
            // Generic path for multi-channel
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += buffer.samples[frame * channelCount + channel]
                }
                monoSamples[frame] = sum / Float(channelCount)
            }
        }
        
        return AudioBuffer(
            samples: monoSamples,
            sampleRate: buffer.sampleRate,
            channelCount: 1,
            timestamp: buffer.timestamp,
            id: buffer.id
        )
    }
    
    /// Resamples audio to target sample rate using linear interpolation.
    private func resample(_ buffer: AudioBuffer, to targetRate: Double) async throws -> AudioBuffer {
        let sourceRate = buffer.sampleRate
        let ratio = sourceRate / targetRate
        let sourceCount = buffer.samples.count
        let targetCount = Int(Double(sourceCount) / ratio)
        
        guard targetCount > 0 else {
            throw MLXAudioError.resamplingFailed
        }
        
        var resampled = [Float](repeating: 0, count: targetCount)
        
        // Linear interpolation resampling
        for i in 0..<targetCount {
            let sourceIndex = Double(i) * ratio
            let index0 = Int(sourceIndex)
            let index1 = min(index0 + 1, sourceCount - 1)
            let fraction = Float(sourceIndex - Double(index0))
            
            let sample0 = buffer.samples[index0]
            let sample1 = buffer.samples[index1]
            
            resampled[i] = sample0 * (1 - fraction) + sample1 * fraction
        }
        
        return AudioBuffer(
            samples: resampled,
            sampleRate: targetRate,
            channelCount: buffer.channelCount,
            timestamp: buffer.timestamp,
            id: buffer.id
        )
    }
    
    /// Normalizes audio to target peak level using vDSP.
    private func normalize(_ buffer: AudioBuffer) -> AudioBuffer {
        guard !buffer.samples.isEmpty else { return buffer }
        
        // Find peak using vDSP
        var peak: Float = 0
        vDSP_maxv(buffer.samples, 1, &peak, vDSP_Length(buffer.samples.count))
        
        guard peak > 0 else { return buffer }
        
        // Target peak level: -1 dB (about 0.89 linear)
        let targetLevel: Float = 0.89
        let gain = targetLevel / peak
        
        var normalized = [Float](repeating: 0, count: buffer.samples.count)
        var g = gain
        vDSP_vsmul(buffer.samples, 1, &g, &normalized, 1, vDSP_Length(buffer.samples.count))
        
        return AudioBuffer(
            samples: normalized,
            sampleRate: buffer.sampleRate,
            channelCount: buffer.channelCount,
            timestamp: buffer.timestamp,
            id: buffer.id
        )
    }
    
    // MARK: - Utility Methods
    
    /// Calculates RMS energy of audio buffer.
    /// - Parameter buffer: Audio buffer
    /// - Returns: RMS energy value
    public func calculateEnergy(_ buffer: AudioBuffer) -> Float {
        guard !buffer.samples.isEmpty else { return 0 }
        
        var meanSquare: Float = 0
        vDSP_svesq(buffer.samples, 1, &meanSquare, vDSP_Length(buffer.samples.count))
        return sqrt(meanSquare / Float(buffer.samples.count))
    }
    
    /// Applies gain to audio buffer.
    /// - Parameters:
    ///   - buffer: Audio buffer
    ///   - gain: Gain multiplier
    /// - Returns: Scaled audio buffer
    public func applyGain(_ buffer: AudioBuffer, gain: Float) -> AudioBuffer {
        guard gain != 1.0, !buffer.samples.isEmpty else { return buffer }
        
        var result = [Float](repeating: 0, count: buffer.samples.count)
        var g = gain
        vDSP_vsmul(buffer.samples, 1, &g, &result, 1, vDSP_Length(buffer.samples.count))
        
        return AudioBuffer(
            samples: result,
            sampleRate: buffer.sampleRate,
            channelCount: buffer.channelCount,
            timestamp: buffer.timestamp,
            id: buffer.id
        )
    }
}
