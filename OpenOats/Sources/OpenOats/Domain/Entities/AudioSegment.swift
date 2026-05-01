import Foundation

// MARK: - Audio Format

/// Supported audio formats for recording.
public enum AudioFormat: String, Sendable, Equatable, Hashable, Codable {
    /// WAV format (PCM uncompressed).
    case wav
    
    /// MP3 format (compressed).
    case mp3
    
    /// AAC format (compressed).
    case aac
    
    /// FLAC format (lossless compressed).
    case flac
}

// MARK: - Audio Segment Entity

/// Represents a raw audio segment with metadata.
/// Audio segments are the raw data captured during recording.
public struct AudioSegment: Sendable, Equatable, Hashable, Codable {
    /// Unique identifier for this audio segment.
    public let id: AudioSegmentID
    
    /// ID of the parent session.
    public let sessionID: SessionID
    
    /// Raw audio data.
    public let audioData: Data
    
    /// Sample rate in Hz (e.g., 48000, 44100).
    public let sampleRate: Double
    
    /// Number of audio channels (1 for mono, 2 for stereo).
    public let channelCount: Int
    
    /// Bits per sample (typically 16, 24, or 32).
    public let bitsPerSample: Int
    
    /// Start time within the recording.
    public let startTime: Duration
    
    /// Duration of this segment, if known.
    public let duration: Duration?
    
    /// Creates a new AudioSegment instance.
    /// - Parameters:
    ///   - id: Unique identifier for this segment.
    ///   - sessionID: ID of the parent session.
    ///   - audioData: Raw audio data.
    ///   - sampleRate: Sample rate in Hz.
    ///   - channelCount: Number of audio channels.
    ///   - bitsPerSample: Bits per sample.
    ///   - startTime: Start time within the recording.
    ///   - duration: Duration of this segment.
    public init(
        id: AudioSegmentID,
        sessionID: SessionID,
        audioData: Data,
        sampleRate: Double,
        channelCount: Int,
        bitsPerSample: Int,
        startTime: Duration,
        duration: Duration? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.audioData = audioData
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitsPerSample = bitsPerSample
        self.startTime = startTime
        self.duration = duration
    }
    
    /// The size of the audio data in bytes.
    public var dataSizeBytes: Int {
        audioData.count
    }
    
    /// Whether this audio segment has valid format parameters.
    /// Validation checks that sample rate > 0, channel count > 0,
    /// and bits per sample is a common value (8, 16, 24, or 32).
    public var isValid: Bool {
        sampleRate > 0 &&
        channelCount > 0 &&
        [8, 16, 24, 32].contains(bitsPerSample)
    }
    
    /// The total duration calculated from data size if duration is not set.
    /// Returns nil if sampleRate or channelCount is invalid.
    public var calculatedDuration: Duration? {
        guard sampleRate > 0, channelCount > 0, bitsPerSample > 0 else {
            return nil
        }
        
        let bytesPerSample = bitsPerSample / 8
        let bytesPerFrame = bytesPerSample * channelCount
        let totalFrames = audioData.count / bytesPerFrame
        let seconds = Double(totalFrames) / sampleRate
        
        return .seconds(seconds)
    }
}
