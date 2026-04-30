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
        
        // Test model loading and transcription
        print("\n[Test 2] Model loading & transcription...")
        do {
            let result = try await MLXAudioSpike.testModelLoadingAndTranscription(samples: syntheticSamples)
            print("\n✅ Test 2 passed! Result: \"\(result)\"")
        } catch {
            print("\n⚠️ Test 2 failed (expected if model not cached): \(error)")
        }
        
        // Test performance measurement
        print("\n[Test 3] Performance measurement...")
        do {
            let metrics = try await MLXAudioSpike.measurePerformance(samples: syntheticSamples)
            print("\n✅ Test 3 passed!")
            print("📊 Summary: \(metrics.summary)")
            
            // Evaluate RTF
            if metrics.rtf < 0.3 {
                print("🎉 RTF target met! (< 0.3)")
            } else {
                print("⚠️ RTF above target: \(String(format: "%.3f", metrics.rtf)) (target: <0.3)")
            }
        } catch {
            print("\n⚠️ Test 3 failed (expected if model not cached): \(error)")
        }
        
        print("\n✅ Step 3 validation complete")
        print("\n📚 mlx-audio-swift: https://github.com/Blaizzy/mlx-audio-swift")
        print("💡 Note: First run downloads ~2GB model from HuggingFace")
        print("   Cache location: ~/Library/Caches/huggingface/")
    }
}
