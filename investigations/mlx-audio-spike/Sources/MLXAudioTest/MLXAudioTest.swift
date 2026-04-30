import MLX
import MLXAudioSTT
import MLXAudioSpike

/// Test executable for MLX Audio spike validation - Step 3: Model Loading
/// 
/// Run via xcodebuild (required for Metal support):
/// DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -scheme MLXAudioTest -destination 'platform=macOS'
@main
struct MLXAudioTest {
    static func main() async throws {
        print("🔬 MLX Audio Spike Validation - Step 3: Model Loading")
        print("======================================================")
        
        // Generate synthetic audio for testing
        print("\n[Test 0] Generate synthetic audio...")
        let syntheticSamples = MLXAudioSpike.generateSyntheticAudio(duration: 3.0, frequency: 440.0)
        
        // List available models
        print("\n[Test 1] Available models...")
        MLXAudioSpike.listAvailableModels()
        
        // Benchmark multiple models
        print("\n[Test 2] Benchmark models against each other...")
        await MLXAudioSpike.benchmarkModels(samples: syntheticSamples)
        
        // Test single high-quality model
        print("\n[Test 3] Test high-quality Voxtral 4B model...")
        do {
            let result = try await MLXAudioSpike.testModelLoadingAndTranscription(samples: syntheticSamples)
            print("\n✅ Test 3 passed! Result: \"\(result)\"")
        } catch {
            print("\n⚠️ Test 3 failed: \(error)")
        }
        
        print("\n✅ Step 3 validation complete")
        print("\n📚 mlx-audio-swift: https://github.com/Blaizzy/mlx-audio-swift")
        print("💡 Models cached at: ~/.cache/huggingface/hub/mlx-audio/")
    }
}
