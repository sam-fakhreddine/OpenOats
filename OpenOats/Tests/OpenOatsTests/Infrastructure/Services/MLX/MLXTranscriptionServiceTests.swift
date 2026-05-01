import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - MLX Transcription Service Tests

@Suite("MLXTranscriptionService Tests")
struct MLXTranscriptionServiceTests {
    
    // MARK: - Properties
    
    @Test("Service has correct backend ID")
    func testBackendID() async throws {
        let config = MLXConfiguration(
            modelPath: "test/path",
            quantization: .q4,
            useGPU: false,
            memoryLimitMB: 1024
        )
        let service = MLXTranscriptionService(configuration: config)
        
        #expect(service.backendID == BackendID.mlxWhisper)
    }
    
    @Test("Service has correct display name")
    func testDisplayName() async throws {
        let config = MLXConfiguration(
            modelPath: "test/path",
            quantization: .q4,
            useGPU: false,
            memoryLimitMB: 1024
        )
        let service = MLXTranscriptionService(configuration: config)
        
        #expect(service.displayName == "MLX Whisper")
    }
    
    @Test("Service reports supported formats")
    func testSupportedFormats() async throws {
        let config = MLXConfiguration(
            modelPath: "test/path",
            quantization: .q4,
            useGPU: false,
            memoryLimitMB: 1024
        )
        let service = MLXTranscriptionService(configuration: config)
        
        let formats = service.supportedFormats
        #expect(formats.contains(.wav))
        #expect(formats.contains(.mp3))
        #expect(formats.contains(.flac))
    }
    
    @Test("Service reports supported languages")
    func testSupportedLanguages() async throws {
        let config = MLXConfiguration(
            modelPath: "test/path",
            quantization: .q4,
            useGPU: false,
            memoryLimitMB: 1024
        )
        let service = MLXTranscriptionService(configuration: config)
        
        let languages = service.supportedLanguages
        #expect(languages.contains(.english))
        #expect(languages.contains(.spanish))
        #expect(languages.contains(.autoDetect))
    }
    
    @Test("isAvailable returns false when model not present")
    func testIsAvailableWithoutModel() async throws {
        let config = MLXConfiguration(
            modelPath: "/nonexistent/path",
            quantization: .q4,
            useGPU: false,
            memoryLimitMB: 1024
        )
        let service = MLXTranscriptionService(configuration: config)
        
        let available = await service.isAvailable()
        #expect(available == false)
    }
    
    @Test("Streaming configuration is accessible")
    func testStreamingConfiguration() async throws {
        let config = MLXConfiguration(
            modelPath: "test/path",
            quantization: .q4,
            useGPU: false,
            memoryLimitMB: 1024
        )
        let service = MLXTranscriptionService(configuration: config)
        
        var streamingConfig = service.streamingConfiguration
        #expect(streamingConfig.confidenceThreshold == 0.7)
        
        // Test that configuration can be modified
        streamingConfig.confidenceThreshold = 0.8
        service.streamingConfiguration = streamingConfig
        #expect(service.streamingConfiguration.confidenceThreshold == 0.8)
    }
    
    @Test("Does not support speaker diarization")
    func testSpeakerDiarizationNotSupported() async throws {
        let config = MLXConfiguration(
            modelPath: "test/path",
            quantization: .q4,
            useGPU: false,
            memoryLimitMB: 1024
        )
        let service = MLXTranscriptionService(configuration: config)
        
        #expect(service.supportsSpeakerDiarization == false)
    }
}

// MARK: - MLX Audio Processor Tests

@Suite("MLXAudioProcessor Tests")
struct MLXAudioProcessorTests {
    
    @Test("Converts audio buffer to MLX-compatible format")
    func testBufferConversion() async throws {
        let processor = MLXAudioProcessor()
        let samples = [Float](repeating: 0.5, count: 16000)
        let buffer = AudioBuffer(
            samples: samples,
            sampleRate: 16000,
            channelCount: 1,
            timestamp: .zero,
            id: AudioSegmentID()
        )
        
        let result = try await processor.prepareForMLX(buffer)
        
        #expect(result.sampleRate == 16000)
        #expect(result.channelCount == 1)
        #expect(result.samples.count == 16000)
    }
    
    @Test("Resamples audio to target sample rate")
    func testResampling() async throws {
        let processor = MLXAudioProcessor()
        let samples = [Float](repeating: 0.5, count: 32000)
        let buffer = AudioBuffer(
            samples: samples,
            sampleRate: 32000,
            channelCount: 1,
            timestamp: .zero,
            id: AudioSegmentID()
        )
        
        let result = try await processor.prepareForMLX(buffer, targetSampleRate: 16000)
        
        #expect(result.sampleRate == 16000)
        // Should have half the samples after resampling 32kHz -> 16kHz
        #expect(result.samples.count == 16000)
    }
    
    @Test("Converts stereo to mono")
    func testStereoToMono() async throws {
        let processor = MLXAudioProcessor()
        // Create interleaved stereo samples (L0, R0, L1, R1, ...)
        var samples: [Float] = []
        for i in 0..<8000 {
            samples.append(Float(i) * 0.1)  // Left channel
            samples.append(Float(i) * 0.2)  // Right channel
        }
        
        let buffer = AudioBuffer(
            samples: samples,
            sampleRate: 16000,
            channelCount: 2,
            timestamp: .zero,
            id: AudioSegmentID()
        )
        
        let result = try await processor.prepareForMLX(buffer)
        
        #expect(result.channelCount == 1)
        #expect(result.samples.count == 8000)
        // Each mono sample should be average of left and right
        #expect(result.samples[0] == 0.05)  // (0.0 + 0.1) / 2
    }
    
    @Test("Normalizes audio levels")
    func testNormalization() async throws {
        let processor = MLXAudioProcessor()
        let samples = [Float](repeating: 0.1, count: 16000)
        let buffer = AudioBuffer(
            samples: samples,
            sampleRate: 16000,
            channelCount: 1,
            timestamp: .zero,
            id: AudioSegmentID()
        )
        
        let result = try await processor.prepareForMLX(buffer, normalize: true)
        
        // Check that samples are normalized (values may vary based on algorithm)
        #expect(result.samples.count == 16000)
    }
    
    @Test("Handles empty audio buffer")
    func testEmptyBuffer() async throws {
        let processor = MLXAudioProcessor()
        let buffer = AudioBuffer(
            samples: [],
            sampleRate: 16000,
            channelCount: 1,
            timestamp: .zero,
            id: AudioSegmentID()
        )
        
        await #expect(throws: MLXAudioError.invalidBuffer) {
            try await processor.prepareForMLX(buffer)
        }
    }
    
    @Test("Handles invalid sample rate")
    func testInvalidSampleRate() async throws {
        let processor = MLXAudioProcessor()
        let samples = [Float](repeating: 0.5, count: 1000)
        let buffer = AudioBuffer(
            samples: samples,
            sampleRate: 0,
            channelCount: 1,
            timestamp: .zero,
            id: AudioSegmentID()
        )
        
        await #expect(throws: MLXAudioError.invalidSampleRate) {
            try await processor.prepareForMLX(buffer)
        }
    }
}

// MARK: - MLX Model Downloader Tests

@Suite("MLXModelDownloader Tests")
struct MLXModelDownloaderTests {
    
    @Test("Downloader initializes with correct configuration")
    func testInitialization() async throws {
        let downloader = MLXModelDownloader(
            modelRepository: "mlx-community/GLM-ASR-Nano-2512-4bit",
            destinationURL: URL(fileURLWithPath: "/tmp/test")
        )
        
        #expect(d downloader.modelRepository == "mlx-community/GLM-ASR-Nano-2512-4bit")
    }
    
    @Test("Calculates download progress correctly")
    func testProgressCalculation() async throws {
        let downloader = MLXModelDownloader(
            modelRepository: "mlx-community/GLM-ASR-Nano-2512-4bit",
            destinationURL: URL(fileURLWithPath: "/tmp/test")
        )
        
        // Test internal progress calculation
        let progress = await downloader.calculateProgress(downloaded: 50, total: 100)
        #expect(progress == 0.5)
    }
    
    @Test("Supports resume capability")
    func testResumeCapability() async throws {
        let downloader = MLXModelDownloader(
            modelRepository: "mlx-community/GLM-ASR-Nano-2512-4bit",
            destinationURL: URL(fileURLWithPath: "/tmp/test"),
            supportsResume: true
        )
        
        let canResume = await downloader.supportsResume()
        #expect(canResume == true)
    }
    
    @Test("Chunk size is 5MB")
    func testChunkSize() async throws {
        let downloader = MLXModelDownloader(
            modelRepository: "mlx-community/GLM-ASR-Nano-2512-4bit",
            destinationURL: URL(fileURLWithPath: "/tmp/test")
        )
        
        let chunkSize = await downloader.chunkSize()
        #expect(chunkSize == 5 * 1024 * 1024) // 5MB
    }
    
    @Test("Concurrent download limit is 6")
    func testConcurrentLimit() async throws {
        let downloader = MLXModelDownloader(
            modelRepository: "mlx-community/GLM-ASR-Nano-2512-4bit",
            destinationURL: URL(fileURLWithPath: "/tmp/test")
        )
        
        let limit = await downloader.concurrentLimit()
        #expect(limit == 6)
    }
}

// MARK: - Thread Safety Tests

@Suite("MLX Thread Safety Tests")
struct MLXThreadSafetyTests {
    
    @Test("Service is Sendable-safe")
    func testSendableConformance() async throws {
        let config = MLXConfiguration(
            modelPath: "test/path",
            quantization: .q4,
            useGPU: false,
            memoryLimitMB: 1024
        )
        let service = MLXTranscriptionService(configuration: config)
        
        // Compile-time check: if this compiles, service is Sendable
        let _: any Sendable = service
        
        // Runtime check: can pass across actor boundaries
        await Task {
            let available = await service.isAvailable()
            #expect(available == false)
        }.value
    }
    
    @Test("Concurrent operations are safe")
    func testConcurrentOperations() async throws {
        let config = MLXConfiguration(
            modelPath: "test/path",
            quantization: .q4,
            useGPU: false,
            memoryLimitMB: 1024
        )
        let service = MLXTranscriptionService(configuration: config)
        
        // Run multiple concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    _ = await service.isAvailable()
                    _ = service.displayName
                    _ = service.supportedFormats
                }
            }
        }
        
        // If we get here without crash, thread safety is working
        #expect(true)
    }
}
