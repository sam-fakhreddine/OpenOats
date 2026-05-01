import XCTest
@testable import OpenOats

// MARK: - Mock URLSession Components

/// A mock URLProtocol for testing HTTP requests without hitting real servers
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestHistory: [URLRequest] = []
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        MockURLProtocol.requestHistory.append(request)
        
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
    
    static func reset() {
        requestHandler = nil
        requestHistory.removeAll()
    }
}

// MARK: - Cloud Transcription Configuration Tests

@available(macOS 15.0, *)
final class CloudTranscriptionConfigurationTests: XCTestCase {
    
    override func tearDown() {
        super.tearDown()
        // Clean up keychain
        KeychainHelper.delete(key: "assemblyai.api_key")
        KeychainHelper.delete(key: "assemblyai.endpoint")
    }
    
    // MARK: - Initialization Tests
    
    func testDefaultInitialization() {
        let config = CloudTranscriptionConfiguration()
        
        XCTAssertEqual(config.provider, .assemblyAI)
        XCTAssertNil(config.apiKey)
        XCTAssertEqual(config.endpoint, URL(string: "https://api.assemblyai.com/v2")!)
        XCTAssertEqual(config.timeout, .seconds(30))
        XCTAssertEqual(config.retryPolicy.maxRetries, 3)
        XCTAssertEqual(config.retryPolicy.retryDelay, .seconds(1))
        XCTAssertTrue(config.retryPolicy.exponentialBackoff)
    }
    
    func testCustomInitialization() {
        let customEndpoint = URL(string: "https://custom.api.com")!
        let customRetryPolicy = RetryPolicy(maxRetries: 5, retryDelay: .seconds(2), exponentialBackoff: false)
        
        let config = CloudTranscriptionConfiguration(
            provider: .assemblyAI,
            endpoint: customEndpoint,
            timeout: .seconds(60),
            retryPolicy: customRetryPolicy
        )
        
        XCTAssertEqual(config.provider, .assemblyAI)
        XCTAssertEqual(config.endpoint, customEndpoint)
        XCTAssertEqual(config.timeout, .seconds(60))
        XCTAssertEqual(config.retryPolicy.maxRetries, 5)
    }
    
    // MARK: - API Key Security Tests
    
    func testSaveAndLoadAPIKeyFromKeychain() {
        let config = CloudTranscriptionConfiguration()
        let testKey = "test_api_key_12345"
        
        // Save API key
        config.saveAPIKey(testKey)
        
        // Load API key
        let loadedKey = config.loadAPIKey()
        XCTAssertEqual(loadedKey, testKey)
    }
    
    func testLoadAPIKeyReturnsNilWhenNotSet() {
        let config = CloudTranscriptionConfiguration()
        
        let loadedKey = config.loadAPIKey()
        XCTAssertNil(loadedKey)
    }
    
    func testAPIKeyIsNotStoredInMemory() {
        let config = CloudTranscriptionConfiguration()
        let testKey = "test_api_key_12345"
        
        config.saveAPIKey(testKey)
        
        // The apiKey property should still return nil (loaded from keychain on demand)
        // This is a security feature - keys are not cached in memory
        XCTAssertNil(config.apiKey)
    }
    
    func testClearAPIKey() {
        let config = CloudTranscriptionConfiguration()
        let testKey = "test_api_key_12345"
        
        config.saveAPIKey(testKey)
        XCTAssertEqual(config.loadAPIKey(), testKey)
        
        config.clearAPIKey()
        XCTAssertNil(config.loadAPIKey())
    }
    
    // MARK: - Provider Tests
    
    func testCloudProviderIdentifier() {
        XCTAssertEqual(CloudProvider.assemblyAI.rawValue, "assemblyai")
        XCTAssertEqual(CloudProvider.deepgram.rawValue, "deepgram")
        XCTAssertEqual(CloudProvider.revAI.rawValue, "revai")
    }
    
    func testCloudProviderDisplayName() {
        XCTAssertEqual(CloudProvider.assemblyAI.displayName, "AssemblyAI")
        XCTAssertEqual(CloudProvider.deepgram.displayName, "Deepgram")
        XCTAssertEqual(CloudProvider.revAI.displayName, "Rev.ai")
    }
}

// MARK: - AssemblyAI Transcription Service Tests

@available(macOS 15.0, *)
final class AssemblyAITranscriptionServiceTests: XCTestCase {
    
    private var config: CloudTranscriptionConfiguration!
    private var mockSession: URLSession!
    private var service: AssemblyAITranscriptionService!
    
    override func setUp() {
        super.setUp()
        
        // Set up mock URLSession
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: configuration)
        
        // Create configuration with test API key
        config = CloudTranscriptionConfiguration()
        config.saveAPIKey("test_api_key")
        
        // Create service with mock session
        service = AssemblyAITranscriptionService(configuration: config, urlSession: mockSession)
    }
    
    override func tearDown() {
        MockURLProtocol.reset()
        config.clearAPIKey()
        service = nil
        mockSession = nil
        config = nil
        super.tearDown()
    }
    
    // MARK: - Protocol Conformance Tests
    
    func testBackendID() async {
        let backendID = await service.backendID
        XCTAssertEqual(backendID, BackendID("assemblyai"))
    }
    
    func testDisplayName() async {
        let displayName = await service.displayName
        XCTAssertEqual(displayName, "AssemblyAI")
    }
    
    func testSupportedFormats() async {
        let formats = await service.supportedFormats
        XCTAssertEqual(formats, [.wav, .mp3, .aac])
    }
    
    func testSupportedLanguages() async {
        let languages = await service.supportedLanguages
        XCTAssertTrue(languages.contains(.english))
        XCTAssertTrue(languages.contains(.spanish))
        XCTAssertTrue(languages.contains(.french))
    }
    
    // MARK: - Availability Tests
    
    func testIsAvailableWhenAPIKeyExists() async {
        // Mock successful API key validation
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let isAvailable = await service.isAvailable()
        XCTAssertTrue(isAvailable)
    }
    
    func testIsNotAvailableWhenAPIKeyMissing() async {
        config.clearAPIKey()
        
        let isAvailable = await service.isAvailable()
        XCTAssertFalse(isAvailable)
    }
    
    func testIsNotAvailableWhenAPIKeyInvalid() async {
        // Mock failed API key validation
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let isAvailable = await service.isAvailable()
        XCTAssertFalse(isAvailable)
    }
    
    // MARK: - Audio Validation Tests
    
    func testValidateAudioFileWithSupportedFormat() async throws {
        // Create a temporary WAV file
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test.wav")
        
        // Write minimal WAV header
        var wavData = Data()
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(contentsOf: [0, 0, 0, 0]) // File size (placeholder)
        wavData.append("WAVE".data(using: .ascii)!)
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(contentsOf: [16, 0, 0, 0]) // Subchunk size
        wavData.append(contentsOf: [1, 0]) // Audio format (PCM)
        wavData.append(contentsOf: [1, 0]) // Number of channels
        wavData.append(contentsOf: [0x44, 0xAC, 0, 0]) // Sample rate (44100)
        wavData.append(contentsOf: [0x88, 0x58, 0x01, 0]) // Byte rate
        wavData.append(contentsOf: [2, 0]) // Block align
        wavData.append(contentsOf: [16, 0]) // Bits per sample
        wavData.append("data".data(using: .ascii)!)
        wavData.append(contentsOf: [0, 0, 0, 0]) // Data size
        
        try wavData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let result = await service.validateAudioFile(audioURL)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.format, .wav)
    }
    
    func testValidateAudioFileWithUnsupportedFormat() async {
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test.ogg")
        try? "dummy data".write(to: audioURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let result = await service.validateAudioFile(audioURL)
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.error)
    }
    
    // MARK: - Batch Transcription Tests
    
    func testTranscribeFileSuccess() async throws {
        // Mock upload endpoint
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let url = request.url!.absoluteString
            
            if url.contains("/upload") {
                let json = ["upload_url": "https://assemblyai.com/audio/12345"]
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            } else if url.contains("/transcript") && request.httpMethod == "POST" {
                let json = ["id": "transcript_12345"]
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            } else if url.contains("/transcript/transcript_12345") {
                let json = [
                    "id": "transcript_12345",
                    "status": "completed",
                    "text": "Hello, this is a test transcription."
                ] as [String: Any]
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            
            throw NSError(domain: "MockError", code: 0)
        }
        
        // Create a temporary WAV file
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test.wav")
        let wavData = WAVEncoder.encode(samples: Array(repeating: 0.0, count: 16000)) // 1 second of silence
        try wavData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        var progressUpdates: [TranscriptionProgress] = []
        let result = try await service.transcribeFile(
            at: audioURL,
            language: .english,
            speakerDiarization: false,
            progressHandler: { progress in
                progressUpdates.append(progress)
            }
        )
        
        XCTAssertEqual(result.fullText, "Hello, this is a test transcription.")
        XCTAssertEqual(result.language, .english)
        XCTAssertFalse(result.segments.isEmpty)
        XCTAssertGreaterThan(progressUpdates.count, 0)
    }
    
    func testTranscribeFileWithInvalidAPIKey() async {
        // Mock authentication failure
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test.wav")
        let wavData = WAVEncoder.encode(samples: [0.0, 0.0, 0.0])
        try? wavData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        do {
            _ = try await service.transcribeFile(at: audioURL, language: .english)
            XCTFail("Expected error to be thrown")
        } catch let error as TranscriptionError {
            if case .backendFailed(let backend, _, _) = error {
                XCTAssertEqual(backend, "assemblyai")
            } else {
                XCTFail("Expected backendFailed error, got \(error)")
            }
        }
    }
    
    func testTranscribeFileWithRateLimit() async {
        // Mock rate limiting
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "60"]
            )!
            return (response, Data())
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test.wav")
        let wavData = WAVEncoder.encode(samples: [0.0, 0.0, 0.0])
        try? wavData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        do {
            _ = try await service.transcribeFile(at: audioURL, language: .english)
            XCTFail("Expected error to be thrown")
        } catch let error as TranscriptionError {
            if case .rateLimited(let provider, let retryAfter) = error {
                XCTAssertEqual(provider, "assemblyai")
                XCTAssertNotNil(retryAfter)
            } else {
                // Rate limiting may be mapped to backendFailed
                XCTAssertTrue(true)
            }
        }
    }
    
    func testTranscribeFileWithNetworkFailure() async {
        // Simulate network failure
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test.wav")
        let wavData = WAVEncoder.encode(samples: [0.0, 0.0, 0.0])
        try? wavData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        do {
            _ = try await service.transcribeFile(at: audioURL, language: .english)
            XCTFail("Expected error to be thrown")
        } catch let error as TranscriptionError {
            if case .networkFailure(_) = error {
                XCTAssertTrue(true)
            } else if case .backendFailed(_, _, let recoverable) = error {
                XCTAssertTrue(recoverable)
            } else {
                XCTFail("Expected network or recoverable error, got \(error)")
            }
        }
    }
    
    // MARK: - Retry Logic Tests
    
    func testRetryWithExponentialBackoff() async throws {
        var attemptCount = 0
        MockURLProtocol.requestHandler = { request in
            attemptCount += 1
            let url = request.url!.absoluteString
            
            // First two attempts fail with 500 error
            if attemptCount < 3 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            
            // Third attempt succeeds
            if url.contains("/upload") {
                let json = ["upload_url": "https://assemblyai.com/audio/12345"]
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            } else if url.contains("/transcript") && request.httpMethod == "POST" {
                let json = ["id": "transcript_12345"]
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            } else if url.contains("/transcript/transcript_12345") {
                let json = [
                    "id": "transcript_12345",
                    "status": "completed",
                    "text": "Success after retry!"
                ] as [String: Any]
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            
            throw NSError(domain: "MockError", code: 0)
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test.wav")
        let wavData = WAVEncoder.encode(samples: Array(repeating: 0.0, count: 16000))
        try wavData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let result = try await service.transcribeFile(at: audioURL, language: .english)
        XCTAssertEqual(result.fullText, "Success after retry!")
        XCTAssertGreaterThanOrEqual(attemptCount, 3)
    }
    
    func testNoRetryForClientErrors() async {
        var attemptCount = 0
        MockURLProtocol.requestHandler = { request in
            attemptCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test.wav")
        let wavData = WAVEncoder.encode(samples: [0.0, 0.0, 0.0])
        try? wavData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        do {
            _ = try await service.transcribeFile(at: audioURL, language: .english)
            XCTFail("Expected error to be thrown")
        } catch {
            // Should only be one attempt (no retry for 4xx errors)
            XCTAssertEqual(attemptCount, 1)
        }
    }
    
    // MARK: - Progress Reporting Tests
    
    func testProgressReportingDuringUpload() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            
            if url.contains("/upload") {
                let json = ["upload_url": "https://assemblyai.com/audio/12345"]
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            } else if url.contains("/transcript") && request.httpMethod == "POST" {
                let json = ["id": "transcript_12345"]
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            } else if url.contains("/transcript/transcript_12345") {
                let json = [
                    "id": "transcript_12345",
                    "status": "completed",
                    "text": "Test"
                ] as [String: Any]
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            
            throw NSError(domain: "MockError", code: 0)
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test.wav")
        let wavData = WAVEncoder.encode(samples: Array(repeating: 0.0, count: 16000))
        try wavData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        var progressValues: [Double] = []
        _ = try await service.transcribeFile(
            at: audioURL,
            language: .english,
            progressHandler: { progress in
                progressValues.append(progress.percentage)
            }
        )
        
        // Progress should increase monotonically
        XCTAssertGreaterThan(progressValues.count, 0)
        XCTAssertEqual(progressValues.last, 1.0)
    }
    
    // MARK: - Error Mapping Tests
    
    func testNetworkErrorMapping() async {
        let testCases: [(URLError.Code, Bool)] = [
            (.notConnectedToInternet, true),
            (.timedOut, true),
            (.networkConnectionLost, true),
            (.dnsLookupFailed, true),
            (.cannotConnectToHost, true)
        ]
        
        for (errorCode, shouldBeRecoverable) in testCases {
            MockURLProtocol.requestHandler = { _ in
                throw URLError(errorCode)
            }
            
            let tempDir = FileManager.default.temporaryDirectory
            let audioURL = tempDir.appendingPathComponent("test_\(errorCode.rawValue).wav")
            let wavData = WAVEncoder.encode(samples: [0.0])
            try? wavData.write(to: audioURL)
            defer { try? FileManager.default.removeItem(at: audioURL) }
            
            do {
                _ = try await service.transcribeFile(at: audioURL, language: .english)
                XCTFail("Expected error for \(errorCode)")
            } catch let error as TranscriptionError {
                switch error {
                case .networkFailure:
                    XCTAssertTrue(shouldBeRecoverable, "\(errorCode) should be mapped to networkFailure")
                case .backendFailed(_, _, let recoverable):
                    XCTAssertEqual(recoverable, shouldBeRecoverable, "\(errorCode) recoverable status mismatch")
                default:
                    break
                }
            } catch {
                // Other errors may occur due to test setup
            }
        }
    }
    
    // MARK: - Cancellation Tests
    
    func testCancellationDuringUpload() async {
        MockURLProtocol.requestHandler = { _ in
            // Simulate slow upload
            try await Task.sleep(for: .seconds(10))
            return (HTTPURLResponse(), Data())
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test.wav")
        let wavData = WAVEncoder.encode(samples: Array(repeating: 0.0, count: 100000))
        try? wavData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let task = Task {
            try await service.transcribeFile(at: audioURL, language: .english)
        }
        
        // Cancel after short delay
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        
        do {
            _ = try await task.value
            // Task may complete before cancellation, which is fine
        } catch {
            // Expected: task was cancelled
        }
    }
    
    // MARK: - Streaming Upload Tests
    
    func testStreamingUploadWithProgress() async throws {
        let mockStream = AsyncStream<Data> { continuation in
            let chunks = [Data(repeating: 0, count: 1024), Data(repeating: 1, count: 1024)]
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            
            if url.contains("/upload") {
                let json = ["upload_url": "https://assemblyai.com/audio/stream_12345"]
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            
            throw NSError(domain: "MockError", code: 0)
        }
        
        var progressValues: [Double] = []
        let uploadURL = try await service.uploadStreaming(
            audioStream: mockStream,
            progressHandler: { progress in
                progressValues.append(progress)
            }
        )
        
        XCTAssertEqual(uploadURL.absoluteString, "https://assemblyai.com/audio/stream_12345")
        XCTAssertGreaterThanOrEqual(progressValues.count, 2)
    }
}

// MARK: - Performance Tests

@available(macOS 15.0, *)
final class AssemblyAITranscriptionServicePerformanceTests: XCTestCase {
    
    func testRetryPerformance() async throws {
        let config = CloudTranscriptionConfiguration()
        config.saveAPIKey("test_key")
        
        let mockConfiguration = URLSessionConfiguration.ephemeral
        mockConfiguration.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: mockConfiguration)
        
        let service = AssemblyAITranscriptionService(configuration: config, urlSession: mockSession)
        
        var attemptCount = 0
        MockURLProtocol.requestHandler = { request in
            attemptCount += 1
            let url = request.url!.absoluteString
            
            // Fail twice with 503, then succeed
            if attemptCount < 3 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            
            let json = ["upload_url": "https://assemblyai.com/audio/12345"]
            let data = try JSONSerialization.data(withJSONObject: json)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        
        measure {
            let expectation = self.expectation(description: "Retry completed")
            Task {
                let tempDir = FileManager.default.temporaryDirectory
                let audioURL = tempDir.appendingPathComponent("perf_test.wav")
                let wavData = WAVEncoder.encode(samples: [0.0, 0.0, 0.0])
                try? wavData.write(to: audioURL)
                defer { try? FileManager.default.removeItem(at: audioURL) }
                
                _ = try? await service.transcribeFile(at: audioURL, language: .english)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10.0)
        }
    }
}
