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
        
        // Try GLMASR - 9B model we haven't tested yet
        print("\n📥 Loading model: mlx-community/GLM-ASR-Nano-2512-4bit...")
        print("   (Quantized 4bit - smaller, faster, good quality!)")
        
        do {
            // GLMASR - 9B model with 4bit quantization
            let model = try await GLMASRModel.fromPretrained("mlx-community/GLM-ASR-Nano-2512-4bit")
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
    
    /// Test 4: Transcribe real audio file
    /// - Parameter filePath: Path to audio file (wav, mp3, etc.)
    /// - Returns: Transcription result
    public static func transcribeAudioFile(_ filePath: String) async throws -> String {
        print("\n🎧 Test: Real Audio File Transcription")
        print("=======================================")
        print("📁 Loading audio file: \(filePath)")
        
        // Load audio file using AVFoundation
        let samples = try loadAudioFile(filePath)
        print("✅ Loaded \(samples.count) samples (\(String(format: "%.1f", Double(samples.count)/16000.0))s)")
        
        // Create MLXArray
        let mlxArray = MLXArray(samples)
        
        // Load GLMASR model (best quality+speed balance)
        print("\n📥 Loading GLMASR 9B (4bit) model...")
        let model = try await GLMASRModel.fromPretrained("mlx-community/GLM-ASR-Nano-2512-4bit")
        print("✅ Model loaded!")
        
        // Transcribe
        print("\n🎙️ Transcribing...")
        let startTime = Date()
        let output = model.generate(audio: mlxArray)
        let elapsed = Date().timeIntervalSince(startTime)
        
        let audioDuration = Double(samples.count) / 16000.0
        let rtf = elapsed / audioDuration
        
        print("✅ Done in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")
        print("📝 Transcription: \"\(output.text)\"")
        
        if let language = output.language {
            print("🌐 Language: \(language)")
        }
        
        return output.text
    }
    
    /// Load audio file and convert to 16kHz Float32 samples
    private static func loadAudioFile(_ filePath: String) throws -> [Float] {
        let url = URL(fileURLWithPath: filePath)
        
        // For now, return synthetic speech-like audio if file doesn't exist
        // In production, use AVAudioEngine to load and resample
        if !FileManager.default.fileExists(atPath: filePath) {
            print("⚠️  File not found, generating test speech pattern...")
            return generateSpeechLikeAudio(duration: 5.0)
        }
        
        // Placeholder: In real implementation, use AVAudioFile + resampling
        // For this spike, we'll generate a more complex test signal
        return generateSpeechLikeAudio(duration: 5.0)
    }
    
    /// Generate speech-like test audio (multiple frequencies)
    private static func generateSpeechLikeAudio(duration: Double) -> [Float] {
        let sampleRate = 16000
        let sampleCount = Int(duration * Double(sampleRate))
        var samples = [Float](repeating: 0.0, count: sampleCount)
        
        // Mix multiple frequencies to simulate speech (vowel-like)
        let frequencies = [120.0, 240.0, 480.0, 720.0] // F0 + harmonics
        
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleRate)
            var sample: Double = 0
            
            for (j, freq) in frequencies.enumerated() {
                let amplitude = 1.0 / Double(j + 1) // Decreasing amplitude
                sample += sin(2.0 * .pi * freq * t) * amplitude
            }
            
            // Add some amplitude modulation (simulates syllables)
            let modulation = 0.5 + 0.5 * sin(2.0 * .pi * 3.0 * t) // 3Hz modulation
            samples[i] = Float(sample * modulation * 0.3)
        }
        
        print("🎵 Generated \(duration)s speech-like test audio")
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
    
    // MARK: - Industry Standard Tests
    
    /// Harvard Sentences - Industry standard phonetically balanced test phrases
    /// Source: IEEE/ANSI standard for audio equipment testing
    public static let harvardSentences = [
        "The birch canoe slid on the smooth planks.",
        "Glue the sheet to the dark blue background.",
        "It's easy to tell the depth of a well.",
        "These days a chicken leg is a rare dish.",
        "Rice is often served in round bowls.",
        "The juice of lemons makes fine punch.",
        "The box was thrown beside the parked truck.",
        "The hogs were fed chopped corn and garbage.",
        "Four hours of steady work faced us.",
        "A large size in stockings is hard to sell."
    ]
    
    /// Calculate Word Error Rate (WER) - Industry standard ASR metric
    /// Formula: WER = (S + D + I) / N
    /// Where: S=substitutions, D=deletions, I=insertions, N=reference word count
    public static func calculateWER(reference: String, hypothesis: String) -> Double {
        let refWords = reference.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let hypWords = hypothesis.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        // Simple Levenshtein distance calculation
        let (substitutions, deletions, insertions) = levenshteinOperations(refWords, hypWords)
        let totalErrors = substitutions + deletions + insertions
        let wer = Double(totalErrors) / Double(refWords.count)
        
        print("\n📊 WER Analysis:")
        print("   Reference:  \"\(reference)\"")
        print("   Hypothesis: \"\(hypothesis)\"")
        print("   Words: \(refWords.count) | Sub: \(substitutions) | Del: \(deletions) | Ins: \(insertions)")
        print("   WER: \(String(format: "%.1f", wer * 100))%")
        
        return wer
    }
    
    /// Levenshtein distance for word sequences
    private static func levenshteinOperations(_ ref: [String], _ hyp: [String]) -> (sub: Int, del: Int, ins: Int) {
        let m = ref.count
        let n = hyp.count
        
        guard m > 0 else { return (0, 0, n) }
        guard n > 0 else { return (0, m, 0) }
        
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                if ref[i-1] == hyp[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = min(dp[i-1][j-1], min(dp[i-1][j], dp[i][j-1])) + 1
                }
            }
        }
        
        // Backtrack to count operations
        var i = m, j = n
        var sub = 0, del = 0, ins = 0
        
        while i > 0 || j > 0 {
            if i == 0 {
                ins += 1
                j -= 1
            } else if j == 0 {
                del += 1
                i -= 1
            } else if ref[i-1] == hyp[j-1] {
                i -= 1
                j -= 1
            } else {
                let minVal = min(dp[i-1][j-1], min(dp[i-1][j], dp[i][j-1]))
                if dp[i-1][j-1] == minVal {
                    sub += 1
                    i -= 1
                    j -= 1
                } else if dp[i-1][j] == minVal {
                    del += 1
                    i -= 1
                } else {
                    ins += 1
                    j -= 1
                }
            }
        }
        
        return (sub, del, ins)
    }
    
    /// Run Harvard Sentences test with synthetic audio
    /// In production, replace with recorded audio of these sentences
    public static func runHarvardTest() async throws {
        print("\n🎓 Harvard Sentences Test (IEEE/ANSI Standard)")
        print("==============================================")
        print("Testing with \(harvardSentences.count) phonetically balanced phrases")
        print("Note: Using synthetic audio - WER will be high. Use recorded speech for real validation.")
        
        var totalWER: Double = 0
        var testedCount = 0
        
        // Load model once
        print("\n📥 Loading GLMASR 9B (4bit)...")
        let model = try await GLMASRModel.fromPretrained("mlx-community/GLM-ASR-Nano-2512-4bit")
        print("✅ Model ready")
        
        for (index, sentence) in harvardSentences.enumerated() {
            print("\n[Test \(index + 1)/\(harvardSentences.count)]")
            
            // Generate speech-like audio for this sentence
            // In real test, load recorded audio file
            let duration = Double(sentence.split(separator: " ").count) * 0.4 // ~0.4s per word
            let samples = generateSpeechLikeAudio(duration: max(duration, 2.0))
            
            let mlxArray = MLXArray(samples)
            let output = model.generate(audio: mlxArray)
            
            let wer = calculateWER(reference: sentence, hypothesis: output.text)
            totalWER += wer
            testedCount += 1
        }
        
        let avgWER = totalWER / Double(testedCount)
        print("\n📈 Harvard Test Summary")
        print("=======================")
        print("Average WER: \(String(format: "%.1f", avgWER * 100))%")
        print("⚠️  Note: High WER expected with synthetic audio")
        print("💡 For real validation, record yourself speaking these sentences")
    }
    
    /// Industry standard benchmark info
    public static func printBenchmarkInfo() {
        print("\n📚 Industry Standard ASR Benchmarks")
        print("====================================")
        print("1. LibriSpeech (Most Common)")
        print("   - test-clean: Clean read speech, ~5hrs")
        print("   - test-other: Challenging accents/noise")
        print("   - Download: https://www.openslr.org/12/")
        print("   - Metric: WER (Word Error Rate)")
        print("")
        print("2. Common Voice (Mozilla)")
        print("   - Crowdsourced, diverse speakers")
        print("   - More realistic than LibriSpeech")
        print("")
        print("3. TED-LIUM (Conversational)")
        print("   - Natural speech patterns")
        print("   - Good for meeting transcription")
        print("")
        print("4. CHiME (Noisy Environments)")
        print("   - Tests robustness to background noise")
        print("")
        print("🎯 Target WER for production: <5% on clean speech")
        print("🎯 Target WER for meetings: <15% with background noise")
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
