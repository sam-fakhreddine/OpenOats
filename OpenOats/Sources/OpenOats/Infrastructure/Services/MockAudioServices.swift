import Foundation

// MARK: - Mock Audio Capture Service

/// Mock implementation of AudioCaptureService for testing.
@available(macOS 15.0, *)
public actor MockAudioCaptureService: AudioCaptureService, @unchecked Sendable {
    public nonisolated let configuration: AudioCaptureConfiguration
    
    private var captureState: Bool = false
    private var permissionStatus: PermissionStatus
    private var captureLevelValue: Float
    private var capturedBuffers: [AudioBuffer] = []
    private var shouldThrowError: AudioError?
    private var continuation: AsyncStream<AudioBuffer>.Continuation?
    
    public init(
        configuration: AudioCaptureConfiguration = AudioCaptureConfiguration(),
        permissionStatus: PermissionStatus = PermissionStatus(
            microphone: .authorized,
            systemAudio: .authorized
        ),
        captureLevel: Float = 0.5
    ) {
        self.configuration = configuration
        self.permissionStatus = permissionStatus
        self.captureLevelValue = captureLevel
    }
    
    public func checkPermissions() async -> PermissionStatus {
        return permissionStatus
    }
    
    public func requestPermissions() async -> PermissionStatus {
        // Simulate granting permissions
        permissionStatus = PermissionStatus(
            microphone: .authorized,
            systemAudio: .authorized
        )
        return permissionStatus
    }
    
    public func startCapture() async throws -> AsyncStream<AudioBuffer> {
        if let error = shouldThrowError {
            throw error
        }
        
        guard permissionStatus.allGranted else {
            throw AudioError.permissionDenied
        }
        
        captureState = true
        
        return AsyncStream { continuation in
            self.continuation = continuation
            
            // Simulate capturing some audio buffers
            Task {
                for i in 0..<5 {
                    let buffer = AudioBuffer(
                        samples: Array(repeating: Float(0.1), count: 1024),
                        sampleRate: 48000,
                        channelCount: 1,
                        timestamp: .milliseconds(i * 100),
                        id: AudioSegmentID()
                    )
                    continuation.yield(buffer)
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        }
    }
    
    public func stopCapture() async {
        captureState = false
        continuation?.finish()
        continuation = nil
    }
    
    public nonisolated var currentLevel: Float {
        // Access through MainActor since we can't access actor state directly
        0.5
    }
    
    public nonisolated var isCapturing: Bool {
        // Access through MainActor since we can't access actor state directly
        false
    }
    
    // MARK: - Test Helpers
    
    public func setPermissionStatus(_ status: PermissionStatus) {
        self.permissionStatus = status
    }
    
    public func setCaptureLevel(_ level: Float) {
        self.captureLevelValue = level
    }
    
    public func setShouldThrowError(_ error: AudioError?) {
        self.shouldThrowError = error
    }
    
    public func addCapturedBuffer(_ buffer: AudioBuffer) {
        self.capturedBuffers.append(buffer)
    }
    
    public func simulateCaptureBuffer(_ buffer: AudioBuffer) {
        continuation?.yield(buffer)
    }
}

// MARK: - Mock Audio Format Service

/// Mock implementation of AudioFormatService for testing.
@available(macOS 15.0, *)
public actor MockAudioFormatService: AudioFormatService {
    private var audioInfoResults: [URL: AudioInfo] = [:]
    private var conversionResults: [URL: Result<URL, AudioError>] = [:]
    private var validationResults: [URL: ValidationResult] = [:]
    private var splitResults: [URL: Result<[URL], AudioError>] = [:]
    private var mergeResults: [URL: Result<URL, AudioError>] = [:]
    
    public init() {}
    
    public func getAudioInfo(for audioURL: URL) async -> Result<AudioInfo, AudioError> {
        if let result = audioInfoResults[audioURL] {
            return .success(result)
        }
        return .success(AudioInfo(
            format: .wav,
            sampleRate: 48000,
            channelCount: 1,
            duration: .seconds(60),
            fileSize: 1024 * 1024,
            bitRate: 128000
        ))
    }
    
    public func convertAudio(
        from sourceURL: URL,
        to destinationURL: URL,
        targetFormat: AudioFormat,
        sampleRate: Double?
    ) async -> Result<URL, AudioError> {
        if let result = conversionResults[sourceURL] {
            return result
        }
        return .success(destinationURL)
    }
    
    public func validateAudioFile(_ audioURL: URL) async -> ValidationResult {
        return validationResults[audioURL] ?? .valid
    }
    
    public func splitAudio(
        at audioURL: URL,
        chunkDuration: Duration,
        outputDirectory: URL
    ) async -> Result<[URL], AudioError> {
        if let result = splitResults[audioURL] {
            return result
        }
        return .success([audioURL])
    }
    
    public func mergeAudioFiles(
        _ audioURLs: [URL],
        to destinationURL: URL
    ) async -> Result<URL, AudioError> {
        if let firstURL = audioURLs.first,
           let result = mergeResults[firstURL] {
            return result
        }
        return .success(destinationURL)
    }
    
    // MARK: - Test Helpers
    
    public func setAudioInfo(for url: URL, info: AudioInfo) {
        audioInfoResults[url] = info
    }
    
    public func setConversionResult(for url: URL, result: Result<URL, AudioError>) {
        conversionResults[url] = result
    }
    
    public func setValidationResult(for url: URL, result: ValidationResult) {
        validationResults[url] = result
    }
    
    public func setSplitResult(for url: URL, result: Result<[URL], AudioError>) {
        splitResults[url] = result
    }
    
    public func setMergeResult(for url: URL, result: Result<URL, AudioError>) {
        mergeResults[url] = result
    }
}
