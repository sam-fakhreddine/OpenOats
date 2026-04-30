import MLX
import MLXAudioSTT
import Foundation

/// MLX Audio investigation spike for OpenOats ASR migration
///
/// This module validates MLX Swift Audio API compatibility with the
/// TranscriptionBackend protocol requirements.
public struct MLXAudioSpike {
    
    /// Test 1: Load a model and perform transcription
    /// - Parameter samples: Raw audio samples (16kHz, Float32, mono)
    /// - Returns: Transcription result
    public static func testModelLoadingAndTranscription(samples: [Float]) async throws -> String {
        print("\n🎯 Test: Model Loading & Transcription")
        print("========================================")
        
        // Create MLXArray from samples
        let mlxArray = MLXArray(samples)
        print("✅ Created MLXArray with shape: \(mlxArray.shape), dtype: \(mlxArray.dtype)")
        
        // Use high-quality GraniteSpeech model (IBM's 3.3B - better quality!)
        print("\n📥 Loading model: ibm-granite/granite-speech-3.3b...")
        print("   (This will download ~6GB on first run - quality model for M4 Pro!)")
        
        do {
            // GraniteSpeech 3.3B - IBM's quality model
            let model = try await GraniteSpeechModel.fromPretrained("ibm-granite/granite-speech-3.3b")
            print("✅ Model loaded successfully!")
            
            // Generate transcription
            print("\n🎙️ Generating transcription...")
            let startTime = Date()
            let output = model.generate(audio: mlxArray)
            let elapsed = Date().timeIntervalSince(startTime)
            
            print("✅ Transcription complete in \(String(format: "%.2f", elapsed))s")
            print("📝 Result: \"\(output.text)\"")
            
            if let language = output.language {
                print("🌐 Detected language: \(language)")
            }
            
            return output.text
        } catch {
            print("❌ Error: \(error)")
            throw error
        }
    }
    
    /// Test 2: Generate synthetic audio (sine wave) for testing
    public static func generateSyntheticAudio(duration: Double = 3.0, frequency: Double = 440.0) -> [Float] {
        let sampleRate = 16000
        let sampleCount = Int(duration * Double(sampleRate))
        var samples = [Float](repeating: 0.0, count: sampleCount)
        
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleRate)
            samples[i] = Float(sin(2.0 * .pi * frequency * t) * 0.5)
        }
        
        print("🎵 Generated \(duration)s synthetic audio at \(frequency)Hz")
        print("   Samples: \(sampleCount), Sample rate: \(sampleRate)Hz")
        return samples
    }
    
    /// Test 3: Measure performance metrics
    public static func measurePerformance(samples: [Float]) async throws -> PerformanceMetrics {
        print("\n📊 Test: Performance Measurement")
        print("================================")
        
        let mlxArray = MLXArray(samples)
        
        // Load model from mlx-community
        let loadStart = Date()
        let model = try await ParakeetModel.fromPretrained("mlx-community/parakeet-tdt-0.6b-v3")
        let loadTime = Date().timeIntervalSince(loadStart)
        
        // Generate transcription
        let inferenceStart = Date()
        let output = model.generate(audio: mlxArray)
        let inferenceTime = Date().timeIntervalSince(inferenceStart)
        
        // Calculate RTF (Real-Time Factor)
        let audioDuration = Double(samples.count) / 16000.0
        let rtf = inferenceTime / audioDuration
        
        let metrics = PerformanceMetrics(
            loadTime: loadTime,
            inferenceTime: inferenceTime,
            audioDuration: audioDuration,
            rtf: rtf,
            text: output.text
        )
        
        print("⏱️  Load time: \(String(format: "%.2f", loadTime))s")
        print("⏱️  Inference time: \(String(format: "%.2f", inferenceTime))s")
        print("🎵 Audio duration: \(String(format: "%.2f", audioDuration))s")
        print("📈 RTF: \(String(format: "%.3f", rtf)) (target: <0.3)")
        print("📝 Transcription: \"\(output.text)\"")
        
        return metrics
    }
    
    /// Benchmark multiple models against each other
    public static func benchmarkModels(samples: [Float]) async {
        print("\n🏆 Model Benchmark Comparison")
        print("==============================")
        print("Testing on M4 Pro with \(samples.count/16000)s of audio\n")
        
        let models = [
            ("Parakeet 0.6B", "mlx-community/parakeet-tdt-0.6b-v3", "fast"),
            ("GraniteSpeech 3.3B", "ibm-granite/granite-speech-3.3b", "quality"),
        ]
        
        var results: [(name: String, loadTime: Double, inferenceTime: Double, rtf: Double)] = []
        
        for (name, repo, category) in models {
            print("📊 Testing \(name) [\(category)]...")
            do {
                let mlxArray = MLXArray(samples)
                
                let loadStart = Date()
                // Try GraniteSpeech for quality comparison
                let model = try await GraniteSpeechModel.fromPretrained(repo)
                let loadTime = Date().timeIntervalSince(loadStart)
                
                let inferenceStart = Date()
                let _ = model.generate(audio: mlxArray)
                let inferenceTime = Date().timeIntervalSince(inferenceStart)
                
                let audioDuration = Double(samples.count) / 16000.0
                let rtf = inferenceTime / audioDuration
                
                results.append((name, loadTime, inferenceTime, rtf))
                print("   ✅ RTF: \(String(format: "%.3f", rtf)) | Load: \(String(format: "%.1f", loadTime))s | Inference: \(String(format: "%.2f", inferenceTime))s")
            } catch {
                print("   ❌ Failed: \(error)")
            }
        }
        
        print("\n📈 Benchmark Results Summary")
        print("=============================")
        print("Model                | RTF    | Load | Inference")
        print("---------------------|--------|------|----------")
        for result in results {
            let name = result.name.padding(toLength: 20, withPad: " ", startingAt: 0)
            print("\(name)| \(String(format: "%.3f", result.rtf).padding(toLength: 6, withPad: " ", startingAt: 0))| \(String(format: "%.1f", result.loadTime).padding(toLength: 5, withPad: " ", startingAt: 0))| \(String(format: "%.2f", result.inferenceTime))s")
        }
        
        if let best = results.min(by: { $0.rtf < $1.rtf }) {
            print("\n🥇 Best RTF: \(best.name) (RTF: \(String(format: "%.3f", best.rtf)))")
        }
    }
    
    /// Lists available STT models from mlx-audio-swift
    public static func listAvailableModels() {
        print("\n📋 Available STT Models (mlx-community repos):")
        print("===============================================")
        print("FAST (Speed priority):")
        print("   mlx-community/parakeet-tdt-0.6b-v3 (~2.5GB)")
        print("")
        print("BALANCED:")
        print("   mlx-community/parakeet-tdt-1.1b-v2 (~5GB)")
        print("   mlx-community/Qwen3-ASR-1.7B-8bit (~2GB quantized)")
        print("")
        print("QUALITY (Your M4 Pro can handle these!):")
        print("   mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16 (~8GB)")
        print("   mlx-community/VibeVoice-ASR-bf16 (~9GB)")
        print("   mlx-community/whisper-large-v3-turbo-asr-fp16 (~6GB)")
        print("")
        print("⚠️  Use mlx-community repos - optimized for MLX Metal")
    }
}

/// Performance metrics structure
public struct PerformanceMetrics {
    public let loadTime: Double
    public let inferenceTime: Double
    public let audioDuration: Double
    public let rtf: Double
    public let text: String
    
    public var summary: String {
        "RTF: \(String(format: "%.3f", rtf)) | Load: \(String(format: "%.1f", loadTime))s | Inference: \(String(format: "%.2f", inferenceTime))s"
    }
}
