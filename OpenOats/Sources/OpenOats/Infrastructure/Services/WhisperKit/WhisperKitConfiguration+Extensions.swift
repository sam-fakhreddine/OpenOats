import Foundation
import WhisperKit

// MARK: - WhisperKit Configuration Extensions

/// Extension to add computed properties and helpers to the existing WhisperKitConfiguration
extension WhisperKitConfiguration {
    
    /// Target sample rate for audio processing.
    /// Whisper models expect 16kHz audio.
    public var sampleRate: Double { 16000 }
    
    /// Target audio format for processing.
    public var audioFormat: AudioFormat { .wav }
    
    /// Whether to prewarm the model (load and prepare for inference).
    public var prewarmModel: Bool { true }
    
    /// Whether to use quantized models for faster inference.
    public var useQuantization: Bool { false }
    
    /// Maximum audio chunk size in seconds.
    public var maxChunkSizeSeconds: Double { 30 }
    
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
    
    /// Detailed description of the configuration.
    public var description: String {
        "WhisperKitConfiguration(model: \(model), computeUnits: \(computeUnits), timestamps: \(enableTimestamps))"
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


