import Foundation

// MARK: - Audio Capture Service

/// Protocol for audio capture (microphone, system audio).
/// Provides a Sendable-safe interface for capturing audio data.
public protocol AudioCaptureService: Sendable {
    /// Current configuration.
    var configuration: AudioCaptureConfiguration { get }
    
    /// Check if the service has necessary permissions.
    func checkPermissions() async -> PermissionStatus
    
    /// Request permissions from the user.
    func requestPermissions() async -> PermissionStatus
    
    /// Start capturing audio.
    /// - Returns: Async stream of audio buffers.
    func startCapture() async throws -> AsyncStream<AudioBuffer>
    
    /// Stop capturing audio.
    func stopCapture() async
    
    /// Current capture level (for VU meter UI).
    var currentLevel: Float { get }
    
    /// Check if currently capturing.
    var isCapturing: Bool { get }
}

// MARK: - Supporting Types

/// Configuration for audio capture.
public struct AudioCaptureConfiguration: Sendable, Equatable {
    /// Target sample rate.
    public let sampleRate: Double
    
    /// Number of channels (1 = mono, 2 = stereo).
    public let channelCount: Int
    
    /// Audio format for capture.
    public let format: AudioFormat
    
    /// Capture source.
    public let source: AudioSource
    
    /// Buffer size in frames.
    public let bufferSize: Int
    
    public init(
        sampleRate: Double = 48000,
        channelCount: Int = 1,
        format: AudioFormat = .wav,
        source: AudioSource = .microphone,
        bufferSize: Int = 1024
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.format = format
        self.source = source
        self.bufferSize = bufferSize
    }
}

/// Audio source types.
public enum AudioSource: String, Sendable, Equatable, Codable {
    case microphone
    case systemAudio
    case bothMixed
}

/// A buffer of audio samples.
public struct AudioBuffer: Sendable, Equatable, Identifiable {
    public let samples: [Float]
    public let sampleRate: Double
    public let channelCount: Int
    public let timestamp: Duration
    public let id: AudioSegmentID
    
    public init(
        samples: [Float],
        sampleRate: Double,
        channelCount: Int,
        timestamp: Duration,
        id: AudioSegmentID
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.timestamp = timestamp
        self.id = id
    }
    
    /// Duration of this buffer.
    public var duration: Duration {
        .seconds(Double(samples.count) / sampleRate / Double(channelCount))
    }
    
    /// Convert to mono if stereo.
    public func toMono() -> AudioBuffer {
        guard channelCount > 1 else { return self }
        
        var monoSamples: [Float] = []
        monoSamples.reserveCapacity(samples.count / channelCount)
        
        for i in stride(from: 0, to: samples.count, by: channelCount) {
            var sum: Float = 0
            for c in 0..<channelCount {
                sum += samples[i + c]
            }
            monoSamples.append(sum / Float(channelCount))
        }
        
        return AudioBuffer(
            samples: monoSamples,
            sampleRate: sampleRate,
            channelCount: 1,
            timestamp: timestamp,
            id: id
        )
    }
}

/// Permission status for audio capture.
public struct PermissionStatus: Sendable, Equatable {
    public let microphone: AuthorizationStatus
    public let systemAudio: AuthorizationStatus
    
    public init(
        microphone: AuthorizationStatus,
        systemAudio: AuthorizationStatus
    ) {
        self.microphone = microphone
        self.systemAudio = systemAudio
    }
    
    public var allGranted: Bool {
        microphone == .authorized && systemAudio == .authorized
    }
}

/// Authorization status values.
public enum AuthorizationStatus: String, Sendable, Equatable, Codable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

// MARK: - Audio Format Service

/// Protocol for audio format conversion and validation.
public protocol AudioFormatService: Sendable {
    /// Get information about an audio file.
    func getAudioInfo(for audioURL: URL) async -> Result<AudioInfo, AudioError>
    
    /// Convert audio file to a different format.
    /// - Parameters:
    ///   - sourceURL: Source audio file.
    ///   - destinationURL: Destination path.
    ///   - targetFormat: Desired format.
    ///   - sampleRate: Target sample rate (nil = keep original).
    /// - Returns: URL to converted file.
    func convertAudio(
        from sourceURL: URL,
        to destinationURL: URL,
        targetFormat: AudioFormat,
        sampleRate: Double?
    ) async -> Result<URL, AudioError>
    
    /// Validate that an audio file can be read.
    func validateAudioFile(_ audioURL: URL) async -> ValidationResult
    
    /// Split audio file into chunks.
    /// - Parameters:
    ///   - audioURL: Source audio file.
    ///   - chunkDuration: Duration of each chunk.
    ///   - outputDirectory: Where to save chunks.
    /// - Returns: URLs to chunk files.
    func splitAudio(
        at audioURL: URL,
        chunkDuration: Duration,
        outputDirectory: URL
    ) async -> Result<[URL], AudioError>
    
    /// Merge multiple audio files.
    /// - Parameters:
    ///   - audioURLs: Files to merge (in order).
    ///   - destinationURL: Output file path.
    /// - Returns: URL to merged file.
    func mergeAudioFiles(
        _ audioURLs: [URL],
        to destinationURL: URL
    ) async -> Result<URL, AudioError>
}

/// Information about an audio file.
public struct AudioInfo: Sendable, Equatable {
    public let format: AudioFormat
    public let sampleRate: Double
    public let channelCount: Int
    public let duration: Duration
    public let fileSize: Int64
    public let bitRate: Int?
    
    public init(
        format: AudioFormat,
        sampleRate: Double,
        channelCount: Int,
        duration: Duration,
        fileSize: Int64,
        bitRate: Int?
    ) {
        self.format = format
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.duration = duration
        self.fileSize = fileSize
        self.bitRate = bitRate
    }
    
    /// Check if the audio is valid for transcription.
    public var isValidForTranscription: Bool {
        // Check if sample rate is reasonable (8kHz - 192kHz)
        sampleRate >= 8000 && sampleRate <= 192000 && duration > .zero
    }
}
