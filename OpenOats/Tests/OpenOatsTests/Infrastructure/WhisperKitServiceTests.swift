import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - WhisperKit Configuration Tests

@Suite("WhisperKit Configuration Tests")
struct WhisperKitConfigurationTests {
    
    @Test("Default configuration initializes correctly")
    func testDefaultConfiguration() async {
        let config = WhisperKitConfiguration()
        
        #expect(config.model == "small")
        #expect(config.computeUnits == .cpuAndNeuralEngine)
        #expect(config.enableTimestamps == true)
        #expect(config.sampleRate == 16000)
        #expect(config.audioFormat == .wav)
    }
    
    @Test("Custom configuration with all parameters")
    func testCustomConfiguration() async {
        let config = WhisperKitConfiguration(
            model: "large-v3",
            computeUnits: .all,
            enableTimestamps: false,
            sampleRate: 48000,
            audioFormat: .mp3
        )
        
        #expect(config.model == "large-v3")
        #expect(config.computeUnits == .all)
        #expect(config.enableTimestamps == false)
        #expect(config.sampleRate == 48000)
        #expect(config.audioFormat == .mp3)
    }
    
    @Test("Configuration is Sendable and Equatable")
    func testConfigurationSendableAndEquatable() async {
        let config1 = WhisperKitConfiguration(model: "base")
        let config2 = WhisperKitConfiguration(model: "base")
        let config3 = WhisperKitConfiguration(model: "small")
        
        #expect(config1 == config2)
        #expect(config1 != config3)
    }
    
    @Test("CoreML compute options map correctly")
    func testComputeOptionsMapping() async {
        let cpuOnly = WhisperKitConfiguration(model: "base", computeUnits: .cpuOnly)
        let cpuAndGPU = WhisperKitConfiguration(model: "base", computeUnits: .cpuAndGPU)
        let cpuAndNeuralEngine = WhisperKitConfiguration(model: "base", computeUnits: .cpuAndNeuralEngine)
        let all = WhisperKitConfiguration(model: "base", computeUnits: .all)
        
        #expect(cpuOnly.computeUnits == .cpuOnly)
        #expect(cpuAndGPU.computeUnits == .cpuAndGPU)
        #expect(cpuAndNeuralEngine.computeUnits == .cpuAndNeuralEngine)
        #expect(all.computeUnits == .all)
    }
    
    @Test("Configuration validates model names")
    func testModelValidation() async {
        let validModels = ["tiny", "base", "small", "medium", "large", "large-v3"]
        
        for modelName in validModels {
            let config = WhisperKitConfiguration(model: modelName)
            #expect(config.model == modelName)
        }
    }
    
    @Test("Configuration description is meaningful")
    func testConfigurationDescription() async {
        let config = WhisperKitConfiguration(model: "small", computeUnits: .cpuAndNeuralEngine)
        let description = config.description
        
        #expect(description.contains("small"))
        #expect(description.contains("cpuAndNeuralEngine") || description.contains("CPU+ANE"))
    }
}

// MARK: - WhisperKit Audio Processor Tests

@Suite("WhisperKit Audio Processor Tests")
struct WhisperKitAudioProcessorTests {
    
    @Test("Processor initializes with default configuration")
    func testDefaultInitialization() async {
        let processor = await WhisperKitAudioProcessor()
        let config = await processor.configuration
        
        #expect(config.sampleRate == 16000)
        #expect(config.audioFormat == .wav)
    }
    
    @Test("Processor initializes with custom configuration")
    func testCustomInitialization() async {
        let customConfig = WhisperKitConfiguration(sampleRate: 48000, audioFormat: .mp3)
        let processor = await WhisperKitAudioProcessor(configuration: customConfig)
        let config = await processor.configuration
        
        #expect(config.sampleRate == 48000)
        #expect(config.audioFormat == .mp3)
    }
    
    @Test("Converts audio data to float samples")
    func testConvertToFloatSamples() async throws {
        let processor = await WhisperKitAudioProcessor()
        
        // Create 16-bit PCM audio data (sine wave)
        let sampleCount = 16000 // 1 second at 16kHz
        var audioData = Data()
        for i in 0..<sampleCount {
            let value = Int16(sin(Double(i) * 0.1) * 1000)
            audioData.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Array($0) })
        }
        
        let samples = try await processor.convertToFloatSamples(audioData, bitsPerSample: 16)
        
        #expect(samples.count == sampleCount)
        #expect(samples.allSatisfy { $0 >= -1.0 && $0 <= 1.0 })
    }
    
    @Test("Resamples audio to target sample rate")
    func testResampleAudio() async throws {
        let processor = await WhisperKitAudioProcessor()
        
        // Create 1 second of 48kHz audio
        let sourceSamples = Array(repeating: Float(0.5), count: 48000)
        
        let resampled = try await processor.resampleAudio(
            sourceSamples,
            fromSampleRate: 48000,
            toSampleRate: 16000
        )
        
        // Should be roughly 1/3 the size
        #expect(resampled.count == 16000)
    }
    
    @Test("Validates supported audio formats")
    func testValidateSupportedFormats() async {
        let processor = await WhisperKitAudioProcessor()
        
        let wavResult = await processor.validateFormat(.wav)
        let mp3Result = await processor.validateFormat(.mp3)
        let aacResult = await processor.validateFormat(.aac)
        let flacResult = await processor.validateFormat(.flac)
        
        #expect(wavResult.isValid == true)
        #expect(mp3Result.isValid == true)
        #expect(aacResult.isValid == true)
        #expect(flacResult.isValid == true)
    }
    
    @Test("Processes audio file URL")
    func testProcessAudioFile() async throws {
        let processor = await WhisperKitAudioProcessor()
        
        // Create a temporary test file with valid WAV header
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_audio.wav")
        
        // Simple WAV header + 1 second of silence (16-bit, 16kHz, mono)
        var wavData = Data()
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(contentsOf: [0x24, 0x00, 0x00, 0x80]) // Chunk size (placeholder)
        wavData.append("WAVE".data(using: .ascii)!)
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(contentsOf: [0x10, 0x00, 0x00, 0x00]) // Subchunk size (16)
        wavData.append(contentsOf: [0x01, 0x00]) // Audio format (PCM)
        wavData.append(contentsOf: [0x01, 0x00]) // Num channels (1)
        wavData.append(contentsOf: [0x80, 0x3E, 0x00, 0x00]) // Sample rate (16000)
        wavData.append(contentsOf: [0x00, 0x7D, 0x00, 0x00]) // Byte rate
        wavData.append(contentsOf: [0x02, 0x00]) // Block align
        wavData.append(contentsOf: [0x10, 0x00]) // Bits per sample (16)
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Data size (placeholder)
        // Add 1 second of silence
        let silence = Array(repeating: UInt8(0), count: 32000)
        wavData.append(contentsOf: silence)
        
        try wavData.write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        let result = try await processor.processAudioFile(at: testFile)
        
        #expect(result.samples.count == 16000) // 1 second at 16kHz
        #expect(result.sampleRate == 16000)
        #expect(result.channelCount == 1)
        
        // Cleanup
        try? FileManager.default.removeItem(at: testFile)
    }
    
    @Test("Handles invalid audio format error")
    func testInvalidAudioFormatError() async {
        let processor = await WhisperKitAudioProcessor()
        
        let tempDir = FileManager.default.temporaryDirectory
        let invalidFile = tempDir.appendingPathComponent("invalid.xyz")
        try? "invalid".write(to: invalidFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: invalidFile) }
        
        do {
            _ = try await processor.processAudioFile(at: invalidFile)
            #expect(false, "Expected error to be thrown")
        } catch let error as TranscriptionError {
            if case .audioFormatUnsupported = error {
                #expect(true)
            } else {
                #expect(false, "Expected audioFormatUnsupported error")
            }
        }
    }
}

// MARK: - WhisperKit Transcription Service Tests

@Suite("WhisperKit Transcription Service Tests")
struct WhisperKitTranscriptionServiceTests {
    
    @Test("Service initializes with correct backend ID")
    func testServiceInitialization() async {
        let service = await WhisperKitTranscriptionService()
        
        #expect(service.backendID == .whisperKit)
        #expect(service.displayName == "WhisperKit")
    }
    
    @Test("Service reports correct supported formats")
    func testSupportedFormats() async {
        let service = await WhisperKitTranscriptionService()
        let formats = service.supportedFormats
        
        #expect(formats.contains(.wav))
        #expect(formats.contains(.mp3))
        #expect(formats.contains(.aac))
        #expect(formats.contains(.flac))
    }
    
    @Test("Service reports correct supported languages")
    func testSupportedLanguages() async {
        let service = await WhisperKitTranscriptionService()
        let languages = service.supportedLanguages
        
        #expect(languages.contains(.english))
        #expect(languages.contains(.spanish))
        #expect(languages.contains(.french))
        #expect(languages.contains(.autoDetect))
    }
    
    @Test("Availability check returns false before prepare")
    func testAvailabilityBeforePrepare() async {
        let service = await WhisperKitTranscriptionService()
        let available = await service.isAvailable()
        
        #expect(available == false)
    }
    
    @Test("Validate audio file returns correct result")
    func testValidateAudioFile() async throws {
        let service = await WhisperKitTranscriptionService()
        
        // Create a valid temporary audio file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test.wav")
        
        // Simple WAV data
        var wavData = Data()
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(contentsOf: Array(repeating: UInt8(0), count: 4))
        wavData.append("WAVE".data(using: .ascii)!)
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(contentsOf: Array(repeating: UInt8(0), count: 16))
        wavData.append("data".data(using: .ascii)!)
        wavData.append(contentsOf: Array(repeating: UInt8(0), count: 4))
        wavData.append(contentsOf: Array(repeating: UInt8(0), count: 100))
        
        try wavData.write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        let result = await service.validateAudioFile(testFile)
        
        #expect(result.isValid == true)
        #expect(result.format == .wav)
        
        // Cleanup
        try? FileManager.default.removeItem(at: testFile)
    }
    
    @Test("Streaming configuration is configurable")
    func testStreamingConfiguration() async {
        let service = await WhisperKitTranscriptionService()
        
        var config = await service.streamingConfiguration
        config.confidenceThreshold = 0.8
        config.vadSensitivity = .high
        
        await service.setStreamingConfiguration(config)
        
        let updatedConfig = await service.streamingConfiguration
        #expect(updatedConfig.confidenceThreshold == 0.8)
        #expect(updatedConfig.vadSensitivity == .high)
    }
    
    @Test("Resource cleanup completes without error")
    func testResourceCleanup() async {
        let service = await WhisperKitTranscriptionService()
        
        // Should not throw
        await service.cleanup()
        
        // After cleanup, service should report not available
        let available = await service.isAvailable()
        #expect(available == false)
    }
    
    @Test("Transcription error mapping works correctly")
    func testErrorMapping() async {
        let service = await WhisperKitTranscriptionService()
        
        // Test various error mappings
        let backendError = await service.mapError(
            WhisperKitServiceError.modelNotLoaded
        )
        
        if case .modelUnavailable = backendError {
            #expect(true)
        } else {
            #expect(false, "Expected modelUnavailable error")
        }
        
        let timeoutError = await service.mapError(
            WhisperKitServiceError.transcriptionTimeout
        )
        
        if case .timeout = timeoutError {
            #expect(true)
        } else {
            #expect(false, "Expected timeout error")
        }
    }
}

// MARK: - WhisperKit Service Error Tests

@Suite("WhisperKit Service Error Tests")
struct WhisperKitServiceErrorTests {
    
    @Test("Error cases exist and are distinguishable")
    func testErrorCases() async {
        let errors: [WhisperKitServiceError] = [
            .modelNotLoaded,
            .audioFormatNotSupported(format: "xyz"),
            .transcriptionTimeout,
            .audioProcessingFailed(reason: "test"),
            .coreMLError(underlying: NSError(domain: "test", code: 1))
        ]
        
        // Verify all errors are unique
        let uniqueErrors = Set(errors.map { String(describing: $0) })
        #expect(uniqueErrors.count == errors.count)
    }
    
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() async {
        let modelError = WhisperKitServiceError.modelNotLoaded
        #expect(modelError.localizedDescription.contains("not loaded") || modelError.localizedDescription.contains("initialized"))
        
        let formatError = WhisperKitServiceError.audioFormatNotSupported(format: "xyz")
        #expect(formatError.localizedDescription.contains("xyz"))
        
        let timeoutError = WhisperKitServiceError.transcriptionTimeout
        #expect(timeoutError.localizedDescription.contains("timeout") || timeoutError.localizedDescription.contains("timed out"))
    }
}
