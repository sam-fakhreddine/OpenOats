import Foundation
import MLX
import MLXAudioSTT

/// Transcription backend for MLX Audio models (GLMASR 9B 4bit quantized).
/// Uses Apple's Metal GPU for high-performance local transcription.
///
/// @unchecked Sendable: model is written once in prepare() before any transcribe() calls.
final class MLXWhisperBackend: TranscriptionBackend, @unchecked Sendable {
    let displayName = "MLX Whisper (GLMASR 9B)"

    /// The MLX model instance - loaded during prepare()
    private var model: GLMASRModel?

    /// Model repository identifier
    private let modelRepo = "mlx-community/GLM-ASR-Nano-2512-4bit"

    /// Custom cache directory for MLX models (optional)
    private let customCacheDirectory: URL?

    /// Cache directory for MLX models
    private var cacheDirectory: URL {
        customCacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
            .appendingPathComponent("mlx-audio")
    }

    /// Creates a new MLX Whisper backend.
    /// - Parameter customCacheDirectory: Optional custom directory for model storage. If nil, uses default cache.
    init(customCacheDirectory: URL? = nil) {
        self.customCacheDirectory = customCacheDirectory
    }
    
    func checkStatus() -> BackendStatus {
        let modelCacheDir = cacheDirectory.appendingPathComponent("mlx-community_GLM-ASR-Nano-2512-4bit")
        let exists = FileManager.default.fileExists(atPath: modelCacheDir.path)
        return exists ? .ready : .needsDownload(
            prompt: "MLX Whisper requires a one-time model download (~1.2 GB)."
        )
    }
    
    func clearModelCache() {
        let modelCacheDir = cacheDirectory.appendingPathComponent("mlx-community_GLM-ASR-Nano-2512-4bit")
        try? FileManager.default.removeItem(at: modelCacheDir)
    }
    
    func prepare(onStatus: @Sendable (String) -> Void, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        onStatus("Loading MLX Whisper model...")
        
        // Load the model - MLX Audio handles download automatically if not cached
        // Note: Progress reporting is handled internally by MLX Audio's HuggingFace integration
        let loadedModel = try await GLMASRModel.fromPretrained(modelRepo)
        self.model = loadedModel
        
        onStatus("MLX Whisper ready")
    }
    
    func transcribe(_ samples: [Float], locale: Locale, previousContext: String? = nil) async throws -> String {
        guard let model else {
            throw TranscriptionBackendError.notPrepared
        }
        
        // Convert samples to MLXArray
        let mlxArray = MLXArray(samples)
        
        // Generate transcription
        let output = model.generate(audio: mlxArray)
        
        // Return transcribed text, trimmed
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
