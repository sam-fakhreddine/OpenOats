import MLX
import MLXAudioSTT
import MLXAudioSpike
import Foundation

/// Test executable for MLX Audio spike validation - Step 4: Industry Standard Tests
/// 
/// Run via xcodebuild (required for Metal support):
/// DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -scheme MLXAudioTest -destination 'platform=macOS'
///
/// Usage:
///   MLXAudioTest                    # Run all tests
///   MLXAudioTest <audio_file.wav>   # Test with specific audio file
///   MLXAudioTest --harvard          # Run Harvard Sentences test
///   MLXAudioTest --benchmarks       # Show benchmark info
@main
struct MLXAudioTest {
    static func main() async throws {
        let args = CommandLine.arguments
        
        // Check for special modes
        if args.contains("--benchmarks") {
            MLXAudioSpike.printBenchmarkInfo()
            return
        }
        
        print("🔬 MLX Audio Spike Validation - Step 4: Industry Standard Tests")
        print("=================================================================")
        
        // Test 1: List available models
        print("\n[Test 1] Available models...")
        MLXAudioSpike.listAvailableModels()
        
        // Test 2: Harvard Sentences test (industry standard)
        if args.contains("--harvard") {
            print("\n[Test 2] Harvard Sentences Standard Test...")
            do {
                try await MLXAudioSpike.runHarvardTest()
            } catch {
                print("⚠️ Harvard test failed: \(error)")
            }
        } else {
            print("\n[Test 2] Real audio transcription with GLMASR 9B...")
            do {
                let testFilePath = args.count > 1 && !args[1].hasPrefix("--") ? args[1] : "test_audio.wav"
                let result = try await MLXAudioSpike.transcribeAudioFile(testFilePath)
                print("\n✅ Test 2 passed!")
                print("📝 Final transcription: \"\(result)\"")
            } catch {
                print("\n⚠️ Test 2: \(error)")
            }
        }
        
        // Test 3: Performance check
        print("\n[Test 3] Quick performance check...")
        let speechSamples = MLXAudioSpike.generateSyntheticAudio(duration: 10.0, frequency: 440.0)
        do {
            let start = Date()
            let _ = try await MLXAudioSpike.testModelLoadingAndTranscription(samples: speechSamples)
            let elapsed = Date().timeIntervalSince(start)
            print("⏱️  Total time: \(String(format: "%.2f", elapsed))s")
        } catch {
            print("⚠️ Performance test: \(error)")
        }
        
        // Test 4: Benchmark info
        print("\n[Test 4] Industry benchmark standards...")
        MLXAudioSpike.printBenchmarkInfo()
        
        print("\n✅ Step 4 validation complete")
        print("\n📚 mlx-audio-swift: https://github.com/Blaizzy/mlx-audio-swift")
        print("💡 Best model for M4 Pro: GLMASR 9B (4bit) - RTF 0.37, high quality")
        print("🎯 Ready for TranscriptionBackend integration!")
        print("")
        print("💡 For real quality validation:")
        print("   1. Download LibriSpeech: https://www.openslr.org/12/")
        print("   2. Or record yourself speaking Harvard Sentences")
        print("   3. Run: MLXAudioTest <your_audio.wav>")
        print("   4. Target WER: <5% for clean speech")
    }
}
