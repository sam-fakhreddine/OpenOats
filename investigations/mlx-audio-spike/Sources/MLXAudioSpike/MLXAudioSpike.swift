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
        
        // Use mlx-community Whisper model (optimized for MLX)
        print("\n📥 Loading model: mlx-community/whisper-large-v3-turbo-asr-fp16...")
        print("   (This will download ~1.5GB on first run)")
        
        do {
            // Note: Need to check if Whisper is available in MLXAudioSTT
            // For now, try Parakeet from mlx-community
            let model = try await ParakeetModel.fromPretrained("mlx-community/parakeet-tdt-0.6b-v3")
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
    
    /// Lists available STT models from mlx-audio-swift
    public static func listAvailableModels() {
        print("\n📋 Available STT Models (mlx-community repos):")
        print("===============================================")
        print("1. Whisper (OpenAI)")
        print("   - mlx-community/whisper-large-v3-turbo-asr-fp16 ⭐ Recommended")
        print("")
        print("2. Parakeet (NVIDIA)")
        print("   - mlx-community/parakeet-tdt-0.6b-v3 ⭐ Tested")
        print("   - mlx-community/parakeet-tdt-1.1b-v2")
        print("")
        print("3. Qwen3ASR (Alibaba)")
        print("   - mlx-community/Qwen3-ASR-1.7B-8bit")
        print("")
        print("4. Voxtral (Mistral)")
        print("   - mlx-community/Voxtral-Mini-3B-2507-bf16")
        print("   - mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16")
        print("")
        print("5. VibeVoice-ASR (Microsoft)")
        print("   - mlx-community/VibeVoice-ASR-bf16")
        print("")
        print("⚠️  Important: Use mlx-community repos, not original HF repos!")
        print("   mlx-community models are optimized for MLX Metal backend")
        print("")
        print("Usage:")
        print("  let model = try await ParakeetModel.fromPretrained(\"mlx-community/parakeet-tdt-0.6b-v3\")")
        print("  let output = model.generate(audio: mlxArray)")
        print("  print(output.text)")
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
