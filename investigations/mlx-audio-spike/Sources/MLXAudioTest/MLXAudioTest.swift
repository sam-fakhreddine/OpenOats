import MLX
import MLXAudioSTT
import MLXAudioSpike

/// Test executable for MLX Audio spike validation
/// 
/// Run via xcodebuild (required for Metal support):
/// DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -scheme MLXAudioTest -destination 'platform=macOS'
@main
struct MLXAudioTest {
    static func main() async throws {
        print("🔬 MLX Audio Spike Validation")
        print("==============================")
        
        // Test 1: Basic MLX operations
        print("\n[Test 1] Basic MLX operations...")
        MLXAudioSpike.testAudioOperations()
        
        // Test 2: Zero-copy buffer transfer
        print("\n[Test 2] Buffer transfer...")
        let testSamples = [Float](repeating: 0.0, count: 16000) // 1 second of silence
        MLXAudioSpike.testZeroCopyTransfer(samples: testSamples)
        
        // Test 3: Transcription validation
        print("\n[Test 3] Transcription validation...")
        let result = try await MLXAudioSpike.validateTranscription(samples: testSamples)
        print("Result: \(result)")
        
        // Test 4: List available models
        print("\n[Test 4] Available models...")
        MLXAudioSpike.listAvailableModels()
        
        print("\n✅ Spike validation complete")
        print("\n📚 mlx-audio-swift: https://github.com/Blaizzy/mlx-audio-swift")
        print("📖 API: Model.fromPretrained() -> model.generate(audio: MLXArray) -> STTOutput")
    }
}
