import Foundation

// NOTE: MLX dependencies temporarily disabled due to Swift Package Manager version conflicts.
// See MLX_INTEGRATION.md for full details.
// import MLX
// import MLXAudioSTT

/// Transcription backend for MLX Audio models (GLMASR 9B 4bit quantized).
/// Uses Apple's Metal GPU for high-performance local transcription.
/// 
/// STATUS: Implementation complete but dependencies disabled pending resolution of:
/// - WhisperKit depends on swift-transformers 1.1.x
/// - mlx-audio-swift depends on swift-transformers 1.2.x via mlx-swift-lm
/// 
/// @unchecked Sendable: model is written once in prepare() before any transcribe() calls.
final class MLXWhisperBackend: TranscriptionBackend, @unchecked Sendable {
    let displayName = "MLX Whisper (GLMASR 9B)"
    
    /*
    /// The MLX model instance - loaded during prepare()
    private var model: GLMASRModel?
    
    /// Model repository identifier
    private let modelRepo = "mlx-community/GLM-ASR-Nano-2512-4bit"
    
    /// Cache directory for MLX models
    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
            .appendingPathComponent("mlx-audio")
    }
    */
    
    /// Cache directory for MLX models
    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
            .appendingPathComponent("mlx-audio")
    }
    
    func checkStatus() -> BackendStatus {
        #if ENABLE_MLX
        let modelCacheDir = cacheDirectory.appendingPathComponent("mlx-community_GLM-ASR-Nano-2512-4bit")
        let exists = FileManager.default.fileExists(atPath: modelCacheDir.path)
        return exists ? .ready : .needsDownload(
            prompt: "MLX Whisper requires a one-time model download (~1.2 GB)."
        )
        #else
        return .error(reason: "MLX dependencies not enabled. See MLX_INTEGRATION.md")
        #endif
    }
    
    func clearModelCache() {
        let modelCacheDir = cacheDirectory.appendingPathComponent("mlx-community_GLM-ASR-Nano-2512-4bit")
        try? FileManager.default.removeItem(at: modelCacheDir)
    }
    
    func prepare(onStatus: @Sendable (String) -> Void, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        #if ENABLE_MLX
        onStatus("Loading MLX Whisper model...")
        
        // Load the model - MLX Audio handles download automatically if not cached
        // Note: Progress reporting is handled internally by MLX Audio's HuggingFace integration
        // let loadedModel = try await GLMASRModel.fromPretrained(modelRepo)
        // self.model = loadedModel
        
        onStatus("MLX Whisper ready")
        #else
        throw TranscriptionBackendError.notPrepared
        #endif
    }
    
    func transcribe(_ samples: [Float], locale: Locale, previousContext: String? = nil) async throws -> String {
        #if ENABLE_MLX
        /*
        guard let model else {
            throw TranscriptionBackendError.notPrepared
        }
        
        // Convert samples to MLXArray
        let mlxArray = MLXArray(samples)
        
        // Generate transcription
        let output = model.generate(audio: mlxArray)
        
        // Return transcribed text, trimmed
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        */
        throw TranscriptionBackendError.notPrepared
        #else
        throw TranscriptionBackendError.notPrepared
        #endif
    }
}
