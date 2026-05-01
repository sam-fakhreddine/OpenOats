import Foundation
import WhisperKit
import AVFoundation

// MARK: - WhisperKit Configuration

/// Configuration for WhisperKit transcription backend.
/// Defines model settings, CoreML optimization options, and audio processing parameters.
public struct WhisperKitConfiguration: Sendable, Equatable, CustomStringConvertible {
    
    // MARK: - Model Settings
    
    /// Whisper model variant to use.
    /// Supported values: "tiny", "base", "small", "medium", "large", "large-v3"
    public let model: String
    
    /// Compute units for CoreML execution.
    public let computeUnits: ComputeUnits
    
    /// Whether to enable timestamp generation in transcriptions.
    public let enableTimestamps: Bool
    
    // MARK: - Audio Settings
    
    /// Target sample rate for audio processing.
    /// Whisper models expect 16kHz audio.
    public let sampleRate: Double
    
    /// Target audio format for processing.
    public let audioFormat: AudioFormat
    
    // MARK: - CoreML Optimization
    
    /// Whether to prewarm the model (load and prepare for inference).
    public let prewarmModel: Bool
    
    /// Whether to use quantized models for faster inference.
    public let useQuantization: Bool
    
    /// Maximum audio chunk size in seconds.
    public let maxChunkSizeSeconds: Double
    
    // MARK: - Initialization
    
    /// Creates a new WhisperKit configuration.
    /// - Parameters:
    ///   - model: Model variant (default: "small")
    ///   - computeUnits: CoreML compute units (default: .cpuAndNeuralEngine)
    ///   - enableTimestamps: Whether to generate timestamps (default: true)
    ///   - sampleRate: Target sample rate (default: 16000)
    ///   - audioFormat: Audio format (default: .wav)
    ///   - prewarmModel: Whether to prewarm model (default: true)
    ///   - useQuantization: Whether to use quantization (default: false)
    ///   - maxChunkSizeSeconds: Max chunk size (default: 30)
    public init(
        model: String = "small",
        computeUnits: ComputeUnits = .cpuAndNeuralEngine,
        enableTimestamps: Bool = true,
        sampleRate: Double = 16000,
        audioFormat: AudioFormat = .wav,
        prewarmModel: Bool = true,
        useQuantization: Bool = false,
        maxChunkSizeSeconds: Double = 30
    ) {
        self.model = model
        self.computeUnits = computeUnits
        self.enableTimestamps = enableTimestamps
        self.sampleRate = sampleRate
        self.audioFormat = audioFormat
        self.prewarmModel = prewarmModel
        self.useQuantization = useQuantization
        self.maxChunkSizeSeconds = maxChunkSizeSeconds
    }
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        "WhisperKitConfiguration(model: \(model), computeUnits: \(computeUnits), " +
        "sampleRate: \(sampleRate)Hz, timestamps: \(enableTimestamps))"
    }
    
    // MARK: - WhisperKit Model Variants
    
    /// Returns the full HuggingFace model identifier.
    public var modelIdentifier: String {
        "whisper-\(model)"
    }
    
    /// HuggingFace repository hosting the CoreML models.
    public static let modelRepo = "argmaxinc/whisperkit-coreml"
    
    /// Model download size estimate for UI display.
    public var modelSizeEstimate: String {
        switch model {
        case "tiny": return "~75 MB"
        case "base": return "~142 MB"
        case "small": return "~244 MB"
        case "medium": return "~769 MB"
        case "large", "large-v3": return "~1.5 GB"
        default: return "~244 MB"
        }
    }
}

// MARK: - Compute Units Extension

extension ComputeUnits {
    /// Maps to WhisperKit compute options.
    var whisperKitComputeOptions: MLComputeUnits {
        switch self {
        case .cpuOnly:
            return .cpuOnly
        case .cpuAndGPU:
            return .cpuAndGPU
        case .cpuAndNeuralEngine:
            return .cpuAndNeuralEngine
        case .all:
            return .all
        }
    }
}

/// ML Compute Units for CoreML (re-exported for WhisperKit compatibility)
public enum MLComputeUnits: String, Sendable, Equatable, Codable {
    case cpuOnly = "cpuOnly"
    case cpuAndGPU = "cpuAndGPU"
    case cpuAndNeuralEngine = "cpuAndNeuralEngine"
    case all = "all"
}
